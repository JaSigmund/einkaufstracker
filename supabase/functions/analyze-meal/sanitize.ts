// Eingabepruefung und Bereinigung der KI-Antwort fuer analyze-meal.
//
// Eigenes Modul ohne Netz- und Datenbankzugriff, damit es mit `deno test` pruefbar ist (sanitize_test.ts).
// Grundsatz: Weder die Eingabe noch die Antwort des Modells wird als vertrauenswuerdig behandelt. Ein direkter
// API-Aufruf (nicht der normale Client) darf keine beliebig grossen Prompts erzeugen, und das Modell darf keine
// IDs erfinden, die die App dann einem Produkt zuordnet.

export const MAX_PRODUCTS = 80;
export const MAX_LABEL_CHARS = 200;
// Das Foto kommt von der App auf hoechstens 1600 px und etwa 400 KB verkleinert; als Base64 sind das gut 540 000
// Zeichen. Die Obergrenze laesst Luft, verhindert aber, dass jemand Megabyte-Bilder durchreicht.
export const MAX_IMAGE_BASE64_CHARS = 1_000_000;
export const MAX_INGREDIENTS = 20;
export const MAX_AMOUNT_G = 5000;
export const MEAL_TYPES = ["breakfast", "lunch", "dinner", "snack", "drink"] as const;
export const KINDS = ["food", "drink"] as const;
export const STATES = ["raw", "cooked", "ready_made"] as const;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// Anfang jedes JPEG in Base64 (FF D8 FF): das Modell bekommt nur JPEG, so passt der media_type, den wir angeben.
const JPEG_BASE64_PREFIX = "/9j/";

export type Product = { id: string; name: string };
export type AnalyzeRequest = { household_id: string; image_base64: string; products: Product[]; model?: string };
/// kind: Speise oder Getraenk (Getraenke fuehrt die App in ml). state: roh, gekocht oder fertig gekauft, null = nicht erkennbar.
export type Ingredient = {
  name: string;
  inventory_product_id: string | null;
  est_amount_g: number | null;
  confidence: number;
  kind: "food" | "drink";
  state: "raw" | "cooked" | "ready_made" | null;
};
export type Analysis = {
  dish_title: string;
  meal_type_guess: string | null;
  servings_visible: number | null;
  ingredients: Ingredient[];
  notes: string | null;
};

export type Parsed = { ok: true; value: AnalyzeRequest } | { ok: false; error: string };

export function parseRequest(body: unknown): Parsed {
  if (typeof body !== "object" || body === null) return { ok: false, error: "invalid_input" };
  const b = body as Record<string, unknown>;
  if (typeof b.household_id !== "string" || !UUID.test(b.household_id)) return { ok: false, error: "invalid_input" };
  if (typeof b.image_base64 !== "string" || b.image_base64.length === 0) return { ok: false, error: "invalid_input" };
  if (b.image_base64.length > MAX_IMAGE_BASE64_CHARS) return { ok: false, error: "image_too_large" };
  if (!b.image_base64.startsWith(JPEG_BASE64_PREFIX)) return { ok: false, error: "invalid_image" };
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(b.image_base64)) return { ok: false, error: "invalid_image" };

  const productsRaw = b.products ?? [];
  if (!Array.isArray(productsRaw)) return { ok: false, error: "invalid_input" };
  if (productsRaw.length > MAX_PRODUCTS) return { ok: false, error: "too_many_products" };
  const products: Product[] = [];
  for (const p of productsRaw) {
    if (typeof p !== "object" || p === null) return { ok: false, error: "invalid_input" };
    const { id, name } = p as Record<string, unknown>;
    if (typeof id !== "string" || !UUID.test(id)) return { ok: false, error: "invalid_input" };
    if (typeof name !== "string" || name.trim().length === 0 || name.length > MAX_LABEL_CHARS) {
      return { ok: false, error: "invalid_input" };
    }
    products.push({ id, name: name.trim() });
  }
  if (b.model != null && typeof b.model !== "string") return { ok: false, error: "invalid_input" };
  return {
    ok: true,
    value: { household_id: b.household_id, image_base64: b.image_base64, products, model: b.model as string | undefined },
  };
}

const text = (v: unknown, max: number): string | null => {
  if (typeof v !== "string") return null;
  const t = v.trim();
  return t.length === 0 ? null : t.slice(0, max);
};

const number = (v: unknown): number | null => (typeof v === "number" && Number.isFinite(v) ? v : null);

/// Bereinigt die Tool-Antwort des Modells. Verwirft einzelne kaputte Zutaten statt die ganze Antwort, begrenzt
/// Zahlen und laesst nur Produkt-IDs durch, die die App selbst mitgeschickt hat.
export function sanitizeAnalysis(raw: unknown, allowedProductIds: Set<string>): Analysis {
  const r = (typeof raw === "object" && raw !== null ? raw : {}) as Record<string, unknown>;
  const ingredients: Ingredient[] = [];
  if (Array.isArray(r.ingredients)) {
    for (const item of r.ingredients) {
      if (ingredients.length >= MAX_INGREDIENTS) break;
      if (typeof item !== "object" || item === null) continue;
      const i = item as Record<string, unknown>;
      const name = text(i.name, MAX_LABEL_CHARS);
      if (name === null) continue;
      const id = typeof i.inventory_product_id === "string" && allowedProductIds.has(i.inventory_product_id)
        ? i.inventory_product_id
        : null;
      const amount = number(i.est_amount_g);
      const confidence = number(i.confidence);
      ingredients.push({
        name,
        inventory_product_id: id,
        est_amount_g: amount === null || amount <= 0 ? null : Math.min(amount, MAX_AMOUNT_G),
        confidence: confidence === null ? 0 : Math.min(1, Math.max(0, confidence)),
        kind: i.kind === "drink" ? "drink" : "food",
        state: typeof i.state === "string" && (STATES as readonly string[]).includes(i.state) ? i.state as Ingredient["state"] : null,
      });
    }
  }
  const guess = typeof r.meal_type_guess === "string" && (MEAL_TYPES as readonly string[]).includes(r.meal_type_guess)
    ? r.meal_type_guess
    : null;
  const servings = number(r.servings_visible);
  return {
    dish_title: text(r.dish_title, 120) ?? "",
    meal_type_guess: guess,
    servings_visible: servings === null || servings <= 0 ? null : Math.min(servings, 50),
    ingredients,
    notes: text(r.notes, 500),
  };
}
