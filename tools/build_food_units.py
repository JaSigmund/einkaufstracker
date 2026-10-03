#!/usr/bin/env python3
"""Stueckgewichte und Haushaltsmasse fuer die Naehrwert-Zuordnung (Phase N2, ADR-033).

Zwei Schritte, getrennt, damit die CI ohne die grossen USDA-Dateien pruefen kann:

1. ``--usda <SR-Ordner> [--ff <Foundation-Ordner>]``  baut ``tools/food_units.csv`` aus den Portionsgewichten der USDA FoodData
   Central (``food_portion.csv``, US-Public-Domain) anhand der gepflegten Zuordnung ``tools/food_units_map.csv`` (BLS-Code ->
   USDA-Eintrag). Die Rohdateien werden nicht eingecheckt (Download: https://fdc.nal.usda.gov/download-datasets/, SR Legacy
   2018-04 und Foundation Foods). Das Skript prueft:
   - gibt es einen zweiten USDA-Eintrag, wird er verglichen, mehr als 20 % Abweichung: Wert wird NICHT uebernommen
   - mehrdeutige Angaben (zwei Werte derselben Einheit) nur, wenn sie hoechstens 30 % auseinanderliegen (dann Mittelwert)
   - Erwartungswerte aus Alltagswissen (``tools/food_units_expect.csv``): Abweichungen ueber 20 % werden gemeldet, nicht still
     uebernommen oder verworfen, sie gehen in die Pruefliste (``--report``)
2. ohne Parameter (oder ``--check``): erzeugt ``tools/food_units_import.sql`` aus ``tools/food_units.csv`` und prueft gegen die
   echte BLS (``tools/bls_foods_import.sql``), dass jeder BLS-Code existiert. ``--check`` schreibt nichts und schlaegt fehl, wenn
   die SQL-Datei nicht zur CSV passt (CI).

Das Skript fuehrt NICHTS gegen die Datenbank aus. Einspielen (nach der Migration 0024):
    npx supabase db query --linked --file tools/food_units_import.sql

Die USDA-Gewichte gelten fuer den essbaren Anteil (Banane ohne Schale), genau das, worauf sich die BLS-Naehrwerte beziehen.
Quelle in der Datenbank: ``usda`` (Gewicht unveraendert), ``curated`` (mit Faktor umgerechnet, z.B. Schaelverlust).
"""
import argparse
import csv
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAP_CSV = ROOT / "tools" / "food_units_map.csv"
EXPECT_CSV = ROOT / "tools" / "food_units_expect.csv"
UNITS_CSV = ROOT / "tools" / "food_units.csv"
BLS_SQL = ROOT / "tools" / "bls_foods_import.sql"
OUT_SQL = ROOT / "tools" / "food_units_import.sql"

UNIT_KEYS = {"piece", "slice", "tbsp", "tsp", "clove", "head", "stalk"}
SIZED_UNITS = {"piece", "head", "stalk"}
SIZES = {"small", "medium", "large"}
MAX_SPREAD = 1.30  # mehrdeutige Angaben derselben Einheit: groesster durch kleinster Wert
MAX_CROSS_DEVIATION = 0.20  # zwei Quellen, ADR-033

# Angaben, die keine Haushaltseinheit sind (amerikanische Mengen, Verpackungen, Teile)
NOT_A_UNIT = re.compile(
    r"^(cups?|oz|lb|fl oz|ml|liter|pint|quart|gallon|can|package|container|bottle|jar|packet|serving|nlea|individual|bunch|wedge|"
    r"cubic inch|ring|strips?|leaf|leaves|floweret|pat|glass|dash|grams?|unit|yields?|sprigs?|milliliter|block|drink box|"
    r"box|miniature box|small box|bag|bar|undetermined|tablespoons? label|slice,? thin|slice,? snack)\b",
    re.I,
)
SIZE_WORD = re.compile(r"\b(extra small|extra large|small|medium|large|mini|jumbo)\b", re.I)


def classify(modifier: str):
    """(unit_key, size) einer USDA-Portionsangabe oder None, wenn sie keine Haushaltseinheit ist."""
    m = modifier.strip().lower()
    if not m or m == "?":
        return None
    if re.search(r"\b(thin|snack-size|snack size)\b", m) and m.startswith("slice"):
        return None
    if re.match(r"^(tbsp|tablespoons?)\b", m):
        return "tbsp", ""
    if re.match(r"^(tsp|teaspoons?)\b", m):
        return "tsp", ""
    if re.match(r"^slices?\b", m):
        return "slice", ""
    if re.match(r"^clove", m):
        return "clove", ""
    if NOT_A_UNIT.match(m):
        return None
    unit = "piece"
    if re.match(r"^head\b", m):
        unit = "head"
    elif re.match(r"^(stalk|spear)\b", m):
        unit = "stalk"
    size_match = SIZE_WORD.search(m)
    size = size_match.group(1).lower() if size_match else ""
    return unit, size


