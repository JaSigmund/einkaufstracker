import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/features/report/report_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Receipt _receipt(String id, DateTime utc, int cents) => Receipt(
      id: id, householdId: 'h', purchasedAt: utc, totalCents: cents, status: 'confirmed', source: 'pdf_text',
      sumMismatch: false, updatedAt: DateTime.utc(2026),
    );

ReceiptItem _item(String rid, String id, int no, String text, int cents, {String? cat, String kind = 'article'}) => ReceiptItem(
      id: id, householdId: 'h', receiptId: rid, lineNo: no, kind: kind, rawText: text, quantity: 1, quantityUnit: 'piece',
      lineTotalCents: cents, categoryId: cat, needsReview: false, updatedAt: DateTime.utc(2026),
    );

Category _cat(String id, String name) => Category(id: id, householdId: 'h', name: name, sortOrder: 0, isStorable: false, updatedAt: DateTime.utc(2026));

void main() {
  Widget host() => ProviderScope(
        overrides: [
          receiptsStreamProvider.overrideWith((ref) => Stream.value([
                _receipt('a', DateTime.utc(2026, 9, 10, 10), 700),
                _receipt('b', DateTime.utc(2026, 8, 5, 10), 300),
              ])),
          allItemsStreamProvider.overrideWith((ref) => Stream.value([
                _item('a', 'i1', 1, 'Clever Champignon weiß', 500, cat: 'g'),
                _item('a', 'i2', 2, 'Clever Hirtenkäse', 200, cat: 'k'),
                _item('b', 'i3', 1, 'Karottenbrot', 300, cat: 'b'),
              ])),
          categoriesStreamProvider.overrideWith((ref) => Stream.value([_cat('g', 'Gemüse'), _cat('k', 'Käse'), _cat('b', 'Brot & Backwaren')])),
        ],
        child: MaterialApp(home: Scaffold(body: ReportPage(now: DateTime.utc(2026, 9, 26, 12)))),
      );

  testWidgets('zeigt den aktuellen Monat mit Kategorien, Vormonat per Pfeil, Drill-down per Tippen', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('September 2026'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('report-total'))).data, '7,00 €');
    expect(find.text('Gemüse'), findsOneWidget);
    expect(find.text('Käse'), findsOneWidget);
    expect(find.text('Brot & Backwaren'), findsNothing);

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
}
