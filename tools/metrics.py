"""Kennzahlen aus dem Testkonzept (Doku 10, Metriken) aus den echten Daten im Supabase-Projekt.

Nur lesende Abfragen (SELECT) ueber die Supabase CLI (`npx supabase db query --linked`), im Repo-Ordner ausfuehren:

    python tools/metrics.py

Ausgegeben werden je Quelle (pdf_text = digital, on_device = Foto lokal, llm = Foto per Cloud):
- Anzahl Bons und Anteil Bons, deren Positionssumme der Bon-Summe entspricht (Summenuebereinstimmung, Ziel >= 90 %)
- Fallback-Quote der Foto-Bons (Anteil Cloud, Ziel <= 30 % nach Tuning)
- Kosten je Cloud-Bon aus llm_usage (Ziel im Mittel unter 1 Cent)
- Anteil Artikel mit Kategorie (Naeherung fuer die Alias-Trefferquote, Ziel >= 90 % nach 4 bis 6 Wochen)

Hinweis: `sum_mismatch` wird beim Speichern aus den Pruefungen der Vorschau gesetzt, auch nach einer Korrektur durch den
Nutzer. Ein korrigierter Bon zaehlt also als "stimmig". Die Zahl misst daher, wie viele Bons nach der Pruefansicht
aufgehen, nicht wie gut die Erkennung allein war. Die Erkennung allein zeigt die Fallback-Quote.
"""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def query(sql: str):
    out = subprocess.run(
        ["npx", "supabase", "db", "query", "--linked", "--output", "json", sql],
        cwd=ROOT, capture_output=True, text=True, shell=(sys.platform == "win32"),
    )
    if out.returncode != 0:
        sys.exit(f"Abfrage fehlgeschlagen:\n{out.stderr or out.stdout}")
    data = json.loads(out.stdout)
    # je nach CLI-Version steht die Ergebniszeile direkt oder unter "rows"
    return data.get("rows", data) if isinstance(data, dict) else data


def pct(part, whole):
    return "-" if not whole else f"{100 * part / whole:.1f} %"


def main():
    rows = query(
        "select source::text as source, count(*)::int as n, "
        "count(*) filter (where not sum_mismatch)::int as ok "
        "from receipts where deleted_at is null and status = 'confirmed' group by source order by source"
    )
    print("Bons je Quelle")
    total = ok = 0
    photo = cloud = 0
    for r in rows:
        print(f"  {r['source']:<10} {r['n']:>4} Bons, Summe stimmig: {pct(r['ok'], r['n'])}")
        total += r["n"]
        ok += r["ok"]
        if r["source"] in ("on_device", "llm"):
            photo += r["n"]
            if r["source"] == "llm":
                cloud += r["n"]
    print(f"  {'gesamt':<10} {total:>4} Bons, Summe stimmig: {pct(ok, total)}  (Ziel >= 90 %)")
    print(f"\nFallback-Quote der Foto-Bons: {pct(cloud, photo)} ({cloud} von {photo}, Ziel <= 30 %)")

    usage = query("select count(*)::int as calls, coalesce(sum(cost_micro_usd),0)::bigint as micro, "
                  "coalesce(round(avg(duration_ms)),0)::int as ms from llm_usage")[0]
    per_call = usage["micro"] / usage["calls"] / 10_000 if usage["calls"] else 0  # Mikro-USD -> Cent
    print(f"\nCloud: {usage['calls']} Aufrufe, Summe {usage['micro'] / 1_000_000:.3f} USD, "
          f"Mittel {per_call:.2f} Cent je Aufruf, {usage['ms']} ms (Ziel < 1 Cent)")

    items = query("select count(*)::int as n, count(category_id)::int as cat, "
                  "count(*) filter (where needs_review)::int as review "
                  "from receipt_items where deleted_at is null and kind = 'article'")[0]
    print(f"\nArtikel mit Kategorie: {pct(items['cat'], items['n'])} ({items['cat']} von {items['n']}, "
          f"{items['review']} noch zu pruefen, Ziel >= 90 %)")


if __name__ == "__main__":
    main()
