import 'dart:async';
import 'dart:io';

import 'package:einkaufstracker/data/household/household_invites.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Abbildung von Serverfehlern auf Meldungen fuer Einladungen (Phase 6): reine Funktionen, ohne Netz.
void main() {
  group('acceptFailureFor (Antworten von accept-invite)', () {
    String msg(String? error, {int status = 400}) => acceptFailureFor(status, error == null ? null : {'error': error}).message;

    test('falscher Code, falsche Adresse und benutzter Code geben dieselbe Meldung', () {
      expect(msg('invite_invalid', status: 404), contains('nicht gefunden'));
    });

    test('abgelaufen, gesperrt, Haushalt voll, Adresse hat schon ein Konto', () {
      expect(msg('invite_expired', status: 410), contains('abgelaufen'));
      expect(msg('invite_locked', status: 429), contains('Fehlversuche'));
      expect(msg('household_full', status: 409), contains('höchste Zahl'));
      expect(msg('email_taken', status: 409), contains('schon ein Konto'));
    });

    test('Passwort-Fehler und Eingabefehler', () {
      expect(msg('weak_password'), contains('mindestens 10 Zeichen'));
      expect(msg('password_too_long'), contains('zu lang'));
      expect(msg('invalid_input'), contains('prüfen'));
      expect(msg('invite_unavailable', status: 409), contains('nicht mehr gültig'));
    });

    test('unbekannter oder fehlender Fehlercode nennt wenigstens den Status', () {
      expect(msg('etwas_neues', status: 500), contains('500'));
      expect(msg(null, status: 502), contains('502'));
      expect(acceptFailureFor(500, 'kein Objekt').message, contains('500'));
    });
  });

  group('inviteFailureFor (Fehler beim Anlegen, Laden, Zurueckziehen)', () {
    test('doppelte offene Einladung (Unique-Verletzung 23505)', () {
      final e = inviteFailureFor(const PostgrestException(message: 'duplicate key value', code: '23505'));
      expect(e.message, contains('schon eine offene Einladung'));
    });

    test('zu viele offene Einladungen (Trigger)', () {
      final e = inviteFailureFor(const PostgrestException(message: 'too_many_open_invites', code: 'P0001'));
      expect(e.message, contains('zu viele Einladungen'));
    });

    test('fehlende Berechtigung (RLS)', () {
      expect(inviteFailureFor(const PostgrestException(message: 'new row violates row-level security policy', code: '42501')).message, contains('Berechtigung'));
    });

    test('anderer Datenbankfehler nennt den Code', () {
      expect(inviteFailureFor(const PostgrestException(message: 'x', code: '99999')).message, contains('99999'));
    });

    test('Netzfehler und Zeitueberschreitung', () {
      expect(inviteFailureFor(const SocketException('offline')).message, contains('Kein Netz'));
      expect(inviteFailureFor(TimeoutException('x')).message, contains('hängt'));
      expect(inviteFailureFor(Exception('ClientException: Failed host lookup')).message, contains('Kein Netz'));
    });

    test('eine InviteFailure bleibt unveraendert', () {
      const original = InviteFailure('schon verstaendlich');
      expect(identical(inviteFailureFor(original), original), isTrue);
    });

    test('unbekannter Fehler wird sichtbar gemacht statt verschluckt', () {
      expect(inviteFailureFor(StateError('boom')).message, contains('boom'));
    });
  });

  group('HouseholdInvite', () {
    final json = {
      'id': 'i1',
      'email': 'neu@test.at',
      'token': 'ABCDEFGHJKMN',
      'expires_at': '2026-10-09T10:00:00+00:00',
      'created_at': '2026-10-02T10:00:00+00:00',
    };

    test('liest die Zeile des Servers', () {
      final i = HouseholdInvite.fromJson(json);
      expect(i.email, 'neu@test.at');
      expect(i.token, 'ABCDEFGHJKMN');
      expect(i.expiresAt, DateTime.utc(2026, 10, 9, 10));
    });

    test('abgelaufen ab dem Ablaufzeitpunkt (nicht erst danach)', () {
      final i = HouseholdInvite.fromJson(json);
      expect(i.isExpired(DateTime.utc(2026, 10, 9, 9, 59)), isFalse);
      expect(i.isExpired(DateTime.utc(2026, 10, 9, 10)), isTrue);
      expect(i.isExpired(DateTime.utc(2026, 10, 10)), isTrue);
    });
  });
}
