"""Einmaliger Import des Bundeslebensmittelschluessels (BLS) 4.0 in public.bls_foods (Phase 7a).

Liest BLS_4_0_Daten_2025_DE.xlsx und BLS_4_0_Components_DE_EN.xlsx aus --source-dir und schreibt
tools/bls_foods_import.sql (INSERT ... ON CONFLICT, idempotent). Das Skript fuehrt NICHTS gegen die
Datenbank aus -- nach Pruefung der erzeugten Datei von Hand einspielen:

    npx supabase db query --linked --file tools/bls_foods_import.sql

Quelle:  https://blsdb.de/assets/uploads/BLS_4_0_2025_DE.zip (entpacken nach tools/bls_source/, gitignored)
Lizenz:  CC BY 4.0 -- Max Rubner-Institut (2025): Bundeslebensmittelschlüssel (BLS), Version 4.0 —
         Deutsche Nährstoffdatenbank. Die Namensnennung steht im Kopf der erzeugten SQL-Datei.

Voraussetzungen: pip install pandas openpyxl
Aufruf:
    python tools/import_bls_foods.py --inspect      # nur Zuordnung zeigen (Codes, Spalten, Einheiten), nichts schreiben
    python tools/import_bls_foods.py                # tools/bls_foods_import.sql erzeugen

Vorgehen: Die 8 benoetigten Naehrwerte werden NICHT ueber Spaltenpositionen gefunden (418 Spalten waeren
fragil), sondern erst ueber den BLS-Komponentencode, danach ueber den deutschen/englischen Namen in
der Components-Tabelle. Ist eine Zuordnung nicht eindeutig, bricht das Skript mit einer Liste der
Kandidaten ab, statt zu raten. Salz hat ein bekanntes Risiko: Falls keine direkte Salz-Spalte existiert,
wird es aus Natrium abgeleitet (Natrium x 2,5), mit Warnung im Ergebnis.
"""
import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SOURCE = ROOT / "tools" / "bls_source"
DEFAULT_OUT = ROOT / "tools" / "bls_foods_import.sql"
DATA_FILE = "BLS_4_0_Daten_2025_DE.xlsx"
COMPONENTS_FILE = "BLS_4_0_Components_DE_EN.xlsx"

ATTRIBUTION = ("Max Rubner-Institut (2025): Bundeslebensmittelschlüssel (BLS), Version 4.0 — "
               "Deutsche Nährstoffdatenbank (CC BY 4.0)")

SODIUM_TO_SALT = 2.5  # NaCl-Aequivalent: Salz (g) = Natrium (g) x 2,5

# key -> Zuordnungsregeln. "required": ohne Treffer bricht das Skript ab; sonst nur Warnung und NULL.
# codes werden zuerst probiert (exakter Treffer in der Code-Spalte), danach names (exakter, case-insensitiver
# Treffer in einer Namensspalte). unit ist die erwartete Einheit je 100 g laut Components-Tabelle.
NUTRIENTS = {
    "kcal":      {"required": True,  "unit": "kcal", "codes": ["ENERCC"],
                  "names": ["Energie (Kilokalorien)", "Energie (kcal)", "Energy (kilocalories)", "Energy (kcal)"]},
    "protein_g": {"required": True,  "unit": "g", "codes": ["PROT625"],
                  "names": ["Protein (Nx6,25)", "Protein (N x 6,25)", "Protein", "Protein (N x 6.25)"]},
    "fat_g":     {"required": True,  "unit": "g", "codes": ["FAT"],
                  "names": ["Fett", "Fat"]},
    "sat_fat_g": {"required": False, "unit": "g", "codes": ["FASAT"],
                  "names": ["Fettsäuren, gesättigt", "Fatty acids, saturated"]},
    "carbs_g":   {"required": True,  "unit": "g", "codes": ["CHO", "CHOAVL"],
                  "names": ["Kohlenhydrate, verfügbar", "Kohlenhydrate", "Carbohydrates, available"]},
    "sugar_g":   {"required": False, "unit": "g", "codes": ["SUGAR", "MDSA", "MDS"],
                  "names": ["Zucker", "Zucker (Summe)", "Mono- und Disaccharide", "Sugars, total", "Sugar"]},
    "fiber_g":   {"required": True,  "unit": "g", "codes": ["FIBT"],
                  "names": ["Ballaststoffe", "Ballaststoffe, gesamt", "Fibre, total", "Dietary fibre"]},
    "salt_g":    {"required": False, "unit": "g", "codes": ["NACL"],
                  "names": ["Salz (NaCl)", "Kochsalz", "Natriumchlorid", "Salt (NaCl)", "Salt"]},
}
SODIUM = {"unit": "mg", "codes": ["NA"], "names": ["Natrium", "Sodium"]}


