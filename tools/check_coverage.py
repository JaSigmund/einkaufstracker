"""Zeilenabdeckung der App-Tests je Schicht und Untergrenze fuer die CI (Codereview 2026-10-16).

    cd app && flutter test --coverage
    python tools/check_coverage.py app/coverage/lcov.info --min 70 --min-domain 85

Erzeugter Code (*.g.dart, test/generated_migrations) zaehlt nicht mit. Die Untergrenzen sind eine Sperrklinke: sie liegen
knapp unter dem aktuellen Stand und werden angehoben, wenn die Abdeckung steigt, nie gesenkt, um eine Aenderung durch die
CI zu bekommen. Ausgabe als Markdown-Tabelle, damit sie in der CI auch in der Job-Zusammenfassung steht.
Rueckgabe: 0 = Untergrenzen eingehalten, 1 = unterschritten, 2 = keine Abdeckungsdaten.
"""
import argparse
import os
import sys
from collections import defaultdict

LAYERS = ["domain", "data", "features", "app", "core"]


def parse_lcov(text):
    """{Datei: (gefundene Zeilen, getroffene Zeilen)} aus einem lcov-Bericht."""
    files, current, found, hit = {}, None, 0, 0
    for line in text.splitlines():
        if line.startswith("SF:"):
            current, found, hit = line[3:].strip().replace("\\", "/"), 0, 0
        elif line.startswith("DA:") and current is not None:
            found += 1
            if int(line[3:].split(",")[1]) > 0:
                hit += 1
        elif line == "end_of_record" and current is not None:
            files[current] = (found, hit)
            current = None
    return files


def is_generated(path):
    return path.endswith(".g.dart") or "/generated_migrations/" in path


def layer_of(path):
    marker = "lib/"
    i = path.rfind(marker)
    rest = path[i + len(marker):] if i >= 0 else path
    top = rest.split("/", 1)[0]
    return top if top in LAYERS else "andere"


def summarize(files):
    per_layer = defaultdict(lambda: [0, 0])
    for path, (found, hit) in files.items():
        if is_generated(path):
            continue
        per_layer[layer_of(path)][0] += found
        per_layer[layer_of(path)][1] += hit
    total = [sum(v[0] for v in per_layer.values()), sum(v[1] for v in per_layer.values())]
    return per_layer, total


def pct(found, hit):
    return 100.0 * hit / found if found else 100.0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("lcov")
    ap.add_argument("--min", type=float, default=0.0, help="Untergrenze gesamt in Prozent")
    ap.add_argument("--min-domain", type=float, default=0.0, help="Untergrenze fuer lib/domain in Prozent")
    args = ap.parse_args(argv)

    if not os.path.exists(args.lcov):
        print(f"Keine Abdeckungsdaten: {args.lcov} fehlt (vorher 'flutter test --coverage' ausfuehren)")
        return 2
    with open(args.lcov, encoding="utf-8") as f:
        per_layer, total = summarize(parse_lcov(f.read()))
    if total[0] == 0:
        print("Keine Abdeckungsdaten im Bericht")
        return 2

    lines = ["| Schicht | Zeilen | getroffen | Abdeckung |", "|---|---:|---:|---:|"]
    for layer in LAYERS + ["andere"]:
        if layer in per_layer:
            found, hit = per_layer[layer]
            lines.append(f"| lib/{layer} | {found} | {hit} | {pct(found, hit):.1f} % |")
    lines.append(f"| **gesamt** | {total[0]} | {total[1]} | **{pct(*total):.1f} %** |")
    report = "\n".join(lines)
    print(report)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write("### Testabdeckung der App\n\n" + report + "\n")

    failed = []
    if pct(*total) < args.min:
        failed.append(f"gesamt {pct(*total):.1f} % < {args.min} %")
    domain = per_layer.get("domain")
    if domain and pct(*domain) < args.min_domain:
        failed.append(f"lib/domain {pct(*domain):.1f} % < {args.min_domain} %")
    for f in failed:
        print("UNTERSCHRITTEN: " + f)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
