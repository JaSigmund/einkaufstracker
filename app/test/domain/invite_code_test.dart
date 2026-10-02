import 'package:einkaufstracker/domain/household/invite_code.dart';
import 'package:flutter_test/flutter_test.dart';

/// Gleiche Regeln wie supabase/functions/accept-invite/validate.ts (dort mit Deno-Tests).
void main() {
  group('normalizeInviteCode', () {
    test('Grossbuchstaben, ohne Leerzeichen und Bindestriche', () {
      expect(normalizeInviteCode('ABCD-EFGH-JKMN'), 'ABCDEFGHJKMN');
      expect(normalizeInviteCode(' abcd efgh jkmn '), 'ABCDEFGHJKMN');
      expect(normalizeInviteCode('abcdefghjkmn'), 'ABCDEFGHJKMN');
    });

    test('falsche Laenge und verwechselbare Zeichen werden abgelehnt', () {
      for (final bad in ['', 'ABCDEFGHJKM', 'ABCDEFGHJKMNP', 'ABCDEFGHJKM0', 'ABCDEFGHJKM1', 'ABCDEFGHJKMI', 'ABCDEFGHJKML', 'ABCDEFGHJKMO', 'ABCD-EFGH-JKM!']) {
        expect(normalizeInviteCode(bad), isNull, reason: bad);
      }
    });
  });

  group('formatInviteCode', () {
    test('Dreiergruppen mit Bindestrich', () => expect(formatInviteCode('ABCDEFGHJKMN'), 'ABCD-EFGH-JKMN'));
    test('Format und Normalisierung sind zueinander umkehrbar', () {
      expect(normalizeInviteCode(formatInviteCode('ABCDEFGHJKMN')), 'ABCDEFGHJKMN');
    });
    test('ein Text, der kein Code ist, bleibt unveraendert', () => expect(formatInviteCode('kurz'), 'kurz'));
  });

  group('normalizeEmail', () {
    test('klein geschrieben und getrimmt', () => expect(normalizeEmail('  Neu@Test.AT '), 'neu@test.at'));
    test('offensichtlich Falsches wird abgelehnt', () {
      for (final bad in ['', 'keine-adresse', 'a@b', 'a b@c.de', '@test.at', 'a@@test.at']) {
        expect(normalizeEmail(bad), isNull, reason: bad);
      }
      expect(normalizeEmail('${'a' * 250}@test.at'), isNull, reason: 'laenger als 254 Zeichen');
    });
  });

  group('passwordProblem', () {
    test('zu kurz', () => expect(passwordProblem('x' * (minPasswordChars - 1)), contains('mindestens $minPasswordChars Zeichen')));
    test('genau die Mindestlaenge ist in Ordnung', () => expect(passwordProblem('x' * minPasswordChars), isNull));
    test('Obergrenze in Bytes: 72 ASCII-Zeichen gehen, 73 nicht', () {
      expect(passwordProblem('x' * maxPasswordBytes), isNull);
      expect(passwordProblem('x' * (maxPasswordBytes + 1)), contains('zu lang'));
    });
    test('Umlaute zaehlen als zwei Bytes, Emojis als vier', () {
      expect(passwordProblem('ä' * 10), isNull, reason: '10 Zeichen, 20 Bytes');
      expect(passwordProblem('ä' * 37), contains('zu lang'), reason: '74 Bytes');
      expect(passwordProblem('🔑' * 10), isNull, reason: '10 Zeichen, 40 Bytes');
      expect(passwordProblem('🔑' * 19), contains('zu lang'), reason: '76 Bytes');
    });
  });

  test('utf8Length zaehlt wie UTF-8', () {
    expect(utf8Length('abc'), 3);
    expect(utf8Length('äöü'), 6);
    expect(utf8Length('€'), 3);
    expect(utf8Length('🔑'), 4);
    expect(utf8Length(''), 0);
  });

  test('inviteShareText nennt Code im Dreiergruppen-Format, Ablauf und Hinweis auf die Adresse', () {
    final text = inviteShareText(code: 'ABCDEFGHJKMN', validUntil: DateTime(2026, 10, 9));
    expect(text, contains('ABCD-EFGH-JKMN'));
    expect(text, contains('9.10.2026'));
    expect(text, contains('Einladung annehmen'));
    expect(text, contains('E-Mail-Adresse'));
  });
}
