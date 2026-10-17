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
import { json } from "../_shared/http.ts";
import { callAnthropic, costMicroUsd, firstText, PRICES, recordUsage, releaseCall, reserveCall } from "../_shared/llm.ts";
import { parseRequest } from "./validate.ts";

const DEFAULT_MODEL = Deno.env.get("RECIPE_MODEL") ?? "claude-haiku-4-5-20251001";
// Laengen und Anzahl von Nachricht, Rezepttitel, Zutaten und Verlauf begrenzt validate.ts (Codereview-Funde 2026-10-01
// und 2026-10-16).

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  // 1) Nutzer aus JWT
  const authHeader = req.headers.get("Authorization") ?? "";
  const userClient = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData.user) return json({ error: "unauthorized" }, 401);

  // 2) Eingabe (validate.ts; kappt Zutaten und Verlauf serverseitig, Q-22)
  let raw: unknown;
  try {
    raw = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const parsed = parseRequest(raw);
  if (!parsed.ok) return json({ error: parsed.error }, 400);
  const body = parsed.value;
  const { ingredients, history } = body;
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

  // 3b) Tageslimit je Haushalt (Doku 09 §2, Missbrauchsschutz): alle KI-Aufrufe der letzten 24 Stunden, atomar reserviert
  //     (_shared/llm.ts, Migration 0030). Schlaegt die Pruefung selbst fehl, wird abgelehnt statt blind zugelassen.
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const reservation = await reserveCall(admin, body.household_id, model);
  if (!reservation.ok) return json({ error: reservation.error }, reservation.status);

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
  const reply = await callAnthropic({ model, max_tokens: 512, system, messages });
  const text = reply ? firstText(reply) : null;
  if (!reply || text === null) {
    await releaseCall(admin, reservation.id);
    return json({ error: "llm_failed" }, 502);
  }

  // 5) Nutzung in die reservierte Zeile eintragen
  await recordUsage(admin, reservation.id, { model, usage: reply.usage, durationMs: Date.now() - started });

  return json({
    reply: text,
    model,
    usage: { ...reply.usage, cost_micro_usd: costMicroUsd(model, reply.usage) },
    duration_ms: Date.now() - started,
  });
});
