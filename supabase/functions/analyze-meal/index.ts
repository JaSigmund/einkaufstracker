// Edge Function: analyze-meal
// STATUS: neu (Phase 7c "Foto-KI", Doku 15 §6).
//
// Ablauf: JWT pruefen -> Eingabe pruefen (Foto, Produktliste) -> Mitgliedschaft + Einwilligung pruefen
//         (household_settings.allow_cloud_ocr, dieselbe Einstellung wie bei den Bons und den Rezeptvorschlaegen)
//         -> Tageslimit ueber llm_usage -> Foto, Angaben des Nutzers (Titel, Notiz, Portionen, schon eingetragene Zutaten) und
//         Produktnamen an Claude mit strengem Tool-Schema (prompt.ts)
//         -> Antwort bereinigen (sanitize.ts) -> Zutaten den Naehrwerten der Lebensmitteldatenbank zuordnen (analyze.ts, resolve.ts:
//         SQL-Suche, bei Bedarf kurze zweite KI-Auswahl aus echten Kandidaten) -> Nutzung in llm_usage protokollieren -> JSON zurueck.
//
// Die Antwort ist immer nur ein VORSCHLAG zum Bearbeiten (Doku 15 §6: Mengen aus einem Foto sind Schaetzungen mit
// hoher Streuung). Die Function legt das Foto nirgends ab; es liegt nur fuer die Dauer des Aufrufs im Speicher. Was Anthropic mit API-Eingaben tut, regeln deren Bedingungen.
//
// Benoetigte Secrets:  ANTHROPIC_API_KEY, optional MEAL_MODEL
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
} from "../_shared/llm.ts";
import { buildUserText, SYSTEM, TOOL } from "./prompt.ts";
import { parseRequest, sanitizeAnalysis } from "./sanitize.ts";
import { totalGrams, type UnitInfo, unitInfoFor, type UnitRow } from "./units.ts";
import { resolveIngredients, type Usage } from "./analyze.ts";
import { buildChoosePrompt, CHOOSE_SYSTEM, CHOOSE_TOOL, type ChooseItem, type FoodRow, parseFoodRow } from "./resolve.ts";

// Preise und Tageslimit stehen in _shared/llm.ts (gemeinsam fuer alle KI-Functions). Ein Foto zaehlt als ein Aufruf.
const DEFAULT_MODEL = Deno.env.get("MEAL_MODEL") ?? "claude-sonnet-5-5";
// Die Auswahl aus den Kandidaten ist reine Textarbeit und braucht das Foto-Modell nicht.
const CHOOSE_MODEL = "claude-haiku-5-5";
// Lehnt ein Sicherheitsfilter von Sonnet 5.5 faelschlich ab, antwortet der Server selbst mit einem passenden anderen Modell.
const FALLBACK_BETA = "server-side-fallback-2026-07-01";

