import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Anmeldung. Selbstregistrierung gibt es bewusst nicht (im Supabase-Projekt abgeschaltet).
abstract class AuthRepository {
  String? get currentEmail;
  Future<void> signIn(String email, String password);
  Future<void> signOut();
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
}
