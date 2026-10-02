import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fakes.dart';

final _fakeUser = User(id: 'u1', appMetadata: const {}, userMetadata: const {}, aud: 'authenticated', createdAt: '2026-01-01T00:00:00Z');
final _fakeSession = Session(accessToken: 'token', tokenType: 'bearer', user: _fakeUser);

/// Testet die neue Update-Sperre in `SyncController.sync()` (ADR-022): eine zu alte Version darf gar
/// nicht erst versuchen zu synchronisieren. Der normale Sync-Erfolgspfad ist bereits in `sync_test.dart`
/// (SyncEngine direkt) abgedeckt -- hier geht es nur um das neue Fruehzeitig-Abbrechen.
void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  testWidgets('appUpdateRequiredProvider=true: sync() bricht ab, Status zeigt updateRequired statt zu laufen', (tester) async {
    late WidgetRef ref;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sessionProvider.overrideWith((ref) => Stream.value(_fakeSession)),
        // syncEngineProvider wird in sync() noch VOR der Session-/Update-Pruefung gelesen (nur fuer
        // engine.isRunning) -- ohne Attrappe wuerde das echte remoteStoreProvider ein nicht
        // initialisiertes Supabase.instance brauchen.
        remoteStoreProvider.overrideWithValue(FakeRemoteStore()),
        appUpdateRequiredProvider.overrideWithValue(true),
      ],
      child: MaterialApp(home: Consumer(builder: (context, r, _) {
        ref = r;
        // sessionProvider erzwingen zu abonnieren, BEVOR sync() es per ref.read() abfragt --
        // sonst initialisiert ref.read() den StreamProvider erst in diesem Moment und sein
        // erster Stream-Wert ist noch nicht synchron angekommen (.value waere noch null).
        r.watch(sessionProvider);
        return const SizedBox();
      })),
    ));
    await tester.pumpAndSettle();

    await ref.read(syncControllerProvider.notifier).sync();

    final status = ref.read(syncControllerProvider);
    expect(status.updateRequired, isTrue);
    expect(status.running, isFalse);
    expect(status.error, contains('Update erforderlich'));
  });

  testWidgets('appUpdateRequiredProvider=false: Sperre greift nicht (Status bleibt im Ausgangszustand)', (tester) async {
    late WidgetRef ref;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sessionProvider.overrideWith((ref) => Stream.value(null)), // nicht angemeldet, damit sync() sonst nichts tut
        remoteStoreProvider.overrideWithValue(FakeRemoteStore()),
        appUpdateRequiredProvider.overrideWithValue(false),
      ],
      child: MaterialApp(home: Consumer(builder: (context, r, _) {
        ref = r;
        r.watch(sessionProvider);
        return const SizedBox();
      })),
    ));
    await tester.pumpAndSettle();

    await ref.read(syncControllerProvider.notifier).sync();

    final status = ref.read(syncControllerProvider);
    expect(status.updateRequired, isFalse);
    expect(status.error, isNull);
  });

  testWidgets('Codereview-Fund 2026-10-01: authTransitionInProgressProvider=true blockiert sync() komplett (waehrend Abmelden/Loeschen)', (tester) async {
    late WidgetRef ref;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sessionProvider.overrideWith((ref) => Stream.value(_fakeSession)),
        remoteStoreProvider.overrideWithValue(FakeRemoteStore()),
        appUpdateRequiredProvider.overrideWithValue(false),
      ],
      child: MaterialApp(home: Consumer(builder: (context, r, _) {
        ref = r;
        r.watch(sessionProvider);
        return const SizedBox();
      })),
    ));
    await tester.pumpAndSettle();

    // Genau das setzt SettingsPage._signOut()/_deleteAccount() vor dem eigentlichen Aufraeumen.
    ref.read(authTransitionInProgressProvider.notifier).start();
    await ref.read(syncControllerProvider.notifier).sync();

    // sync() haette sonst (Session vorhanden, kein Update noetig) tatsaechlich zu laufen begonnen --
    // die Sperre muss das schon vor jeder anderen Pruefung abfangen.
    final status = ref.read(syncControllerProvider);
    expect(status.running, isFalse);
    expect(status.updateRequired, isFalse);
    expect(status.lastSync, isNull);
  });
}
