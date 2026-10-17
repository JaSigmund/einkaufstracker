import 'package:drift/native.dart';
import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/settings_repository.dart';
import 'package:einkaufstracker/features/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';

const _settings = HouseholdSettings(notifyTime: '07:30', notifyLeadDays: 1, allowCloudOcr: false, keepReceiptImages: true);

void main() {
  Widget host(FakeSettingsRepository repo) => ProviderScope(
        overrides: [
          householdIdProvider.overrideWith((r) async => 'h1'),
          settingsRepositoryProvider.overrideWithValue(repo),
          authRepositoryProvider.overrideWithValue(FakeAuth()),
        ],
        child: MaterialApp.router(routerConfig: GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => const SettingsPage())])),
      );

  group('Konto löschen (Play-Store-Pflicht "Account Deletion")', () {
    Widget deleteHost(FakeAuth auth, {required AppDatabase db, FakeNotificationScheduler? scheduler}) => ProviderScope(
          overrides: [
            householdIdProvider.overrideWith((r) async => 'h1'),
            settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository(_settings)),
            authRepositoryProvider.overrideWithValue(auth),
            databaseProvider.overrideWithValue(db),
            // Der echte Drift-Stream (SyncStatusBanner) hinterlaesst beim Dispose einen Timer, den
            // flutter_test als "still pending" meldet -- hier nicht relevant, deshalb ein Stub.
            pendingChangesProvider.overrideWith((ref) => Stream.value(0)),
            notificationSchedulerProvider.overrideWithValue(scheduler ?? FakeNotificationScheduler()),
            receiptFileServiceProvider.overrideWithValue(FakeReceiptFileService(db)),
            mealPhotoServiceProvider.overrideWithValue(FakeMealPhotoService(db, mealRepo(db))),
          ],
          child: MaterialApp.router(routerConfig: GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => const SettingsPage())])),
        );

    void useTallViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('Bestätigungs-Button bleibt gesperrt, bis "LÖSCHEN" eingetippt wird', (tester) async {
      useTallViewport(tester);
      final db = memoryDb();
      addTearDown(db.close);
      await tester.pumpWidget(deleteHost(FakeAuth(), db: db));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settings-delete-account')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Endgültig löschen'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Endgültig löschen')).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'löschen'); // Kleinschreibung reicht nicht
      await tester.pump();
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Endgültig löschen')).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'LÖSCHEN');
      await tester.pump();
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Endgültig löschen')).onPressed, isNotNull);
    });

    testWidgets('Bestätigen ruft deleteAccount auf', (tester) async {
      useTallViewport(tester);
      final auth = FakeAuth();
      final db = memoryDb();
      addTearDown(db.close);
      await tester.pumpWidget(deleteHost(auth, db: db));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settings-delete-account')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'LÖSCHEN');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Endgültig löschen'));
      await tester.pumpAndSettle();

      expect(auth.deleteAccountCalls, 1);
    });

    testWidgets('Abbrechen ruft deleteAccount nicht auf', (tester) async {
      useTallViewport(tester);
      final auth = FakeAuth();
      final db = memoryDb();
      addTearDown(db.close);
      await tester.pumpWidget(deleteHost(auth, db: db));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settings-delete-account')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();

      expect(auth.deleteAccountCalls, 0);
    });

    testWidgets('Fehler bei der Löschung: Hinweis statt Absturz', (tester) async {
      useTallViewport(tester);
      final auth = FakeAuth(failWith: 'Keine Verbindung.');
      final db = memoryDb();
      addTearDown(db.close);
      await tester.pumpWidget(deleteHost(auth, db: db));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settings-delete-account')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'LÖSCHEN');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Endgültig löschen'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Keine Verbindung'), findsOneWidget);
    });

    testWidgets('Codereview-Fund 2026-10-01: signOut() scheitert nach erfolgreicher Loeschung -- wipe() laeuft trotzdem, kein Absturz', (tester) async {
      useTallViewport(tester);
      final auth = FakeAuth(failSignOutWith: 'Netzwerkfehler');
      final db = memoryDb();
      addTearDown(db.close);
      await db.into(db.products).insert(ProductsCompanion.insert(id: 'p1', householdId: 'h1', name: 'Milch', updatedAt: DateTime.now().toUtc()));

      await tester.pumpWidget(deleteHost(auth, db: db));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settings-delete-account')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'LÖSCHEN');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Endgültig löschen'));
      await tester.pumpAndSettle();

      expect(auth.deleteAccountCalls, 1);
      expect(auth.signOutCalls, 1); // wird trotz Fehler versucht
      final remaining = await db.select(db.products).get();
      expect(remaining, isEmpty); // wipe() lief trotzdem
    });

    testWidgets('Codereview-Fund 2026-10-16: scheitert das Leeren der Datenbank, werden Erinnerungen trotzdem storniert', (tester) async {
      useTallViewport(tester);
      final db = _FailingWipeDb();
      addTearDown(db.close);
      final scheduler = FakeNotificationScheduler();
      final auth = FakeAuth();
      await tester.pumpWidget(deleteHost(auth, db: db, scheduler: scheduler));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settings-delete-account')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'LÖSCHEN');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Endgültig löschen'));
      await tester.pumpAndSettle();

      expect(scheduler.cancelCalls, 1);
      expect(auth.signOutCalls, 1);
    });

    testWidgets('Codereview-Fund 2026-10-16: nach der Loeschung keine Erinnerungen des alten Kontos mehr', (tester) async {
      useTallViewport(tester);
      final db = memoryDb();
      addTearDown(db.close);
      final scheduler = FakeNotificationScheduler();
      await tester.pumpWidget(deleteHost(FakeAuth(), db: db, scheduler: scheduler));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settings-delete-account')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'LÖSCHEN');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Endgültig löschen'));
      await tester.pumpAndSettle();

      expect(scheduler.cancelCalls, 1);
    });
  });

  group('Abmelden', () {
    Widget signOutHost(FakeAuth auth, {required AppDatabase db, FakeNotificationScheduler? scheduler, FakeReceiptFileService? files, FakeMealPhotoService? photos}) => ProviderScope(
          overrides: [
            householdIdProvider.overrideWith((r) async => 'h1'),
            settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository(_settings)),
            authRepositoryProvider.overrideWithValue(auth),
            databaseProvider.overrideWithValue(db),
            pendingChangesProvider.overrideWith((ref) => Stream.value(0)),
            notificationSchedulerProvider.overrideWithValue(scheduler ?? FakeNotificationScheduler()),
            receiptFileServiceProvider.overrideWithValue(files ?? FakeReceiptFileService(db)),
            mealPhotoServiceProvider.overrideWithValue(photos ?? FakeMealPhotoService(db, mealRepo(db))),
          ],
          child: MaterialApp.router(routerConfig: GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => const SettingsPage())])),
        );

    testWidgets('loescht die lokalen Daten und meldet ab', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = FakeAuth();
      final db = memoryDb();
      addTearDown(db.close);
      await db.into(db.products).insert(ProductsCompanion.insert(id: 'p1', householdId: 'h1', name: 'Milch', updatedAt: DateTime.now().toUtc()));

      await tester.pumpWidget(signOutHost(auth, db: db));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settings-sign-out')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Abmelden'));
      await tester.pumpAndSettle();

      expect(auth.signOutCalls, 1);
      final remaining = await db.select(db.products).get();
      expect(remaining, isEmpty);
    });

    testWidgets('Codereview-Fund 2026-10-16: storniert die Erinnerungen und loescht lokale Belege und Essensfotos', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = memoryDb();
      addTearDown(db.close);
      final scheduler = FakeNotificationScheduler();
      final files = FakeReceiptFileService(db);
      final photos = FakeMealPhotoService(db, mealRepo(db));

      await tester.pumpWidget(signOutHost(FakeAuth(), db: db, scheduler: scheduler, files: files, photos: photos));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-sign-out')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Abmelden'));
      await tester.pumpAndSettle();

      expect(scheduler.cancelCalls, 1);
      expect(files.deleteAllLocalCalls, 1);
      expect(photos.deleteAllLocalCalls, 1);
    });
  });

  testWidgets('kein Budget gesetzt: Hinweistext', (tester) async {
    await tester.pumpWidget(host(FakeSettingsRepository(_settings)));
    await tester.pumpAndSettle();
    expect(find.text('Kein Budget gesetzt'), findsOneWidget);
  });

  testWidgets('Budget gesetzt: Betrag angezeigt', (tester) async {
    await tester.pumpWidget(host(FakeSettingsRepository(const HouseholdSettings(
      notifyTime: '07:30', notifyLeadDays: 1, allowCloudOcr: false, keepReceiptImages: true, monthlyBudgetCents: 30000,
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Warnung ab 300,00 € pro Monat'), findsOneWidget);
  });

  testWidgets('Budget eingeben speichert monthly_budget_cents in Cent', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeSettingsRepository(_settings);
    await tester.pumpWidget(host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Monatsbudget'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('budget-input')), '250');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    expect(repo.lastUpdate, {'monthly_budget_cents': 25000});
  });

  testWidgets('Budget leeren entfernt es wieder', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeSettingsRepository(const HouseholdSettings(
      notifyTime: '07:30', notifyLeadDays: 1, allowCloudOcr: false, keepReceiptImages: true, monthlyBudgetCents: 30000,
    ));
    await tester.pumpWidget(host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Monatsbudget'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('budget-input')), '');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    expect(repo.lastUpdate, {'monthly_budget_cents': null});
  });

  testWidgets('CSV-Export: Eintrag vorhanden, Tippen fuehrt nicht zum Absturz (Doku 07 §5)', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(FakeSettingsRepository(_settings)));
    await tester.pumpAndSettle();

    expect(find.text('Bon-Daten exportieren (CSV)'), findsOneWidget);
    await tester.tap(find.text('Bon-Daten exportieren (CSV)'));
    await tester.pumpAndSettle();
    // Kein Plattform-Kanal fuer databaseProvider/share_plus in flutter test: faellt auf die
    // Fehlermeldung zurueck statt abzustuerzen.
    expect(find.text('Export nicht möglich.'), findsOneWidget);
  });

  // Hinweis zum Fix "Erinnerungszeit aendern wirkt nicht sofort" (Codereview-Fund 2026-10-01,
  // SettingsPage._update): kein Widget-Test dafuer -- der Material-TimePicker-Dialog, der sich dabei
  // oeffnet, haelt in diesem Projekt (gleiche Grenze wie bei ReceiptEditPage's Datum/Uhrzeit-Picker)
  // eine laufende Animation, auf die pumpAndSettle() nie "settelt" (beobachtet: 10 Minuten bis zum
  // Timeout, auch mit einzelnen pump()-Aufrufen statt pumpAndSettle() weiterhin ein haengender Timer
  // beim Dispose). Die eigentliche Logik (`rescheduleExpiryReminders`) ist bereits in
  // expiry_reminder_scheduling_test.dart abgedeckt; der Fix selbst ist eine einzelne, bedingte
  // Zeile in `_update`.
}

/// Datenbank, deren Leeren scheitert (z.B. Speicher voll), fuer die Fehlerpfade beim Abmelden und Loeschen.
class _FailingWipeDb extends AppDatabase {
  _FailingWipeDb() : super(NativeDatabase.memory());

  @override
  Future<void> wipe() async => throw StateError('Datenbank nicht beschreibbar');
}
