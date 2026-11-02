// Tests fuer validate.ts. Lokal und in der CI: `deno test validate_test.ts`
import { assertEquals } from "jsr:@std/assert@1";
import { ingredientLines, MAX_INGREDIENTS, MAX_LABEL_CHARS, MAX_QUANTITY, parseRequest } from "./validate.ts";

const HOUSEHOLD = "11111111-2222-3333-4444-555555555555";
const valid = () => ({ household_id: HOUSEHOLD, ingredients: [{ name: "Joghurt", quantity: 2, unit: "Stk" }, { name: "Reis" }] });

Deno.test("parseRequest: gueltige Eingabe der App", () => {
  const r = parseRequest(valid());
  assertEquals(r.ok, true);
  if (r.ok) assertEquals(r.value.ingredients, [{ name: "Joghurt", quantity: 2, unit: "Stk" }, { name: "Reis" }]);
});

Deno.test("parseRequest: kein Objekt, falsche Haushalts-ID, leere oder zu lange Zutatenliste", () => {
  assertEquals(parseRequest(null), { ok: false, error: "invalid_input" });
  assertEquals(parseRequest([]), { ok: false, error: "invalid_input" });
  assertEquals(parseRequest({ ...valid(), household_id: "x" }), { ok: false, error: "invalid_input" });
  assertEquals(parseRequest({ ...valid(), ingredients: [] }), { ok: false, error: "invalid_input" });
  assertEquals(parseRequest({ ...valid(), ingredients: "Reis" }), { ok: false, error: "invalid_input" });
  const many = Array.from({ length: MAX_INGREDIENTS + 1 }, (_, i) => ({ name: `Zutat ${i}` }));
  assertEquals(parseRequest({ ...valid(), ingredients: many }), { ok: false, error: "too_many_ingredients" });
});

Deno.test("parseRequest: null in der Zutatenliste ist ein 400, kein Absturz", () => {
  assertEquals(parseRequest({ ...valid(), ingredients: [null] }), { ok: false, error: "invalid_input" });
  assertEquals(parseRequest({ ...valid(), ingredients: ["Reis"] }), { ok: false, error: "invalid_input" });
});

Deno.test("parseRequest: Menge muss eine endliche, nicht negative Zahl sein (sie landet im Prompt)", () => {
  for (const quantity of ["x".repeat(10_000), -1, Number.NaN, MAX_QUANTITY + 1, { a: 1 }]) {
    assertEquals(parseRequest({ ...valid(), ingredients: [{ name: "Reis", quantity }] }).ok, false, String(quantity));
  }
  assertEquals(parseRequest({ ...valid(), ingredients: [{ name: "Reis", quantity: 0.5 }] }).ok, true);
  assertEquals(parseRequest({ ...valid(), ingredients: [{ name: "Reis", quantity: null }] }).ok, true);
});

Deno.test("parseRequest: Name und Einheit sind in Typ und Laenge begrenzt", () => {
  assertEquals(parseRequest({ ...valid(), ingredients: [{ name: "  " }] }).ok, false);
  assertEquals(parseRequest({ ...valid(), ingredients: [{ name: "x".repeat(MAX_LABEL_CHARS + 1) }] }).ok, false);
  assertEquals(parseRequest({ ...valid(), ingredients: [{ name: "Reis", unit: 5 }] }).ok, false);
  assertEquals(parseRequest({ ...valid(), ingredients: [{ name: "Reis", unit: "x".repeat(MAX_LABEL_CHARS + 1) }] }).ok, false);
  assertEquals(parseRequest({ ...valid(), model: 1 }).ok, false);
});

Deno.test("ingredientLines: Menge und Einheit nur, wenn vorhanden", () => {
  assertEquals(ingredientLines([{ name: "Joghurt", quantity: 2, unit: "Stk" }, { name: "Reis" }, { name: "Milch", quantity: 1 }]),
    "- Joghurt (2 Stk)\n- Reis\n- Milch (1)");
});

Deno.test("parseRequest: allow_missing ist optional und nur als boolean erlaubt", () => {
  const off = parseRequest(valid());
  assertEquals(off.ok && off.value.allow_missing, false);
  const on = parseRequest({ ...valid(), allow_missing: true });
  assertEquals(on.ok && on.value.allow_missing, true);
  assertEquals(parseRequest({ ...valid(), allow_missing: "ja" }).ok, false);
});