def load_portions(folder: Path):
    """fdc_id -> [(Angabe, Gramm je Einheit)] aus food_portion.csv; Beschreibung aus food.csv."""
    desc = {r["fdc_id"]: r["description"] for r in csv.DictReader(open(folder / "food.csv", encoding="utf-8"))}
    por = defaultdict(list)
    for r in csv.DictReader(open(folder / "food_portion.csv", encoding="utf-8")):
        try:
            grams = float(r["gram_weight"])
            amount = float(r["amount"] or 1) or 1.0
        except ValueError:
            continue
        por[r["fdc_id"]].append(((r["modifier"] or r["portion_description"] or "").strip(), grams / amount))
    return desc, por


def units_of(portions, flt: str, size_map: dict, unit_override: str = ""):
    """(unit, size) -> Liste von Gramm, nach Filter, Klassifikation und Groessen-Umbenennung."""
    out = defaultdict(list)
    rx = re.compile(flt, re.I) if flt else None
    for modifier, grams in portions:
        if rx and not rx.search(modifier):
            continue
        c = classify(modifier)
        if not c:
            continue
        unit, size = c
        if unit_override:
            unit = unit_override
        if unit not in SIZED_UNITS:
            size = ""
        elif size_map:
            if size not in size_map:
                continue
            size = size_map[size]
        elif size not in SIZES and size != "":
            continue  # extra small, extra large, mini, jumbo
        if not 0.2 <= grams <= 5000:
            continue
        out[(unit, size)].append(grams)
    # eine Angabe ohne Groesse neben benannten Groessen ist die mittlere
    for unit in SIZED_UNITS:
        sized = {s for (u, s) in out if u == unit and s}
        if (unit, "") in out and sized and "medium" not in sized:
            out[(unit, "medium")] = out.pop((unit, ""))
        elif (unit, "") in out and sized:
            out.pop((unit, ""))
    return out


def merge(values, label, report):
    lo, hi = min(values), max(values)
    if hi / lo > MAX_SPREAD:
        report.append(f"verworfen (mehrdeutig, {lo:g} bis {hi:g} g): {label}")
        return None
    return sum(values) / len(values)


def build(args):
    sr_desc, sr_por = load_portions(Path(args.usda))
    ff_desc, ff_por = load_portions(Path(args.ff)) if args.ff else ({}, {})
    desc = {**sr_desc, **ff_desc}
    por = {**sr_por, **ff_por}
    expect = {}
    if EXPECT_CSV.exists():
        for r in csv.DictReader(open(EXPECT_CSV, encoding="utf-8")):
            expect[(r["bls_code"], r["unit_key"], r["size"])] = (float(r["grams"]), r["note"])
    rows, report = [], []
    for r in csv.DictReader(open(MAP_CSV, encoding="utf-8")):
        code = r["bls_code"]
        size_map = dict(p.split(":") for p in r["size_map"].split(";")) if r["size_map"] else {}
        factor = float(r["factor"]) if r["factor"] else 1.0
        if r["fdc_id"] not in por:
            report.append(f"{code}: USDA-Eintrag {r['fdc_id']} hat keine Portionen")
        first = units_of(por.get(r["fdc_id"], []), r["filter"], size_map, r["unit"])
        second = units_of(por.get(r["fdc_id2"], []), r["filter"], size_map, r["unit"]) if r["fdc_id2"] else {}
        if not first:
            report.append(f"{code}: keine passende Haushaltseinheit in {r['fdc_id']} ({desc.get(r['fdc_id'], '?')[:50]})")
        for (unit, size), values in sorted(first.items()):
            label = f"{code} {unit} {size or '-'} ({desc.get(r['fdc_id'], '?')[:40]})"
            grams = merge(values, label, report)
            if grams is None:
                continue
            if (unit, size) in second:
                other = merge(second[(unit, size)], label + " (zweite Quelle)", report)
                if other is not None and abs(grams - other) / max(grams, other) > MAX_CROSS_DEVIATION:
                    report.append(f"verworfen (zwei Quellen {grams:g} gegen {other:g} g): {label}")
                    continue
            grams_final = round(grams * factor, 1)
            source = "usda" if factor == 1.0 else "curated"
            exp = expect.get((code, unit, size))
            if exp and abs(grams_final - exp[0]) / exp[0] > 0.20:
                report.append(f"PRUEFEN {label}: {grams_final:g} g, erwartet etwa {exp[0]:g} g ({exp[1]})")
            rows.append((code, unit, size, grams_final, source, r["note"]))
    rows.sort()
    with open(UNITS_CSV, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["bls_code", "unit_key", "size", "grams_edible", "source", "note"])
        w.writerows(rows)
    print(f"{len(rows)} Einheiten fuer {len({r[0] for r in rows})} Lebensmittel geschrieben")
    if args.report:
        Path(args.report).write_text("\n".join(report) + "\n", encoding="utf-8")
    for line in report:
        print(" -", line)


