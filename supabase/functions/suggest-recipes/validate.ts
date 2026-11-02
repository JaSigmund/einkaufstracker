// Eingabepruefung fuer suggest-recipes.
//
// Eigenes Modul ohne Netz- und Datenbankzugriff, damit es mit `deno test` pruefbar ist (validate_test.ts).
// Codereview-Fund 2026-10-16: Name und Einheit jeder Zutat waren in der Laenge begrenzt, die Menge aber gar nicht
// geprueft -- sie landet als Text im Prompt (`${i.quantity}`), ein direkter API-Aufruf konnte dort beliebig lange
// Texte unterbringen. Ein `null` in der Zutatenliste fuehrte ausserdem zu einem Absturz (500) statt zu einem 400.

export const MAX_INGREDIENTS = 40;
export const MAX_LABEL_CHARS = 200;
export const MAX_QUANTITY = 100_000;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export type Ingredient = { name: string; quantity?: number; unit?: string };
export type SuggestRequest = { household_id: string; ingredients: Ingredient[]; model?: string; allow_missing: boolean };
export type Parsed = { ok: true; value: SuggestRequest } | { ok: false; error: string };

export function parseRequest(body: unknown): Parsed {
  if (typeof body !== "object" || body === null || Array.isArray(body)) return { ok: false, error: "invalid_input" };
  const b = body as Record<string, unknown>;
  if (typeof b.household_id !== "string" || !UUID.test(b.household_id)) return { ok: false, error: "invalid_input" };
  if (!Array.isArray(b.ingredients) || b.ingredients.length < 1) return { ok: false, error: "invalid_input" };
  if (b.ingredients.length > MAX_INGREDIENTS) return { ok: false, error: "too_many_ingredients" };

  const ingredients: Ingredient[] = [];
  for (const raw of b.ingredients) {
    if (typeof raw !== "object" || raw === null) return { ok: false, error: "invalid_input" };
    const { name, quantity, unit } = raw as Record<string, unknown>;
    if (typeof name !== "string" || name.trim().length === 0 || name.length > MAX_LABEL_CHARS) {
      return { ok: false, error: "invalid_input" };
    }
    if (quantity != null && (typeof quantity !== "number" || !Number.isFinite(quantity) || quantity < 0 || quantity > MAX_QUANTITY)) {
      return { ok: false, error: "invalid_input" };
    }
    if (unit != null && (typeof unit !== "string" || unit.length > MAX_LABEL_CHARS)) return { ok: false, error: "invalid_input" };
    ingredients.push({
      name: name.trim(),
      ...(quantity != null ? { quantity: quantity as number } : {}),
      ...(unit != null ? { unit: unit as string } : {}),
    });
  }
  if (b.model != null && typeof b.model !== "string") return { ok: false, error: "invalid_input" };
  if (b.allow_missing != null && typeof b.allow_missing !== "boolean") return { ok: false, error: "invalid_input" };
  return { ok: true, value: { household_id: b.household_id, ingredients, model: b.model as string | undefined, allow_missing: b.allow_missing === true } };
}

/// Zutatenzeilen fuer den Prompt, dringlichste zuerst (Reihenfolge der App).
export function ingredientLines(ingredients: Ingredient[]): string {
  return ingredients.map((i) => `- ${i.name}${i.quantity ? ` (${i.quantity}${i.unit ? " " + i.unit : ""})` : ""}`).join("\n");
}
