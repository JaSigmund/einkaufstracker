import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/features/diary/balance_card.dart';
import 'package:einkaufstracker/features/diary/balance_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';

/// Verbrauchsbilanz in der Oberflaeche (LH-MEAL-10): Karte im Tagebuch und Verlaufsseite.
InventoryMovement _mv(String id, String type, double delta, DateTime utc, {String product = 'p1', String unit = 'kg', String? mealId}) =>
    InventoryMovement(
      id: id, householdId: 'h1', productId: product, occurredAt: utc, type: type, quantityDelta: delta, unit: unit,
      mealId: mealId, updatedAt: DateTime.utc(2026),
    );

void main() {
  // Freitag, 2. Oktober 2026; aktuelle Woche ab Montag, 28. September
  final now = DateTime.utc(2026, 10, 2, 12);
  final thisWeek = DateTime.utc(2026, 9, 30, 10);
  final lastWeek = DateTime.utc(2026, 9, 23, 10);

  Widget host(List<InventoryMovement> movements, {List<Product> products = const [], bool page = false}) => ProviderScope(
        overrides: [
          balanceMovementsProvider.overrideWith((ref) => Stream.value(movements)),
          productsStreamProvider.overrideWith((ref) => Stream.value(products)),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(routes: [
            GoRoute(path: '/', builder: (_, _) => Scaffold(body: page ? BalancePage(now: now) : BalanceCard(now: now))),
            GoRoute(path: '/balance', builder: (_, _) => BalancePage(now: now)),
          ]),
        ),
      );

  testWidgets('Karte ohne Bewegungen: Hinweis statt Zahlen', (tester) async {
    await tester.pumpWidget(host(const []));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('balance-empty')), findsOneWidget);
  });

  testWidgets('Karte zeigt Deckungsgrad, erklaerte Menge, Einkauf und Abfall der laufenden Woche', (tester) async {
    await tester.pumpWidget(host([
      _mv('1', 'purchase', 2, thisWeek),
      _mv('2', 'meal', -0.6, thisWeek, mealId: 'a'),
      _mv('3', 'consumed', -0.4, thisWeek),
      _mv('4', 'discarded', -0.25, thisWeek),
      _mv('5', 'meal', -9, lastWeek, mealId: 'old'), // Vorwoche zaehlt nicht
    ]));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('balance-coverage-2026-9-28'))).data, 'Deckungsgrad 60 %');
    expect(find.text('Vom Bestand sind 1,0 kg abgegangen, 600 g davon durch Mahlzeiten erklärt.'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('balance-flow-2026-9-28'))).data, 'Eingekauft 2,0 kg · weggeworfen 250 g');
  });

  testWidgets('nur Einkauf, kein Abgang: kein Deckungsgrad (kein "0 %" und kein Teilen durch null)', (tester) async {
    await tester.pumpWidget(host([_mv('1', 'purchase', 1, thisWeek)]));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('balance-coverage-2026-9-28'))).data, 'Kein Bestandsabgang in dieser Woche.');
  });

  testWidgets('Stueck ohne bekanntes Gewicht werden benannt, nicht stillschweigend ignoriert', (tester) async {
    await tester.pumpWidget(host([
      _mv('1', 'meal', -0.5, thisWeek, mealId: 'a'),
      _mv('2', 'meal', -3, thisWeek, product: 'ei', unit: 'piece', mealId: 'b'),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('1 Buchung in Stück ohne bekanntes Gewicht ist nicht eingerechnet.'), findsOneWidget);
  });

  testWidgets('Stueck mit bekanntem Stueckgewicht gehen ein', (tester) async {
    final db = memoryDb();
    addTearDown(db.close);
    final egg = await productRepo(db).create(name: 'Eier', baseUnit: 'piece', unitWeightG: 60);
    await tester.pumpWidget(host([_mv('1', 'meal', -5, thisWeek, product: egg.id, unit: 'piece', mealId: 'a')], products: [egg]));
    await tester.pumpAndSettle();
    expect(find.text('Vom Bestand sind 300 g abgegangen, 300 g davon durch Mahlzeiten erklärt.'), findsOneWidget);
    expect(find.textContaining('nicht eingerechnet'), findsNothing);
  });

  testWidgets('Info-Knopf erklaert die Grenzen der Bilanz', (tester) async {
    await tester.pumpWidget(host(const []));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('balance-info')));
    await tester.pumpAndSettle();
    expect(find.text('Wie die Bilanz rechnet'), findsOneWidget);
    expect(find.textContaining('Stückgewicht'), findsOneWidget, reason: 'Grenze der Stueck-Umrechnung wird genannt');
    expect(find.textContaining('ganzen Haushalt'), findsOneWidget);
  });

  testWidgets('Verlauf-Knopf oeffnet die Verlaufsseite', (tester) async {
    await tester.pumpWidget(host([_mv('1', 'meal', -0.5, thisWeek, mealId: 'a')]));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('balance-history')));
    await tester.pumpAndSettle();
    expect(find.text('Bilanz'), findsOneWidget);
  });

  testWidgets('Verlaufsseite: eine Karte je Woche mit Zeitraum, neueste zuerst', (tester) async {
    await tester.pumpWidget(host([
      _mv('1', 'meal', -0.5, thisWeek, mealId: 'a'),
      _mv('2', 'meal', -0.2, lastWeek, mealId: 'b'),
      _mv('3', 'consumed', -0.2, lastWeek),
    ], page: true));
    await tester.pumpAndSettle();
    expect(find.text('28. Sep – 4. Okt'), findsOneWidget);
    expect(find.text('21. Sep – 27. Sep'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('balance-coverage-2026-9-28'))).data, 'Deckungsgrad 100 %');
    expect(tester.widget<Text>(find.byKey(const Key('balance-coverage-2026-9-21'))).data, 'Deckungsgrad 50 %');
    expect(tester.getTopLeft(find.text('28. Sep – 4. Okt')).dy, lessThan(tester.getTopLeft(find.text('21. Sep – 27. Sep')).dy));
  });

  testWidgets('Verlaufsseite ohne Bewegungen nennt den Zeitraum, keine leeren Karten', (tester) async {
    await tester.pumpWidget(host(const [], page: true));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('balance-none')), findsOneWidget);
    expect(find.byType(Card), findsNothing);
  });
}
