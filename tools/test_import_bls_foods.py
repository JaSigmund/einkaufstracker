"""Tests fuer tools/import_bls_foods.py mit kuenstlichen Tabellen im Format der echten BLS-4.0-Dateien.

Aufruf: python tools/test_import_bls_foods.py     (benoetigt: pip install pandas openpyxl)
Die Ueberschriften entsprechen den echten Dateien (Components: 'Index', 'Nährstoffcode / Component code', ...;
Daten: 'ENERCC Energie (Kilokalorien) [kcal/100g]' + '... Datenherkunft' + '... Referenz'). Die echten Werte
werden hier nicht geprueft, dafuer gibt es den --inspect-Lauf und die Stichprobe gegen eine unabhaengige Quelle.
"""
import sys
import tempfile
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
import import_bls_foods as m  # noqa: E402

results = []


def check(name, cond):
    results.append(bool(cond))
    print(("PASS " if cond else "FAIL ") + name)


COMPONENT_ROWS = [
    ("ENERCC", "Energie (Kilokalorien)", "Energy (kilocalorie)", "kcal"),
    ("PROT625", "Protein (Nx6,25)", "Protein (Nx6.25)", "g"),
    ("FAT", "Fett", "Fat", "g"),
    ("FASAT", "Fettsäuren, gesättigt, gesamt", "Fatty acids, saturated, total", "g"),
    ("CHO", "Kohlenhydrate, verfügbar", "Carbohydrate, available", "g"),
    ("SUGAR", "Zucker (Mono- und Disaccharide), gesamt", "Sugars (mono- and disaccharides), total", "g"),
    ("FIBT", "Ballaststoffe, gesamt", "Fibre, dietary, total", "g"),
    ("NACL", "Salz (Natriumchlorid)", "Salt (sodium chloride)", "g"),
    ("NA", "Natrium", "Sodium", "mg"),  # Code "NA" darf nie als fehlender Wert gelesen werden
]
CODES = [c[0] for c in COMPONENT_ROWS]
UNITS = {c[0]: c[3] for c in COMPONENT_ROWS}
NAMES = {c[0]: c[1] for c in COMPONENT_ROWS}
NUTRIENT_ORDER = ["ENERCC", "PROT625", "FAT", "FASAT", "CHO", "SUGAR", "FIBT", "NACL"]


def components(extra=None, drop=None):
    rows = [r for r in COMPONENT_ROWS if r[0] != drop] + (extra or [])
    return pd.DataFrame([(i + 1, *r, "Makronährstoffe", "Proximate composition") for i, r in enumerate(rows)],
                        columns=["Index", "Nährstoffcode / Component code", "Nährstoffbezeichnung", "Component name",
                                 "Einheit / Unit", "Nährstoffgruppe", "Component group"])


def data(rows):
    cols = ["BLS Code", "Lebensmittelbezeichnung", "Food name"]
    for code in CODES:
        cols += [f"{code} {NAMES[code]} [{UNITS[code]}/100g]", f"{code} Datenherkunft", f"{code} Referenz"]
    return pd.DataFrame(rows, columns=cols)


def row(code, name_de, name_en, **v):
    r = [code, name_de, name_en]
    for c in CODES:
        r += [v.get(c), "Analyse", "-"]
    return r


# 1) Normalfall: Zuordnung ueber Codes, Werte uebernommen, Datenherkunft-/Referenz-Spalten ignoriert
d = data([row("B100000", "Apfel roh", "Apple raw", ENERCC=52, PROT625=0.3, FAT=0.4, FASAT=0.1, CHO=11.4,
              SUGAR=10.4, FIBT=2.0, NACL=0.0025, NA=1.0)])
rows, mapping, stats = m.build_rows(components(), d)
check("Zuordnung: kcal ueber Code ENERCC", mapping["kcal"]["code"] == "ENERCC")
check("Zuordnung: Code-Spalte ist 'Nährstoffcode / Component code', nicht die Index-Spalte",
      m.components_columns(components())[0] == "Nährstoffcode / Component code")
check("Zuordnung: Wertspalte ist die Zahlen-Spalte, nicht Datenherkunft/Referenz",
      mapping["kcal"]["column"] == "ENERCC Energie (Kilokalorien) [kcal/100g]")
check("Zeilen: Werte stimmen", rows[0][3]["kcal"] == 52 and rows[0][3]["carbs_g"] == 11.4 and rows[0][3]["salt_g"] == 0.0025)
check("Alle 8 Naehrwerte zugeordnet", len(mapping) == 8)

# 2) Dezimalkomma als Text, nicht lesbare Marker und leere Zellen (keep_default_na=False liefert '')
d = data([row("B100002", "Test", "Test", ENERCC="12,5", PROT625="-", FAT="n.b.", FASAT="", CHO="3,25", SUGAR=None,
              FIBT="1,5", NACL=0.1)])
rows, *_ = m.build_rows(components(), d)
v = rows[0][3]
check("Dezimalkomma als Text wird gelesen", v["kcal"] == 12.5 and v["carbs_g"] == 3.25)
check("Marker '-', 'n.b.', leere Zelle und None ergeben None statt 0",
      v["protein_g"] is None and v["fat_g"] is None and v["sat_fat_g"] is None and v["sugar_g"] is None)

