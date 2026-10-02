/// Einladungscodes und Adressen fuer Haushalts-Einladungen (Phase 6, ADR-017). Reine Funktionen.
///
/// Ein Code hat 12 Zeichen aus A-Z ohne I, L, O sowie 2-9 (keine 0 und 1: verwechselbar beim Abtippen). Er wird in
/// Dreiergruppen angezeigt ("ABCD-EFGH-JKMN"); beim Eingeben sind Gross-/Kleinschreibung, Leerzeichen und Bindestriche egal.
/// Die Regeln entsprechen `supabase/functions/accept-invite/validate.ts` und `public.new_invite_code()`.
library;

const inviteCodeLength = 12;
const inviteValidityDays = 7;

/// Mindestlaenge des Passworts fuer neue Konten (wie die Edge Function).
const minPasswordChars = 10;

/// Obergrenze in UTF-8-Bytes: bcrypt schneidet danach ab (wie die Edge Function).
const maxPasswordBytes = 72;

final _codePattern = RegExp(r'^[A-HJKMNP-Z2-9]{12}$');
final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// "abcd efgh-jkmn" -> "ABCDEFGHJKMN"; `null`, wenn das kein gueltiger Code sein kann.
String? normalizeInviteCode(String input) {
  final code = input.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  return _codePattern.hasMatch(code) ? code : null;
}

/// "ABCDEFGHJKMN" -> "ABCD-EFGH-JKMN". Ein Text, der kein Code ist, bleibt unveraendert.
String formatInviteCode(String code) {
  if (!_codePattern.hasMatch(code)) return code;
  return '${code.substring(0, 4)}-${code.substring(4, 8)}-${code.substring(8)}';
}

/// Kleingeschrieben und ohne Leerzeichen am Rand, `null` bei offensichtlich Falschem (wie die Datenbank-Pruefung).
String? normalizeEmail(String input) {
  final email = input.trim().toLowerCase();
  return email.length <= 254 && _email.hasMatch(email) ? email : null;
}

/// `null` = in Ordnung, sonst der Grund auf Deutsch.
String? passwordProblem(String password) {
  if (password.runes.length < minPasswordChars) return 'Das Passwort braucht mindestens $minPasswordChars Zeichen.';
  if (utf8Length(password) > maxPasswordBytes) return 'Das Passwort ist zu lang (höchstens $maxPasswordBytes Bytes, Umlaute zählen doppelt).';
  return null;
}

/// Laenge in UTF-8-Bytes ohne `dart:convert` (bleibt damit auch im Web ohne Zusatz-Import nutzbar).
int utf8Length(String s) {
  var n = 0;
  for (final r in s.runes) {
    n += r < 0x80 ? 1 : (r < 0x800 ? 2 : (r < 0x10000 ? 3 : 4));
  }
  return n;
}

/// Text zum Weitergeben per Nachrichten-App.
String inviteShareText({required String code, required DateTime validUntil}) {
  final until = '${validUntil.day}.${validUntil.month}.${validUntil.year}';
  return 'Du bist zu meinem Haushalt im Einkaufstracker eingeladen.\n'
      'Öffne die App, tippe beim Anmelden auf "Einladung annehmen" und gib diesen Code ein:\n\n'
      '${formatInviteCode(code)}\n\n'
      'Dazu brauchst du die E-Mail-Adresse, an die ich die Einladung geschickt habe. Der Code gilt bis $until und nur einmal.';
}
