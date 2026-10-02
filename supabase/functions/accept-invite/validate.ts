// Eingabepruefung und Fehlerabbildung fuer accept-invite.
//
// Eigenes Modul ohne Netz- und Datenbankzugriff, damit es mit `deno test` pruefbar ist (validate_test.ts). Die Function
// ist OHNE JWT erreichbar (der Eingeladene hat noch kein Konto), deshalb wird hier streng geprueft und nach aussen
// moeglichst wenig verraten.

export const CODE_PATTERN = /^[A-HJKMNP-Z2-9]{12}$/;
export const MIN_PASSWORD_CHARS = 10;
// bcrypt, das Supabase Auth fuer Passwoerter nutzt, schneidet nach 72 Bytes ab: laengere Passwoerter wuerden
// stillschweigend gekuerzt und wirkten sicherer, als sie sind.
export const MAX_PASSWORD_BYTES = 72;
export const MAX_EMAIL_CHARS = 254;

const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

export type AcceptRequest = { code: string; email: string; password: string };
export type Parsed = { ok: true; value: AcceptRequest } | { ok: false; error: string };

/// Grossbuchstaben, ohne Leerzeichen und Bindestriche ("abcd-efgh jkmn" -> "ABCDEFGHJKMN"). `null`, wenn es kein
/// gueltiger Code sein kann.
export function normalizeCode(raw: unknown): string | null {
  if (typeof raw !== "string" || raw.length > 40) return null;
  const code = raw.replace(/[\s-]/g, "").toUpperCase();
  return CODE_PATTERN.test(code) ? code : null;
}

export function normalizeEmail(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const email = raw.trim().toLowerCase();
  return email.length <= MAX_EMAIL_CHARS && EMAIL.test(email) ? email : null;
}

export function parseRequest(body: unknown): Parsed {
  if (typeof body !== "object" || body === null) return { ok: false, error: "invalid_input" };
  const b = body as Record<string, unknown>;
  const code = normalizeCode(b.code);
  const email = normalizeEmail(b.email);
  if (code === null || email === null || typeof b.password !== "string") return { ok: false, error: "invalid_input" };
  const password = b.password;
  if ([...password].length < MIN_PASSWORD_CHARS) return { ok: false, error: "weak_password" };
  if (new TextEncoder().encode(password).length > MAX_PASSWORD_BYTES) return { ok: false, error: "password_too_long" };
  return { ok: true, value: { code, email, password } };
}

/// Status aus `peek_invite()` -> HTTP-Antwort. Unbekannter Code, falsche Adresse und bereits benutzter Code sehen von
/// aussen gleich aus (404 invite_invalid), damit niemand daran erkennt, welche Codes oder Adressen es gibt.
export function responseForStatus(status: string): { http: number; error: string } {
  switch (status) {
    case "expired":
      return { http: 410, error: "invite_expired" };
    case "locked":
      return { http: 429, error: "invite_locked" };
    case "full":
      return { http: 409, error: "household_full" };
    case "not_found":
    case "email_mismatch":
    case "used":
      return { http: 404, error: "invite_invalid" };
    default:
      return { http: 500, error: "invite_check_failed" };
  }
}

/// Fehler von `auth.admin.createUser`: gibt es die Adresse schon, ist das ein eigener, erwartbarer Fall.
export function isEmailTaken(error: { message?: string; code?: string; status?: number } | null | undefined): boolean {
  if (!error) return false;
  const text = `${error.code ?? ""} ${error.message ?? ""}`.toLowerCase();
  return error.code === "email_exists" || text.includes("already") || text.includes("registered") || error.status === 422;
}
