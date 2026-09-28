import 'package:einkaufstracker/app/providers.dart';
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
}
