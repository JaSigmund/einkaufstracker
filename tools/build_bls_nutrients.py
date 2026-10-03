#!/usr/bin/env python3
"""Register der Mikronaehrstoffe und BLS-Import der 38 Werte (Phase N3, ADR-032).

Quelle der Wahrheit ist ``tools/nutrient_registry.json`` (Schluessel, Name, Gruppe, Einheit, Nachkommastellen, BLS-Code,
Umrechnung, EU-Referenzmenge). Daraus entstehen:

1. ``app/lib/domain/nutrition/nutrient_registry.dart``   (immer, auch ohne BLS-Dateien)
2. ``tools/bls_nutrients_import.sql``                     (nur mit ``--source-dir``: liest die BLS-Excel-Dateien)

``--check`` schreibt nichts: es prueft, dass die Dart-Datei zur JSON passt und die SQL-Datei jeden Registerschluessel kennt (CI,
ohne die grossen BLS-Dateien).

Regeln fuer die Werte (nie raten):
- Datenherkunft ``-`` oder Wert ``-``/leer: der Schluessel fehlt (unbekannt, NICHT 0)
- ``<LOD``, ``<LOQ``, ``<LOD or <LOQ`` (unter der Bestimmungsgrenze), ``TR`` (Spuren) und der Wert ``0``: ``0``
- Einheiten der BLS-Spalte muessen zur Registerangabe passen (``bls_unit``), sonst Abbruch; ``factor`` rechnet in die Registereinheit
  um (Vitamin B6, Kupfer, Mangan, Fluorid: ug -> mg)

Quelle:  https://blsdb.de/assets/uploads/BLS_4_0_2025_DE.zip (entpackt nach tools/BLS_4_0_2025_DE/)
Lizenz:  CC BY 4.0 -- Max Rubner-Institut (2025): Bundeslebensmittelschluessel (BLS), Version 4.0 -- Deutsche Naehrstoffdatenbank.

Das Skript fuehrt NICHTS gegen die Datenbank aus. Einspielen (nach der Migration 0025):
    npx supabase db query --linked --file tools/bls_nutrients_import.sql

Aufruf:
    python tools/build_bls_nutrients.py --source-dir tools/BLS_4_0_2025_DE   # Dart und SQL erzeugen
    python tools/build_bls_nutrients.py                                      # nur die Dart-Datei
    python tools/build_bls_nutrients.py --check                              # CI
"""
import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REGISTRY = ROOT / "tools" / "nutrient_registry.json"
DART_OUT = ROOT / "app" / "lib" / "domain" / "nutrition" / "nutrient_registry.dart"
SQL_OUT = ROOT / "tools" / "bls_nutrients_import.sql"
DATA_FILE = "BLS_4_0_Daten_2025_DE.xlsx"
COMPONENTS_FILE = "BLS_4_0_Components_DE_EN.xlsx"
ATTRIBUTION = ("Max Rubner-Institut (2025): Bundeslebensmittelschlüssel (BLS), Version 4.0 — "
               "Deutsche Nährstoffdatenbank (CC BY 4.0)")
BELOW_LIMIT = re.compile(r"^(<\s*(lod|loq).*|tr)$", re.IGNORECASE)

GROUPS_DART = {"vitamin": "NutrientGroup.vitamin", "mineral": "NutrientGroup.mineral", "fat": "NutrientGroup.fat", "other": "NutrientGroup.other"}


def load_registry():
    doc = json.loads(REGISTRY.read_text(encoding="utf-8"))
    items = doc["nutrients"]
    keys = [i["key"] for i in items]
    if len(set(keys)) != len(keys):
        sys.exit("Registerschluessel doppelt")
    groups = {g["key"] for g in doc["groups"]}
    for i in items:
        if i["group"] not in groups:
            sys.exit(f"{i['key']}: unbekannte Gruppe {i['group']}")
        if not re.fullmatch(r"[a-z0-9]+(_[a-z0-9]+)*_(g|mg|ug)", i["key"]):
            sys.exit(f"{i['key']}: der Schluessel muss mit der Einheit enden (g, mg, ug)")
        unit_suffix = i["key"].rsplit("_", 1)[1]
        if {"g": "g", "mg": "mg", "ug": "µg"}[unit_suffix] != i["unit"]:
            sys.exit(f"{i['key']}: Einheit {i['unit']} passt nicht zum Schluessel")
    return doc


def dart_str(s):
    return "'" + s.replace("\\", "\\\\").replace("'", "\\'") + "'"


