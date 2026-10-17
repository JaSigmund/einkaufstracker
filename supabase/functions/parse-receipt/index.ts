// Edge Function: parse-receipt
// STATUS: deployt und in Phase 0 gegen echte Bons getestet (siehe Doku 05 Bon-Erkennung §8).
//
// Ablauf: JWT pruefen -> Eingabe pruefen (validate.ts) -> Einwilligung pruefen -> Tageslimit ueber llm_usage
//         -> Bild an Claude Vision mit erzwungenem Tool-Schema
//         -> Ergebnis serverseitig validieren (Summencheck) -> optional Nachfrage bei Abweichung (v3)
//         -> Nutzung in llm_usage protokollieren -> JSON zurueck.
//
// Varianten (Body-Feld "variant"):
//   v1  urspruengliche, ausfuehrliche Ausgabe (nur noch als Vergleichswert)
//   v2  knappe Ausgabe + praezisere Regeln (Mengenzeilen sind keine Positionen, Rabatt/Pfand, Ziffern exakt)
//   v3  wie v2, bei Summenabweichung eine Nachfrage an das Modell (max. 1)
// Modell (Body-Feld "model") nur aus der Allowlist; Standard aus Secret RECEIPT_MODEL.
//
// Benoetigte Secrets:  ANTHROPIC_API_KEY, optional RECEIPT_MODEL
// Automatisch vorhanden: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "npm:@supabase/supabase-js@2";
import { json } from "../_shared/http.ts";
import {
  callAnthropic,
  costMicroUsd,
  firstToolUse,
  PRICES,
  recordExtraCall,
  recordUsage,
  releaseCall,
  reserveCall,
  type ToolUse,
  type Usage,
} from "../_shared/llm.ts";
import { parseRequest } from "./validate.ts";

// Preise und Tageslimit stehen in _shared/llm.ts (gemeinsam fuer alle KI-Functions). Codereview-Fund 2026-10-16: die
// Bon-Erkennung zaehlte zwar in llm_usage mit, pruefte das Limit aber selbst nicht.
const DEFAULT_MODEL = Deno.env.get("RECEIPT_MODEL") ?? "claude-haiku-4-5-20251001";

// ---------------------------------------------------------------------------
// v1 (Vergleichswert)
// ---------------------------------------------------------------------------
const SYSTEM_V1 = `Du liest oesterreichische Einkaufsbons (Billa, Hofer u.a.) und gibst sie strukturiert wieder.
Regeln:
- Gib nur Zeilen wieder, die auf dem Bon stehen. Nichts erfinden. Bei unleserlichen Stellen: uncertain=true.
- Betraege als ganze Cent (2,49 EUR = 249). Rabatte negativ mit kind="discount". Pfand mit kind="deposit".
- Keine Zahlungs-, Steuer- oder Bonus-Club-Zeilen als Positionen.
- Mengenzeilen (z.B. "2 x 1,29" oder "0,534 kg x 3,99") gehoeren zur Position darueber: quantity, quantity_unit, unit_price_cents setzen.
- Wiegeware: quantity in kg, unit_price_cents je kg.
- category_hint: exakt einen Namen aus der uebergebenen Kategorieliste waehlen, sonst null.
- purchased_at als ISO-8601 (Europe/Vienna), total_cents = Endsumme "Zu zahlen".`;

const TOOL_V1 = {
  name: "submit_receipt",
  description: "Uebergibt den gelesenen Kassenbon.",
  input_schema: {
    type: "object",
    properties: {
      store_name: { type: ["string", "null"] },
      purchased_at: { type: ["string", "null"] },
      total_cents: { type: ["integer", "null"] },
      items: {
        type: "array",
        items: {
          type: "object",
          properties: {
            raw_text: { type: "string" },
            kind: { type: "string", enum: ["article", "deposit", "discount"] },
            quantity: { type: "number" },
            quantity_unit: { type: "string", enum: ["piece", "kg", "l"] },
            unit_price_cents: { type: ["integer", "null"] },
            line_total_cents: { type: "integer" },
            category_hint: { type: ["string", "null"] },
            uncertain: { type: "boolean" },
          },
          required: ["raw_text", "kind", "quantity", "quantity_unit", "line_total_cents", "uncertain"],
        },
      },
      notes: { type: ["string", "null"] },
    },
    required: ["items"],
  },
};

