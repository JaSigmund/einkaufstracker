"""Vergleichstest der Edge Function parse-receipt mit echten Bon-Fotos (Phase 0, Schritt S7).

Pro Foto werden mehrere Kombinationen aus Modell und Variante getestet, die Ergebnisse gegen die
manuell abgelesenen Soll-Werte (testdata/receipts/truth/*.json) gezaehlt und Kosten/Dauer ausgegeben.

Aufruf (PowerShell, im Repo-Ordner):
  python tools/test_parse_receipt.py testdata/receipts/billa-002.jpg testdata/receipts/billa-001-scan-17-32-26.jpg
Optional andere Kombinationen:
  python tools/test_parse_receipt.py --combos haiku:v2,sonnet:v3 testdata/receipts/billa-002.jpg

Die Anmeldung erfolgt mit E-Mail und Passwort deines Supabase-Kontos (Passwort per getpass, nie im Chat).
Voraussetzungen: tools/.test_config.json, allow_cloud_ocr = true, Secret ANTHROPIC_API_KEY im Projekt.
Nur Python-Standardbibliothek.
"""
import base64
import collections
import getpass
import json
import pathlib
import sys
import time
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
CFG = json.loads((ROOT / "tools" / ".test_config.json").read_text(encoding="utf-8"))
OUT = ROOT / "testdata" / "receipts" / "cloud_results"
TRUTH = ROOT / "testdata" / "receipts" / "truth"
MODELS = {"haiku": "claude-haiku-4-5-20251001", "sonnet": "claude-sonnet-5"}
DEFAULT_COMBOS = "haiku:v1,haiku:v2,haiku:v3,sonnet:v2,sonnet:v3"


def post(url, payload, headers):
    req = urllib.request.Request(url, data=json.dumps(payload).encode("utf-8"), headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            return r.status, json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        try:
            return e.code, json.loads(body)
        except ValueError:
            return e.code, {"raw": body[:500]}


def login():
    email = input("E-Mail deines Supabase-Kontos: ").strip()
    password = getpass.getpass("Passwort (Eingabe unsichtbar): ")
    status, body = post(
        f"{CFG['url']}/auth/v1/token?grant_type=password",
        {"email": email, "password": password},
        {"apikey": CFG["publishable_key"], "Content-Type": "application/json"},
    )
    if status != 200:
        sys.exit(f"Anmeldung fehlgeschlagen ({status}): {body.get('msg') or body.get('error_description') or body}")
    return body["access_token"], body["user"]["id"]


def find_truth(stem):
    for f in sorted(TRUTH.glob("*.json"), key=lambda p: -len(p.stem)):
        if stem.startswith(f.stem):
            return json.loads(f.read_text(encoding="utf-8"))
    return None


def accuracy(truth, items):
    got = collections.Counter(i["line_total_cents"] for i in items if i.get("line_total_cents") is not None)
    want = collections.Counter(truth["lines"])
    matched = sum((got & want).values())
    return matched, sum((got - want).values()), sum((want - got).values())


def main(argv):
    combos = DEFAULT_COMBOS
    paths = []
    it = iter(argv)
    for a in it:
        if a == "--combos":
            combos = next(it)
        else:
            paths.append(a)
    if not paths:
        sys.exit(__doc__)
    combos = [c.split(":") for c in combos.split(",")]

    token, user_id = login()
    headers = {"Authorization": f"Bearer {token}", "apikey": CFG["publishable_key"], "Content-Type": "application/json"}

    def get(path):
        req = urllib.request.Request(f"{CFG['url']}/rest/v1/{path}", headers=headers)
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read().decode("utf-8"))

    hh = get(f"household_members?user_id=eq.{user_id}&select=household_id")
    if not hh:
        sys.exit("Kein Haushalt gefunden.")
    household_id = hh[0]["household_id"]
    categories = [c["name"] for c in get(f"categories?household_id=eq.{household_id}&select=name&order=sort_order")]
    OUT.mkdir(parents=True, exist_ok=True)

    agg = collections.defaultdict(list)  # combo -> Liste von Ergebnissen
    for p in paths:
        path = pathlib.Path(p)
        img = base64.b64encode(path.read_bytes()).decode("ascii")
        truth = find_truth(path.stem)
        print(f"\n=== {path.name}" + (f"  (Soll: {len(truth['lines'])} Positionen, Summe {truth['total_cents']})" if truth else "  (kein Soll-Wert)"))
        for alias, variant in combos:
            t0 = time.time()
            status, body = post(
                f"{CFG['url']}/functions/v1/parse-receipt",
                {"household_id": household_id, "images": [img], "categories": categories, "store_hint": "Billa",
                 "variant": variant, "model": MODELS[alias]},
                headers,
            )
            dt = time.time() - t0
            (OUT / f"{path.stem}.{alias}.{variant}.json").write_text(json.dumps(body, ensure_ascii=False, indent=1), encoding="utf-8")
            key = f"{alias}:{variant}"
            if status != 200:
                print(f"  {key:<10} HTTP {status}: {json.dumps(body, ensure_ascii=False)[:200]}")
                continue
            r = body["receipt"]
            items = r.get("items", [])
            u = body["usage"]
            line = (f"  {key:<10} {dt:5.1f} s  Token {u['input_tokens']}/{u['output_tokens']}  {u['cost_micro_usd']/10000:5.2f} ct  "
                    f"Aufrufe {body['attempts']}  {len(items):>2} Pos.  Summe {'OK' if not body['sum_mismatch'] else 'ABWEICHUNG ' + str(body['computed_sum_cents'] - (r.get('total_cents') or 0))}")
            res = {"sec": dt, "cost": u["cost_micro_usd"], "sum_ok": not body["sum_mismatch"]}
            if truth:
                m, extra, missing = accuracy(truth, items)
                line += f"  | richtig {m}/{len(truth['lines'])}, zusaetzlich {extra}, fehlend {missing}"
                res.update({"matched": m, "want": len(truth["lines"]), "extra": extra, "missing": missing,
                            "exact": extra == 0 and missing == 0})
            print(line)
            agg[key].append(res)

    print("\n=== Zusammenfassung je Kombination")
    print(f"  {'Kombi':<10} {'Bons':>4} {'exakt':>6} {'Summe OK':>9} {'Ø Positionen richtig':>21} {'Ø Kosten':>10} {'Ø Dauer':>8}")
    for key, rs in agg.items():
        n = len(rs)
        exact = sum(1 for r in rs if r.get("exact"))
        sum_ok = sum(1 for r in rs if r["sum_ok"])
        rec = sum(r["matched"] / r["want"] for r in rs if "matched" in r) / max(1, sum(1 for r in rs if "matched" in r))
        print(f"  {key:<10} {n:>4} {exact:>6} {sum_ok:>9} {rec*100:>20.0f}% {sum(r['cost'] for r in rs)/n/10000:>8.2f} ct {sum(r['sec'] for r in rs)/n:>6.1f} s")
    print(f"\nRohantworten: {OUT}")


if __name__ == "__main__":
    main(sys.argv[1:])
