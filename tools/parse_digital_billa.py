"""Prototyp: Billa-Textparser fuer digitale Bons (PDF-Textebene). Referenz fuer den spaeteren Dart-Parser."""
import glob, re, sys, json
from decimal import Decimal
import pypdf

D = r"C:\Users\jakob\Downloads"
PRICE = r"-?\d{1,4}[.,]\d{2}"

def cents(s):
    s = s.replace(",", ".")
    neg = s.startswith("-")
    v = int((Decimal(s.lstrip("-")) * 100).to_integral_value())
    return -v if neg else v

def read_text(path):
    r = pypdf.PdfReader(path)
    text = "\n".join((p.extract_text(extraction_mode="layout") or "") for p in r.pages)
    return text.replace(" ", " ")  # PDF-Textebene enthaelt geschuetzte Leerzeichen

def parse(text):
    lines = [l.rstrip() for l in text.splitlines()]
    out = {"items": [], "qty_lines": [], "warnings": []}
    # Kopf
    for l in lines:
        m = re.search(r"Datum:\s*(\d{2}\.\d{2}\.\d{4})\s+Zeit:\s*(\d{2}:\d{2})", l)
        if m:
            out["date"], out["time"] = m.group(1), m.group(2)
            break
    start = next((i for i, l in enumerate(lines) if re.search(r"Datum:\s*\d{2}\.\d{2}\.\d{4}\s+Zeit:", l)), None)
    end = next((i for i, l in enumerate(lines) if re.match(r"\s*Summe\s+EUR\s+" + PRICE, l)), None)
    if start is None or end is None:
        out["warnings"].append("Kopf oder Summe nicht gefunden")
        return out
    out["total"] = cents(re.search(PRICE, lines[end]).group())
    pending_qty = None
    for l in lines[start + 1:end]:
        if not l.strip() or set(l.strip()) <= set("-="):
            continue
        # Mengenzeile: "2 x 1.19", "-2 x 0.25", "0.986 kg (N) x 4.99 EUR/kg" (ohne Zeilenpreis am Ende)
        mq = re.match(r"^\s*(-?\d+(?:[.,]\d+)?)\s*(kg|g|l)?\s*(?:\(N\))?\s*[xX]\s+(" + PRICE + r")\s*(?:EUR/(kg|l))?\s*$", l)
        if mq:
            pending_qty = {"qty": mq.group(1), "unit": mq.group(2) or "Stk", "unit_price": mq.group(3), "raw": l.strip()}
            out["qty_lines"].append(pending_qty)
            continue
        # Zwischensumme
        mz = re.match(r"^\s*Zwischensumme\s+EUR\s+(" + PRICE + r")\s*$", l)
        if mz:
            out["subtotal"] = cents(mz.group(1))
            continue
        # Rabatt auf Bon-Ebene (ohne Steuerbuchstaben): "jö Rabattsammler 20% -4.51", "Mineralwasser Rabatt 25% -0.37"
        mb = re.match(r"^\s*(.+?)\s+(?:(\d+)%\s+)?(-\d{1,4}[.,]\d{2})\s*$", l)
        if mb and not re.search(r"\s[A-Z]\s+-?\d", l):
            out.setdefault("bon_discounts", []).append({"name": mb.group(1).strip(), "pct": mb.group(2), "cents": cents(mb.group(3))})
            continue
        # Positionszeile: Name ... Steuerbuchstabe Preis
        mi = re.match(r"^\s*(.+?)\s+([A-Z])\s+(" + PRICE + r")\s*$", l)
        if mi:
            name, tax, price = mi.group(1).strip(), mi.group(2), cents(mi.group(3))
            kind = "article"
            if name.upper().startswith("EXTREM AKTION") or "AKTION" in name.upper() or price < 0:
                kind = "discount"
            if re.search(r"PFAND|LEERGUT|FLASCHENKASSEN", name.upper()):
                kind = "deposit"
            item = {"name": name, "tax": tax, "cents": price, "kind": kind}
            if pending_qty:
                item["qty"] = pending_qty
                pending_qty = None
            out["items"].append(item)
            continue
        if re.match(r"^\s*[A-Za-zÄÖÜäöüß .\-]+$", l):   # Label-Zeile ohne Preis (z.B. "EXTREM AKTION")
            out.setdefault("labels", []).append(l.strip())
            continue
        out["warnings"].append("Nicht erkannt: " + l.strip())
    # Steuerblock
    out["tax"] = {}
    for l in lines:
        m = re.match(r"^\s*([A-Z])\s*:\s*(?:([\d.,]+)%\s*MwSt\s*von|nicht steuerbar)\s*(" + PRICE + r")?\s*(?:=\s*(" + PRICE + r"))?", l)
        if m:
            letter = m.group(1)
            if "nicht steuerbar" in l:
                gross = cents(re.search(PRICE, l).group())
                out["tax"][letter] = {"rate": None, "gross": gross}
            else:
                net = cents(m.group(3)); vat = cents(m.group(4))
                out["tax"][letter] = {"rate": m.group(2), "net": net, "vat": vat, "gross": net + vat}
    return out