class MappingError(Exception):
    """Zuordnung eines Naehrwerts zu Components-/Datenspalte nicht eindeutig oder nicht moeglich."""


def clean(value):
    """Zelle als bereinigter String ('' fuer leere Zellen/NaN)."""
    if value is None:
        return ""
    if isinstance(value, float):
        if value != value:  # NaN
            return ""
        if value.is_integer():
            return str(int(value))
    return str(value).strip()


def to_float(value):
    """Zahl aus einer Excel-Zelle (auch '12,5' als Text); nicht lesbare Marker ('-', 'n.b.', 'Sp.') ergeben None."""
    if value is None:
        return None
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return None if value != value else float(value)
    s = str(value).strip().replace(",", ".")
    if not s:
        return None
    try:
        return float(s)
    except ValueError:
        return None


def sql_text(value):
    return "null" if value is None else "'" + value.replace("'", "''") + "'"


def sql_num(value):
    if value is None:
        return "null"
    s = f"{value:.3f}"
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return "0" if s in ("", "-0") else s


def components_columns(components):
    """Findet Code-, Einheit- und Namensspalten der Components-Tabelle anhand der Ueberschriften."""
    headers = {col: clean(col).casefold() for col in components.columns}
    code_col = next((c for c, h in headers.items() if re.fullmatch(r"(bls[\s_-]*)?(code|komponente|component)", h)), None)
    code_col = code_col if code_col is not None else components.columns[0]
    unit_col = next((c for c, h in headers.items() if re.search(r"einheit|unit", h)), None)
    name_cols = [c for c, h in headers.items()
                 if c != code_col and c != unit_col and re.search(r"name|bezeichnung|deutsch|german|englisch|english", h)]
    if not name_cols:
        name_cols = [c for c in components.columns if c != code_col and c != unit_col]
    return code_col, unit_col, name_cols


def pick_component(components, rules, key):
    """Liefert (code, unit) der eindeutig passenden Components-Zeile oder None, wenn nichts passt.

    Wirft MappingError bei mehreren verschiedenen Treffern in derselben Stufe -- nie raten.
    """
    code_col, unit_col, name_cols = components_columns(components)
    for stage, wanted in (("Code", rules["codes"]), ("Name", rules["names"])):
        wanted_cf = {w.casefold() for w in wanted}
        hits = []
        for _, row in components.iterrows():
            code = clean(row[code_col])
            if not code:
                continue
            if stage == "Code":
                matched = code.casefold() in wanted_cf
            else:
                matched = any(clean(row[c]).casefold() in wanted_cf for c in name_cols)
            if matched:
                unit = clean(row[unit_col]) if unit_col is not None else ""
                hits.append((code, unit))
        distinct = sorted(set(hits))
        if len(distinct) == 1:
            return distinct[0]
        if len(distinct) > 1:
            raise MappingError(f"{key}: mehrere Treffer ueber {stage} {wanted}: {distinct}")
    return None


def keyword_candidates(components, rules, limit=10):
    """Fuer die Fehlermeldung: Components-Zeilen, die ein Stichwort des Naehrwerts enthalten."""
    code_col, unit_col, name_cols = components_columns(components)
    words = [w.casefold() for w in rules["codes"] + [n.split()[0] for n in rules["names"]]]
    out = []
    for _, row in components.iterrows():
        cells = [clean(row[c]).casefold() for c in [code_col] + name_cols]
        if any(w and w in cell for w in words for cell in cells):
            out.append((clean(row[code_col]), [clean(row[c]) for c in name_cols], clean(row[unit_col]) if unit_col is not None else ""))
        if len(out) >= limit:
            break
    return out


def find_value_column(data_columns, code):
    """Spalte der Daten-Tabelle mit dem Wert je 100 g fuer einen Komponentencode (nicht Datenherkunft/Referenz)."""
    pattern = re.compile(rf"^{re.escape(code)}(?![A-Za-z0-9])", re.IGNORECASE)
    skip = re.compile(r"herkunft|referenz|origin|reference|source", re.IGNORECASE)
    hits = [c for c in data_columns if pattern.match(clean(c)) and not skip.search(clean(c))]
    if len(hits) == 1:
        return hits[0]
    raise MappingError(f"Wertspalte fuer Code {code}: {len(hits)} Treffer in den Daten ({hits[:5]}), erwartet genau 1")


