// Tests fuer llm.ts. Lokal und in der CI: `deno test` im Ordner _shared
import { assertEquals } from "jsr:@std/assert@1";
import {
  type Admin,
  callAnthropic,
  costMicroUsd,
  DAILY_CALL_LIMIT,
  firstText,
  firstToolUse,
  isAllowedModel,
  recordExtraCall,
  recordUsage,
  releaseCall,
  reserveCall,
} from "./llm.ts";

const HAIKU = "claude-haiku-4-5-20251001";

/// Service-Client-Attrappe: merkt sich die Aufrufe, Fehler je Aufruf steuerbar.
function fakeAdmin(opts: { rpc?: { data: unknown; error: unknown }; failWithReceipt?: boolean } = {}) {
  const calls: { op: string; table?: string; row?: Record<string, unknown>; id?: unknown; args?: unknown }[] = [];
  const result = (row?: Record<string, unknown>) => ({
    error: opts.failWithReceipt && row && row.receipt_id ? { message: "23503 anderer Haushalt" } : null,
  });
  const admin = {
    rpc: (fn: string, args: unknown) => {
      calls.push({ op: `rpc:${fn}`, args });
      return Promise.resolve(opts.rpc ?? { data: "reserviert-1", error: null });
    },
    from: (table: string) => ({
      update: (row: Record<string, unknown>) => ({
        eq: (_c: string, id: unknown) => {
          calls.push({ op: "update", table, row, id });
          return Promise.resolve(result(row));
        },
      }),
      insert: (row: Record<string, unknown>) => {
        calls.push({ op: "insert", table, row });
        return Promise.resolve(result(row));
      },
      delete: () => ({
        eq: (_c: string, id: unknown) => {
          calls.push({ op: "delete", table, id });
          return Promise.resolve({ error: null });
        },
      }),
    }),
  };
  return { admin: admin as unknown as Admin, calls };
}

Deno.test("Preise: nur erlaubte Modelle, Kosten in Mikro-USD", () => {
  assertEquals(isAllowedModel(HAIKU), true);
  assertEquals(isAllowedModel("gpt-irgendwas"), false);
  assertEquals(costMicroUsd(HAIKU, { input_tokens: 1000, output_tokens: 200 }), 1000 * 1 + 200 * 5);
  assertEquals(costMicroUsd("unbekannt", { input_tokens: 1, output_tokens: 1 }), 0);
});

Deno.test("reserveCall: Zeilen-ID -> erlaubt, null -> Tageslimit, Fehler -> abgelehnt statt blind zugelassen", async () => {
  const ok = fakeAdmin();
  assertEquals(await reserveCall(ok.admin, "h1", HAIKU), { ok: true, id: "reserviert-1" });
  assertEquals(ok.calls[0].args, { p_household: "h1", p_model: HAIKU, p_limit: DAILY_CALL_LIMIT });
  assertEquals(await reserveCall(fakeAdmin({ rpc: { data: null, error: null } }).admin, "h1", HAIKU), {
    ok: false,
    status: 429,
    error: "daily_limit_reached",
  });
  const origError = console.error;
  console.error = () => {};
  try {
    assertEquals(await reserveCall(fakeAdmin({ rpc: { data: null, error: { message: "kaputt" } } }).admin, "h1", HAIKU), {
      ok: false,
      status: 500,
      error: "usage_check_failed",
    });
  } finally {
    console.error = origError;
  }
});

Deno.test("recordUsage: traegt Tokens, Kosten und Dauer in die reservierte Zeile ein", async () => {
  const { admin, calls } = fakeAdmin();
  await recordUsage(admin, "r1", { model: HAIKU, usage: { input_tokens: 10, output_tokens: 2 }, durationMs: 1234 });
  assertEquals(calls, [{
    op: "update",
    table: "llm_usage",
    id: "r1",
    row: { model: HAIKU, input_tokens: 10, output_tokens: 2, cost_micro_usd: 20, duration_ms: 1234, receipt_id: null },
  }]);
});

Deno.test("recordUsage: fremde oder unbekannte Bon-ID -> ohne Verweis protokollieren, nicht gar nicht", async () => {
  const { admin, calls } = fakeAdmin({ failWithReceipt: true });
  await recordUsage(admin, "r1", { model: HAIKU, usage: { input_tokens: 1, output_tokens: 1 }, durationMs: 1, receiptId: "fremd" });
  assertEquals(calls.map((c) => [c.op, c.row?.receipt_id]), [["update", "fremd"], ["update", null]]);
});

Deno.test("recordExtraCall: eigene Zeile, bei fremder Bon-ID ohne Verweis", async () => {
  const { admin, calls } = fakeAdmin({ failWithReceipt: true });
  await recordExtraCall(admin, { householdId: "h1", model: HAIKU, usage: { input_tokens: 3, output_tokens: 0 }, durationMs: 5, receiptId: "x" });
  assertEquals(calls.map((c) => [c.op, c.row?.household_id, c.row?.receipt_id]), [["insert", "h1", "x"], ["insert", "h1", null]]);
});

Deno.test("releaseCall: loescht die reservierte Zeile (ein Fehlschlag zaehlt nicht zum Limit)", async () => {
  const { admin, calls } = fakeAdmin();
  await releaseCall(admin, "r1");
  assertEquals(calls, [{ op: "delete", table: "llm_usage", id: "r1" }]);
});

Deno.test("callAnthropic: Antwort mit Tool und Usage, Fehlerstatus -> null", async () => {
  const reply = { content: [{ type: "text", text: "Hallo" }, { type: "tool_use", id: "t1", name: "submit", input: { a: 1 } }], usage: { input_tokens: 5, output_tokens: 7 } };
  const ok = await callAnthropic({ model: HAIKU }, { apiKey: "test", fetch: () => Promise.resolve(new Response(JSON.stringify(reply))) });
  assertEquals(ok?.usage, { input_tokens: 5, output_tokens: 7 });
  assertEquals(firstToolUse(ok!), { id: "t1", name: "submit", input: { a: 1 } });
  assertEquals(firstText(ok!), "Hallo");

  const origError = console.error;
  console.error = () => {};
  try {
    assertEquals(await callAnthropic({ model: HAIKU }, { apiKey: "test", fetch: () => Promise.resolve(new Response("overloaded", { status: 529 })) }), null);
  } finally {
    console.error = origError;
  }
});

Deno.test("callAnthropic: fehlende Felder der Antwort werden zu leeren Werten statt eines Absturzes", async () => {
  const empty = await callAnthropic({}, { apiKey: "test", fetch: () => Promise.resolve(new Response("{}")) });
  assertEquals(empty, { content: [], usage: { input_tokens: 0, output_tokens: 0 } });
  assertEquals(firstToolUse(empty!), null);
  assertEquals(firstText(empty!), null);
});
