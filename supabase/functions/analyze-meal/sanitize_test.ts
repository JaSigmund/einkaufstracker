// Tests fuer sanitize.ts. Lokal und in der CI: `deno test sanitize_test.ts`
import { assertEquals } from "jsr:@std/assert@1";
import {
  MAX_AMOUNT_G,
  MAX_COUNT,
  MAX_IMAGE_BASE64_CHARS,
  MAX_INGREDIENTS,
  MAX_PRODUCTS,
  EMPTY_CONTEXT,
  MAX_KNOWN_INGREDIENTS,
  MAX_NOTE_CHARS,
  parseRequest,
  sanitizeAnalysis,
} from "./sanitize.ts";

const HOUSEHOLD = "11111111-2222-3333-4444-555555555555";
const PRODUCT = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
const OTHER = "99999999-8888-7777-6666-555555555555";
const IMAGE = "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBD";

const valid = () => ({ household_id: HOUSEHOLD, image_base64: IMAGE, products: [{ id: PRODUCT, name: "Reis" }] });

Deno.test("parseRequest: gueltige Eingabe", () => {
  const r = parseRequest(valid());
  assertEquals(r.ok, true);
  if (r.ok) {
    assertEquals(r.value.products, [{ id: PRODUCT, name: "Reis" }]);
    assertEquals(r.value.model, undefined);
  }
});

Deno.test("parseRequest: ohne Produktliste ist erlaubt (leerer Vorrat)", () => {
  const { products: _p, ...rest } = valid();
  const r = parseRequest(rest);
  assertEquals(r.ok && r.value.products, []);
});

Deno.test("parseRequest: kein Objekt, falsche Haushalts-ID, fehlendes Bild", () => {
  assertEquals(parseRequest(null), { ok: false, error: "invalid_input" });
  assertEquals(parseRequest("x"), { ok: false, error: "invalid_input" });
  assertEquals(parseRequest({ ...valid(), household_id: "nicht-uuid" }), { ok: false, error: "invalid_input" });
  assertEquals(parseRequest({ ...valid(), image_base64: "" }), { ok: false, error: "invalid_input" });
  assertEquals(parseRequest({ ...valid(), image_base64: 42 }), { ok: false, error: "invalid_input" });
});

Deno.test("parseRequest: Bild muss JPEG in Base64 sein und darf nicht zu gross sein", () => {
  assertEquals(parseRequest({ ...valid(), image_base64: "iVBORw0KGgo=" }), { ok: false, error: "invalid_image" });
  assertEquals(parseRequest({ ...valid(), image_base64: "/9j/ kein base64!" }), { ok: false, error: "invalid_image" });
  assertEquals(
    parseRequest({ ...valid(), image_base64: "/9j/" + "A".repeat(MAX_IMAGE_BASE64_CHARS) }),
    { ok: false, error: "image_too_large" },
  );
  assertEquals(parseRequest({ ...valid(), image_base64: "/9j/" + "A".repeat(MAX_IMAGE_BASE64_CHARS - 4) }).ok, true);
});

Deno.test("parseRequest: Produktliste wird geprueft (Anzahl, ID, Name, Laenge)", () => {
  const many = Array.from({ length: MAX_PRODUCTS + 1 }, () => ({ id: PRODUCT, name: "x" }));
  assertEquals(parseRequest({ ...valid(), products: many }), { ok: false, error: "too_many_products" });
  assertEquals(parseRequest({ ...valid(), products: "Reis" }), { ok: false, error: "invalid_input" });
  assertEquals(parseRequest({ ...valid(), products: [{ id: "kein-uuid", name: "Reis" }] }), { ok: false, error: "invalid_input" });
  assertEquals(parseRequest({ ...valid(), products: [{ id: PRODUCT, name: "  " }] }), { ok: false, error: "invalid_input" });
  assertEquals(parseRequest({ ...valid(), products: [{ id: PRODUCT, name: "x".repeat(201) }] }), { ok: false, error: "invalid_input" });
  assertEquals(parseRequest({ ...valid(), products: [null] }), { ok: false, error: "invalid_input" });
});

Deno.test("parseRequest: Produktnamen werden getrimmt, Modell muss ein Text sein", () => {
  const r = parseRequest({ ...valid(), products: [{ id: PRODUCT, name: "  Reis  " }], model: "claude-haiku-4-5-20251001" });
  assertEquals(r.ok && r.value.products[0].name, "Reis");
  assertEquals(r.ok && r.value.model, "claude-haiku-4-5-20251001");
  assertEquals(parseRequest({ ...valid(), model: 5 }), { ok: false, error: "invalid_input" });
});