def dart_text(doc):
    lines = [
        "// GENERIERT von tools/build_bls_nutrients.py aus tools/nutrient_registry.json -- nicht von Hand aendern.",
        "// Register der Mikronaehrstoffe (Phase N3, ADR-032): Schluessel, Name, Gruppe, Einheit, Nachkommastellen und die",
        "// Kennzeichnungs-Referenzmenge (Verordnung (EU) Nr. 1169/2011 Anhang XIII Teil A, Erwachsene; keine Empfehlung).",
        "library;",
        "",
        "enum NutrientGroup {",
    ]
    labels = {g["key"]: g["label_de"] for g in doc["groups"]}
    lines += [f"  {g['key']}({dart_str(g['label_de'])})," for g in doc["groups"]]
    lines[-1] = lines[-1][:-1] + ";"
    lines += ["", "  const NutrientGroup(this.label);", "  final String label;", "}", "",
              "class NutrientDef {",
              "  const NutrientDef({required this.key, required this.label, required this.group, required this.unit, required this.decimals, this.euReference, this.featured = false});",
              "",
              "  /// Schluessel in `bls_foods.nutrients`, `meal_ingredients.micros` und `products.nutrients_per_100` (Einheit steht im Schluessel).",
              "  final String key;",
              "  final String label;",
              "  final NutrientGroup group;",
              "  final String unit;",
              "  final int decimals;",
              "",
              "  /// Kennzeichnungs-Referenzmenge fuer Erwachsene in [unit] oder `null`.",
              "  final double? euReference;",
              "",
              "  /// In der Vorauswahl der Seite \"Nährstoffe\" sichtbar (die zwoelf haeufig gefragten).",
              "  final bool featured;",
              "}",
              "",
              "/// Alle Mikronaehrstoffe in Anzeigereihenfolge (Gruppe, dann wie in der Tabelle der Doku).",
              "const nutrientRegistry = <NutrientDef>["]
    for i in doc["nutrients"]:
        ref = "null" if i["eu_reference"] is None else repr(float(i["eu_reference"]))
        lines.append(
            f"  NutrientDef(key: {dart_str(i['key'])}, label: {dart_str(i['label_de'])}, group: {GROUPS_DART[i['group']]}, "
            f"unit: {dart_str(i['unit'])}, decimals: {i['decimals']}"
            + ("" if ref == "null" else f", euReference: {ref}") + (", featured: true" if i["featured"] else "") + "),")
    lines += ["];", "", "final _byKey = {for (final n in nutrientRegistry) n.key: n};", "",
              "/// Die Definition zu einem Schluessel, `null` bei unbekanntem.",
              "NutrientDef? nutrientDef(String key) => _byKey[key];", "",
              "/// Schluessel aller Mikronaehrstoffe.",
              "final nutrientKeys = [for (final n in nutrientRegistry) n.key];", ""]
    del labels
    return "\n".join(lines)


def clean(v):
    if v is None:
        return ""
    if isinstance(v, float):
        if v != v:
            return ""
        if v.is_integer():
            return str(int(v))
    return str(v).strip()


def sql_num(v):
    s = f"{v:.4f}".rstrip("0").rstrip(".")
    return "0" if s in ("", "-0") else s


def components_info(components):
    headers = {c: clean(c).casefold() for c in components.columns}
    code_col = next((c for c, h in headers.items() if "code" in h), None)
    unit_col = next((c for c, h in headers.items() if re.search(r"einheit|unit", h)), None)
    if code_col is None or unit_col is None:
        sys.exit(f"Components-Tabelle: Code- oder Einheitsspalte fehlt, Ueberschriften {list(headers.values())}")
    return {clean(r[code_col]): clean(r[unit_col]) for _, r in components.iterrows() if clean(r[code_col])}


def unit_equal(a, b):
    norm = lambda u: u.replace("µ", "u").replace("μ", "u").replace("µ", "u").casefold()  # noqa: E731
    return norm(a) == norm(b)


def value_columns(columns, code):
    pat = re.compile(rf"^{re.escape(code)}(?![A-Za-z0-9])", re.IGNORECASE)
    skip = re.compile(r"herkunft|referenz|origin|reference|source", re.IGNORECASE)
    hits = [c for c in columns if pat.match(clean(c)) and not skip.search(clean(c))]
    origin = [c for c in columns if pat.match(clean(c)) and re.search(r"herkunft|origin", clean(c), re.IGNORECASE)]
    if len(hits) != 1 or len(origin) != 1:
        sys.exit(f"{code}: {len(hits)} Wertspalten und {len(origin)} Herkunftsspalten, erwartet je genau 1")
    return hits[0], origin[0]


def value_of(raw, origin):
    """Zahl in der BLS-Einheit, 0.0 unter der Bestimmungsgrenze, None wenn unbekannt."""
    o = clean(origin)
    r = raw
    if isinstance(r, bool):
        return None
    if isinstance(r, (int, float)):
        if r != r:
            return None
        return None if o == "-" else float(r)
    s = clean(r)
    if not s or s == "-" or o == "-":
        return None
    if BELOW_LIMIT.match(s):
        return 0.0
    try:
        return float(s.replace(",", "."))
    except ValueError:
        return None


