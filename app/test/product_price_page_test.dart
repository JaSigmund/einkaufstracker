import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/features/report/product_price_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Product _product({String baseUnit = 'l'}) =>
    Product(id: 'p1', householdId: 'h', name: 'Vollmilch', baseUnit: baseUnit, defaultDateKind: 'best_before', defaultLocation: 'pantry', restock: false, updatedAt: DateTime.utc(2026));

Receipt _receipt(String id, String storeId, DateTime purchasedAt) =>
    Receipt(id: id, householdId: 'h', storeId: storeId, purchasedAt: purchasedAt, totalCents: 100, status: 'confirmed', source: 'pdf_text', sumMismatch: false, updatedAt: DateTime.utc(2026));

Store _store(String id, String chain) => Store(id: id, householdId: 'h', chain: chain, updatedAt: DateTime.utc(2026));

ReceiptItem _item(String rid, String id, int unitPriceNormCents) => ReceiptItem(
      id: id, householdId: 'h', receiptId: rid, lineNo: 1, kind: 'article', rawText: 'Vollmilch', quantity: 1, quantityUnit: 'piece',
      lineTotalCents: 129, productId: 'p1', unitPriceNormCents: unitPriceNormCents, needsReview: false, updatedAt: DateTime.utc(2026),
    );

void main() {
  Widget host({DateTime? now}) => ProviderScope(
        overrides: [
          receiptsStreamProvider.overrideWith((ref) => Stream.value([
                _receipt('r1', 's-billa', DateTime.utc(2026, 9, 1)),
                _receipt('r2', 's-billa', DateTime.utc(2026, 8, 1)),
                _receipt('r3', 's-hofer', DateTime.utc(2026, 9, 5)),
                _receipt('r4', 's-hofer', DateTime.utc(2026, 8, 5)),
              ])),
          storesStreamProvider.overrideWith((ref) => Stream.value([_store('s-billa', 'Billa'), _store('s-hofer', 'Hofer')])),
          allItemsStreamProvider.overrideWith((ref) => Stream.value([
                _item('r1', 'i1', 200),
                _item('r2', 'i2', 220),
                _item('r3', 'i3', 150),
                _item('r4', 'i4', 160),
              ])),
        ],
        child: MaterialApp(home: ProductPricePage(product: _product())),
      );

  testWidgets('zeigt Haendlervergleich und Preisverlauf', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('Vollmilch'), findsOneWidget);
    expect(find.byKey(const Key('comparison-card')), findsOneWidget);
    expect(find.text('Hofer'), findsOneWidget);
    expect(find.text('Billa'), findsOneWidget);
    expect(find.textContaining('spart'), findsOneWidget);

    // Preisverlauf: neuester Kauf zuerst
    final tiles = find.byType(ListTile);
    expect(tiles, findsWidgets);
    expect(find.text('2,00 €/l'), findsOneWidget); // r1
    expect(find.text('1,50 €/l'), findsOneWidget); // r3
  });

  testWidgets('zu wenig Daten fuer einen Vergleich: Hinweis statt Karte', (tester) async {
    final widget = ProviderScope(
      overrides: [
        receiptsStreamProvider.overrideWith((ref) => Stream.value([_receipt('r1', 's-billa', DateTime.utc(2026, 9, 1))])),
        storesStreamProvider.overrideWith((ref) => Stream.value([_store('s-billa', 'Billa')])),
        allItemsStreamProvider.overrideWith((ref) => Stream.value([_item('r1', 'i1', 200)])),
      ],
      child: MaterialApp(home: ProductPricePage(product: _product())),
    );
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('comparison-insufficient')), findsOneWidget);
    expect(find.byKey(const Key('comparison-card')), findsNothing);
  });
}