def find_identity_columns(data_columns):
    wanted = {"code": ["bls code", "bls-code", "code"], "name_de": ["lebensmittelbezeichnung"], "name_en": ["food name"]}
    found = {}
    for key, names in wanted.items():
        for c in data_columns:
            if clean(c).casefold() in names:
                found[key] = c
                break
    missing = [k for k in ("code", "name_de") if k not in found]
    if missing:
        raise MappingError(f"Spalten {missing} in den Daten nicht gefunden. Vorhandene Anfangsspalten: "
                           f"{[clean(c) for c in list(data_columns)[:8]]}")
    return found


def resolve_mapping(components, data_columns):
    """Ordnet alle Naehrwerte Komponentencode, Einheit und Wertspalte zu. Gibt (mapping, warnings) zurueck."""
    mapping, warnings = {}, []
    for key, rules in NUTRIENTS.items():
        picked = pick_component(components, rules, key)
        if picked is None and key == "salt_g":
            sodium = pick_component(components, SODIUM, "natrium")
            if sodium is None:
                if rules["required"]:
                    raise MappingError("salt_g: weder Salz noch Natrium gefunden")
                warnings.append("salt_g: weder Salz- noch Natrium-Spalte gefunden, salt_g bleibt NULL")
                continue
            code, unit = sodium
            mapping[key] = {"code": code, "unit": unit or SODIUM["unit"], "column": find_value_column(data_columns, code),
                            "derived_from_sodium": True}
            warnings.append(f"salt_g: aus Natrium ({code}) abgeleitet (x{SODIUM_TO_SALT}), kein direkter Salz-Wert in den Daten")
            continue
        if picked is None:
            if rules["required"]:
                cands = keyword_candidates(components, rules)
                raise MappingError(f"{key}: keine Zuordnung ueber Code {rules['codes']} oder Name {rules['names']}. "
                                   f"Aehnliche Components-Zeilen (Code, Namen, Einheit): {cands}")
            warnings.append(f"{key}: keine Zuordnung gefunden, bleibt NULL")
            continue
        code, unit = picked
        if unit and unit.casefold() != rules["unit"].casefold():
            raise MappingError(f"{key}: Einheit in Components ist '{unit}', erwartet '{rules['unit']}' (Code {code})")
        mapping[key] = {"code": code, "unit": unit or rules["unit"], "column": find_value_column(data_columns, code),
                        "derived_from_sodium": False}
    return mapping, warnings


def build_rows(components, data):
    """Wandelt die Roh-Tabellen in Zeilen fuer bls_foods. Gibt (rows, mapping, warnings, stats) zurueck."""
    ident = find_identity_columns(data.columns)
    mapping, warnings = resolve_mapping(components, data.columns)
    rows, null_counts, implausible = [], {k: 0 for k in NUTRIENTS}, []
    for _, rec in data.iterrows():
        code = clean(rec[ident["code"]])
        name_de = clean(rec[ident["name_de"]])
        if not code or not name_de:
            continue
        values = {}
        for key in NUTRIENTS:
            m = mapping.get(key)
            raw = to_float(rec[m["column"]]) if m else None
            if raw is not None and m["derived_from_sodium"]:
                # Natrium liegt in mg vor: mg -> g, dann x 2,5
                raw = raw / 1000 * SODIUM_TO_SALT if m["unit"].casefold() == "mg" else raw * SODIUM_TO_SALT
            values[key] = raw
            if raw is None:
                null_counts[key] += 1
        macros = [values[k] for k in ("protein_g", "fat_g", "carbs_g") if values[k] is not None]
        if (values["kcal"] is not None and values["kcal"] > 950) or any(v > 100.5 for v in macros) \
                or any(v is not None and v < 0 for v in values.values()):
            implausible.append((code, name_de, values["kcal"]))
        rows.append((code, name_de, clean(rec[ident["name_en"]]) if "name_en" in ident else "", values))
    stats = {"rows": len(rows), "null_counts": null_counts, "implausible": implausible}
    return rows, mapping, warnings, stats