def check(res):
    msgs = []
    items_sum = sum(i["cents"] for i in res["items"])
    bon_disc = sum(d["cents"] for d in res.get("bon_discounts", []))
    expected_total = items_sum + bon_disc
    ok_total = expected_total == res.get("total")
    msgs.append(f"Positionen {items_sum/100:.2f} + Bon-Rabatte {bon_disc/100:.2f} = {expected_total/100:.2f} gegen Summe {res.get('total', 0)/100:.2f}: {'OK' if ok_total else 'ABWEICHUNG'}")
    if "subtotal" in res:
        ok_sub = res["subtotal"] == items_sum
        msgs.append(f"Zwischensumme {res['subtotal']/100:.2f} gegen Positionen {items_sum/100:.2f}: {'OK' if ok_sub else 'ABWEICHUNG'}")
        ok_total = ok_total and ok_sub
    # Steuerblock: je Klasse Bruttosumme der Positionen; Bon-Rabatte verteilt der Bon anteilig auf die Klassen
    per = {}
    for i in res["items"]:
        per[i["tax"]] = per.get(i["tax"], 0) + i["cents"]
    block_sum = sum(t["gross"] for t in res["tax"].values())
    missing = [k for k in per if k not in res["tax"]]
    if bon_disc == 0:
        diffs = {k: per[k] - res["tax"][k]["gross"] for k in per if k in res["tax"] and per[k] != res["tax"][k]["gross"]}
        ok_tax = not missing and not diffs
        if diffs: msgs.append("  Klassen-Abweichung: " + ", ".join(f"{k} {v/100:+.2f}" for k, v in diffs.items()))
    else:
        # mit Bon-Rabatt: Summe ueber alle Klassen muss der Bon-Summe entsprechen
        ok_tax = not missing and block_sum == res.get("total")
        msgs.append(f"  Bon-Rabatt vorhanden: Steuerblock gesamt {block_sum/100:.2f} gegen Summe {res.get('total', 0)/100:.2f}")
    if missing: msgs.append(f"  Klassen ohne Steuerblock: {missing}")
    msgs.append("Steuerblock: " + ("OK" if ok_tax else "ABWEICHUNG"))
    return ok_total, ok_tax, msgs

if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    tot = 0; ok_all = 0
    for f in sorted(glob.glob(D + r"\00-0*.pdf")):
        res = parse(read_text(f))
        ok_total, ok_tax, msgs = check(res)
        tot += 1; ok_all += ok_total and ok_tax
        print("==", f.split("\\")[-1], "| Datum", res.get("date"), "| Positionen", len(res["items"]),
              "| Rabatt", sum(i["kind"] == "discount" for i in res["items"]),
              "| Pfand", sum(i["kind"] == "deposit" for i in res["items"]),
              "| Mengenzeilen", len(res["qty_lines"]))
        for m in msgs: print("  ", m)
        for w in res["warnings"]: print("   WARN", w)
    print(f"\n{ok_all}/{tot} Bons mit Summe UND Steuerblock exakt")
