// Edge Function: suggest-recipes
// STATUS: neu (ADR-021 "Rezeptvorschlaege aus Inventar + Koch-Chatbot"), Q-21 bis Q-24 beantwortet.
//
// Ablauf: JWT pruefen -> Mitgliedschaft + Einwilligung pruefen (household_settings.allow_cloud_ocr,
//         dieselbe Einstellung wie bei der Bon-Cloud-Erkennung, Q-23) -> Zutatenliste an Claude mit
//         erzwungenem Tool-Schema -> Nutzung in llm_usage protokollieren -> JSON zurueck.
//
// Wird NUR auf Tastendruck aufgerufen (Q-21, kein taeglicher Automatismus) -- die App-Seite entscheidet,
// wann sie ruft, diese Function selbst hat kein eigenes Scheduling.
//
// Liefert bewusst KEINE Kochanleitung (siehe ADR-021 Punkt "Rezeptquelle"): nur Titel, eine kurze
// Begruendung und welche Zutaten passen. Die Anleitung kommt von der echten Rezeptseite
// (recipe_search_url.dart), nicht von der KI -- vermeidet sowohl Urheberrechtsfragen als auch eine
// ungeprueft erfundene Anleitung (Lebensmittelsicherheit bei Zeiten/Temperaturen).
//
// Benoetigte Secrets:  ANTHROPIC_API_KEY, optional RECIPE_MODEL
// Automatisch vorhanden: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "npm:@supabase/supabase-js@2";
import { json } from "../_shared/http.ts";
import { callAnthropic, costMicroUsd, firstToolUse, PRICES, recordUsage, releaseCall, reserveCall } from "../_shared/llm.ts";
import { ingredientLines, parseRequest } from "./validate.ts";

const DEFAULT_MODEL = Deno.env.get("RECIPE_MODEL") ?? "claude-haiku-4-5-20251001";
// Anzahl und Laenge der Zutaten (Name, Menge, Einheit) begrenzt validate.ts (Codereview-Funde 2026-10-01 und 2026-10-16).

const SYSTEM = `Du schlaegst Rezeptideen fuer einen Haushalt vor, basierend auf Zutaten, die er gerade zuhause hat.
Die Liste ist nach Dringlichkeit geordnet: die ersten Eintraege verderben bald und sollten bevorzugt verwertet werden.

Regeln:
- Schlage 3 bis 5 Rezeptideen vor, die moeglichst viele der gelisteten Zutaten verwenden, besonders die ersten (dringenden) in der Liste.
- Gib NUR Titel, eine kurze Begruendung (ein Satz, z.B. "nutzt den Joghurt, der bald ablaeuft") und die passenden Zutatennamen aus der Liste zurueck.
- Erfinde KEINE Kochanleitung, keine Mengenangaben, keine Zeiten oder Temperaturen -- das liefert eine andere Quelle.
- Nenne nur Zutaten aus der uebergebenen Liste als "matchingIngredients", keine erfundenen.`;

// Nur mit allow_missing (ADR-042): Gerichte fuer die Wochenplanung, fuer die erst noch eingekauft wird.
const SYSTEM_ALLOW_MISSING = `
- Die Rezeptideen duerfen auch Zutaten brauchen, die NICHT in der Liste stehen. Nenne sie als "missingIngredients", hoechstens 6 je Idee, mit einem einfachen deutschen Namen ohne Menge (z.B. "Sahne").
- Salz, Pfeffer, Wasser und Oel gelten als vorhanden und werden nicht genannt.
- Nutze trotzdem moeglichst viel aus der Liste.`;

const TOOL = {
  name: "submit_suggestions",
  description: "Uebergibt die vorgeschlagenen Rezeptideen.",
  input_schema: {
    type: "object",
    properties: {
      suggestions: {
        type: "array",
        items: {
          type: "object",
          properties: {
            title: { type: "string" },
            reason: { type: "string" },
            matchingIngredients: { type: "array", items: { type: "string" } },
            missingIngredients: { type: "array", items: { type: "string" } },
          },
          required: ["title", "reason", "matchingIngredients"],
        },
      },
    },
    required: ["suggestions"],
  },
};

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  // 1) Nutzer aus JWT
  const authHeader = req.headers.get("Authorization") ?? "";
  const userClient = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData.user) return json({ error: "unauthorized" }, 401);

  // 2) Eingabe (validate.ts)
  let raw: unknown;
  try {
    raw = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const parsed = parseRequest(raw);
  if (!parsed.ok) return json({ error: parsed.error }, 400);
  const body = parsed.value;
  const model = body.model ?? DEFAULT_MODEL;
  if (!(model in PRICES)) return json({ error: "model_not_allowed", allowed: Object.keys(PRICES) }, 400);

  // 3) Mitgliedschaft + Einwilligung ueber RLS des Aufrufers pruefen (Q-23: dieselbe Einstellung wie
  //    bei der Bon-Cloud-Erkennung, kein eigener Schalter).
  const { data: settings, error: setErr } = await userClient
    .from("household_settings")
    .select("allow_cloud_ocr")
    .eq("household_id", body.household_id)
    .maybeSingle();
  if (setErr || !settings) return json({ error: "forbidden" }, 403);
  if (!settings.allow_cloud_ocr) return json({ error: "cloud_ocr_not_allowed" }, 403);

  // 3b) Tageslimit je Haushalt (Doku 09 §2, Missbrauchsschutz): alle KI-Aufrufe der letzten 24 Stunden, atomar reserviert
  //     (_shared/llm.ts, Migration 0030). Schlaegt die Pruefung selbst fehl, wird abgelehnt statt blind zugelassen.
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const reservation = await reserveCall(admin, body.household_id, model);
  if (!reservation.ok) return json({ error: reservation.error }, reservation.status);

  // 4) Claude
  const messages = [{
    role: "user",
    content: `Zutaten im Haus (dringlichste zuerst):\n${ingredientLines(body.ingredients)}\n\nRufe submit_suggestions auf.`,
  }];

  const started = Date.now();
  const reply = await callAnthropic({
    model,
    max_tokens: body.allow_missing ? 1536 : 1024,
    system: body.allow_missing ? SYSTEM + SYSTEM_ALLOW_MISSING : SYSTEM,
    tools: [TOOL],
    tool_choice: { type: "tool", name: "submit_suggestions" },
    messages,
  });
  const toolUse = reply ? firstToolUse(reply) : null;
  if (!reply || !toolUse) {
    await releaseCall(admin, reservation.id);
    return json({ error: "llm_failed" }, 502);
  }

  // 5) Nutzung in die reservierte Zeile eintragen
  await recordUsage(admin, reservation.id, { model, usage: reply.usage, durationMs: Date.now() - started });

  const input = (toolUse.input ?? {}) as { suggestions?: unknown };
  return json({
    suggestions: input.suggestions ?? [],
    model,
    usage: { ...reply.usage, cost_micro_usd: costMicroUsd(model, reply.usage) },
    duration_ms: Date.now() - started,
  });
});
