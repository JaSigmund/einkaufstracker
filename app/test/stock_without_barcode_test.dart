import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/inventory_repository.dart';
import 'package:einkaufstracker/data/repositories/product_repository.dart';
import 'package:einkaufstracker/domain/products/packaging.dart';
import 'package:einkaufstracker/features/products/manual_stock_page.dart';
import 'package:einkaufstracker/features/products/stock_entry_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';

Product _bananen() => Product(
      id: 'p1',
      householdId: 'h1',
      name: 'Ja! Bio Bananen kg',
      baseUnit: 'kg',
      defaultDateKind: 'best_before',
      defaultLocation: 'pantry',
      restock: false,
      updatedAt: DateTime.utc(2026),
    );

/// Fehlerbericht "Produkte ohne Barcode" (2026-11-02): lose Ware kam nur ueber den Scanner ins Inventar.
void main() {
  late AppDatabase db;
  late InventoryRepository repo;
  late ProductRepository products;
  late String productId;

  setUp(() async {
    db = memoryDb();
    repo = inventoryRepo(db);
    products = productRepo(db);
    productId = (await products.create(name: 'Bananen', baseUnit: 'kg')).id;
  });
  tearDown(() => db.close());

  group('recordFromScan ohne Barcode', () {
    test('legt bestaetigten Bestand mit Kaufbewegung an', () async {
      final item = await repo.recordFromScan(productId: productId, quantity: 1.4, unit: 'kg');

      expect(item.ean, isNull);
      expect(item.isSuggestion, isFalse);
      final movements = await db.select(db.inventoryMovements).get();
      expect(movements.single.type, 'purchase');
    });

    test('uebernimmt genau den gewaehlten Vorschlag, auch wenn er aelter als 7 Tage ist', () async {
      final old = await repo.createSuggestionFromReceipt(productId: productId, receiptItemId: 'ri1', quantity: 1.406, unit: 'kg', purchasedOn: DateTime.utc(2026, 1, 1));

      final item = await repo.recordFromScan(productId: productId, suggestionId: old.id, quantity: 1.406, unit: 'kg');

      expect(item.id, old.id);
      expect(item.isSuggestion, isFalse);
      expect(item.receiptItemId, 'ri1');
      expect((await db.select(db.inventoryItems).get()).length, 1);
      expect((await db.select(db.inventoryMovements).get()).length, 1, reason: 'der Bon hat den Kauf schon gebucht');
    });

    test('ohne Vorschlags-ID wird ein frischer Vorschlag desselben Produkts weiter verfeinert', () async {
      final fresh = await repo.createSuggestionFromReceipt(productId: productId, receiptItemId: 'ri1', quantity: 1, unit: 'kg', purchasedOn: DateTime.utc(2026, 11, 1));

      final item = await repo.recordFromScan(productId: productId, quantity: 1, unit: 'kg', now: DateTime.utc(2026, 11, 2));

      expect(item.id, fresh.id);
      expect(item.isSuggestion, isFalse);
    });
  });

  group('Seiten', () {
    Widget app(Widget home) {
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => home),
        GoRoute(path: '/stock-entry', builder: (_, s) {
          final a = s.extra as StockEntryArgs;
          return StockEntryPage(product: a.product, ean: a.ean, suggestion: a.suggestion, labelScanAvailable: false);
        }),
        GoRoute(path: '/inventory', builder: (_, _) => const Text('Inventar')),
      ]);
      return ProviderScope(
        overrides: [
          productsStreamProvider.overrideWith((ref) => Stream.value([_bananen()])),
          activeInventoryStreamProvider.overrideWith((ref) => Stream.value(const <InventoryItem>[])),
          inventoryRepositoryProvider.overrideWithValue(repo),
          productRepositoryProvider.overrideWithValue(products),
        ],
        child: MaterialApp.router(routerConfig: router),
      );
    }

    testWidgets('Auswahl fuehrt zur Erfassung ohne Barcode-Aktion, die Suche filtert', (tester) async {
      await tester.pumpWidget(app(const ManualStockPage()));
      await tester.pump();
      expect(find.byKey(const Key('manual-stock-product-p1')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('manual-stock-search')), 'apfel');
      await tester.pump();
      expect(find.byKey(const Key('manual-stock-product-p1')), findsNothing);
      expect(find.text('„apfel“ neu anlegen'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('manual-stock-search')), 'banan');
      await tester.pump();
      await tester.tap(find.byKey(const Key('manual-stock-product-p1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stock-save')), findsOneWidget);
      expect(find.byKey(const Key('stock-reassign')), findsNothing);
    });

    testWidgets('ein Bon-Vorschlag belegt Menge, Einheit und Lagerort vor', (tester) async {
      final suggestion = InventoryItem(
        id: 's1',
        householdId: 'h1',
        productId: 'p1',
        receiptItemId: 'ri1',
        quantity: 1.406,
        unit: 'kg',
        location: 'fridge',
        dateKind: 'best_before',
        status: 'sealed',
        isSuggestion: true,
        updatedAt: DateTime.utc(2026),
      );
      await tester.pumpWidget(app(StockEntryPage(product: _bananen(), suggestion: suggestion, labelScanAvailable: false)));
      await tester.pump();

      expect(tester.widget<TextField>(find.byKey(const Key('stock-quantity'))).controller!.text, '1,406');
      expect(tester.widget<DropdownButtonFormField<QuantityOption>>(find.byKey(const Key('stock-unit'))).initialValue?.label, 'kg');
      expect(tester.widget<DropdownButtonFormField<String>>(find.byKey(const Key('stock-location'))).initialValue, 'fridge');
    });
  });
}