// ---------------------------------------------------------------------------
// v2 / v3: knappes Format, praezisere Regeln
// ---------------------------------------------------------------------------
const SYSTEM_V2 = `Du liest oesterreichische Einkaufsbons (Billa, Hofer u.a.) von Fotos und gibst die Positionen exakt wieder.

Umfang: Nur der Positionsbereich zwischen der Zeile mit Datum/Zeit und der Zeile "Summe". Kopf, Kundenbeleg/Zahlungsblock, Steuerblock, QR-Codes und Fussbereich ignorieren.

Regeln:
1. Eine Position je gedruckter Artikelzeile, die mit einem Betrag endet (rechts steht oft ein Steuerbuchstabe wie B, C, D, H vor dem Betrag).
2. MENGENZEILEN sind KEINE Positionen. Zeilen wie "2 x 1.19", "-2 x 0.25" oder "0.986 kg (N) x 4.99 EUR/kg" stehen VOR der Artikelzeile, haben keinen Zeilenbetrag und gehoeren zur Artikelzeile darunter. Nutze sie nur fuer qty (Menge) und unit ("kg" oder "l" bei Wiegeware), gib sie nie als eigene Position aus.
3. Rabattzeilen (z.B. "EXTREM AKTION", "NIMM MEHR", "Rabatt 25%", "Rabattsammler") haben einen negativen Betrag: kind="discount". Pfand-Zeilen (PFAND, LEERGUT, EINWEGPFAND, FLASCHENKASSEN): kind="deposit" (Rueckgaben sind negativ). Alles andere: kind="article".
4. Zeilen ohne Betrag (z.B. nur "EXTREM AKTION" als Hinweis) sind keine Positionen.
5. Betraege in ganzen Cent, so wie gedruckt: 3.89 = 389, -0.86 = -86. Ziffern EXAKT abschreiben, nicht raten oder runden. Ist eine Ziffer nicht sicher lesbar, setze unsure=true.
6. text = Artikelname genau wie gedruckt (inkl. Praefixe wie "IC").
7. Kontrolle: Die Summe aller total-Werte muss dem Betrag in der Zeile "Summe" (total_cents) entsprechen. Stimmt sie nicht, lies die Preise noch einmal genau, bevor du antwortest.
8. purchased_at als ISO-8601 (Europe/Vienna) aus Datum und Zeit des Bons.`;

const TOOL_V2 = {
  name: "submit_receipt",
  description: "Uebergibt den gelesenen Kassenbon.",
  input_schema: {
    type: "object",
    properties: {
      store: { type: "string" },
      purchased_at: { type: "string" },
      total_cents: { type: "integer", description: "Betrag der Zeile Summe in Cent" },
      items: {
        type: "array",
        items: {
          type: "object",
          properties: {
            text: { type: "string" },
            kind: { type: "string", enum: ["article", "deposit", "discount"] },
            total: { type: "integer", description: "Zeilenbetrag in Cent" },
            qty: { type: "number", description: "Menge, nur wenn nicht 1" },
            unit: { type: "string", enum: ["kg", "l"], description: "nur bei Wiegeware" },
            unsure: { type: "boolean", description: "nur setzen wenn true" },
          },
          required: ["text", "kind", "total"],
        },
      },
    },
    required: ["total_cents", "items"],
  },
};

type Item = {
  raw_text: string;
  kind: string;
  quantity: number;
  quantity_unit: string;
  line_total_cents: number | null;
  uncertain: boolean;
  category_hint?: string | null;
  unit_price_cents?: number | null;
};
type Receipt = { store_name: string | null; purchased_at: string | null; total_cents: number | null; items: Item[] };

// v2-Ausgabe auf das gemeinsame Format abbilden. `input` ist die Tool-Ausgabe des Modells, deren Form erst hier
// hergestellt wird; deshalb bewusst ohne genauen Typ.
// deno-lint-ignore no-explicit-any
function normalize(variant: string, input: any): Receipt {
  if (variant === "v1") {
    return {
      store_name: input.store_name ?? null,
      purchased_at: input.purchased_at ?? null,
      total_cents: input.total_cents ?? null,
      items: input.items ?? [],
    };
  }
  return {
    store_name: input.store ?? null,
    purchased_at: input.purchased_at ?? null,
    total_cents: input.total_cents ?? null,
    // deno-lint-ignore no-explicit-any
    items: (input.items ?? []).map((i: any): Item => ({
      raw_text: i.text,
      kind: i.kind,
      quantity: i.qty ?? 1,
      quantity_unit: i.unit ?? "piece",
      line_total_cents: Number.isInteger(i.total) ? i.total : null,
      uncertain: i.unsure === true,
    })),
  };
}

const sumCents = (r: Receipt) => r.items.reduce((s, i) => s + (Number.isInteger(i.line_total_cents) ? i.line_total_cents! : 0), 0);

