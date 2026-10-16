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
import { ingredientLines, parseRequest } from "./validate.ts";

// Gleiche Preistabelle wie parse-receipt (Stand 2026-09; vor Produktivbetrieb gegen die offizielle
// Preisliste pruefen).
const PRICES: Record<string, { in: number; out: number }> = {
  "claude-haiku-4-5-20251001": { in: 1, out: 5 },
  "claude-sonnet-5": { in: 2, out: 10 },
};
const DEFAULT_MODEL = Deno.env.get("RECIPE_MODEL") ?? "claude-haiku-4-5-20251001";
// Anzahl und Laenge der Zutaten (Name, Menge, Einheit) begrenzt validate.ts (Codereview-Funde 2026-10-01 und 2026-10-16).

// Tageslimit je Haushalt ueber alle KI-Funktionen (siehe Block 3b). Grosszuegig fuer normale Nutzung (ein
// Kochabend mit Chat sind ein paar Dutzend Nachrichten), aber eine harte Obergrenze fuer die Kosten.
const DAILY_CALL_LIMIT = 40;

const SYSTEM = `Du schlaegst Rezeptideen fuer einen Haushalt vor, basierend auf Zutaten, die er gerade zuhause hat.
Die Liste ist nach Dringlichkeit geordnet: die ersten Eintraege verderben bald und sollten bevorzugt verwertet werden.

Regeln:
- Schlage 3 bis 5 Rezeptideen vor, die moeglichst viele der gelisteten Zutaten verwenden, besonders die ersten (dringenden) in der Liste.
- Gib NUR Titel, eine kurze Begruendung (ein Satz, z.B. "nutzt den Joghurt, der bald ablaeuft") und die passenden Zutatennamen aus der Liste zurueck.
- Erfinde KEINE Kochanleitung, keine Mengenangaben, keine Zeiten oder Temperaturen -- das liefert eine andere Quelle.
- Nenne nur Zutaten aus der uebergebenen Liste als "matchingIngredients", keine erfundenen.`;

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
          },
          required: ["title", "reason", "matchingIngredients"],
        },
      },
    },
    required: ["suggestions"],
  },
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

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

  // 3b) Tageslimit je Haushalt (Doku 09 §2, Missbrauchsschutz): zaehlt ALLE KI-Aufrufe der letzten 24 Stunden
  //     ueber llm_usage (Bon-Erkennung, Rezeptvorschlaege, Koch-Chat teilen sich die Tabelle). llm_usage
  //     protokolliert Kosten sonst nur im Nachhinein -- ohne dieses Limit koennte ein direkter API-Aufruf
  //     beliebig oft Kosten erzeugen. Schlaegt die Zaehlung selbst fehl, wird abgelehnt statt blind zugelassen.
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { count: usedToday, error: countErr } = await admin
    .from("llm_usage")
    .select("id", { count: "exact", head: true })
    .eq("household_id", body.household_id)
    .gte("created_at", new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString());
  if (countErr) return json({ error: "usage_check_failed" }, 500);
  if ((usedToday ?? 0) >= DAILY_CALL_LIMIT) return json({ error: "daily_limit_reached" }, 429);

  // 4) Claude
  const messages = [{
    role: "user",
    content: `Zutaten im Haus (dringlichste zuerst):\n${ingredientLines(body.ingredients)}\n\nRufe submit_suggestions auf.`,
  }];

  const started = Date.now();
  const resp = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": Deno.env.get("ANTHROPIC_API_KEY")!,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model,
      max_tokens: 1024,
      system: SYSTEM,
      tools: [TOOL],
      tool_choice: { type: "tool", name: "submit_suggestions" },
      messages,
    }),
  });
  if (!resp.ok) {
    console.error("anthropic_error", resp.status, await resp.text());
    return json({ error: "llm_failed" }, 502);
  }
  const result = await resp.json();
  const toolUse = (result.content ?? []).find((c: { type: string }) => c.type === "tool_use");
  if (!toolUse) return json({ error: "llm_failed" }, 502);
  const usage = result.usage ?? { input_tokens: 0, output_tokens: 0 };

  // 5) Nutzung protokollieren (service role, gleiche Tabelle wie bei parse-receipt)
  const price = PRICES[model];
  await admin.from("llm_usage").insert({
    household_id: body.household_id,
    receipt_id: null,
    model,
    input_tokens: usage.input_tokens,
    output_tokens: usage.output_tokens,
    cost_micro_usd: usage.input_tokens * price.in + usage.output_tokens * price.out,
    duration_ms: Date.now() - started,
  });

  return json({
    suggestions: toolUse.input.suggestions ?? [],
    model,
    usage: { input_tokens: usage.input_tokens, output_tokens: usage.output_tokens, cost_micro_usd: usage.input_tokens * price.in + usage.output_tokens * price.out },
    duration_ms: Date.now() - started,
  });
});