# 3) Mehrdeutigkeit: identische Zeile doppelt ist ein Treffer, zwei verschiedene Codes sind ein Abbruch
dup = components(extra=[("ENERCC", "Energie (Kilokalorien)", "Energy (kilocalorie)", "kcal")])
check("Dieselbe Components-Zeile doppelt: wird zu einem Treffer zusammengefasst",
      m.pick_component(dup, m.NUTRIENTS["kcal"], "kcal") == ("ENERCC", "kcal"))

two_names = components(drop="CHO", extra=[("CHOX", "Kohlenhydrate, verfügbar", "x", "g"), ("CHOY", "Kohlenhydrate, verfügbar", "y", "g")])
try:
    m.pick_component(two_names, m.NUTRIENTS["carbs_g"], "carbs_g")
    raised = False
except m.MappingError:
    raised = True
check("Zwei verschiedene Codes mit demselben Namen (Name-Stufe): Abbruch statt Raten", raised)

by_name = components(drop="FAT", extra=[("FATX", "Fett", "Fat", "g")])
check("Fehlender Code, eindeutiger Name: Zuordnung ueber den Namen", m.pick_component(by_name, m.NUTRIENTS["fat_g"], "fat_g") == ("FATX", "g"))

# 4) Falsche Einheit bricht ab
bad_unit = components()
bad_unit.loc[bad_unit["Nährstoffcode / Component code"] == "FAT", "Einheit / Unit"] = "mg"
try:
    m.resolve_mapping(bad_unit, data([]).columns)
    raised = False
except m.MappingError as e:
    raised = "FAT" in str(e) or "fat_g" in str(e)
check("Unerwartete Einheit (Fett in mg) bricht ab", raised)

# 5) Fehlender Naehrwert bricht mit Hinweis ab (alle 8 sind Pflicht)
for drop, key in (("FIBT", "fiber_g"), ("NACL", "salt_g"), ("SUGAR", "sugar_g")):
    try:
        m.resolve_mapping(components(drop=drop), data([]).columns)
        raised = False
    except m.MappingError as e:
        raised = key in str(e)
    check(f"Fehlender Naehrwert {key} bricht mit Hinweis ab", raised)

# 6) Wertspalte: Praefix darf keine laengeren Codes treffen (NA vs NACL) und keine Herkunftsspalten
cols = ["NACL Salz (Natriumchlorid) [g/100g]", "NACL Datenherkunft", "NA Natrium [mg/100g]", "NA Referenz"]
check("find_value_column: NA trifft nicht NACL und nicht die Referenzspalte",
      m.find_value_column(cols, "NA") == "NA Natrium [mg/100g]")
check("find_value_column: NACL trifft nicht NA", m.find_value_column(cols, "NACL") == "NACL Salz (Natriumchlorid) [g/100g]")
check("find_value_column: Codes mit Sonderzeichen (F4:0) funktionieren",
      m.find_value_column(["F4:0 Fettsäure C4:0 [g/100g]", "F4:0 Datenherkunft"], "F4:0") == "F4:0 Fettsäure C4:0 [g/100g]")

# 7) SQL-Ausgabe: Quote-Escaping, NULL, Attribution, idempotentes on conflict
d = data([row("B100003", "Kind's Müsli", "Kids' muesli", ENERCC=380, PROT625=9, FAT=6, FASAT=1, CHO=70, SUGAR=20,
              FIBT=8, NACL=None)])
rows, *_ = m.build_rows(components(), d)
with tempfile.TemporaryDirectory() as tmp:
    out = Path(tmp) / "out.sql"
    m.write_sql(rows, out)
    sql = out.read_text(encoding="utf-8")
check("SQL: einfaches Anfuehrungszeichen wird verdoppelt", "'Kind''s Müsli'" in sql)
check("SQL: Attribution im Kopf", "Max Rubner-Institut (2025)" in sql and "CC BY 4.0" in sql)
check("SQL: on conflict (bls_code) do update", "on conflict (bls_code) do update set" in sql)
check("SQL: NULL fuer fehlende Werte", ", null)" in sql)

# 8) Batches: 1200 Zeilen -> 3 INSERT-Statements bei batch=500
many = data([row(f"B{i:06d}", f"Lebensmittel {i}", f"Food {i}", ENERCC=100, PROT625=1, FAT=1, FASAT=0.5, CHO=10,
                 SUGAR=5, FIBT=1, NACL=0.1) for i in range(1200)])
rows, *_ = m.build_rows(components(), many)
with tempfile.TemporaryDirectory() as tmp:
    out = Path(tmp) / "out.sql"
    m.write_sql(rows, out, batch=500)
    sql = out.read_text(encoding="utf-8")
check("Batches: 1200 Zeilen ergeben 3 INSERT-Statements", sql.count("insert into public.bls_foods") == 3)
check("Batches: alle 1200 Zeilen enthalten", sql.count("('B0") == 1200)

# 9) Auffaellige Zeilen werden gemeldet (kcal > 950)
d = data([row("B9", "Unmoeglich", "Impossible", ENERCC=1200, PROT625=1, FAT=1, FASAT=1, CHO=1, SUGAR=1, FIBT=1, NACL=1)])
_, _, stats = m.build_rows(components(), d)
check("Plausibilitaet: kcal > 950 wird als auffaellig gemeldet", len(stats["implausible"]) == 1)

failed = results.count(False)
print(f"\n{len(results) - failed}/{len(results)} Tests bestanden")
sys.exit(1 if failed else 0)
