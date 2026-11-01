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
export const MAX_COUNT = 50;
export const MEAL_TYPES = ["breakfast", "lunch", "dinner", "snack", "drink"] as const;
export const KINDS = ["food", "drink"] as const;
export const STATES = ["raw", "cooked", "ready_made"] as const;
export const COUNT_UNITS = ["piece", "slice", "tbsp", "tsp", "clove", "head", "stalk"] as const;
export const MAX_SEARCH_TERMS = 3;
export const MAX_TITLE_CHARS = 120;
export const MAX_NOTE_CHARS = 500;
export const MAX_KNOWN_INGREDIENTS = 30;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// Anfang jedes JPEG in Base64 (FF D8 FF): das Modell bekommt nur JPEG, so passt der media_type, den wir angeben.
const JPEG_BASE64_PREFIX = "/9j/";

export type Product = { id: string; name: string };
/// Was der Nutzer schon eingetragen hat. Es beschreibt das Gericht besser als das Foto (Pizzabroetchen sieht man den Belag nicht an).
export type MealContext = {
  title: string | null;
  note: string | null;
  meal_type: string | null;
  servings_made: number | null;
  known_ingredients: string[];
};
export const EMPTY_CONTEXT: MealContext = { title: null, note: null, meal_type: null, servings_made: null, known_ingredients: [] };
export type AnalyzeRequest = { household_id: string; image_base64: string; products: Product[]; context: MealContext; model?: string };
/// kind: Speise oder Getraenk (Getraenke fuehrt die App in ml). state: roh, gekocht oder fertig gekauft, null = nicht erkennbar.
export type Ingredient = {
  name: string;
  inventory_product_id: string | null;
  est_amount_g: number | null;
  confidence: number;
  kind: "food" | "drink";
  state: "raw" | "cooked" | "ready_made" | null;
  /// Anzahl bei Stueckware (2 Eier, 3 Scheiben Brot), in halben Schritten; null = nicht zaehlbar. Die Function rechnet damit in
  /// Gramm um (units.ts), die KI schaetzt kein Stueckgewicht.
  count: number | null;
  count_unit: typeof COUNT_UNITS[number];
  /// Andere Namen fuer die Suche in der Lebensmitteldatenbank ("Rote Beete" -> "Rote Bete"), resolve.ts.
  search_terms: string[];
  /// visible: auf dem Foto zu sehen. inferred: nicht zu sehen, gehoert aber zum Gericht (Bratoel, Dressing), die App markiert es.
  origin: "visible" | "inferred";
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
  if (b.context != null && (typeof b.context !== "object" || Array.isArray(b.context))) return { ok: false, error: "invalid_input" };
  return {
    ok: true,
    value: {
      household_id: b.household_id,
      image_base64: b.image_base64,
      products,
      context: parseContext(b.context),
      model: b.model as string | undefined,
    },
  };
}

/// Einzeiliger Text: die Angaben landen im Prompt und sollen dort keine eigenen Zeilen vortaeuschen koennen.
const line = (v: unknown, max: number): string | null => {
  if (typeof v !== "string") return null;
  const t = v.replace(/\s+/g, " ").trim();
  return t.length === 0 ? null : t.slice(0, max);
};

/// Liest die Angaben des Nutzers. Sie sind freiwillig: Unbrauchbares faellt weg, die Analyse laeuft trotzdem.
function parseContext(raw: unknown): MealContext {
  if (typeof raw !== "object" || raw === null) return EMPTY_CONTEXT;
  const c = raw as Record<string, unknown>;
  const known = Array.isArray(c.known_ingredients) ? c.known_ingredients : [];
  const servings = typeof c.servings_made === "number" && Number.isFinite(c.servings_made) && c.servings_made > 0 ? Math.min(c.servings_made, 50) : null;
  return {
    title: line(c.title, MAX_TITLE_CHARS),
    note: line(c.note, MAX_NOTE_CHARS),
    meal_type: typeof c.meal_type === "string" && (MEAL_TYPES as readonly string[]).includes(c.meal_type) ? c.meal_type : null,
    servings_made: servings,
    known_ingredients: known.map((k) => line(k, MAX_LABEL_CHARS)).filter((k): k is string => k !== null).slice(0, MAX_KNOWN_INGREDIENTS),
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
      const kind = i.kind === "drink" ? "drink" : "food";
      const counted = number(i.count);
      const count = kind === "drink" || counted === null || counted <= 0 ? null : Math.min(MAX_COUNT, Math.round(counted * 2) / 2);
      const terms = Array.isArray(i.search_terms) ? i.search_terms : [];
      ingredients.push({
        name,
        inventory_product_id: id,
        est_amount_g: amount === null || amount <= 0 ? null : Math.min(amount, MAX_AMOUNT_G),
        confidence: confidence === null ? 0 : Math.min(1, Math.max(0, confidence)),
        kind,
        state: typeof i.state === "string" && (STATES as readonly string[]).includes(i.state) ? i.state as Ingredient["state"] : null,
        count: count === 0 ? null : count,
        count_unit: typeof i.count_unit === "string" && (COUNT_UNITS as readonly string[]).includes(i.count_unit)
          ? i.count_unit as Ingredient["count_unit"]
          : "piece",
        search_terms: [...new Set(terms.map((t) => text(t, 60)).filter((t): t is string => t !== null && t.toLowerCase() !== name.toLowerCase()))]
          .slice(0, MAX_SEARCH_TERMS),
        origin: i.origin === "inferred" ? "inferred" : "visible",
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
