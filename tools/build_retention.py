#!/usr/bin/env python3
"""Garfaktoren (Phase N4, ADR-037): Verluste von Vitaminen und Mineralstoffen beim Garen, aus der USDA Table of Nutrient Retention Factors.

Quelle: USDA Table of Nutrient Retention Factors, Release 6 (2007), Agricultural Research Service, Ag Data Commons,
DOI 10.15482/USDA.ADC/1409034, Lizenz CC0 1.0 (gemeinfrei). Dateien: NutrientRetention.csv (472.734 Byte) und NutrientRetentionDD.csv
(Datenwoerterbuch). Die Rohdateien werden nicht eingecheckt.

Zwei Schritte, getrennt, damit die CI ohne die Rohdatei pruefen kann:

1. ``--usda <Ordner>``  liest ``NutrientRetention.csv`` und schreibt ``tools/retention_factors.csv`` mit den Faktoren (Prozent, wie viel
   des Naehrstoffs nach dem Garen noch da ist, bezogen auf das Rohgewicht) fuer genau die Eintraege und Naehrstoffe, die in
   ``tools/retention_rules.json`` stehen. Fehlt ein Eintrag oder ein Naehrstoff, bricht das Skript ab.
2. ohne Parameter  erzeugt ``app/lib/domain/nutrition/retention_data.dart`` aus ``tools/retention_factors.csv`` und
   ``tools/retention_rules.json`` (Zuordnung Kategorie x Zubereitung -> USDA-Eintrag, BLS-Regeln). ``--check`` schreibt nichts und
   schlaegt fehl, wenn die Datei nicht passt (CI). ``--report`` zeigt, welche BLS-Eintraege zu welcher Kategorie gehoeren und welche
   rohen Eintraege der Gruppen G, K, C, E, T, U, V keine Kategorie haben (zur Sichtkontrolle).

Das Skript fuehrt nichts gegen die Datenbank aus: die Faktoren liegen als Konstanten in der App, es gibt keine Migration.
"""
import argparse
import csv
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RULES = ROOT / "tools" / "retention_rules.json"
FACTORS = ROOT / "tools" / "retention_factors.csv"
REGISTRY = ROOT / "tools" / "nutrient_registry.json"
BLS_SQL = ROOT / "tools" / "bls_foods_import.sql"
OUT = ROOT / "app" / "lib" / "domain" / "nutrition" / "retention_data.dart"

CSV_FIELDS = ["retn_code", "retn_desc", "nutr_no", "nutrient_key", "factor_percent"]


def load_rules():
    return json.loads(RULES.read_text(encoding="utf-8"))


def used_codes(spec):
    return sorted({code for methods in spec["methods"].values() for code in methods.values()})