def write_sql(rows, out_path, batch=500):
    cols = "bls_code, name_de, name_en, " + ", ".join(NUTRIENTS)
    updates = ", ".join(f"{c} = excluded.{c}" for c in ["name_de", "name_en", *NUTRIENTS]) + ", imported_at = now()"
    lines = [f"-- {ATTRIBUTION}",
             "-- Erzeugt von tools/import_bls_foods.py -- nicht von Hand aendern, bei Bedarf neu erzeugen.",
             "-- Einspielen: npx supabase db query --linked --file tools/bls_foods_import.sql", ""]
    for i in range(0, len(rows), batch):
        chunk = rows[i:i + batch]
        values = ",\n".join(
            "  (" + ", ".join([sql_text(code), sql_text(name_de), sql_text(name_en or None),
                               *[sql_num(v[k]) for k in NUTRIENTS]]) + ")"
            for code, name_de, name_en, v in chunk)
        lines.append(f"insert into public.bls_foods ({cols}) values\n{values}\non conflict (bls_code) do update set {updates};\n")
    out_path.write_text("\n".join(lines), encoding="utf-8")


def print_mapping(mapping, warnings):
    print("Zuordnung der Naehrwerte (je 100 g):")
    for key in NUTRIENTS:
        m = mapping.get(key)
        if m:
            extra = "  [aus Natrium abgeleitet]" if m["derived_from_sodium"] else ""
            print(f"  {key:10s} Code {m['code']:10s} Einheit {m['unit']:5s} Spalte '{clean(m['column'])}'{extra}")
        else:
            print(f"  {key:10s} (keine Zuordnung)")
    for w in warnings:
        print("  WARNUNG:", w)


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="BLS 4.0 nach tools/bls_foods_import.sql umwandeln")
    parser.add_argument("--source-dir", type=Path, default=DEFAULT_SOURCE, help="Ordner mit den entpackten BLS-Excel-Dateien")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="Ziel der erzeugten SQL-Datei")
    parser.add_argument("--inspect", action="store_true", help="Nur Zuordnung und Stichprobe zeigen, nichts schreiben")
    args = parser.parse_args()

    import pandas as pd

    data_path, comp_path = args.source_dir / DATA_FILE, args.source_dir / COMPONENTS_FILE
    for p in (data_path, comp_path):
        if not p.exists():
            sys.exit(f"Datei fehlt: {p}\nBLS_4_0_2025_DE.zip von https://blsdb.de/assets/uploads/BLS_4_0_2025_DE.zip "
                     f"laden und nach {args.source_dir} entpacken.")
    print("Lese Excel-Dateien (kann bei 7140 Zeilen x 418 Spalten etwas dauern)...")
    components = pd.read_excel(comp_path, dtype=object)
    data = pd.read_excel(data_path, dtype=object)
    print(f"Components: {len(components)} Zeilen, Spalten {[clean(c) for c in components.columns]}")
    print(f"Daten: {len(data)} Zeilen, {len(data.columns)} Spalten")

    try:
        rows, mapping, warnings, stats = build_rows(components, data)
    except MappingError as e:
        sys.exit(f"ABBRUCH, Zuordnung nicht eindeutig: {e}\nMit --inspect die Struktur ansehen und NUTRIENTS im Skript anpassen.")

    print_mapping(mapping, warnings)
    print(f"\n{stats['rows']} Zeilen ausgewertet.")
    for key, n in stats["null_counts"].items():
        print(f"  {key:10s} ohne Wert: {n}")
    if stats["implausible"]:
        print(f"  {len(stats['implausible'])} auffaellige Zeilen (kcal > 950, Makro > 100 g oder negativ), erste 10:")
        for code, name, kcal in stats["implausible"][:10]:
            print(f"    {code}  {name}  kcal={kcal}")
    print("\nStichprobe (erste 3 Zeilen):")
    for code, name_de, name_en, v in rows[:3]:
        print(f"  {code}  {name_de} / {name_en}: " + ", ".join(f"{k}={sql_num(v[k])}" for k in NUTRIENTS))

    if args.inspect:
        print("\n--inspect: nichts geschrieben.")
        return
    write_sql(rows, args.out)
    print(f"\n{args.out} geschrieben ({stats['rows']} Zeilen).")
    print("Naechster Schritt: Stichprobe pruefen, dann npx supabase db query --linked --file", args.out)


if __name__ == "__main__":
    main()