def build_sql(doc, source_dir):
    import pandas as pd
    components = pd.read_excel(source_dir / COMPONENTS_FILE, dtype=object, keep_default_na=False)
    data = pd.read_excel(source_dir / DATA_FILE, dtype=object, keep_default_na=False)
    units = components_info(components)
    code_col = next(c for c in data.columns if clean(c).casefold() in ("bls code", "bls-code", "code"))
    cols = {}
    for n in doc["nutrients"]:
        if n["bls_code"] not in units:
            sys.exit(f"{n['key']}: BLS-Code {n['bls_code']} steht nicht in der Components-Tabelle")
        if not unit_equal(units[n["bls_code"]].split("/")[0], n["bls_unit"]):
            sys.exit(f"{n['key']}: Einheit in der BLS ist '{units[n['bls_code']]}', erwartet '{n['bls_unit']}'")
        cols[n["key"]] = value_columns(list(data.columns), n["bls_code"])
    rows, missing = [], {n["key"]: 0 for n in doc["nutrients"]}
    for _, rec in data.iterrows():
        code = clean(rec[code_col])
        if not code:
            continue
        vals = {}
        for n in doc["nutrients"]:
            vcol, ocol = cols[n["key"]]
            v = value_of(rec[vcol], rec[ocol])
            if v is None:
                missing[n["key"]] += 1
            elif v < 0:
                sys.exit(f"{code} {n['key']}: negativer Wert {v}")
            else:
                vals[n["key"]] = round(v * n["factor"], 4)
        rows.append((code, vals))
    lines = [f"-- {ATTRIBUTION}",
             "-- Erzeugt von tools/build_bls_nutrients.py -- nicht von Hand aendern, bei Bedarf neu erzeugen.",
             "-- Die 38 Mikronaehrstoffe je 100 g aus tools/nutrient_registry.json; ein fehlender Schluessel heisst unbekannt, 0 ist eine echte Null.",
             "-- Einspielen (nach Migration 0025): npx supabase db query --linked --file tools/bls_nutrients_import.sql", ""]
    batch = 400
    for i in range(0, len(rows), batch):
        chunk = rows[i:i + batch]
        values = ",\n".join(
            "  ('" + code + "', '" + json.dumps(vals, separators=(",", ":"), sort_keys=True) + "'::jsonb)" for code, vals in chunk)
        lines.append("update public.bls_foods b set nutrients = v.n from (values\n" + values +
                     "\n) as v(code, n) where b.bls_code = v.code;\n")
    SQL_OUT.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    return rows, missing


def check_sql(doc):
    if not SQL_OUT.exists():
        sys.exit(f"{SQL_OUT.name} fehlt: python tools/build_bls_nutrients.py --source-dir tools/BLS_4_0_2025_DE")
    text = SQL_OUT.read_text(encoding="utf-8")
    keys = {n["key"] for n in doc["nutrients"]}
    used = set(re.findall(r'"([a-z0-9_]+_(?:g|mg|ug))":', text))
    if not used <= keys:
        sys.exit(f"{SQL_OUT.name} enthaelt Schluessel, die das Register nicht kennt: {sorted(used - keys)}")
    absent = keys - used
    if absent:
        sys.exit(f"{SQL_OUT.name} enthaelt keine Werte fuer: {sorted(absent)} (Register geaendert? neu erzeugen)")
    return text.count("::jsonb)")


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser()
    ap.add_argument("--source-dir", type=Path, help="Ordner mit den entpackten BLS-Excel-Dateien (erzeugt zusaetzlich die SQL-Datei)")
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    doc = load_registry()
    dart = dart_text(doc)
    if args.check:
        if not DART_OUT.exists() or DART_OUT.read_text(encoding="utf-8") != dart:
            sys.exit("nutrient_registry.dart passt nicht zu tools/nutrient_registry.json: python tools/build_bls_nutrients.py")
        n = check_sql(doc)
        print(f"OK: {len(doc['nutrients'])} Naehrstoffe, {n} Lebensmittel in der SQL-Datei")
        return
    DART_OUT.write_text(dart, encoding="utf-8", newline="\n")
    print(f"{DART_OUT.relative_to(ROOT)}: {len(doc['nutrients'])} Naehrstoffe")
    if args.source_dir:
        rows, missing = build_sql(doc, args.source_dir)
        print(f"{SQL_OUT.relative_to(ROOT)}: {len(rows)} Lebensmittel")
        for key, n in missing.items():
            print(f"  {key:16s} ohne Wert: {n:5d} ({100 * n / len(rows):.1f} %)")


if __name__ == "__main__":
    main()
