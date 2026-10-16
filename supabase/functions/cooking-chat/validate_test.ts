// Tests fuer validate.ts. Lokal und in der CI: `deno test validate_test.ts`
import { assertEquals } from "jsr:@std/assert@1";
import { MAX_HISTORY, MAX_INGREDIENTS, MAX_LABEL_CHARS, MAX_MESSAGE_CHARS, parseRequest } from "./validate.ts";

const HOUSEHOLD = "11111111-2222-3333-4444-555555555555";
const valid = () => ({
  household_id: HOUSEHOLD,
  message: "Womit ersetze ich Sahne?",
  recipe_title: "Nudelauflauf",
  ingredients: ["Nudeln", "Käse"],
  history: [{ text: "Hallo", from_user: true }, { text: "Hallo, wie kann ich helfen?", from_user: false }],
});

Deno.test("parseRequest: gueltige Eingabe der App", () => {
  const r = parseRequest(valid());
  assertEquals(r.ok, true);
  if (r.ok) {
    assertEquals(r.value.history.length, 2);
    assertEquals(r.value.recipe_title, "Nudelauflauf");
  }
});

Deno.test("parseRequest: ohne Verlauf, Zutaten und Rezepttitel", () => {
  const r = parseRequest({ household_id: HOUSEHOLD, message: "Hallo" });
  assertEquals(r.ok && { h: r.value.history, i: r.value.ingredients, t: r.value.recipe_title }, { h: [], i: [], t: null });
});

Deno.test("parseRequest: Nachricht fehlt, ist leer oder zu lang", () => {
  assertEquals(parseRequest({ ...valid(), message: "  " }), { ok: false, error: "invalid_input" });
  assertEquals(parseRequest({ ...valid(), message: 42 }), { ok: false, error: "invalid_input" });
  assertEquals(parseRequest({ ...valid(), message: "x".repeat(MAX_MESSAGE_CHARS + 1) }), { ok: false, error: "message_too_long" });
  assertEquals(parseRequest({ ...valid(), household_id: "x" }), { ok: false, error: "invalid_input" });
  assertEquals(parseRequest("x"), { ok: false, error: "invalid_input" });
});

Deno.test("parseRequest: Zutaten und Verlauf muessen Listen sein (vorher TypeError und 500)", () => {
  assertEquals(parseRequest({ ...valid(), ingredients: "Nudeln" }), { ok: false, error: "invalid_input" });
  assertEquals(parseRequest({ ...valid(), history: "Hallo" }), { ok: false, error: "invalid_input" });
  assertEquals(parseRequest({ ...valid(), history: [null] }), { ok: false, error: "invalid_input" });
  assertEquals(parseRequest({ ...valid(), history: [{ text: "Hallo" }] }), { ok: false, error: "invalid_input" }, "from_user fehlt");
  assertEquals(parseRequest({ ...valid(), history: [{ text: "Hallo", from_user: "ja" }] }).ok, false);
});

Deno.test("parseRequest: Laengen von Titel, Zutaten und Verlaufseintraegen", () => {
  assertEquals(parseRequest({ ...valid(), recipe_title: "x".repeat(MAX_LABEL_CHARS + 1) }).ok, false);
  assertEquals(parseRequest({ ...valid(), ingredients: ["x".repeat(MAX_LABEL_CHARS + 1)] }).ok, false);
  assertEquals(parseRequest({ ...valid(), history: [{ text: "x".repeat(MAX_MESSAGE_CHARS + 1), from_user: true }] }).ok, false);
});

Deno.test("parseRequest: Verlauf und Zutaten werden serverseitig gekappt", () => {
  const history = Array.from({ length: MAX_HISTORY + 4 }, (_, i) => ({ text: `n${i}`, from_user: i % 2 === 0 }));
  const ingredients = Array.from({ length: MAX_INGREDIENTS + 5 }, (_, i) => `z${i}`);
  const r = parseRequest({ ...valid(), history, ingredients });
  assertEquals(r.ok, true);
  if (r.ok) {
    assertEquals(r.value.history.length, MAX_HISTORY);
    assertEquals(r.value.history.at(-1)?.text, `n${MAX_HISTORY + 3}`, "die juengsten Eintraege bleiben");
    assertEquals(r.value.ingredients.length, MAX_INGREDIENTS);
  }
});
