import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/features/report/trend_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Receipt _receipt(String id, DateTime utc, int cents) => Receipt(
      id: id, householdId: 'h', purchasedAt: utc, totalCents: cents, status: 'confirmed', source: 'pdf_text',
      sumMismatch: false, updatedAt: DateTime.utc(2026),
    );

ReceiptItem _item(String rid, String id, int no, String text, int cents, {String? cat}) => ReceiptItem(
      excluded: false,
      id: id, householdId: 'h', receiptId: rid, lineNo: no, kind: 'article', rawText: text, quantity: 1, quantityUnit: 'piece',
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
                _item('a', 'i1', 1, 'Champignon', 500, cat: 'g'),
                _item('a', 'i2', 2, 'Hirtenkäse', 200, cat: 'k'),
                _item('b', 'i3', 1, 'Karotten', 300, cat: 'g'),
              ])),
          categoriesStreamProvider.overrideWith((ref) => Stream.value([_cat('g', 'Gemüse'), _cat('k', 'Käse')])),
        ],
        child: MaterialApp(home: TrendPage(now: DateTime.utc(2026, 9, 26, 12))),
      );

  testWidgets('zeigt die letzten 6 Monate, aeltester oben, aufklappen zeigt Kategorien', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('Sep 2026'), findsOneWidget);
    expect(find.text('Aug 2026'), findsOneWidget);
    expect(find.text('7,00 €'), findsOneWidget);
    expect(find.text('3,00 €'), findsOneWidget);

    expect(find.text('Gemüse'), findsNothing);
    await tester.tap(find.byKey(const Key('trend-month-5'))); // letzter Eintrag = September (endMonth)
    await tester.pumpAndSettle();
    expect(find.text('Gemüse'), findsOneWidget);
    expect(find.text('Käse'), findsOneWidget);
  });

  testWidgets('Umschalten auf 12 Monate', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('12 M.'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trend-month-11')), findsOneWidget);
  });
}
