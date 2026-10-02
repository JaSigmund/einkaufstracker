"""Tests fuer tools/import_bls_foods.py mit kuenstlichen, BLS-aehnlichen Tabellen (ohne die echten Excel-Dateien).

Aufruf: python tools/test_import_bls_foods.py     (benoetigt: pip install pandas openpyxl)
Echte Daten werden damit NICHT geprueft -- dafuer gibt es die Stichprobenpruefung im Plan (Phase 7a).
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


def components(extra=None, salt=True):
    rows = [
        ("ENERCC", "Energie (Kilokalorien)", "Energy (kilocalories)", "kcal"),
        ("PROT625", "Protein (Nx6,25)", "Protein (N x 6.25)", "g"),
        ("FAT", "Fett", "Fat", "g"),
        ("FASAT", "Fettsäuren, gesättigt", "Fatty acids, saturated", "g"),
        ("CHO", "Kohlenhydrate, verfügbar", "Carbohydrates, available", "g"),
        ("MDSA", "Mono- und Disaccharide", "Mono- and disaccharides", "g"),
        ("FIBT", "Ballaststoffe", "Fibre, total", "g"),
        ("NA", "Natrium", "Sodium", "mg"),
    ]
    if salt:
        rows.append(("NACL", "Salz (NaCl)", "Salt (NaCl)", "g"))
    rows += extra or []
    return pd.DataFrame(rows, columns=["Code", "Name DE", "Name EN", "Einheit"])


def data(rows):
    cols = ["BLS Code", "Lebensmittelbezeichnung", "Food name"]
    for code in ["ENERCC", "PROT625", "FAT", "FASAT", "CHO", "MDSA", "FIBT", "NA", "NACL"]:
        cols += [code, f"{code} Datenherkunft", f"{code} Referenz"]
    return pd.DataFrame(rows, columns=cols)


def row(code, name_de, name_en, kcal, protein, fat, sat, carbs, sugar, fiber, na, nacl):
    r = [code, name_de, name_en]
    for v in (kcal, protein, fat, sat, carbs, sugar, fiber, na, nacl):
        r += [v, "Analyse", "Ref1"]
    return r


# 1) Normalfall: Zuordnung ueber Codes, Werte uebernommen, Datenherkunft-/Referenz-Spalten ignoriert
d = data([row("B100000", "Apfel roh", "Apple raw", 52, 0.3, 0.4, 0.1, 11.4, 10.4, 2.0, 1.0, 0.0025)])
rows, mapping, warnings, stats = m.build_rows(components(), d)
check("Zuordnung: kcal ueber Code ENERCC", mapping["kcal"]["code"] == "ENERCC")
check("Zuordnung: Wertspalte ist die Zahlen-Spalte, nicht Datenherkunft", mapping["kcal"]["column"] == "ENERCC")
check("Zeilen: Werte stimmen", rows[0][3]["kcal"] == 52 and rows[0][3]["carbs_g"] == 11.4)
check("Salz: direkte Salz-Spalte hat Vorrang vor Natrium", mapping["salt_g"]["derived_from_sodium"] is False)

# 2) Natrium-Fallback: keine Salz-Zeile in Components -> aus Natrium (mg) x 2,5 abgeleitet
d = data([row("B100001", "Brot", "Bread", 250, 8, 2, 0.5, 48, 3, 6, 400, None)])
rows, mapping, warnings, stats = m.build_rows(components(salt=False), d)
check("Natrium-Fallback: Salz aus Natrium abgeleitet", mapping["salt_g"]["derived_from_sodium"] is True)
check("Natrium-Fallback: 400 mg Natrium = 1,0 g Salz", abs(rows[0][3]["salt_g"] - 1.0) < 1e-9)
check("Natrium-Fallback: erzeugt eine Warnung", any("Natrium" in w for w in warnings))

# 3) Dezimalkomma als Text und nicht lesbare Marker
d = data([row("B100002", "Test", "Test", "12,5", "-", "n.b.", None, "3,25", "", "1,5", "5", None)])
rows, *_ = m.build_rows(components(), d)
v = rows[0][3]
check("Dezimalkomma als Text wird gelesen", v["kcal"] == 12.5 and v["carbs_g"] == 3.25)
check("Marker '-' und 'n.b.' und leere Zelle ergeben None statt 0", v["protein_g"] is None and v["fat_g"] is None and v["sugar_g"] is None)

# 4) Mehrdeutigkeit: identische Zeile doppelt ist ein Treffer, zwei verschiedene Codes sind ein Abbruch
dup = components(extra=[("ENERCC", "Energie (Kilokalorien)", "Energy (kilocalories)", "kcal")])
check("Dieselbe Components-Zeile doppelt: wird zu einem Treffer zusammengefasst",
      m.pick_component(dup, m.NUTRIENTS["kcal"], "kcal") == ("ENERCC", "kcal"))

two_codes = components()
two_codes.loc[len(two_codes)] = ["CHOAVL", "Kohlenhydrate, verfügbar", "Carbohydrates, available", "g"]
try:
    m.pick_component(two_codes, m.NUTRIENTS["carbs_g"], "carbs_g")
    raised = False
except m.MappingError:
    raised = True
check("Zwei verschiedene Codes (CHO und CHOAVL) in derselben Stufe: Abbruch statt Raten", raised)

# 5) Falsche Einheit bricht ab
bad_unit = components()
bad_unit.loc[bad_unit["Code"] == "FAT", "Einheit"] = "mg"
try:
    m.resolve_mapping(bad_unit, data([row("B1", "x", "x", 1, 1, 1, 1, 1, 1, 1, 1, 1)]).columns)
    raised = False
except m.MappingError:
    raised = True
check("Unerwartete Einheit (Fett in mg) bricht ab", raised)

# 6) Fehlender Pflicht-Naehrwert bricht ab, fehlender optionaler wird nur gewarnt
no_fiber = components()
no_fiber = no_fiber[no_fiber["Code"] != "FIBT"]
try:
    m.resolve_mapping(no_fiber, data([]).columns)
    raised = False
except m.MappingError as e:
    raised = "fiber_g" in str(e)
check("Fehlender Pflicht-Naehrwert (Ballaststoffe) bricht mit Hinweis ab", raised)

no_sugar = components()
no_sugar = no_sugar[no_sugar["Code"] != "MDSA"]
_, warnings = m.resolve_mapping(no_sugar, data([]).columns)
check("Fehlender optionaler Naehrwert (Zucker) wird nur gewarnt", any("sugar_g" in w for w in warnings))

# 7) Wertspalte: Praefix darf keine laengeren Codes treffen (FAT vs FATRN) und Herkunftsspalten nicht
cols = ["FAT", "FAT Datenherkunft", "FATRN", "FAT Referenz"]
check("find_value_column: FAT trifft nicht FATRN und nicht die Herkunftsspalte", m.find_value_column(cols, "FAT") == "FAT")

# 8) SQL-Ausgabe: Quote-Escaping, NULL, Attribution, idempotentes on conflict
d = data([row("B100003", "Kind's Müsli", "Kids' muesli", 380, 9, 6, 1, 70, 20, 8, 20, None)])
rows, *_ = m.build_rows(components(), d)
with tempfile.TemporaryDirectory() as tmp:
    out = Path(tmp) / "out.sql"
    m.write_sql(rows, out)
    sql = out.read_text(encoding="utf-8")
check("SQL: einfaches Anfuehrungszeichen wird verdoppelt", "'Kind''s Müsli'" in sql)
check("SQL: Attribution im Kopf", "Max Rubner-Institut (2025)" in sql and "CC BY 4.0" in sql)
check("SQL: on conflict (bls_code) do update", "on conflict (bls_code) do update set" in sql)
check("SQL: Umlaute bleiben erhalten (UTF-8)", "Müsli" in sql)

# 9) Batches: 1200 Zeilen -> 3 INSERT-Statements bei batch=500
many = data([row(f"B{i:06d}", f"Lebensmittel {i}", f"Food {i}", 100, 1, 1, 0.5, 10, 5, 1, 10, None) for i in range(1200)])
rows, *_ = m.build_rows(components(), many)
with tempfile.TemporaryDirectory() as tmp:
    out = Path(tmp) / "out.sql"
    m.write_sql(rows, out, batch=500)
    sql = out.read_text(encoding="utf-8")
check("Batches: 1200 Zeilen ergeben 3 INSERT-Statements", sql.count("insert into public.bls_foods") == 3)
check("Batches: alle 1200 Zeilen enthalten", sql.count("('B0") == 1200)

# 10) Auffaellige Zeilen werden gemeldet (kcal > 950)
d = data([row("B9", "Unmoeglich", "Impossible", 1200, 1, 1, 1, 1, 1, 1, 1, None)])
_, _, _, stats = m.build_rows(components(), d)
check("Plausibilitaet: kcal > 950 wird als auffaellig gemeldet", len(stats["implausible"]) == 1)

failed = results.count(False)
print(f"\n{len(results) - failed}/{len(results)} Tests bestanden")
sys.exit(1 if failed else 0)
