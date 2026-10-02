import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/household/invite_code.dart';

/// Eine Einladung in den Haushalt (Tabelle `household_invites`, Migration 0017).
class HouseholdInvite {
  const HouseholdInvite({required this.id, required this.email, required this.token, required this.expiresAt, required this.createdAt});

  final String id;
  final String email;

  /// Der Einladungscode, 12 Zeichen ohne Bindestriche (angezeigt mit [formatInviteCode]).
  final String token;
  final DateTime expiresAt;
  final DateTime createdAt;

  bool isExpired(DateTime now) => !expiresAt.isAfter(now);

  factory HouseholdInvite.fromJson(Map<String, dynamic> j) => HouseholdInvite(
        id: j['id'] as String,
        email: j['email'] as String,
        token: j['token'] as String,
        expiresAt: DateTime.parse(j['expires_at'] as String).toUtc(),
        createdAt: DateTime.parse(j['created_at'] as String).toUtc(),
      );
}

/// Einladen, Einladungen ansehen und zurueckziehen. Nur online moeglich (Einladungen sind serverseitig).
abstract class HouseholdInviteRepository {
  /// Offene (nicht angenommene) Einladungen des Haushalts, neueste zuerst. Abgelaufene sind dabei, damit man sie
  /// zurueckziehen und die Adresse neu einladen kann.
  Future<List<HouseholdInvite>> pending();

  /// Legt eine Einladung an. Wirft [InviteFailure] mit einer verstaendlichen Meldung.
  Future<HouseholdInvite> create(String email);

  Future<void> revoke(String id);

  /// Anzahl der Haushaltsmitglieder (die eigene Person eingerechnet).
  Future<int> memberCount();
}

/// Fehler beim Einladen oder Annehmen mit einer Meldung fuer die Anzeige.
class InviteFailure implements Exception {
  const InviteFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

const _networkTimeout = Duration(seconds: 20);

class SupabaseHouseholdInviteRepository implements HouseholdInviteRepository {
  SupabaseHouseholdInviteRepository(this._client, this._householdId);

  final SupabaseClient _client;
  final Future<String> Function() _householdId;

  @override
  Future<List<HouseholdInvite>> pending() async {
    final household = await _householdId();
    try {
      final rows = await _client
          .from('household_invites')
          .select('id, email, token, expires_at, created_at')
          .eq('household_id', household)
          .isFilter('accepted_at', null)
          .order('created_at', ascending: false)
          .timeout(_networkTimeout);
      return [for (final r in rows) HouseholdInvite.fromJson(r)];
    } catch (e) {
      throw inviteFailureFor(e);
    }
  }

  @override
  Future<HouseholdInvite> create(String email) async {
    final normalized = normalizeEmail(email);
    if (normalized == null) throw const InviteFailure('Bitte eine gültige E-Mail-Adresse eingeben.');
    final household = await _householdId();
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const InviteFailure('Nicht angemeldet.');
    try {
      final row = await _client
          .from('household_invites')
          .insert({'household_id': household, 'invited_by': uid, 'email': normalized})
          .select('id, email, token, expires_at, created_at')
          .single()
          .timeout(_networkTimeout);
      return HouseholdInvite.fromJson(row);
    } catch (e) {
      throw inviteFailureFor(e);
    }
  }

  @override
  Future<void> revoke(String id) async {
    try {
      await _client.from('household_invites').delete().eq('id', id).timeout(_networkTimeout);
    } catch (e) {
      throw inviteFailureFor(e);
    }
  }

  @override
  Future<int> memberCount() async {
    final household = await _householdId();
    try {
      final rows = await _client.from('household_members').select('user_id').eq('household_id', household).timeout(_networkTimeout);
      return rows.length;
    } catch (e) {
      throw inviteFailureFor(e);
    }
  }
}

/// Uebersetzt Fehler von PostgREST und dem Netz in eine Meldung. Oeffentlich fuer Tests.
InviteFailure inviteFailureFor(Object e) {
  if (e is InviteFailure) return e;
  if (e is PostgrestException) {
    final text = '${e.code} ${e.message} ${e.details}'.toLowerCase();
    if (e.code == '23505') {
      return const InviteFailure('Für diese Adresse gibt es schon eine offene Einladung. Ziehe sie zurück, um neu einzuladen.');
    }
    if (text.contains('too_many_open_invites')) {
      return const InviteFailure('Es sind zu viele Einladungen offen. Ziehe nicht mehr benötigte zurück.');
    }
    if (e.code == '42501') return const InviteFailure('Dafür fehlt die Berechtigung.');
    return InviteFailure('Das hat nicht geklappt (${e.code}).');
  }
  if (e is TimeoutException) return const InviteFailure('Verbindung hängt, bitte später erneut versuchen.');
  final text = e.toString();
  if (e is SocketException || text.contains('ClientException') || text.contains('SocketException')) {
    return const InviteFailure('Kein Netz. Einladungen brauchen eine Verbindung.');
  }
  return InviteFailure('Das hat nicht geklappt: $text');
}

/// Nimmt eine Einladung an (Edge Function `accept-invite`, ohne Anmeldung aufrufbar).
abstract class AcceptInviteApi {
  /// Legt das Konto an und tritt dem Haushalt bei. Danach muss sich der Nutzer normal anmelden. Wirft [InviteFailure].
  Future<void> accept({required String code, required String email, required String password});
}

class SupabaseAcceptInviteApi implements AcceptInviteApi {
  SupabaseAcceptInviteApi(this._client);
  final SupabaseClient _client;

  @override
  Future<void> accept({required String code, required String email, required String password}) async {
    try {
      final response = await _client.functions
          .invoke('accept-invite', body: {'code': code, 'email': email, 'password': password})
          .timeout(const Duration(seconds: 30));
      final data = response.data;
      if (data is Map && data['ok'] == true) return;
      throw const InviteFailure('Unerwartete Antwort vom Server.');
    } on FunctionException catch (e) {
      throw acceptFailureFor(e.status, e.details);
    } on InviteFailure {
      rethrow;
    } catch (e) {
      throw inviteFailureFor(e);
    }
  }
}

/// Ordnet die Antwort der Edge Function einer Meldung zu. Reine Funktion, damit sie ohne Netz testbar ist.
InviteFailure acceptFailureFor(int status, Object? details) {
  final error = details is Map ? details['error'] : null;
  return switch (error) {
    'invite_invalid' => const InviteFailure('Die Einladung wurde nicht gefunden oder die E-Mail-Adresse passt nicht dazu.'),
    'invite_expired' => const InviteFailure('Die Einladung ist abgelaufen. Bitte eine neue anfordern.'),
    'invite_locked' => const InviteFailure('Zu viele Fehlversuche, die Einladung ist gesperrt. Bitte eine neue anfordern.'),
    'household_full' => const InviteFailure('Dieser Haushalt hat schon die höchste Zahl an Mitgliedern.'),
    'email_taken' => const InviteFailure('Zu dieser E-Mail-Adresse gibt es schon ein Konto. Melde dich damit an.'),
    'weak_password' => InviteFailure('Das Passwort braucht mindestens $minPasswordChars Zeichen.'),
    'password_too_long' => const InviteFailure('Das Passwort ist zu lang.'),
    'invite_unavailable' => const InviteFailure('Die Einladung ist nicht mehr gültig.'),
    'invalid_input' => const InviteFailure('Bitte Code, E-Mail-Adresse und Passwort prüfen.'),
    _ => InviteFailure('Das hat nicht geklappt (Fehler $status).'),
  };
}
