// KI-Aufrufe der Edge Functions: Preise, Tageslimit, Protokollierung in llm_usage, Aufruf der Anthropic-API.
//
// Codereview 2026-10-16 (Funde A4 und S9): Preistabelle, Tageslimit und Protokollierung standen in vier Functions je
// einmal da; in einer fehlte das Limit deshalb ganz. Ausserdem wurde erst gezaehlt und danach aufgerufen, parallele
// Anfragen konnten das Limit ueberschreiten. Jetzt reserviert reserveCall() atomar eine Zeile in llm_usage
// (RPC reserve_llm_call, Migration 0030); recordUsage() traegt danach Tokens und Kosten ein, releaseCall() gibt die
// Reservierung wieder frei, wenn der Modellaufruf scheitert.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

/// Service-Client (createClient mit dem Service-Schluessel), ohne Datenbank-Typen wie in den Functions selbst.
// deno-lint-ignore no-explicit-any
export type Admin = SupabaseClient<any, any, any>;

/// Preise in Mikro-USD je Token (= USD je Million Tokens). Stand 2026-09; vor Produktivbetrieb gegen die offizielle
/// Preisliste pruefen. Nur Modelle aus dieser Tabelle sind erlaubt.
export const PRICES: Record<string, { in: number; out: number }> = {
  "claude-haiku-4-5-20251001": { in: 1, out: 5 },
  "claude-haiku-5-5": { in: 0.1, out: 0.5 },
  "claude-sonnet-5": { in: 2, out: 10 },
  "claude-sonnet-5-5": { in: 2, out: 10 },
};

/// Tageslimit je Haushalt ueber alle KI-Functions (Doku 09 §2, Missbrauchsschutz): ein Aufruf zaehlt als einer, egal wie
/// gross. Grosszuegig fuer normale Nutzung (ein Kochabend mit Chat sind ein paar Dutzend Nachrichten).
export const DAILY_CALL_LIMIT = 40;

export type Usage = { input_tokens: number; output_tokens: number };

export const isAllowedModel = (model: string) => model in PRICES;

export function costMicroUsd(model: string, usage: Usage): number {
  const price = PRICES[model];
  return price ? usage.input_tokens * price.in + usage.output_tokens * price.out : 0;
}

export type Reservation = { ok: true; id: string } | { ok: false; status: 429 | 500; error: string };

/// Prueft das Tageslimit und reserviert in derselben Transaktion eine Zeile in llm_usage. Schlaegt die Pruefung selbst
/// fehl, wird abgelehnt statt blind zugelassen.
export async function reserveCall(admin: Admin, householdId: string, model: string, limit = DAILY_CALL_LIMIT): Promise<Reservation> {
  const { data, error } = await admin.rpc("reserve_llm_call", { p_household: householdId, p_model: model, p_limit: limit });
  if (error) {
    console.error("reserve_llm_call_failed", error.message);
    return { ok: false, status: 500, error: "usage_check_failed" };
  }
  if (typeof data !== "string") return { ok: false, status: 429, error: "daily_limit_reached" };
  return { ok: true, id: data };
}

/// Traegt Tokens, Kosten und Dauer in die reservierte Zeile ein. Eine Bon-ID, die es nicht gibt oder die zu einem anderen
/// Haushalt gehoert, darf den Aufruf nicht aus dem Protokoll fallen lassen: dann ohne Verweis.
export async function recordUsage(
  admin: Admin,
  reservationId: string,
  entry: { model: string; usage: Usage; durationMs: number; receiptId?: string | null },
): Promise<void> {
  const row = {
    model: entry.model,
    input_tokens: entry.usage.input_tokens,
    output_tokens: entry.usage.output_tokens,
    cost_micro_usd: costMicroUsd(entry.model, entry.usage),
    duration_ms: entry.durationMs,
    receipt_id: entry.receiptId ?? null,
  };
  const { error } = await admin.from("llm_usage").update(row).eq("id", reservationId);
  if (!error) return;
  if (row.receipt_id !== null) {
    const { error: retry } = await admin.from("llm_usage").update({ ...row, receipt_id: null }).eq("id", reservationId);
    if (!retry) return;
    console.error("llm_usage_update_failed", retry.message);
    return;
  }
  console.error("llm_usage_update_failed", error.message);
}