def read_bls_codes():
    codes = set(re.findall(r"^\s*\('([A-Z0-9]{7})',", BLS_SQL.read_text(encoding="utf-8"), re.M))
    if len(codes) < 7000:
        sys.exit(f"BLS-Codes in {BLS_SQL} nicht lesbar ({len(codes)})")
    return codes


def sql_text(rows):
    def q(v):
        return "'" + str(v).replace("'", "''") + "'"

    lines = [
        "-- Stueckgewichte und Haushaltsmasse (Phase N2, ADR-033), erzeugt von tools/build_food_units.py aus tools/food_units.csv.",
        "-- Quelle der Gewichte: USDA FoodData Central (SR Legacy 2018-04, Foundation Foods), US-Public-Domain, geprueft und zugeordnet.",
        "-- Nicht von Hand aendern. Einspielen: npx supabase db query --linked --file tools/food_units_import.sql",
        "",
        "insert into public.food_units (bls_code, unit_key, size, grams_edible, source, note) values",
    ]
    vals = [f"  ({q(c)}, {q(u)}, {q(s)}, {g:g}, {q(src)}, {q(n)})" for c, u, s, g, src, n in rows]
    lines.append(",\n".join(vals))
    lines.append("on conflict (bls_code, unit_key, size) do update set grams_edible = excluded.grams_edible, source = excluded.source, note = excluded.note;")
    return "\n".join(lines) + "\n"


def emit(check: bool):
    codes = read_bls_codes()
    rows = []
    seen = set()
    for r in csv.DictReader(open(UNITS_CSV, encoding="utf-8")):
        key = (r["bls_code"], r["unit_key"], r["size"])
        if key in seen:
            sys.exit(f"doppelt: {key}")
        seen.add(key)
        if r["bls_code"] not in codes:
            sys.exit(f"BLS-Code {r['bls_code']} gibt es nicht")
        if r["unit_key"] not in UNIT_KEYS:
            sys.exit(f"unbekannte Einheit {r['unit_key']}")
        if r["size"] not in SIZES | {""}:
            sys.exit(f"unbekannte Groesse {r['size']}")
        if r["size"] and r["unit_key"] not in SIZED_UNITS:
            sys.exit(f"Groesse bei {r['unit_key']} nicht vorgesehen: {key}")
        grams = float(r["grams_edible"])
        if not 0.2 <= grams <= 5000:
            sys.exit(f"unplausibles Gewicht {grams} bei {key}")
        if r["source"] not in ("usda", "off", "curated", "llm_estimate"):
            sys.exit(f"unbekannte Quelle {r['source']}")
        rows.append((r["bls_code"], r["unit_key"], r["size"], grams, r["source"], r["note"]))
    text = sql_text(rows)
    if check:
        if not OUT_SQL.exists() or OUT_SQL.read_text(encoding="utf-8") != text:
            sys.exit("tools/food_units_import.sql passt nicht zu tools/food_units.csv: python tools/build_food_units.py")
        print(f"OK: {len(rows)} Einheiten, {len({r[0] for r in rows})} Lebensmittel")
    else:
        OUT_SQL.write_text(text, encoding="utf-8", newline="\n")
        print(f"{OUT_SQL.name}: {len(rows)} Einheiten fuer {len({r[0] for r in rows})} Lebensmittel")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--usda", help="Ordner der entpackten SR-Legacy-CSV (food.csv, food_portion.csv)")
    ap.add_argument("--ff", help="Ordner der entpackten Foundation-Foods-CSV (zweite Quelle)")
    ap.add_argument("--report", help="Datei fuer die Pruefliste")
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    if args.usda:
        build(args)
    emit(args.check)


if __name__ == "__main__":
    main()
