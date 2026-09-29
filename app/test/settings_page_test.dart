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
    Widget deleteHost(FakeAuth auth, {required AppDatabase db}) => ProviderScope(
          overrides: [
            householdIdProvider.overrideWith((r) async => 'h1'),
            settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository(_settings)),
            authRepositoryProvider.overrideWithValue(auth),
            databaseProvider.overrideWithValue(db),
            // Der echte Drift-Stream (SyncStatusBanner) hinterlaesst beim Dispose einen Timer, den
            // flutter_test als "still pending" meldet -- hier nicht relevant, deshalb ein Stub.
            pendingChangesProvider.overrideWith((ref) => Stream.value(0)),
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
}
