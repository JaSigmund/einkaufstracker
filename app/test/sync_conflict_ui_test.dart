import 'dart:io';

import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/sync/sync_engine.dart';
import 'package:einkaufstracker/features/common/sync_status_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fakes.dart';

/// Hinweis auf ueberschriebene fremde Aenderungen (ADR-018): SyncController und Banner.
final _user = User(id: 'u1', appMetadata: const {}, userMetadata: const {}, aud: 'authenticated', createdAt: '2026-01-01T00:00:00Z');
final _session = Session(accessToken: 'token', tokenType: 'bearer', user: _user);

void main() {
  late AppDatabase a;
  late AppDatabase b;
  late FakeRemoteStore remote;
  late SyncEngine engineB;

  setUp(() {
    a = memoryDb();
    b = memoryDb();
    remote = FakeRemoteStore();
    engineB = SyncEngine(b, remote);
  });
  tearDown(() async {
    await a.close();
    await b.close();
  });

  /// Geraet B hat einen Konflikt: A hat "Obst" umbenannt, B danach auch, ohne A zu holen.
  Future<void> conflictOnB() async {
    await categoryRepo(a).add('Obst');
    await SyncEngine(a, remote).sync();
    await engineB.sync();
    final id = (await a.select(a.categories).get()).single.id;
    await categoryRepo(a).rename(id, 'Früchte');
    await SyncEngine(a, remote).sync();
    await categoryRepo(b).rename(id, 'Fruits');
  }

  late ProviderContainer container;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(b),
        sessionProvider.overrideWith((ref) => Stream.value(_session)),
        remoteStoreProvider.overrideWithValue(remote),
        syncEngineProvider.overrideWithValue(engineB),
        appUpdateRequiredProvider.overrideWithValue(false),
        pendingChangesProvider.overrideWith((ref) => Stream.value(0)),
        householdInviteRepositoryProvider.overrideWithValue(FakeHouseholdInviteRepository()),
        // Schritte, die nach dem Sync laufen (Belege nachziehen, Dateien hochladen): ohne Server als Attrappen
        householdIdProvider.overrideWith((ref) async => 'h1'),
        receiptFileServiceProvider.overrideWithValue(fileService(b, FakeRemoteFileStore(), Directory.systemTemp.createTempSync('sc'))),
        mealPhotoServiceProvider.overrideWithValue(FakeMealPhotoService(b, mealRepo(b))),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(builder: (context, r, _) {
            r.watch(sessionProvider);
            return const SyncStatusBanner();
          }),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(tester.element(find.byType(SyncStatusBanner)));
  }

  testWidgets('ohne Konflikt: normaler Banner, kein Konflikt-Hinweis', (tester) async {
    await pump(tester);
    await container.read(syncControllerProvider.notifier).sync();
    await tester.pumpAndSettle();
    expect(container.read(syncControllerProvider).conflicts, isEmpty);
    expect(find.byKey(const Key('sync-conflict')), findsNothing);
    expect(find.textContaining('Synchronisiert um'), findsOneWidget);
  });

  testWidgets('Konflikt: Status und Banner nennen den Bereich', (tester) async {
    await conflictOnB();
    await pump(tester);
    await container.read(syncControllerProvider.notifier).sync();
    await tester.pumpAndSettle();

    expect(container.read(syncControllerProvider).conflicts, hasLength(1));
    expect(find.byKey(const Key('sync-conflict')), findsOneWidget);
    expect(find.text('Deine Änderung hat eine neuere von jemand anderem überschrieben (Kategorien).'), findsOneWidget);
    expect(find.text('Tippen zum Bestätigen'), findsOneWidget);
  });

  testWidgets('Tippen auf den Hinweis bestaetigt ihn, der Banner wird wieder normal', (tester) async {
    await conflictOnB();
    await pump(tester);
    await container.read(syncControllerProvider.notifier).sync();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sync-conflict')));
    await tester.pumpAndSettle();
    expect(container.read(syncControllerProvider).conflicts, isEmpty);
    expect(find.byKey(const Key('sync-conflict')), findsNothing);
    expect(find.textContaining('Synchronisiert um'), findsOneWidget);
  });

  testWidgets('der Hinweis bleibt ueber weitere Syncs stehen, bis er bestaetigt wird (kein Verschwinden unbemerkt)', (tester) async {
    await conflictOnB();
    await pump(tester);
    final controller = container.read(syncControllerProvider.notifier);
    await controller.sync();
    await controller.sync();
    await tester.pumpAndSettle();
    expect(container.read(syncControllerProvider).conflicts, hasLength(1));
  });

  testWidgets('ein Fehler beim naechsten Sync loescht den Hinweis nicht', (tester) async {
    await conflictOnB();
    await pump(tester);
    final controller = container.read(syncControllerProvider.notifier);
    await controller.sync();
    remote.offline = true;
    await categoryRepo(b).add('Neu');
    await controller.sync();
    await tester.pump(const Duration(seconds: 16)); // der automatische Wiederholungsversuch laeuft noch offline
    expect(container.read(syncControllerProvider).error, isNotNull);
    expect(container.read(syncControllerProvider).conflicts, hasLength(1));
  });

  testWidgets('dismissConflicts ohne Konflikte aendert nichts', (tester) async {
    await pump(tester);
    final controller = container.read(syncControllerProvider.notifier);
    await controller.sync();
    final before = container.read(syncControllerProvider).lastSync;
    controller.dismissConflicts();
    expect(container.read(syncControllerProvider).lastSync, before);
  });

}
