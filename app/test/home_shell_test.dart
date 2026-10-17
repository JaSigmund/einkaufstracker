// Hauptnavigation (Codereview 2026-10-16, A3/X1/U5): fuenf immer beschriftete Tabs mit eigener URL, deren Zustand beim
// Wechsel erhalten bleibt, "Scannen" als eigene Seite statt als Tab, ab 600 dp eine Seitenleiste und eine begrenzte
// Inhaltsbreite. Layout und Barrierefreiheit der Shell prueft zusaetzlich die Seitenliste in test/support/ui_pages.dart.
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/features/home/home_shell.dart';
import 'package:einkaufstracker/features/receipts/receipts_overview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';
import 'support/ui_pages.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  Future<GoRouter> open(WidgetTester tester, {String location = '/', Size size = const Size(412, 915)}) async {
    useDevice(tester, size);
    final router = homeShellRouter(location: location);
    await tester.pumpWidget(ProviderScope(overrides: homeShellOverrides(db), child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    return router;
  }

  // Adresse im Browser: setzen nur die Tabs (go); gepushte Seiten wie /scan aendern sie bewusst nicht (go_router-Standard)
  String path(GoRouter router) => router.routeInformationProvider.value.uri.path;
  String top(GoRouter router) => router.state.uri.path;
  String title(WidgetTester tester) =>
      tester.widget<Text>(find.descendant(of: find.byType(AppBar), matching: find.byType(Text)).first).data!;
  Finder navLabel(String label) => find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

  testWidgets('Handy: fuenf Ziele, alle beschriftet, Scannen ist kein Tab', (tester) async {
    await open(tester);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations, hasLength(5));
    expect(bar.labelBehavior, NavigationDestinationLabelBehavior.alwaysShow);
    for (final label in ['Übersicht', 'Inventar', 'Liste', 'Auswertung', 'Tagebuch']) {
      expect(navLabel(label), findsOneWidget, reason: label);
    }
    expect(navLabel('Scan'), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('jeder Tab hat eine URL, ein Deep-Link oeffnet ihn direkt', (tester) async {
    final router = await open(tester);
    expect(path(router), '/');
    for (final (label, target) in [('Inventar', '/inventory'), ('Liste', '/list'), ('Auswertung', '/report'), ('Tagebuch', '/diary')]) {
      await tester.tap(navLabel(label));
      await tester.pumpAndSettle();
      expect(path(router), target);
      expect(title(tester), label);
    }
  });

  testWidgets('Deep-Link auf das Tagebuch: Tab gewaehlt, Aktionen des Tabs in der Kopfzeile', (tester) async {
    await open(tester, location: '/diary');
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 4);
    expect(title(tester), 'Tagebuch');
    expect(find.byTooltip('Journal'), findsOneWidget);
    expect(find.byTooltip('Richtwerte'), findsOneWidget);
    expect(find.byTooltip('Rezeptvorschläge'), findsNothing);
  });

  testWidgets('Zustand bleibt beim Tabwechsel erhalten (angefangene Eingabe in der Liste)', (tester) async {
    await open(tester, location: '/list');
    await tester.enterText(find.byKey(const Key('shopping-list-input')), 'Hafermilch');
    await tester.tap(navLabel('Auswertung'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shopping-list-input')), findsNothing); // verdeckt, nicht nur ueberlagert
    await tester.tap(navLabel('Liste'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('shopping-list-input'))).controller!.text, 'Hafermilch');
  });

  testWidgets('Scannen ist von jedem Tab aus erreichbar, Zurueck fuehrt in denselben Tab', (tester) async {
    final router = await open(tester, location: '/inventory');
    await tester.tap(find.byKey(const Key('shell-scan')));
    await tester.pumpAndSettle();
    expect(top(router), '/scan');
    expect(title(tester), 'Scannen');
    expect(find.byKey(const Key('scan-barcode')), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(top(router), '/inventory');
    expect(title(tester), 'Inventar');
  });

  testWidgets('Uebersicht: Scannen als FAB, auf den anderen Tabs nicht', (tester) async {
    final router = await open(tester);
    expect(find.byKey(const Key('overview-scan-fab')), findsOneWidget);
    await tester.tap(find.byKey(const Key('overview-scan-fab')));
    await tester.pumpAndSettle();
    expect(top(router), '/scan');

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(navLabel('Auswertung'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('overview-scan-fab')), findsNothing);
  });

  testWidgets('Rezeptvorschlaege haben ein eigenes Icon, nicht das des Tagebuchs', (tester) async {
    await open(tester, location: '/inventory');
    final action = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.soup_kitchen_outlined));
    expect(action.tooltip, 'Rezeptvorschläge');
    expect(find.descendant(of: find.byType(AppBar), matching: find.byIcon(Icons.restaurant_menu_outlined)), findsNothing);
  });

  // Inventar und Tagebuch haben je einen FAB mit dem Standard-Hero-Tag, die Uebersicht den Scan-FAB
  testWidgets('verdeckte Tabs mit FAB: Seite oeffnen und schliessen ohne Hero-Konflikt', (tester) async {
    final router = await open(tester);
    await tester.tap(navLabel('Tagebuch'));
    await tester.pumpAndSettle();
    await tester.tap(navLabel('Inventar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Einstellungen'));
    await tester.pumpAndSettle();
    expect(top(router), '/settings');
    router.pop();
    await tester.pumpAndSettle();
    expect(title(tester), 'Inventar');
  });

  testWidgets('von einer Seite ueber der Uebersicht direkt ins Inventar (wie nach dem Speichern eines Scans)', (tester) async {
    final router = await open(tester);
    await tester.tap(find.byTooltip('Einstellungen'));
    await tester.pumpAndSettle();
    router.go('/inventory');
    await tester.pumpAndSettle();
    expect(title(tester), 'Inventar');
  });

  group('Tablet (1280x800)', () {
    testWidgets('Seitenleiste mit allen Beschriftungen und Scan-Knopf, Inhalt hoechstens 840 dp breit', (tester) async {
      final router = await open(tester, size: const Size(1280, 800));
      expect(find.byType(NavigationBar), findsNothing);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.labelType, NavigationRailLabelType.all);
      expect(rail.destinations, hasLength(5));
      expect(find.byKey(const Key('overview-scan-fab')), findsNothing);
      expect(tester.getSize(find.byType(ReceiptsOverview)).width, lessThanOrEqualTo(HomeShell.maxContentWidth));

      await tester.tap(find.descendant(of: find.byType(NavigationRail), matching: find.text('Inventar')));
      await tester.pumpAndSettle();
      expect(path(router), '/inventory');

      await tester.tap(find.byKey(const Key('shell-scan')));
      await tester.pumpAndSettle();
      expect(top(router), '/scan');
    });

    testWidgets('Tippflaechen beschriftet und gross genug, Text mit ausreichendem Kontrast', (tester) async {
      final semantics = tester.ensureSemantics();
      await open(tester, size: const Size(1280, 800));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantics.dispose();
    });
  });
}
