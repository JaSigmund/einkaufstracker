import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Anmeldung. Selbstregistrierung gibt es bewusst nicht (im Supabase-Projekt abgeschaltet).
abstract class AuthRepository {
  String? get currentEmail;
  Future<void> signIn(String email, String password);
  Future<void> signOut();

  /// Loescht das Konto unwiderruflich samt allen Haushaltsdaten (Play-Store-Pflicht "Account
  /// Deletion", Edge Function `delete-account`). Meldet danach nicht mehr selbst ab: die Session
  /// wird durch die Loeschung des Auth-Nutzers ungueltig, der Aufrufer soll trotzdem noch lokal
  /// aufraeumen (siehe `SettingsPage._deleteAccount`).
  Future<void> deleteAccount();
}

class SignInFailure implements Exception {
  SignInFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);
  final SupabaseClient _client;

  @override
  String? get currentEmail => _client.auth.currentUser?.email;

  @override
  Future<void> signIn(String email, String password) async {
    try {
      await _client.auth.signInWithPassword(email: email.trim(), password: password).timeout(const Duration(seconds: 20));
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      if (m.contains('invalid login')) throw SignInFailure('E-Mail oder Passwort stimmt nicht.');
      if (m.contains('email not confirmed')) throw SignInFailure('Die E-Mail-Adresse ist noch nicht bestaetigt.');
      throw SignInFailure('Anmeldung fehlgeschlagen: ${e.message}');
    } catch (_) {
      throw SignInFailure('Keine Verbindung. Zum Anmelden wird Netz gebraucht.');
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<void> deleteAccount() async {
    try {
      final response = await _client.functions.invoke('delete-account').timeout(const Duration(seconds: 30));
      final data = response.data;
      if (data is! Map || data['deleted'] != true) throw SignInFailure('Konto konnte nicht gelöscht werden.');
    } on FunctionException catch (e) {
      throw SignInFailure('Konto konnte nicht gelöscht werden (Fehler ${e.status}).');
    } on SignInFailure {
      rethrow;
    } catch (_) {
      throw SignInFailure('Keine Verbindung. Zum Löschen wird Netz gebraucht.');
    }
  }
}