/// Zweiter, kurzer KI-Aufruf ohne Bild: waehlt je Zutat einen der vorgelegten Kandidaten der Lebensmitteldatenbank (resolve.ts).
/// Ein Fehler hier ist kein Fehler der Analyse: `null`, und die Zutaten bleiben "unbekannt".
async function chooseFoods(items: ChooseItem[], dishTitle: string): Promise<{ choices: unknown; usage: Usage } | null> {
  const reply = await callAnthropic({
    model: CHOOSE_MODEL,
    // Das Denken zaehlt mit: bei zu wenig Platz kaeme gar kein Werkzeugaufruf
    max_tokens: 3000,
    output_config: { effort: "low" },
    system: CHOOSE_SYSTEM,
    tools: [CHOOSE_TOOL],
    tool_choice: { type: "auto", disable_parallel_tool_use: true },
    messages: [{ role: "user", content: buildChoosePrompt(items, dishTitle) }],
  });
  const toolUse = reply ? firstToolUse(reply) : null;
  if (!reply || !toolUse) return null;
  return { choices: toolUse.input, usage: reply.usage };
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

  // 2) Eingabe
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

  // 3) Mitgliedschaft + Einwilligung ueber RLS des Aufrufers pruefen
  const { data: settings, error: setErr } = await userClient
    .from("household_settings")
    .select("allow_cloud_ocr")
    .eq("household_id", body.household_id)
    .maybeSingle();
  if (setErr || !settings) return json({ error: "forbidden" }, 403);
  if (!settings.allow_cloud_ocr) return json({ error: "cloud_ocr_not_allowed" }, 403);

  // 3b) Tageslimit je Haushalt: alle KI-Aufrufe der letzten 24 Stunden, atomar reserviert (_shared/llm.ts, Migration 0030).
  //     Schlaegt die Pruefung selbst fehl, wird abgelehnt statt blind zugelassen.
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const reservation = await reserveCall(admin, body.household_id, model);
  if (!reservation.ok) return json({ error: reservation.error }, reservation.status);

  // 4) Claude mit Bildeingabe
  const messages = [{
    role: "user",
    content: [
      { type: "image", source: { type: "base64", media_type: "image/jpeg", data: body.image_base64 } },
      { type: "text", text: buildUserText(body.context, body.products) },
    ],
  }];

  const started = Date.now();
  const isSonnet55 = model === "claude-sonnet-5-5";
  const reply = await callAnthropic({
    model,
    // Das Denken zaehlt mit: bei zu wenig Platz kaeme gar kein Werkzeugaufruf
    max_tokens: 6000,
    ...(isSonnet55 ? { fallbacks: "default" } : {}),
    ...(isSonnet55 || model === "claude-haiku-5-5" ? { output_config: { effort: "medium" } } : {}),
    system: SYSTEM,
    tools: [TOOL],
    // Sonnet 5.5 kennt kein erzwungenes Werkzeug mehr: strenges Schema plus Anweisung im Prompt
    tool_choice: { type: "auto", disable_parallel_tool_use: true },
    messages,
  }, isSonnet55 ? { beta: FALLBACK_BETA } : {});
  const toolUse = reply ? firstToolUse(reply) : null;
  if (!reply || !toolUse) {
    await releaseCall(admin, reservation.id);
    return json({ error: "llm_failed" }, 502);
  }
  const usage = reply.usage;

  // 5) Nutzung in die reservierte Zeile eintragen
  const cost = costMicroUsd(model, usage);
  await recordUsage(admin, reservation.id, { model, usage, durationMs: Date.now() - started });

  const analysis = sanitizeAnalysis(toolUse.input, new Set(body.products.map((p) => p.id)));

  // 6) Zutaten den Naehrwerten der Lebensmitteldatenbank zuordnen (Phase N1, ADR-031)
  const resolution = await resolveIngredients(analysis.ingredients.map((i) => ({ name: i.name, state: i.state, search_terms: i.search_terms })), {
    search: async (q: string): Promise<FoodRow[]> => {
      const { data, error } = await admin.rpc("search_bls_foods", { q, n: 8, p_household: body.household_id });
      if (error) throw new Error(error.message);
      return (data ?? []).map(parseFoodRow).filter((r: FoodRow | null): r is FoodRow => r !== null);
    },
    choose: (items: ChooseItem[]) => chooseFoods(items, body.context.title ?? analysis.dish_title),
  });
  let total: Usage = { input_tokens: usage.input_tokens, output_tokens: usage.output_tokens };
  let totalCost = cost;
  if (resolution.usage) {
    const chooseCost = costMicroUsd(CHOOSE_MODEL, resolution.usage);
    await recordExtraCall(admin, { householdId: body.household_id, model: CHOOSE_MODEL, usage: resolution.usage, durationMs: Date.now() - started });
    total = { input_tokens: total.input_tokens + resolution.usage.input_tokens, output_tokens: total.output_tokens + resolution.usage.output_tokens };
    totalCost += chooseCost;
  }
  console.log("resolved", resolution.stats);

  // 7) Stueckzahlen in Gramm umrechnen (Phase N2, ADR-033): eigenes Gewicht des Haushalts, sonst Tabelle food_units
  const counted = analysis.ingredients
    .map((i, idx) => ({ i, idx, code: resolution.matches[idx]?.code ?? null }))
    .filter((x) => x.i.count !== null && x.code !== null);
  const codes = [...new Set(counted.map((x) => x.code as string))];
  const unitRows = new Map<string, UnitRow[]>();
  const householdWeights = new Map<string, number>();
  if (codes.length > 0) {
    try {
      const [units, links] = await Promise.all([
        admin.from("food_units").select("bls_code, unit_key, size, grams_edible, source").in("bls_code", codes),
        admin.from("household_food_links").select("bls_code, unit_weight_g").eq("household_id", body.household_id).is("deleted_at", null)
          .in("bls_code", codes).not("unit_weight_g", "is", null),
      ]);
      for (const r of (units.data ?? []) as UnitRow[]) {
        unitRows.set(r.bls_code, [...(unitRows.get(r.bls_code) ?? []), { ...r, grams_edible: Number(r.grams_edible) }]);
      }
      for (const r of (links.data ?? []) as { bls_code: string; unit_weight_g: number | string }[]) {
        const g = Number(r.unit_weight_g);
        if (Number.isFinite(g) && g > 0) householdWeights.set(r.bls_code, g);
      }
    } catch (e) {
      console.error("units_failed", e); // ohne Gewichte bleibt es bei der Gramm-Schaetzung der KI
    }
  }
  const unitInfos = new Map<number, UnitInfo>();
  for (const { i, idx, code } of counted) {
    const info = unitInfoFor(i.count, i.count_unit, unitRows.get(code as string) ?? [], householdWeights.get(code as string) ?? null);
    if (info) unitInfos.set(idx, info);
  }

  return json({
    analysis: {
      ...analysis,
      ingredients: analysis.ingredients.map((i, idx) => {
        const info = unitInfos.get(idx);
        const { search_terms: _terms, ...rest } = i;
        return {
          ...rest,
          // Mit bekanntem Stueckgewicht gilt die Zaehlung (2 Eier = 100 g), sonst die Gramm-Schaetzung der KI
          est_amount_g: info ? totalGrams(info) : i.est_amount_g,
          unit: info ?? null,
          match: resolution.matches[idx],
        };
      }),
    },
    model,
    usage: { input_tokens: total.input_tokens, output_tokens: total.output_tokens, cost_micro_usd: totalCost },
    duration_ms: Date.now() - started,
  });
});
