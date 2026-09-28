import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/settings_repository.dart';
import 'package:einkaufstracker/features/report/report_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Receipt _receipt(String id, DateTime utc, int cents) => Receipt(
      id: id, householdId: 'h', purchasedAt: utc, totalCents: cents, status: 'confirmed', source: 'pdf_text',
      sumMismatch: false, updatedAt: DateTime.utc(2026),
    );

ReceiptItem _item(String rid, String id, int no, String text, int cents, {String? cat, String kind = 'article', String? productId}) => ReceiptItem(
      id: id, householdId: 'h', receiptId: rid, lineNo: no, kind: kind, rawText: text, quantity: 1, quantityUnit: 'piece',
      lineTotalCents: cents, categoryId: cat, productId: productId, needsReview: false, updatedAt: DateTime.utc(2026),
    );

Category _cat(String id, String name) => Category(id: id, householdId: 'h', name: name, sortOrder: 0, isStorable: false, updatedAt: DateTime.utc(2026));

Product _product(String id, String name) =>
    Product(id: id, householdId: 'h', name: name, baseUnit: 'piece', defaultDateKind: 'best_before', defaultLocation: 'pantry', restock: false, updatedAt: DateTime.utc(2026));

void main() {
  Widget host() => ProviderScope(
        overrides: [
          receiptsStreamProvider.overrideWith((ref) => Stream.value([
                _receipt('a', DateTime.utc(2026, 9, 10, 10), 700),
                _receipt('b', DateTime.utc(2026, 8, 5, 10), 300),
              ])),
          allItemsStreamProvider.overrideWith((ref) => Stream.value([
                _item('a', 'i1', 1, 'Clever Champignon weiß', 500, cat: 'g', productId: 'p1'),
                _item('a', 'i2', 2, 'Clever Hirtenkäse', 300, cat: 'k'),
                _item('a', 'i4', 3, 'EXTREM AKTION', -100, cat: 'k', kind: 'discount'),
                _item('a', 'i5', 4, 'jö Rabattsammler 20%', -50, kind: 'bill_discount'),
                _item('b', 'i3', 1, 'Karottenbrot', 300, cat: 'b'),
              ])),
          categoriesStreamProvider.overrideWith((ref) => Stream.value([_cat('g', 'Gemüse'), _cat('k', 'Käse'), _cat('b', 'Brot & Backwaren')])),
          productsStreamProvider.overrideWith((ref) => Stream.value([_product('p1', 'Champignon weiß')])),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(routes: [
            GoRoute(path: '/', builder: (_, _) => Scaffold(body: ReportPage(now: DateTime.utc(2026, 9, 26, 12)))),
            GoRoute(path: '/receipt/:id', builder: (_, s) => Scaffold(body: Text('DETAIL ${s.pathParameters['id']}'))),
            GoRoute(path: '/product-price', builder: (_, s) => Scaffold(body: Text('PREIS ${(s.extra as Product).id}'))),
          ]),
        ),
      );

  testWidgets('zeigt den aktuellen Monat mit Kategorien, Vormonat per Pfeil, Drill-down per Tippen', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('September 2026'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('report-total'))).data, '6,50 €');
    expect(find.text('Gemüse'), findsOneWidget);
    expect(find.text('Käse'), findsOneWidget);
    expect(find.text('Brot & Backwaren'), findsNothing);
    // Bon-Rabatt getrennt, nicht in Kategorien verteilt
    expect(find.text('Rabatte auf den ganzen Bon'), findsOneWidget);
    expect(find.text('Nicht auf Kategorien verteilt'), findsOneWidget);

    expect(find.text('Clever Champignon weiß'), findsNothing);
    await tester.tap(find.text('Gemüse'));
    await tester.pumpAndSettle();
    expect(find.text('Clever Champignon weiß'), findsOneWidget);
    expect(find.text('Clever Hirtenkäse'), findsNothing);

    await tester.tap(find.byKey(const Key('month-prev')));
    await tester.pumpAndSettle();
    expect(find.text('August 2026'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('report-total'))).data, '3,00 €');
    expect(find.text('Brot & Backwaren'), findsOneWidget);
    expect(find.text('Clever Champignon weiß'), findsNothing); // Auswahl beim Monatswechsel zurueckgesetzt
  });

  testWidgets('Tippen auf einen zugeordneten Artikel oeffnet das Artikel-Detail (Doku 07 §2)', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Gemüse'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clever Champignon weiß'));
    await tester.pumpAndSettle();
    expect(find.text('PREIS p1'), findsOneWidget);
  });

  testWidgets('Monatswechsel ueber den Jahreswechsel und leerer Monat', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    for (var i = 0; i < 9; i++) {
      await tester.tap(find.byKey(const Key('month-prev')));
      await tester.pumpAndSettle();
    }
    expect(find.text('Dezember 2025'), findsOneWidget);
    expect(find.text('Keine Einkäufe in diesem Monat'), findsOneWidget);
    await tester.tap(find.byKey(const Key('month-next')));
    await tester.pumpAndSettle();
    expect(find.text('Januar 2026'), findsOneWidget);
  });

  testWidgets('Durch Rabatte gespart: Artikel- und Bon-Rabatte, Erklaerung mit Link auf den Bon', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.byKey(const Key('saved-total'))).data, '1,50 €'); // 1,00 + 0,50

    await tester.tap(find.byKey(const Key('saved-card')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('explanation-sheet')), findsOneWidget);
    expect(find.text('EXTREM AKTION'), findsOneWidget);
    expect(find.text('jö Rabattsammler 20%'), findsOneWidget);
    expect(find.text('-1,50 €'), findsWidgets);

    await tester.tap(find.byKey(const Key('receipt-link-a')));
    await tester.pumpAndSettle();
    expect(find.text('DETAIL a'), findsOneWidget); // Link fuehrt zum Bon
  });

  testWidgets('Tippen auf den Betrag einer Kategorie erklaert die Berechnung', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('amount-k')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('explanation-sheet')), findsOneWidget);
    // Artikel 3,00 + Rabatte -1,00 = 2,00
    expect(find.text('Artikel'), findsOneWidget);
    expect(find.text('Rabatte'), findsOneWidget);
    expect(find.text('Summe'), findsOneWidget);
    expect(find.text('2,00 €'), findsWidgets);
    expect(find.text('Clever Hirtenkäse'), findsOneWidget);
  });

  testWidgets('Tippen auf die Gesamtsumme zeigt die Aufteilung auf die Kategorien', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-total-tap')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('explanation-sheet')), findsOneWidget);
    expect(find.text('Ausgaben September 2026'), findsOneWidget);
    expect(find.text('Rabatte auf den ganzen Bon'), findsWidgets);
  });

  group('Monatsbudget (Doku 07 §2)', () {
    Widget hostWithBudget(int? budgetCents) => ProviderScope(
          overrides: [
            receiptsStreamProvider.overrideWith((ref) => Stream.value([_receipt('a', DateTime.utc(2026, 9, 10, 10), 700)])),
            allItemsStreamProvider.overrideWith((ref) => Stream.value([_item('a', 'i1', 1, 'Vollmilch', 700, cat: 'g')])),
            categoriesStreamProvider.overrideWith((ref) => Stream.value([_cat('g', 'Gemüse')])),
            householdSettingsProvider.overrideWith((ref) async => HouseholdSettings(
                  notifyTime: '07:30', notifyLeadDays: 1, allowCloudOcr: false, keepReceiptImages: true, monthlyBudgetCents: budgetCents,
                )),
          ],
          child: MaterialApp(home: Scaffold(body: ReportPage(now: DateTime.utc(2026, 9, 26, 12)))),
        );

    testWidgets('kein Budget gesetzt: keine Budget-Karte', (tester) async {
      await tester.pumpWidget(hostWithBudget(null));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('budget-card')), findsNothing);
    });

    testWidgets('Budget nicht ueberschritten', (tester) async {
      await tester.pumpWidget(hostWithBudget(100000));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('budget-card')), findsOneWidget);
      expect(find.text('7,00 € von 1.000,00 €'), findsOneWidget);
      expect(find.textContaining('überschritten'), findsNothing);
    });

    testWidgets('Budget ueberschritten: Warnhinweis', (tester) async {
      await tester.pumpWidget(hostWithBudget(500));
      await tester.pumpAndSettle();
      expect(find.text('Budget um 2,00 € überschritten'), findsOneWidget);
    });
  });
}
