// Eingabepruefung fuer cooking-chat.
//
// Eigenes Modul ohne Netz- und Datenbankzugriff, damit es mit `deno test` pruefbar ist (validate_test.ts).
// Codereview-Fund 2026-10-16: `ingredients` und `history` wurden nur ueber `.some(...)` geprueft. War eines davon kein
// Array (z.B. ein Text) oder ein Verlaufseintrag `null`, stuerzte die Function mit einem TypeError ab (500) statt mit
// einem sauberen 400 zu antworten; `from_user` wurde gar nicht geprueft.

export const MAX_MESSAGE_CHARS = 2000;
export const MAX_HISTORY = 6;
export const MAX_INGREDIENTS = 40;
export const MAX_LABEL_CHARS = 200;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export type HistoryEntry = { text: string; from_user: boolean };
export type ChatRequest = {
  household_id: string;
  message: string;
  history: HistoryEntry[];
  recipe_title: string | null;
  ingredients: string[];
  model?: string;
};
export type Parsed = { ok: true; value: ChatRequest } | { ok: false; error: string };

export function parseRequest(body: unknown): Parsed {
  if (typeof body !== "object" || body === null || Array.isArray(body)) return { ok: false, error: "invalid_input" };
  const b = body as Record<string, unknown>;
  if (typeof b.household_id !== "string" || !UUID.test(b.household_id)) return { ok: false, error: "invalid_input" };
  if (typeof b.message !== "string" || b.message.trim().length === 0) return { ok: false, error: "invalid_input" };
  if (b.message.length > MAX_MESSAGE_CHARS) return { ok: false, error: "message_too_long" };
  if (b.recipe_title != null && (typeof b.recipe_title !== "string" || b.recipe_title.length > MAX_LABEL_CHARS)) {
    return { ok: false, error: "invalid_input" };
  }

  const ingredientsRaw = b.ingredients ?? [];
  if (!Array.isArray(ingredientsRaw)) return { ok: false, error: "invalid_input" };
  if (ingredientsRaw.some((i) => typeof i !== "string" || i.length > MAX_LABEL_CHARS)) return { ok: false, error: "invalid_input" };

  const historyRaw = b.history ?? [];
  if (!Array.isArray(historyRaw)) return { ok: false, error: "invalid_input" };
  const history: HistoryEntry[] = [];
  for (const h of historyRaw) {
    if (typeof h !== "object" || h === null) return { ok: false, error: "invalid_input" };
    const { text, from_user: fromUser } = h as Record<string, unknown>;
    if (typeof text !== "string" || text.length > MAX_MESSAGE_CHARS || typeof fromUser !== "boolean") {
      return { ok: false, error: "invalid_input" };
    }
    history.push({ text, from_user: fromUser });
  }
  if (b.model != null && typeof b.model !== "string") return { ok: false, error: "invalid_input" };

  return {
    ok: true,
    value: {
      household_id: b.household_id,
      message: b.message,
      // Serverseitig zusaetzlich kappen, unabhaengig davon, was der Client schickt (Q-22).
      history: history.slice(-MAX_HISTORY),
      recipe_title: (b.recipe_title as string | null | undefined) ?? null,
      ingredients: (ingredientsRaw as string[]).slice(0, MAX_INGREDIENTS),
      model: b.model as string | undefined,
    },
  };
}
