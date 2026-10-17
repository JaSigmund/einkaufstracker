import 'package:einkaufstracker/data/remote/remote_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Einstufung der Server-Fehler beim Senden: Datenfehler werden markiert und uebersprungen, alles andere bricht den Sync ab.
void main() {
  test('Constraint-, Format- und Rechtefehler der Daten sind Datenfehler', () {
    for (final code in ['23505', '23503', '22P02', '42501', '42703', 'PGRST116', 'PGRST204', '400', '404', '409', '422']) {
      expect(isRemoteDataError(code), isTrue, reason: code);
    }
  });

  test('Codereview-Fund 2026-10-16: abgelaufene oder ungueltige Anmeldung (PGRST3xx) ist KEIN Datenfehler', () {
    for (final code in ['PGRST301', 'PGRST302', 'PGRST303']) {
      expect(isRemoteDataError(code), isFalse, reason: code);
    }
  });

  test('Anmeldung, Zeitueberschreitung, Drosselung, Serverfehler und fehlender Code sind keine Datenfehler', () {
    for (final code in ['401', '403', '408', '429', '500', '502', '503', null]) {
      expect(isRemoteDataError(code), isFalse, reason: '$code');
    }
  });
}
