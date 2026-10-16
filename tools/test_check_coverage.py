"""Tests fuer tools/check_coverage.py. Aufruf: python tools/test_check_coverage.py"""
import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_coverage as m  # noqa: E402

results = []


def check(name, cond):
    results.append(bool(cond))
    print(("PASS " if cond else "FAIL ") + name)


LCOV = """SF:lib/domain/a.dart
DA:1,1
DA:2,0
DA:3,4
DA:4,1
end_of_record
SF:lib/features/b.dart
DA:1,0
DA:2,0
end_of_record
SF:lib/data/local/database.g.dart
DA:1,0
DA:2,0
DA:3,0
end_of_record
SF:C:\\x\\app\\lib\\core\\c.dart
DA:7,2
end_of_record
"""

files = m.parse_lcov(LCOV)
check("Dateien und Zeilen werden gelesen", files["lib/domain/a.dart"] == (4, 3) and files["lib/features/b.dart"] == (2, 0))
check("Windows-Pfade werden vereinheitlicht", any(p.endswith("lib/core/c.dart") for p in files))
per_layer, total = m.summarize(files)
check("erzeugter Code (*.g.dart) zaehlt nicht mit", total == [7, 4])
check("Zuordnung zu den Schichten", per_layer["domain"] == [4, 3] and per_layer["features"] == [2, 0] and per_layer["core"] == [1, 1])
check("Prozent", round(m.pct(*total), 1) == 57.1 and m.pct(0, 0) == 100.0)

with tempfile.TemporaryDirectory() as d:
    path = os.path.join(d, "lcov.info")
    Path(path).write_text(LCOV, encoding="utf-8")
    os.environ.pop("GITHUB_STEP_SUMMARY", None)
    check("Untergrenze eingehalten -> 0", m.main([path, "--min", "50", "--min-domain", "75"]) == 0)
    check("gesamt unterschritten -> 1", m.main([path, "--min", "60"]) == 1)
    check("domain unterschritten -> 1", m.main([path, "--min-domain", "80"]) == 1)
    check("fehlender Bericht -> 2", m.main([os.path.join(d, "fehlt.info")]) == 2)
    summary = os.path.join(d, "summary.md")
    os.environ["GITHUB_STEP_SUMMARY"] = summary
    m.main([path])
    os.environ.pop("GITHUB_STEP_SUMMARY")
    check("Tabelle landet in der Job-Zusammenfassung", "| **gesamt** |" in Path(summary).read_text(encoding="utf-8"))

failed = results.count(False)
print(f"\n{len(results) - failed}/{len(results)} Tests bestanden")
sys.exit(1 if failed else 0)