async function callClaude(model: string, system: string, tool: unknown, messages: unknown[]): Promise<{ toolUse: ToolUse; usage: Usage } | null> {
  const reply = await callAnthropic({
    model,
    max_tokens: 4096,
    system,
    tools: [tool],
    tool_choice: { type: "tool", name: "submit_receipt" },
    messages,
  });
  const toolUse = reply ? firstToolUse(reply) : null;
  return reply && toolUse ? { toolUse, usage: reply.usage } : null;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  // 1) Nutzer aus JWT
  const authHeader = req.headers.get("Authorization") ?? "";
  const userClient = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData.user) return json({ error: "unauthorized" }, 401);

  // 2) Eingabe (validate.ts: Typen, Laengen, nur JPEG in Base64)
  let raw: unknown;
  try {
    raw = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const parsed = parseRequest(raw);
  if (!parsed.ok) return json({ error: parsed.error }, parsed.status);
  const body = parsed.value;
  const variant = body.variant;
  const model = body.model ?? DEFAULT_MODEL;
  if (!(model in PRICES)) return json({ error: "model_not_allowed", allowed: Object.keys(PRICES) }, 400);

  // 3) Mitgliedschaft + Einwilligung ueber RLS des Aufrufers pruefen
  const { data: settings, error: setErr } = await userClient
    .from("household_settings")
    .select("allow_cloud_ocr")
    .eq("household_id", body.household_id)
    .maybeSingle();
  if (setErr || !settings) return json({ error: "forbidden" }, 403);
  if (!settings.allow_cloud_ocr) return json({ error: "cloud_ocr_not_allowed" }, 403);

  // 4) Tageslimit je Haushalt: alle KI-Aufrufe der letzten 24 Stunden, atomar reserviert (_shared/llm.ts, Migration 0030).
  //    Schlaegt die Pruefung selbst fehl, wird abgelehnt statt blind zugelassen.
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const reservation = await reserveCall(admin, body.household_id, model);
  if (!reservation.ok) return json({ error: reservation.error }, reservation.status);

  // 5) Claude Vision
  const system = variant === "v1" ? SYSTEM_V1 : SYSTEM_V2;
  const tool = variant === "v1" ? TOOL_V1 : TOOL_V2;
  const content: unknown[] = body.images.map((data) => ({
    type: "image",
    source: { type: "base64", media_type: "image/jpeg", data },
  }));
  content.push({
    type: "text",
    text: variant === "v1"
      ? `Kategorieliste: ${JSON.stringify(body.categories)}\nHaendler-Hinweis: ${body.store_hint ?? "unbekannt"}\nLies den Bon (ggf. mehrere Fotos in Lesereihenfolge) und rufe submit_receipt auf.`
      : `Haendler-Hinweis: ${body.store_hint ?? "unbekannt"}. Lies den Bon (ggf. mehrere Fotos in Lesereihenfolge) und rufe submit_receipt auf.`,
  });
  const messages: unknown[] = [{ role: "user", content }];

  const started = Date.now();
  let totalIn = 0, totalOut = 0, attempts = 0;

  let t0 = Date.now();
  const r = await callClaude(model, system, tool, messages);
  attempts++;
  if (!r) {
    await releaseCall(admin, reservation.id);
    return json({ error: "llm_failed" }, 502);
  }
  totalIn += r.usage.input_tokens; totalOut += r.usage.output_tokens;
  // Eine unbekannte oder fremde receipt_id laesst den Aufruf nicht aus dem Protokoll fallen (recordUsage: dann ohne Verweis)
  await recordUsage(admin, reservation.id, { model, usage: r.usage, durationMs: Date.now() - t0, receiptId: body.receipt_id });
  let receipt = normalize(variant, r.toolUse.input);
  let sum = sumCents(receipt);

  // v3: eine Nachfrage, wenn die Summe nicht passt
  if (variant === "v3" && receipt.total_cents != null && receipt.total_cents !== sum) {
    const diff = receipt.total_cents - sum;
    messages.push({ role: "assistant", content: [{ type: "tool_use", ...r.toolUse }] });
    messages.push({
      role: "user",
      content: [{
        type: "tool_result",
        tool_use_id: r.toolUse.id,
        content:
          `Kontrolle fehlgeschlagen: Deine Positionen ergeben ${sum} Cent, die Zeile "Summe" nennt ${receipt.total_cents} Cent (Differenz ${diff} Cent). ` +
          `Pruefe genau: (a) sind Mengenzeilen wie "2 x 1.19" faelschlich als eigene Position ausgegeben, (b) sind Ziffern falsch gelesen, (c) fehlt eine Zeile oder ist eine doppelt? ` +
          `Lies die betroffenen Zeilen noch einmal im Bild und rufe submit_receipt mit der korrigierten vollstaendigen Liste erneut auf.`,
      }],
    });
    t0 = Date.now();
    const r2 = await callClaude(model, system, tool, messages);
    attempts++;
    if (r2) {
      totalIn += r2.usage.input_tokens; totalOut += r2.usage.output_tokens;
      await recordExtraCall(admin, { householdId: body.household_id, model, usage: r2.usage, durationMs: Date.now() - t0, receiptId: body.receipt_id });
      const receipt2 = normalize(variant, r2.toolUse.input);
      const sum2 = sumCents(receipt2);
      // Nur uebernehmen, wenn es nicht schlechter wird
      const better = receipt2.total_cents != null && Math.abs(receipt2.total_cents - sum2) <= Math.abs(receipt.total_cents - sum);
      if (better) {
        receipt = receipt2;
        sum = sum2;
      }
    }
  }

  return json({
    receipt,
    computed_sum_cents: sum,
    sum_mismatch: receipt.total_cents != null && receipt.total_cents !== sum,
    model,
    variant,
    attempts,
    usage: { input_tokens: totalIn, output_tokens: totalOut, cost_micro_usd: costMicroUsd(model, { input_tokens: totalIn, output_tokens: totalOut }) },
    duration_ms: Date.now() - started,
  });
});
