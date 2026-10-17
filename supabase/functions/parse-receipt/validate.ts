// Eingabepruefung fuer parse-receipt.
//
// Eigenes Modul ohne Netz- und Datenbankzugriff, damit es mit `deno test` pruefbar ist (validate_test.ts).
// Codereview-Fund 2026-10-16: Die Function hat als einzige KI-Function weder das Tageslimit noch eine Pruefung der
// einzelnen Felder gehabt. Ein direkter API-Aufruf (nicht der normale Client) konnte so beliebig viele Bilder-Aufrufe
// erzeugen, Nicht-Texte als Bild durchreichen oder beliebig lange Texte (Haendler-Hinweis, Kategorien) in den Prompt
// schreiben. Gleicher Grundsatz wie analyze-meal/sanitize.ts: der Eingabe wird nicht vertraut.

export const MAX_IMAGES = 4;
// Grenze wie bisher (ca. 1,5 MB je Bild nach dem Dekodieren), jetzt in Base64-Zeichen gerechnet.
export const MAX_IMAGE_BYTES = 1_500_000;
export const MAX_IMAGE_BASE64_CHARS = Math.ceil(MAX_IMAGE_BYTES / 3) * 4;
export const MAX_LABEL_CHARS = 200;
export const MAX_CATEGORIES = 100;
export const VARIANTS = ["v1", "v2", "v3"] as const;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// Anfang jedes JPEG in Base64 (FF D8 FF): das Modell bekommt die Bilder als image/jpeg.
const JPEG_BASE64_PREFIX = "/9j/";
const BASE64 = /^[A-Za-z0-9+/]+={0,2}$/;

export type Variant = typeof VARIANTS[number];
export type ReceiptRequest = {
  household_id: string;
  images: string[];
  categories: string[];
  store_hint: string | null;
  receipt_id: string | null;
  variant: Variant;
  model?: string;
};
export type Parsed = { ok: true; value: ReceiptRequest } | { ok: false; error: string; status: number };

const fail = (error: string, status = 400): Parsed => ({ ok: false, error, status });

export function parseRequest(body: unknown): Parsed {
  if (typeof body !== "object" || body === null || Array.isArray(body)) return fail("invalid_input");
  const b = body as Record<string, unknown>;
  if (typeof b.household_id !== "string" || !UUID.test(b.household_id)) return fail("invalid_input");

  if (!Array.isArray(b.images) || b.images.length < 1 || b.images.length > MAX_IMAGES) return fail("invalid_input");
  for (const img of b.images) {
    if (typeof img !== "string" || img.length === 0) return fail("invalid_image");
    if (img.length > MAX_IMAGE_BASE64_CHARS) return fail("image_too_large", 413);
    if (!img.startsWith(JPEG_BASE64_PREFIX) || !BASE64.test(img)) return fail("invalid_image");
  }

  const categoriesRaw = b.categories ?? [];
  if (!Array.isArray(categoriesRaw) || categoriesRaw.length > MAX_CATEGORIES) return fail("invalid_input");
  const categories: string[] = [];
  for (const c of categoriesRaw) {
    if (typeof c !== "string" || c.length > MAX_LABEL_CHARS) return fail("invalid_input");
    categories.push(c);
  }

  let storeHint: string | null = null;
  if (b.store_hint != null) {
    if (typeof b.store_hint !== "string" || b.store_hint.length > MAX_LABEL_CHARS) return fail("invalid_input");
    storeHint = b.store_hint.trim() === "" ? null : b.store_hint.trim();
  }

  let receiptId: string | null = null;
  if (b.receipt_id != null) {
    if (typeof b.receipt_id !== "string" || !UUID.test(b.receipt_id)) return fail("invalid_input");
    receiptId = b.receipt_id;
  }

  const variant = b.variant ?? "v3";
  if (typeof variant !== "string" || !(VARIANTS as readonly string[]).includes(variant)) return fail("invalid_variant");
  if (b.model != null && typeof b.model !== "string") return fail("invalid_input");

  return {
    ok: true,
    value: {
      household_id: b.household_id,
      images: b.images as string[],
      categories,
      store_hint: storeHint,
      receipt_id: receiptId,
      variant: variant as Variant,
      model: b.model as string | undefined,
    },
  };
}