def step_usda(folder: Path):
    spec = load_rules()
    src = folder / "NutrientRetention.csv"
    if not src.exists():
        sys.exit(f"{src} fehlt")
    codes = set(used_codes(spec))
    nutrients = spec["nutrients"]
    registry_keys = {n["key"] for n in json.loads(REGISTRY.read_text(encoding="utf-8"))["nutrients"]} if "nutrients" in json.loads(REGISTRY.read_text(encoding="utf-8")) else None
    if registry_keys is not None:
        for key in nutrients.values():
            if key not in registry_keys:
                sys.exit(f"Naehrstoffschluessel {key} steht nicht im Register")
    out = {}
    desc = {}
    for r in csv.DictReader(src.open(encoding="utf-8-sig", newline="")):
        code = int(r["Retn_Code"])
        nr = r["Nutr_No"].strip()
        if code not in codes or nr not in nutrients:
            continue
        f = (r["Retn_Factor"] or "").strip()
        if not f.isdigit():
            sys.exit(f"Faktor nicht lesbar: {code} {nr} '{f}'")
        out[(code, nr)] = int(f)
        desc[code] = r["RetnDesc"].strip()
    missing = [(c, n) for c in sorted(codes) for n in nutrients if (c, n) not in out]
    if missing:
        sys.exit(f"Faktoren fehlen in der Quelle: {missing[:10]} ...")
    with FACTORS.open("w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh, lineterminator="\n")
        w.writerow(CSV_FIELDS)
        for (code, nr), f in sorted(out.items()):
            if not 0 < f <= 200:
                sys.exit(f"Faktor ausserhalb von 1 bis 200 Prozent: {code} {nr} {f}")
            w.writerow([code, desc[code], nr, nutrients[nr], f])
    print(f"{len(out)} Faktoren fuer {len(codes)} USDA-Eintraege -> {FACTORS.relative_to(ROOT)}")


def load_factors():
    rows = list(csv.DictReader(FACTORS.open(encoding="utf-8", newline="")))
    factors = defaultdict(dict)
    desc = {}
    for r in rows:
        factors[int(r["retn_code"])][r["nutrient_key"]] = int(r["factor_percent"])
        desc[int(r["retn_code"])] = r["retn_desc"]
    return factors, desc


def dq(s: str) -> str:
    """Dart-Zeichenkette in einfachen Anfuehrungszeichen, ohne Interpolation."""
    return "'" + s.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$") + "'"


def raw(pattern: str) -> str:
    """Dart-Raw-String fuer ein regulaeres Ausdrucksmuster (dort gilt kein Escape, nur das einfache Anfuehrungszeichen ist verboten)."""
    if "'" in pattern:
        sys.exit(f"Muster darf kein ' enthalten: {pattern}")
    return "r'" + pattern + "'"


def build_dart():
    spec = load_rules()
    factors, desc = load_factors()
    nutrient_keys = list(spec["nutrients"].values())
    for code in used_codes(spec):
        if code not in factors:
            sys.exit(f"USDA-Eintrag {code} fehlt in retention_factors.csv (erst --usda ausfuehren)")
        if set(factors[code]) != set(nutrient_keys):
            sys.exit(f"USDA-Eintrag {code}: Naehrstoffe unvollstaendig")
    lines = [
        "// GENERIERT von tools/build_retention.py aus tools/retention_rules.json und tools/retention_factors.csv -- nicht von Hand aendern.",
        "// Garfaktoren (Phase N4, ADR-037): Quelle USDA Table of Nutrient Retention Factors, Release 6 (2007), Agricultural Research Service,",
        "// DOI 10.15482/USDA.ADC/1409034, Lizenz CC0 1.0. Faktor in Prozent: so viel des Naehrstoffs ist nach dem Garen noch da, bezogen",
        "// auf das Rohgewicht. Die Faktoren gelten fuer die Naehrstoffe unten, fuer alle anderen gibt es keinen Wert (sie bleiben wie roh).",
        "library;",
        "",
        "/// Eine Zuordnungsregel: ein roher BLS-Eintrag gehoert zu [category], wenn die Gruppe (erster Buchstabe des Codes) passt, der klein",
        "/// geschriebene Name auf [include] und nicht auf [exclude] passt und, bei [raw], auf \"roh\" endet. Die erste passende Regel gilt.",
        "class RetentionRule {",
        "  const RetentionRule({required this.category, required this.groups, required this.include, this.exclude, this.raw = true});",
        "",
        "  final String category;",
        "  final String groups;",
        "  final String include;",
        "  final String? exclude;",
        "  final bool raw;",
        "}",
        "",
        "/// Kategorie -> Zubereitung -> USDA-Eintrag (Retn_Code).",
        "const retentionMethodCodes = <String, Map<String, int>>{",
    ]
    for cat, methods in spec["methods"].items():
        inner = ", ".join(f"{dq(m)}: {c}" for m, c in methods.items())
        lines.append(f"  {dq(cat)}: {{{inner}}},")
    lines += ["};", "", "/// USDA-Beschreibung je Eintrag, fuer die Herkunftsangabe.", "const retentionDescriptions = <int, String>{"]
    for code in used_codes(spec):
        lines.append(f"  {code}: {dq(desc[code])},")
    lines += ["};", "", "/// USDA-Eintrag -> Naehrstoffschluessel (wie im Register) -> Prozent.", "const retentionFactorPercent = <int, Map<String, int>>{"]
    for code in used_codes(spec):
        inner = ", ".join(f"{dq(k)}: {factors[code][k]}" for k in nutrient_keys)
        lines.append(f"  {code}: {{{inner}}},")
    lines += ["};", "", "/// Zuordnung roher BLS-Eintraege zu Kategorien, die erste passende Regel gilt.", "const retentionRules = <RetentionRule>["]
    for r in spec["rules"]:
        parts = [f"category: {dq(r['category'])}", f"groups: {dq(r['groups'])}", f"include: {raw(r['include'])}"]
        if r.get("exclude"):
            parts.append(f"exclude: {raw(r['exclude'])}")
        if not r.get("raw", True):
            parts.append("raw: false")
        lines.append(f"  RetentionRule({', '.join(parts)}),")
    lines += ["];", ""]
    return "\n".join(lines)


def load_bls():
    s = BLS_SQL.read_text(encoding="utf-8")
    rows = []
    for m in re.finditer(r"\('([A-Z][A-Z0-9]{6})', '((?:[^']|'')*)', '((?:[^']|'')*)', ([\d.]+|null), ([\d.]+|null), ([\d.]+|null)", s):
        code, de, _en, _kcal, _prot, fat = m.groups()
        rows.append((code, de.replace("''", "'"), float(fat) if fat != "null" else None))
    return rows


def categorize(code, name, fat, spec):
    lower = name.lower()
    for r in spec["rules"]:
        if code[0] not in r["groups"]:
            continue
        if r.get("raw", True) and not lower.endswith("roh"):
            continue
        if not re.search(r["include"], lower):
            continue
        if r.get("exclude") and re.search(r["exclude"], lower):
            continue
        cat = r["category"]
        if cat == "fish":
            if fat is None:
                return None
            return "fish_lean" if fat <= 5 else "fish_fat"
        return cat
    return None


def report():
    spec = load_rules()
    bls = load_bls()
    got = defaultdict(list)
    none = defaultdict(list)
    for code, name, fat in bls:
        cat = categorize(code, name, fat, spec)
        if cat:
            got[cat].append((code, name))
        elif code[0] in "GKCETUV" and name.lower().endswith("roh"):
            none[code[0]].append(name)
    for cat in spec["methods"]:
        items = got.get(cat, [])
        print(f"{cat:12} {len(items):4}  {'; '.join(n for _, n in items[:6])}")
    print(f"\nzugeordnet: {sum(len(v) for v in got.values())} von {len(bls)}")
    for g, names in sorted(none.items()):
        print(f"\nohne Kategorie, roh, Gruppe {g}: {len(names)}")
        for n in names[:60]:
            print("   ", n)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--usda", type=Path, help="Ordner mit NutrientRetention.csv (schreibt tools/retention_factors.csv)")
    p.add_argument("--check", action="store_true", help="nichts schreiben, fehlschlagen, wenn retention_data.dart nicht passt")
    p.add_argument("--report", action="store_true", help="Zuordnung gegen die echte BLS zeigen")
    args = p.parse_args()
    if args.usda:
        step_usda(args.usda)
        return
    if args.report:
        report()
        return
    text = build_dart()
    if args.check:
        if not OUT.exists() or OUT.read_text(encoding="utf-8").replace("\r\n", "\n") != text:
            sys.exit("retention_data.dart passt nicht zu retention_rules.json/retention_factors.csv: python tools/build_retention.py ausfuehren")
        print("retention_data.dart ist aktuell")
        return
    OUT.write_text(text, encoding="utf-8", newline="\n")
    print(f"{OUT.relative_to(ROOT)} geschrieben")


if __name__ == "__main__":
    main()
