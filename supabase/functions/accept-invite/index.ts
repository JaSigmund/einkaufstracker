// Edge Function: accept-invite
// STATUS: neu (Phase 6, ADR-017 Option A "Selbstbedienung", Migration 0017).
//
// Wird OHNE JWT aufgerufen (verify_jwt = false, siehe supabase/config.toml), weil der Eingeladene noch kein Konto
// hat. Schutz stattdessen: Einladungscode (59 Bit, einmalig, 7 Tage, an die E-Mail-Adresse gebunden), Sperre nach 5
// Fehlversuchen (peek_invite), Mindestlaenge des Passworts, und nach aussen moeglichst wenige Details.
//
// Ablauf: Eingabe pruefen -> peek_invite (Code, Adresse, Ablauf, Fehlversuche, Haushaltsgroesse) -> Auth-Nutzer per
//         Admin-API anlegen (app_metadata.invited_to verhindert den eigenen Haushalt im Signup-Trigger) ->
//         redeem_invite (Mitgliedschaft + Einladung als angenommen, atomar). Scheitert das Einloesen, wird der eben
//         angelegte Nutzer wieder geloescht, damit keine Karteileiche ohne Haushalt zurueckbleibt.
//
// Automatisch vorhanden: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "npm:@supabase/supabase-js@2";
import { json } from "../_shared/http.ts";
import { isEmailTaken, parseRequest, responseForStatus } from "./validate.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let raw: unknown;
  try {
    raw = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const parsed = parseRequest(raw);
  if (!parsed.ok) return json({ error: parsed.error }, 400);
  const { code, email, password } = parsed.value;

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  // 1) Einladung pruefen. Fehlversuche zaehlt die Datenbankfunktion selbst.
  const { data: peek, error: peekErr } = await admin.rpc("peek_invite", { p_token: code, p_email: email });
  const row = Array.isArray(peek) ? peek[0] : null;
  if (peekErr || !row) {
    console.error("peek_invite_failed", peekErr?.message);
    return json({ error: "invite_check_failed" }, 500);
  }
  if (row.status !== "ok") {
    const r = responseForStatus(row.status);
    return json({ error: r.error }, r.http);
  }

  // 2) Auth-Nutzer anlegen. email_confirm: Die Einladung ging persoenlich an diese Adresse, eine Bestaetigungsmail
  //    waere ein zweiter Schritt ohne Gewinn (und Supabase Auth versendet ohne eigenen SMTP-Server kaum Mails).
  const { data: created, error: createErr } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    app_metadata: { invited_to: row.household_id },
  });
  if (createErr || !created?.user) {
    if (isEmailTaken(createErr)) return json({ error: "email_taken" }, 409);
    console.error("create_user_failed", createErr?.message);
    return json({ error: "create_failed" }, 500);
  }

  // 3) Mitgliedschaft anlegen und Einladung verbrauchen
  const { error: redeemErr } = await admin.rpc("redeem_invite", { p_token: code, p_user_id: created.user.id });
  if (redeemErr) {
    console.error("redeem_invite_failed", redeemErr.message);
    const { error: undoErr } = await admin.auth.admin.deleteUser(created.user.id);
    if (undoErr) console.error("undo_create_user_failed", undoErr.message);
    const full = redeemErr.message.includes("household_full");
    return json({ error: full ? "household_full" : "invite_unavailable" }, 409);
  }

  return json({ ok: true });
});
