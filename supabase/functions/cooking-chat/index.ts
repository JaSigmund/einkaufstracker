// Edge Function: cooking-chat
// STATUS: neu (ADR-021 "Rezeptvorschlaege aus Inventar + Koch-Chatbot"), Q-21 bis Q-24 beantwortet.
//
// Ablauf: JWT pruefen -> Mitgliedschaft + Einwilligung pruefen (household_settings.allow_cloud_ocr,
//         Q-23: dieselbe Einstellung wie bei der Bon-Cloud-Erkennung) -> Nachricht + begrenzter
//         Gespraechsverlauf + Rezeptkontext an Claude -> Nutzung in llm_usage protokollieren -> Antwort.
//
// Zustandslos (Q-22): kein Server-seitiger Gespraechsverlauf. Der Client (CookingChatPanel) haelt den
// Verlauf lokal und schickt bei jeder Nachricht ein begrenztes Fenster mit (siehe `history`, serverseitig
// zusaetzlich auf MAX_HISTORY gekappt -- dem Client nie blind vertrauen).
//
// Benoetigte Secrets:  ANTHROPIC_API_KEY, optional RECIPE_MODEL
// Automatisch vorhanden: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "npm:@supabase/supabase-js@2";

const PRICES: Record<string, { in: number; out: number }> = {
  "claude-haiku-4-5-20251001": { in: 1, out: 5 },
  "claude-sonnet-5": { in: 2, out: 10 },
};
const DEFAULT_MODEL = Deno.env.get("RECIPE_MODEL") ?? "claude-haiku-4-5-20251001";
const MAX_MESSAGE_CHARS = 2000;
const MAX_HISTORY = 6;
const MAX_INGREDIENTS = 40;
// Codereview-Fund 2026-10-01: recipe_title hatte gar keine Laengenpruefung, ingredients/history waren nur
// in der Anzahl begrenzt, nicht in der Laenge jedes einzelnen Eintrags -- ein direkter API-Aufruf (nicht
// der normale Client) haette darueber beliebig grosse Prompts und damit Kosten pro Nachricht erzeugen
// koennen.
const MAX_LABEL_CHARS = 200;

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

type HistoryEntry = { text: string; from_user: boolean };

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  // 1) Nutzer aus JWT
  const authHeader = req.headers.get("Authorization") ?? "";
  const userClient = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData.user) return json({ error: "unauthorized" }, 401);

  // 2) Eingabe
  let body: {
    household_id: string;
    message: string;
    history?: HistoryEntry[];
    recipe_title?: string;
    ingredients?: string[];
    model?: string;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  if (!body.household_id || typeof body.message !== "string" || body.message.trim().length === 0) {
    return json({ error: "invalid_input" }, 400);
  }
  if (body.message.length > MAX_MESSAGE_CHARS) return json({ error: "message_too_long" }, 400);
  if (body.recipe_title != null && (typeof body.recipe_title !== "string" || body.recipe_title.length > MAX_LABEL_CHARS)) {
    return json({ error: "invalid_input" }, 400);
  }
  if ((body.ingredients ?? []).some((i) => typeof i !== "string" || i.length > MAX_LABEL_CHARS)) {
    return json({ error: "invalid_input" }, 400);
  }
  if ((body.history ?? []).some((h) => typeof h.text !== "string" || h.text.length > MAX_MESSAGE_CHARS)) {
    return json({ error: "invalid_input" }, 400);
  }
  const ingredients = (body.ingredients ?? []).slice(0, MAX_INGREDIENTS);
  // Serverseitig zusaetzlich kappen, unabhaengig davon, was der Client schickt (Q-22).
  const history = (body.history ?? []).slice(-MAX_HISTORY);
  const model = body.model ?? DEFAULT_MODEL;
  if (!(model in PRICES)) return json({ error: "model_not_allowed", allowed: Object.keys(PRICES) }, 400);

  // 3) Mitgliedschaft + Einwilligung (Q-23: dieselbe Einstellung wie bei der Bon-Cloud-Erkennung)
  const { data: settings, error: setErr } = await userClient
    .from("household_settings")
    .select("allow_cloud_ocr")
    .eq("household_id", body.household_id)
    .maybeSingle();
  if (setErr || !settings) return json({ error: "forbidden" }, 403);
  if (!settings.allow_cloud_ocr) return json({ error: "cloud_ocr_not_allowed" }, 403);

  // 4) Claude (keine Tool-Erzwingung, einfache Textantwort)
  const system = `Du bist ein hilfreicher Koch-Assistent in einer Haushalts-App. ` +
    `Der Nutzer sieht gerade das Rezept "${body.recipe_title ?? "unbekannt"}". ` +
    `Zutaten, die er dafuer im Haus hat: ${ingredients.length > 0 ? ingredients.join(", ") : "keine bekannt"}. ` +
    `Beantworte Kochfragen kurz, praktisch und auf Deutsch. ` +
    `Schlaegst du einen Ersatz fuer eine Zutat vor, nenne eine konkrete Alternative. ` +
    `Erfinde keine genauen Zeiten oder Temperaturen, die du nicht sicher weisst -- verweise im Zweifel auf allgemeine Erfahrungswerte statt exakte Angaben zu behaupten.`;

  const messages = [
    ...history.map((h) => ({ role: h.from_user ? "user" : "assistant", content: h.text })),
    { role: "user", content: body.message },
  ];

  const started = Date.now();
  const resp = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": Deno.env.get("ANTHROPIC_API_KEY")!,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({ model, max_tokens: 512, system, messages }),
  });
  if (!resp.ok) {
    console.error("anthropic_error", resp.status, await resp.text());
    return json({ error: "llm_failed" }, 502);
  }
  const result = await resp.json();
  const textBlock = (result.content ?? []).find((c: { type: string }) => c.type === "text");
  if (!textBlock) return json({ error: "llm_failed" }, 502);
  const usage = result.usage ?? { input_tokens: 0, output_tokens: 0 };

  // 5) Nutzung protokollieren
  const price = PRICES[model];
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
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
    reply: textBlock.text,
    model,
    usage: { input_tokens: usage.input_tokens, output_tokens: usage.output_tokens, cost_micro_usd: usage.input_tokens * price.in + usage.output_tokens * price.out },
    duration_ms: Date.now() - started,
  });
});