Deno.test("sanitizeAnalysis: normale Antwort bleibt erhalten", () => {
  const a = sanitizeAnalysis({
    dish_title: "Reispfanne",
    meal_type_guess: "dinner",
    servings_visible: 2,
    ingredients: [{ name: "Reis", inventory_product_id: PRODUCT, est_amount_g: 150, confidence: 0.8 }],
    notes: "Oel nicht sichtbar",
  }, new Set([PRODUCT]));
  assertEquals(a, {
    dish_title: "Reispfanne",
    meal_type_guess: "dinner",
    servings_visible: 2,
    ingredients: [{ name: "Reis", inventory_product_id: PRODUCT, est_amount_g: 150, confidence: 0.8, kind: "food", state: null, count: null, count_unit: "piece", search_terms: [], origin: "visible" }],
    notes: "Oel nicht sichtbar",
  });
});

Deno.test("sanitizeAnalysis: erfundene Produkt-ID wird verworfen, Zutat bleibt", () => {
  const a = sanitizeAnalysis({ ingredients: [{ name: "Reis", inventory_product_id: OTHER, est_amount_g: 100, confidence: 1 }] }, new Set([PRODUCT]));
  assertEquals(a.ingredients[0].inventory_product_id, null);
  assertEquals(a.ingredients[0].name, "Reis");
});

Deno.test("sanitizeAnalysis: leerer Text als Produkt-ID bedeutet kein Produkt", () => {
  const a = sanitizeAnalysis({ ingredients: [{ name: "Ei", inventory_product_id: "", est_amount_g: 60, confidence: 0.5 }] }, new Set([PRODUCT]));
  assertEquals(a.ingredients[0].inventory_product_id, null);
});

Deno.test("sanitizeAnalysis: Mengen und Konfidenz werden begrenzt, 0 bedeutet unbekannt", () => {
  const a = sanitizeAnalysis({
    ingredients: [
      { name: "A", inventory_product_id: "", est_amount_g: 99999, confidence: 7 },
      { name: "B", inventory_product_id: "", est_amount_g: 0, confidence: -3 },
      { name: "C", inventory_product_id: "", est_amount_g: -5, confidence: 0.3 },
      { name: "D", inventory_product_id: "", est_amount_g: "viel", confidence: "hoch" },
    ],
  }, new Set());
  assertEquals(a.ingredients.map((i) => [i.est_amount_g, i.confidence]), [[MAX_AMOUNT_G, 1], [null, 0], [null, 0.3], [null, 0]]);
});

Deno.test("sanitizeAnalysis: kaputte Zutaten werden einzeln verworfen, nicht die ganze Antwort", () => {
  const a = sanitizeAnalysis({
    ingredients: [
      null,
      "Reis",
      { name: "" },
      { name: 5 },
      { name: "  Karotte  ", inventory_product_id: "", est_amount_g: 80, confidence: 0.6 },
    ],
  }, new Set());
  assertEquals(a.ingredients.map((i) => i.name), ["Karotte"]);
});

Deno.test("sanitizeAnalysis: hoechstens MAX_INGREDIENTS Zutaten", () => {
  const many = Array.from({ length: MAX_INGREDIENTS + 10 }, (_, i) => ({ name: `Z${i}`, inventory_product_id: "", est_amount_g: 1, confidence: 1 }));
  assertEquals(sanitizeAnalysis({ ingredients: many }, new Set()).ingredients.length, MAX_INGREDIENTS);
});

Deno.test("sanitizeAnalysis: unbekannte Tageszeit und unbekannte Portionen werden zu null", () => {
  const a = sanitizeAnalysis({ meal_type_guess: "unknown", servings_visible: 0, ingredients: [] }, new Set());
  assertEquals([a.meal_type_guess, a.servings_visible], [null, null]);
  assertEquals(sanitizeAnalysis({ meal_type_guess: "brunch" }, new Set()).meal_type_guess, null);
  assertEquals(sanitizeAnalysis({ servings_visible: 1e9 }, new Set()).servings_visible, 50);
});

Deno.test("sanitizeAnalysis: Muell als Antwort ergibt eine leere, gueltige Analyse", () => {
  const empty = { dish_title: "", meal_type_guess: null, servings_visible: null, ingredients: [], notes: null };
  assertEquals(sanitizeAnalysis(null, new Set()), empty);
  assertEquals(sanitizeAnalysis("text", new Set()), empty);
  assertEquals(sanitizeAnalysis({ ingredients: "viele" }, new Set()), empty);
});

Deno.test("sanitizeAnalysis: lange Texte werden gekuerzt", () => {
  const a = sanitizeAnalysis({ dish_title: "t".repeat(500), notes: "n".repeat(900), ingredients: [{ name: "z".repeat(900) }] }, new Set());
  assertEquals([a.dish_title.length, a.notes?.length, a.ingredients[0].name.length], [120, 500, 200]);
});