/// Gibt eine Reservierung frei, wenn der Modellaufruf gescheitert ist (ein Fehlschlag zaehlt nicht zum Limit).
export async function releaseCall(admin: Admin, reservationId: string): Promise<void> {
  const { error } = await admin.from("llm_usage").delete().eq("id", reservationId);
  if (error) console.error("llm_usage_release_failed", error.message);
}

/// Ein weiterer Modellaufruf innerhalb desselben Aufrufs (Nachfrage der Bon-Erkennung, Auswahl der Lebensmittel): zaehlt
/// als eigene Zeile, ohne eigene Pruefung des Limits (wie bisher).
export async function recordExtraCall(
  admin: Admin,
  entry: { householdId: string; model: string; usage: Usage; durationMs: number; receiptId?: string | null },
): Promise<void> {
  const row = {
    household_id: entry.householdId,
    model: entry.model,
    input_tokens: entry.usage.input_tokens,
    output_tokens: entry.usage.output_tokens,
    cost_micro_usd: costMicroUsd(entry.model, entry.usage),
    duration_ms: entry.durationMs,
    receipt_id: entry.receiptId ?? null,
  };
  const { error } = await admin.from("llm_usage").insert(row);
  if (!error) return;
  if (row.receipt_id !== null) {
    const { error: retry } = await admin.from("llm_usage").insert({ ...row, receipt_id: null });
    if (!retry) return;
    console.error("llm_usage_insert_failed", retry.message);
    return;
  }
  console.error("llm_usage_insert_failed", error.message);
}

export type ToolUse = { id: string; name: string; input: unknown };
export type AnthropicReply = { content: { type: string; text?: string; id?: string; name?: string; input?: unknown }[]; usage: Usage };

/// Ruft die Messages-API auf. `null` bei einem Fehler der API (wird protokolliert, ohne den Inhalt der Anfrage).
/// [deps]: fetch und apiKey nur fuer Tests (ohne Zugriff auf die Umgebung), beta fuer den Header anthropic-beta.
export async function callAnthropic(
  body: Record<string, unknown>,
  deps: { fetch?: typeof fetch; apiKey?: string; beta?: string } = {},
): Promise<AnthropicReply | null> {
  const resp = await (deps.fetch ?? fetch)("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": deps.apiKey ?? Deno.env.get("ANTHROPIC_API_KEY") ?? "",
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
      ...(deps.beta ? { "anthropic-beta": deps.beta } : {}),
    },
    body: JSON.stringify(body),
  });
  if (!resp.ok) {
    console.error("anthropic_error", resp.status, await resp.text());
    return null;
  }
  const result = await resp.json();
  const u = result.usage ?? {};
  // Bei einer Ablehnung oder ohne Platz fuer die Antwort fehlt der Werkzeugaufruf; der Aufrufer sieht nur noch das Ergebnis
  if (result.stop_reason !== "tool_use" && result.stop_reason !== "end_turn") console.error("anthropic_stop", result.stop_reason);
  return {
    content: Array.isArray(result.content) ? result.content : [],
    usage: { input_tokens: Number(u.input_tokens ?? 0), output_tokens: Number(u.output_tokens ?? 0) },
  };
}

/// Der erste tool_use-Block der Antwort, `null` wenn das Modell kein Werkzeug aufgerufen hat.
export function firstToolUse(reply: AnthropicReply): ToolUse | null {
  const block = reply.content.find((c) => c.type === "tool_use");
  return block ? { id: String(block.id ?? ""), name: String(block.name ?? ""), input: block.input } : null;
}

/// Der erste Textblock der Antwort, `null` wenn es keinen gibt.
export function firstText(reply: AnthropicReply): string | null {
  const block = reply.content.find((c) => c.type === "text");
  return typeof block?.text === "string" ? block.text : null;
}
