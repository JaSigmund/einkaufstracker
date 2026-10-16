// Tests fuer validate.ts. Lokal und in der CI: `deno test validate_test.ts`
import { assertEquals } from "jsr:@std/assert@1";
import { MAX_CATEGORIES, MAX_IMAGE_BASE64_CHARS, MAX_IMAGES, MAX_LABEL_CHARS, parseRequest } from "./validate.ts";

const HOUSEHOLD = "11111111-2222-3333-4444-555555555555";
const RECEIPT = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
const IMAGE = "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBD";

const valid = () => ({ household_id: HOUSEHOLD, images: [IMAGE], store_hint: "Billa" });

Deno.test("parseRequest: gueltige Eingabe der App (Standardvariante v3, keine Kategorien)", () => {
  const r = parseRequest(valid());
  assertEquals(r.ok, true);
  if (r.ok) {
    assertEquals(r.value.variant, "v3");
    assertEquals(r.value.categories, []);
    assertEquals(r.value.store_hint, "Billa");
    assertEquals(r.value.receipt_id, null);
    assertEquals(r.value.model, undefined);
  }
});

Deno.test("parseRequest: Vergleichstest-Felder (Variante, Modell, Kategorien, Bon-ID) werden durchgereicht", () => {
  const r = parseRequest({ ...valid(), variant: "v1", model: "claude-haiku-4-5-20251001", categories: ["Obst"], receipt_id: RECEIPT });
  assertEquals(r.ok, true);
  if (r.ok) {
    assertEquals(r.value.variant, "v1");
    assertEquals(r.value.model, "claude-haiku-4-5-20251001");
    assertEquals(r.value.categories, ["Obst"]);
    assertEquals(r.value.receipt_id, RECEIPT);
  }
});

Deno.test("parseRequest: kein Objekt oder falsche Haushalts-ID", () => {
  for (const body of [null, "x", 42, [valid()]]) {
    assertEquals(parseRequest(body), { ok: false, error: "invalid_input", status: 400 });
  }
  assertEquals(parseRequest({ ...valid(), household_id: "nicht-uuid" }).ok, false);
  assertEquals(parseRequest({ ...valid(), household_id: undefined }).ok, false);
});

Deno.test("parseRequest: Bildanzahl 1 bis MAX_IMAGES", () => {
  assertEquals(parseRequest({ ...valid(), images: [] }).ok, false);
  assertEquals(parseRequest({ ...valid(), images: "nicht-liste" }).ok, false);
  assertEquals(parseRequest({ ...valid(), images: Array(MAX_IMAGES).fill(IMAGE) }).ok, true);
  assertEquals(parseRequest({ ...valid(), images: Array(MAX_IMAGES + 1).fill(IMAGE) }).ok, false);
});

Deno.test("parseRequest: nur Texte als Bild, nur JPEG, nur gueltiges Base64", () => {
  assertEquals(parseRequest({ ...valid(), images: [42] }), { ok: false, error: "invalid_image", status: 400 });
  assertEquals(parseRequest({ ...valid(), images: [""] }), { ok: false, error: "invalid_image", status: 400 });
  assertEquals(parseRequest({ ...valid(), images: ["iVBORw0KGgo="] }), { ok: false, error: "invalid_image", status: 400 }, "PNG");
  assertEquals(parseRequest({ ...valid(), images: ["/9j/<script>"] }), { ok: false, error: "invalid_image", status: 400 });
});

Deno.test("parseRequest: zu grosses Bild ergibt 413", () => {
  const big = "/9j/" + "A".repeat(MAX_IMAGE_BASE64_CHARS);
  assertEquals(parseRequest({ ...valid(), images: [big] }), { ok: false, error: "image_too_large", status: 413 });
  const limit = "/9j/" + "A".repeat(MAX_IMAGE_BASE64_CHARS - 4);
  assertEquals(parseRequest({ ...valid(), images: [limit] }).ok, true, "genau an der Grenze ist erlaubt");
});

Deno.test("parseRequest: Texte fuer den Prompt sind in Typ und Laenge begrenzt", () => {
  assertEquals(parseRequest({ ...valid(), store_hint: "x".repeat(MAX_LABEL_CHARS + 1) }).ok, false);
  assertEquals(parseRequest({ ...valid(), store_hint: { a: 1 } }).ok, false);
  assertEquals(parseRequest({ ...valid(), categories: "Obst" }).ok, false);
  assertEquals(parseRequest({ ...valid(), categories: [1] }).ok, false);
  assertEquals(parseRequest({ ...valid(), categories: ["x".repeat(MAX_LABEL_CHARS + 1)] }).ok, false);
  assertEquals(parseRequest({ ...valid(), categories: Array(MAX_CATEGORIES + 1).fill("Obst") }).ok, false);
});

Deno.test("parseRequest: leerer Haendler-Hinweis gilt als unbekannt", () => {
  const r = parseRequest({ ...valid(), store_hint: "   " });
  assertEquals(r.ok && r.value.store_hint, null);
});

Deno.test("parseRequest: unbekannte Variante, falsches Modell-Feld, kaputte Bon-ID", () => {
  assertEquals(parseRequest({ ...valid(), variant: "v9" }), { ok: false, error: "invalid_variant", status: 400 });
  assertEquals(parseRequest({ ...valid(), variant: 3 }), { ok: false, error: "invalid_variant", status: 400 });
  assertEquals(parseRequest({ ...valid(), model: 5 }).ok, false);
  assertEquals(parseRequest({ ...valid(), receipt_id: "123" }).ok, false);
});