Deno.test("sanitizeAnalysis: kind und state werden gelesen, Unbekanntes wird zu food und null", () => {
  const a = sanitizeAnalysis({
    ingredients: [
      { name: "Cola", inventory_product_id: "", est_amount_g: 330, confidence: 0.9, kind: "drink", state: "ready_made" },
      { name: "Reis", inventory_product_id: "", est_amount_g: 180, confidence: 0.7, kind: "food", state: "cooked" },
      { name: "Salat", inventory_product_id: "", est_amount_g: 60, confidence: 0.6, kind: "food", state: "raw" },
      { name: "Sosse", inventory_product_id: "", est_amount_g: 0, confidence: 0.2, kind: "sauce", state: "unknown" },
      { name: "Etwas", inventory_product_id: "", est_amount_g: 0, confidence: 0.2 },
    ],
  }, new Set());
  assertEquals(a.ingredients.map((i) => [i.kind, i.state]), [
    ["drink", "ready_made"],
    ["food", "cooked"],
    ["food", "raw"],
    ["food", null],
    ["food", null],
  ]);
});

Deno.test("sanitizeAnalysis: count in halben Schritten, begrenzt; Getraenke und Unsinn ohne Anzahl", () => {
  const a = sanitizeAnalysis({
    ingredients: [
      { name: "Ei", count: 2, count_unit: "piece" },
      { name: "Banane", count: 1.4, count_unit: "piece" },
      { name: "Brot", count: 3, count_unit: "slice" },
      { name: "Oel", count: 2, count_unit: "tbsp" },
      { name: "Haufen", count: 5000, count_unit: "piece" },
      { name: "Cola", count: 1, kind: "drink" },
      { name: "Reis", count: 0 },
      { name: "Sosse", count: -2 },
      { name: "Nudeln", count: "viele" },
      { name: "Schale", count: 0.2 },
    ],
  }, new Set());
  assertEquals(a.ingredients.map((i) => [i.name, i.count]), [
    ["Ei", 2],
    ["Banane", 1.5],
    ["Brot", 3],
    ["Oel", 2],
    ["Haufen", MAX_COUNT],
    ["Cola", null],
    ["Reis", null],
    ["Sosse", null],
    ["Nudeln", null],
    ["Schale", null],
  ]);
});

Deno.test("sanitizeAnalysis: count_unit nur aus der Liste, sonst Stueck", () => {
  const a = sanitizeAnalysis({
    ingredients: [
      { name: "a", count: 1, count_unit: "slice" },
      { name: "b", count: 1, count_unit: "handvoll" },
      { name: "c", count: 1 },
      { name: "d", count: 1, count_unit: 7 },
    ],
  }, new Set());
  assertEquals(a.ingredients.map((i) => i.count_unit), ["slice", "piece", "piece", "piece"]);
});

Deno.test("parseRequest: ohne Angaben des Nutzers ist der Kontext leer (aeltere App-Versionen)", () => {
  const r = parseRequest(valid());
  assertEquals(r.ok && r.value.context, EMPTY_CONTEXT);
});

Deno.test("parseRequest: Angaben des Nutzers werden bereinigt und begrenzt", () => {
  const r = parseRequest({
    ...valid(),
    context: {
      title: "  Pizza\nbrötchen ",
      note: "x".repeat(MAX_NOTE_CHARS + 10),
      meal_type: "dinner",
      servings_made: 400,
      known_ingredients: ["Paprika", "", 7, ...Array(MAX_KNOWN_INGREDIENTS + 5).fill("Salz")],
    },
  });
  if (!r.ok) throw new Error("erwartet ok");
  assertEquals(r.value.context.title, "Pizza brötchen");
  assertEquals(r.value.context.note?.length, MAX_NOTE_CHARS);
  assertEquals(r.value.context.meal_type, "dinner");
  assertEquals(r.value.context.servings_made, 50);
  assertEquals(r.value.context.known_ingredients[0], "Paprika");
  assertEquals(r.value.context.known_ingredients.length, MAX_KNOWN_INGREDIENTS);
});

Deno.test("parseRequest: unbrauchbare Angaben fallen weg, ein falscher Typ wird abgelehnt", () => {
  const r = parseRequest({ ...valid(), context: { title: 5, meal_type: "brunch", servings_made: -1, known_ingredients: "Reis" } });
  assertEquals(r.ok && r.value.context, EMPTY_CONTEXT);
  assertEquals(parseRequest({ ...valid(), context: "Pizza" }), { ok: false, error: "invalid_input" });
  assertEquals(parseRequest({ ...valid(), context: [] }), { ok: false, error: "invalid_input" });
});

Deno.test("sanitizeAnalysis: andere Namen und Herkunft der Zutat", () => {
  const a = sanitizeAnalysis({
    ingredients: [
      { name: "Rote Beete", search_terms: ["Rote Bete", "rote beete", "Rote Bete", "", 3, "A", "B", "C"], origin: "inferred" },
      { name: "Reis", origin: "irgendwas" },
    ],
  }, new Set());
  assertEquals(a.ingredients[0].search_terms, ["Rote Bete", "A", "B"]);
  assertEquals(a.ingredients[0].origin, "inferred");
  assertEquals(a.ingredients[1].search_terms, []);
  assertEquals(a.ingredients[1].origin, "visible");
});
