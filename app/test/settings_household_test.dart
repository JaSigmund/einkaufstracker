import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/repositories/settings_repository.dart';
import 'package:einkaufstracker/features/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';

/// Einstellungen: Zugang zur Haushalt-Seite (Phase 6) und ehrlicher Text beim Konto-Loeschen mit mehreren Mitgliedern.
const _settings = HouseholdSettings(notifyTime: '07:30', notifyLeadDays: 1, allowCloudOcr: false, keepReceiptImages: true);

void main() {
  Widget host() => ProviderScope(
        overrides: [
          householdIdProvider.overrideWith((r) async => 'h1'),
          settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository(_settings)),
          authRepositoryProvider.overrideWithValue(FakeAuth()),
          pendingChangesProvider.overrideWith((ref) => Stream.value(0)),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(routes: [
            GoRoute(path: '/', builder: (_, _) => const SettingsPage()),
            GoRoute(path: '/household', builder: (_, _) => const Scaffold(body: Text('HAUSHALT-SEITE'))),
          ]),
        ),
      );

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('Eintrag "Haushalt" oeffnet die Haushalt-Seite', (tester) async {
    tall(tester);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('Personen einladen, Einladungen verwalten'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-household')));
    await tester.pumpAndSettle();
    expect(find.text('HAUSHALT-SEITE'), findsOneWidget);
  });

  testWidgets('Konto loeschen erklaert, was bei mehreren Mitgliedern passiert', (tester) async {
    tall(tester);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-delete-account')));
    await tester.pumpAndSettle();
    expect(find.textContaining('einzige Mitglied'), findsOneWidget);
    expect(find.textContaining('bleiben für die anderen erhalten'), findsOneWidget);
    expect(find.textContaining('Essenstagebuch samt Fotos'), findsOneWidget);
  });
}
