#!/usr/bin/env python3
"""Erzeugt tools/food_synonyms_import.sql aus tools/food_synonyms.csv (Phase N1, ADR-031).

Die CSV ist die gepflegte Quelle: je Zeile ein Alltagsbegriff und der BLS-Code, auf den er zeigt. Das Skript prueft gegen die
echte BLS (tools/bls_foods_import.sql), dass jeder Code existiert, kein Begriff zwei verschiedene Codes bekommt und keiner
doppelt steht, und schreibt die SQL-Datei. Die Notiz in der Datenbank ist der offizielle BLS-Name (nicht die Notiz der CSV),
damit sie nie vom Code abweicht.

Das Skript fuehrt NICHTS gegen die Datenbank aus. Einspielen (nach der Migration 0022):
    npx supabase db query --linked --file tools/food_synonyms_import.sql

Aufruf:  python tools/build_food_synonyms.py            # SQL erzeugen
         python tools/build_food_synonyms.py --check    # nur pruefen (CI)
"""
import argparse
import csv
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CSV_PATH = ROOT / "tools" / "food_synonyms.csv"
BLS_SQL = ROOT / "tools" / "bls_foods_import.sql"
OUT_SQL = ROOT / "tools" / "food_synonyms_import.sql"

STOPWORDS = {
    "und", "mit", "ohne", "in", "im", "vom", "von", "aus", "der", "die", "das", "ein", "eine", "einer", "einem", "etwas", "ca",
    "circa", "frisch", "frische", "frischer", "frisches", "frischen", "ganze", "ganzer", "ganzes", "kleine", "kleiner", "kleines",
    "grosse", "große", "großer", "großes", "stueck", "stück", "stücke", "scheibe", "scheiben", "portion", "portionen", "gramm",
    "kg", "ml", "el", "tl", "bio", "natur", "fett",
}
STATE = re.compile(
    r"^(roh(e[rsnm]?)?|gerieben.*|geschnitten.*|gewürfelt.*|gehackt.*|(hart|weich)?gekocht.*|gebraten.*|frittiert.*|gebacken.*|ueberbacken.*|überbacken.*|geschmort.*|gedünstet.*|gedämpft.*|"
    r"getrocknet.*|gegrillt.*|geräuchert.*|tiefgefroren.*|gefroren.*)$"
)
COLOR = re.compile(r"^(rot|gelb|grün|weiß|weiss|schwarz|braun|fettarm)(e[rsnm]?)$")
FAT15 = re.compile(r"(^|[^0-9])1[,.]5 ?%?")


def food_core(text: str) -> str:
    """Spiegel von public.food_core (Migration 0022): klein, nur Buchstaben, ohne Fuell- und Zustandswoerter, Singular."""
    out = []
    text = FAT15.sub(r"\1 fettarm ", text.lower().translate(str.maketrans("éèêàâîïôûç", "eeeaaiiouc")))
    for t in re.split(r"[^a-zäöüß]+", text):
        if len(t) < 2 or t in STOPWORDS or STATE.match(t):
            continue
        t = COLOR.sub(r"\1", t)
        if (t.endswith("en") and not t.endswith("chen") and len(t) >= 5) or (re.search(r"(ln|rn)$", t) and len(t) >= 6):
            t = t[:-1]
        elif re.search(r"(is|os|as)$", t) and len(t) >= 5 and t not in ("ananas", "kokos", "kürbis", "reis"):
            t = t[:-1]
        out.append(t)
    return " ".join(out)


def food_key(text: str) -> str:
    """Spiegel von public.food_key: die Kernwoerter alphabetisch sortiert."""
    return " ".join(sorted(food_core(text).split()))


def load_bls_names() -> dict:
    names = {}
    for m in re.finditer(r"^\s*\('([A-Z0-9]{7})', '((?:[^']|'')*)'", BLS_SQL.read_text(encoding="utf-8"), re.M):
        names[m.group(1)] = m.group(2).replace("''", "'")
    return names


def sql_text(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="nur pruefen, keine Datei schreiben")
    args = ap.parse_args()

    names = load_bls_names()
    if len(names) < 7000:
        print(f"FEHLER: nur {len(names)} BLS-Eintraege in {BLS_SQL.name} gelesen", file=sys.stderr)
        return 1

    rows, errors, seen = [], [], {}
    with CSV_PATH.open(encoding="utf-8", newline="") as f:
        for n, r in enumerate(csv.DictReader(f), start=2):
            term, code = (r["term"] or "").strip(), (r["bls_code"] or "").strip()
            core = food_key(term)
            if not term or not core:
                errors.append(f"Zeile {n}: Begriff '{term}' ergibt nach der Normalisierung nichts")
                continue
            if code not in names:
                errors.append(f"Zeile {n}: Code {code} ('{term}') gibt es in der BLS nicht")
                continue
            if core in seen:
                if seen[core][0] != code:
                    errors.append(f"Zeile {n}: '{term}' (= '{core}') zeigt auf {code}, steht aber schon mit {seen[core][0]} (Zeile {seen[core][1]})")
                else:
                    errors.append(f"Zeile {n}: '{term}' (= '{core}') steht doppelt (Zeile {seen[core][1]})")
                continue
            seen[core] = (code, n)
            rows.append((core, code))

    if errors:
        print("\n".join(errors), file=sys.stderr)
        print(f"{len(errors)} Fehler", file=sys.stderr)
        return 1
    print(f"{len(rows)} Synonyme geprueft, {len({c for _, c in rows})} verschiedene BLS-Eintraege")
    if args.check:
        return 0

    lines = [
        "-- Max Rubner-Institut (2025): Bundeslebensmittelschlüssel (BLS), Version 4.0 — Deutsche Nährstoffdatenbank (CC BY 4.0)",
        "-- Erzeugt von tools/build_food_synonyms.py aus tools/food_synonyms.csv -- nicht von Hand aendern, bei Bedarf neu erzeugen.",
        "-- Einspielen (nach Migration 0022 und dem BLS-Import): npx supabase db query --linked --file tools/food_synonyms_import.sql",
        "",
        "insert into public.food_synonyms (term_norm, bls_code, note) values",
    ]
    values = [f"  ({sql_text(core)}, {sql_text(code)}, {sql_text(names[code])})" for core, code in rows]
    lines.append(",\n".join(values))
    lines.append("on conflict (term_norm) do update set bls_code = excluded.bls_code, note = excluded.note;")
    lines.append("")
    lines.append("-- Begriffe, die nicht mehr in der CSV stehen, entfernen")
    lines.append("delete from public.food_synonyms where term_norm <> all (array[" + ", ".join(sql_text(c) for c, _ in rows) + "]);")
    OUT_SQL.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(f"geschrieben: {OUT_SQL.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
