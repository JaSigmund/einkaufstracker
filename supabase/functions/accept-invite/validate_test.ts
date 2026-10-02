// Tests fuer validate.ts. Lokal und in der CI: `deno test validate_test.ts`
import { assertEquals } from "jsr:@std/assert@1";
import {
  isEmailTaken,
  MAX_PASSWORD_BYTES,
  MIN_PASSWORD_CHARS,
  normalizeCode,
  normalizeEmail,
  parseRequest,
  responseForStatus,
} from "./validate.ts";

const valid = () => ({ code: "ABCDEFGHJKMN", email: "neu@test.at", password: "ein-langes-passwort" });

Deno.test("normalizeCode: Grossbuchstaben, ohne Leerzeichen und Bindestriche", () => {
  assertEquals(normalizeCode("ABCD-EFGH-JKMN"), "ABCDEFGHJKMN");
  assertEquals(normalizeCode(" abcd efgh jkmn "), "ABCDEFGHJKMN");
  assertEquals(normalizeCode("abcdefghjkmn"), "ABCDEFGHJKMN");
});

Deno.test("normalizeCode: falsche Laenge, verwechselbare Zeichen, Nicht-Texte", () => {
  assertEquals(normalizeCode("ABCDEFGHJKM"), null, "zu kurz");
  assertEquals(normalizeCode("ABCDEFGHJKMNP"), null, "zu lang");
  assertEquals(normalizeCode("ABCDEFGHJKM0"), null, "0 gibt es im Alphabet nicht");
  assertEquals(normalizeCode("ABCDEFGHJKM1"), null, "1 gibt es nicht");
  assertEquals(normalizeCode("ABCDEFGHJKMI"), null, "I gibt es nicht");
  assertEquals(normalizeCode("ABCDEFGHJKML"), null, "L gibt es nicht");
  assertEquals(normalizeCode("ABCDEFGHJKMO"), null, "O gibt es nicht");
  assertEquals(normalizeCode(null), null);
  assertEquals(normalizeCode(123456789012), null);
  assertEquals(normalizeCode("A".repeat(500)), null, "absurd lange Eingabe wird gar nicht erst bearbeitet");
});

Deno.test("normalizeEmail: klein geschrieben und getrimmt, offensichtlich Falsches wird abgelehnt", () => {
  assertEquals(normalizeEmail("  Neu@Test.AT "), "neu@test.at");
  assertEquals(normalizeEmail("keine-adresse"), null);
  assertEquals(normalizeEmail("a@b"), null);
  assertEquals(normalizeEmail("a b@c.de"), null);
  assertEquals(normalizeEmail("@test.at"), null);
  assertEquals(normalizeEmail(42), null);
  assertEquals(normalizeEmail("a".repeat(250) + "@test.at"), null, "laenger als 254 Zeichen");
});

Deno.test("parseRequest: gueltige Eingabe wird normalisiert", () => {
  const r = parseRequest({ code: "abcd-efgh-jkmn", email: " Neu@Test.at", password: "ein-langes-passwort" });
  assertEquals(r.ok && r.value, { code: "ABCDEFGHJKMN", email: "neu@test.at", password: "ein-langes-passwort" });
});

Deno.test("parseRequest: fehlende oder falsche Felder", () => {
  assertEquals(parseRequest(null), { ok: false, error: "invalid_input" });
  assertEquals(parseRequest("x"), { ok: false, error: "invalid_input" });
  assertEquals(parseRequest({ ...valid(), code: undefined }), { ok: false, error: "invalid_input" });
  assertEquals(parseRequest({ ...valid(), code: "ZU-KURZ" }), { ok: false, error: "invalid_input" });
  assertEquals(parseRequest({ ...valid(), email: "nope" }), { ok: false, error: "invalid_input" });
  assertEquals(parseRequest({ ...valid(), password: 123456789012 }), { ok: false, error: "invalid_input" });
  const { password: _p, ...ohnePasswort } = valid();
  assertEquals(parseRequest(ohnePasswort), { ok: false, error: "invalid_input" });
});

Deno.test("parseRequest: Passwort braucht mindestens 10 Zeichen und hoechstens 72 Bytes", () => {
  assertEquals(parseRequest({ ...valid(), password: "x".repeat(MIN_PASSWORD_CHARS - 1) }), { ok: false, error: "weak_password" });
  assertEquals(parseRequest({ ...valid(), password: "x".repeat(MIN_PASSWORD_CHARS) }).ok, true);
  assertEquals(parseRequest({ ...valid(), password: "x".repeat(MAX_PASSWORD_BYTES) }).ok, true);
  assertEquals(parseRequest({ ...valid(), password: "x".repeat(MAX_PASSWORD_BYTES + 1) }), { ok: false, error: "password_too_long" });
});

Deno.test("parseRequest: die Laenge zaehlt in Zeichen, die Obergrenze in Bytes (Umlaute sind 2 Bytes)", () => {
  // 10 Umlaute = 10 Zeichen (genug), 20 Bytes
  assertEquals(parseRequest({ ...valid(), password: "ä".repeat(10) }).ok, true);
  // 37 Umlaute = 74 Bytes: zu lang, obwohl nur 37 Zeichen
  assertEquals(parseRequest({ ...valid(), password: "ä".repeat(37) }), { ok: false, error: "password_too_long" });
  // Emoji ist ein Zeichen aus zwei UTF-16-Einheiten: 10 Emojis sind genug
  assertEquals(parseRequest({ ...valid(), password: "🔑".repeat(10) }).ok, true);
});

Deno.test("responseForStatus: unbekannt, falsche Adresse und benutzt sehen von aussen gleich aus", () => {
  const same = { http: 404, error: "invite_invalid" };
  assertEquals(responseForStatus("not_found"), same);
  assertEquals(responseForStatus("email_mismatch"), same);
  assertEquals(responseForStatus("used"), same);
});

Deno.test("responseForStatus: abgelaufen, gesperrt, Haushalt voll, unbekannter Status", () => {
  assertEquals(responseForStatus("expired"), { http: 410, error: "invite_expired" });
  assertEquals(responseForStatus("locked"), { http: 429, error: "invite_locked" });
  assertEquals(responseForStatus("full"), { http: 409, error: "household_full" });
  assertEquals(responseForStatus("irgendwas"), { http: 500, error: "invite_check_failed" });
});

Deno.test("isEmailTaken: erkennt die Fehler von Supabase Auth, aber keine anderen", () => {
  assertEquals(isEmailTaken(null), false);
  assertEquals(isEmailTaken(undefined), false);
  assertEquals(isEmailTaken({ code: "email_exists", message: "x" }), true);
  assertEquals(isEmailTaken({ message: "A user with this email address has already been registered" }), true);
  assertEquals(isEmailTaken({ status: 422, message: "x" }), true);
  assertEquals(isEmailTaken({ status: 500, message: "database error creating new user" }), false);
});
