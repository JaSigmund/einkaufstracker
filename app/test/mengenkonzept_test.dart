import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/domain/receipt/billa_text_parser.dart';
import 'package:einkaufstracker/features/inventory/inventory_item_detail_page.dart';
import 'package:einkaufstracker/features/products/product_form_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';

/// Das Mengenkonzept durch die echten Repositories und Seiten (ADR-045). Die Regeln selbst stehen in `domain/packaging_test.dart`.
void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  Future<Product> yakult() => productRepo(db).create(name: 'Yakult Drink', baseUnit: 'l', packSize: 0.39, piecesPerPack: 6, pieceLabel: 'Fläschchen', unitWeightG: 65);
  Future<InventoryItem> row(String id) => (db.select(db.inventoryItems)..where((i) => i.id.equals(id))).getSingle();
  Future<List<InventoryMovement>> movements(String id) => (db.select(db.inventoryMovements)..where((m) => m.inventoryItemId.equals(id) & m.deletedAt.isNull())).get();

  group('Verbrauch in Teilen', () {
    test('ein Flaeschchen ist ein Verbrauch, keine Korrektur, und oeffnet den Rest nicht', () async {
      final p = await yakult();
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: p.id, ean: '1', quantity: 0.39, unit: 'l');

      expect(await repo.consumePart(item.id, 0.065, opens: false), isFalse);

      final after = await row(item.id);
      expect(after.quantity, 0.325);
      expect(after.status, 'sealed');
      final last = (await movements(item.id)).singleWhere((m) => m.type == 'consumed');
      expect((last.quantityDelta, last.unit), (-0.065, 'l'));
    });

    test('eine angebrochene Packung gilt als geoeffnet', () async {
      final p = await productRepo(db).create(name: 'Nudeln', baseUnit: 'kg', packSize: 0.5, openedShelfLifeDays: 3);
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: p.id, ean: '1', quantity: 1, unit: 'kg');
      await repo.consumePart(item.id, 0.5, openedShelfLifeDays: 3);
      expect((await row(item.id)).status, 'opened');
    });

    test('alle sechs nacheinander: der letzte schliesst den Eintrag, ohne Rundungsrest, und Rueckgaengig holt ihn zurueck', () async {
      final p = await yakult();
      var emptied = false;
      final repo = inventoryRepo(db, onDepleted: (_) async => emptied = true);
      final item = await repo.recordFromScan(productId: p.id, ean: '1', quantity: 0.39, unit: 'l');
      for (var i = 0; i < 5; i++) {
        expect(await repo.consumePart(item.id, 0.39 / 6, opens: false), isFalse);
      }
      expect(await repo.consumePart(item.id, 0.39 / 6, opens: false), isTrue);

      final closed = await row(item.id);
      expect(closed.status, 'consumed');
      expect(emptied, isTrue, reason: 'der letzte Rest loest den Nachkauf-Vorschlag aus');
      final sum = (await movements(item.id)).fold<double>(0, (s, m) => s + m.quantityDelta);
      expect(sum, closeTo(0, 0.001), reason: 'Kauf und sechs Abgaenge heben sich auf');

      await repo.reopen(item.id);
      final back = await row(item.id);
      expect(back.status, 'sealed');
      expect(back.quantity, closeTo(0.065, 0.001), reason: 'genau das letzte Flaeschchen ist wieder da');
    });

    test('mehr entnehmen als da ist: aufgebraucht, nie negativ', () async {
      final p = await productRepo(db).create(name: 'Kürbis');
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: p.id, ean: '1', quantity: 1);
      expect(await repo.consumePart(item.id, 5), isTrue);
      expect((await row(item.id)).quantity, 1, reason: 'Stand fuer Rueckgaengig');
      final closing = (await movements(item.id)).singleWhere((m) => m.type == 'consumed');
      expect(closing.quantityDelta, -1);
    });

    test('Mahlzeit: einzeln verpackt bleibt versiegelt, die Packung wird geoeffnet', () async {
      final y = await yakult();
      final n = await productRepo(db).create(name: 'Nudeln', baseUnit: 'kg', packSize: 0.5);
      final repo = inventoryRepo(db);
      final a = await repo.recordFromScan(productId: y.id, ean: '1', quantity: 0.39, unit: 'l');
      final b = await repo.recordFromScan(productId: n.id, ean: '2', quantity: 0.5, unit: 'kg');
      await db.transaction(() async {
        await repo.deductForMeal(mealId: 'm1', productId: y.id, quantity: 0.065, unit: 'l', eatenAt: DateTime.utc(2026, 11, 2));
        await repo.deductForMeal(mealId: 'm1', productId: n.id, quantity: 0.1, unit: 'kg', eatenAt: DateTime.utc(2026, 11, 2));
      });
      expect((await row(a.id)).status, 'sealed');
      expect((await row(b.id)).status, 'opened');
    });
  });

  group('Bestand umrechnen', () {
    test('Yakult wie bisher gespeichert: 6 Stueck werden zu 0,39 l, die Buchungen wandern mit', () async {
      final p = await productRepo(db).create(name: 'Yakult Drink', packSize: 0.39);
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: p.id, ean: '1', quantity: 1);
      await repo.adjustQuantity(item.id, 6);
      final before = (await movements(item.id)).length;

      final updated = p.copyWith(baseUnit: 'l', piecesPerPack: const Value(6));
      expect(await repo.normalizeStock(updated), 1);

      final after = await row(item.id);
      expect((after.quantity, after.unit), (0.39, 'l'));
      final ledger = await movements(item.id);
      expect(ledger, hasLength(before), reason: 'keine neuen Korrekturen, Bilanz und Vorhersage sehen keinen Zugang');
      expect(ledger.every((m) => m.unit == 'l'), isTrue);
      expect(ledger.fold<double>(0, (s, m) => s + m.quantityDelta), closeTo(0.39, 0.001));
      expect(await repo.normalizeStock(updated), 0, reason: 'zweimal aendert nichts');
    });

    test('ohne bekannten Inhalt bleibt der Bestand, wie er ist', () async {
      final p = await productRepo(db).create(name: 'Äpfel', baseUnit: 'kg');
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: p.id, ean: '1', quantity: 2, unit: 'piece');
      expect(await repo.normalizeStock(p), 0);
      expect((await row(item.id)).unit, 'piece');
    });

    test('Scan verfeinert einen Vorschlag in anderer Einheit: keine Mischung im Ledger', () async {
      final p = await productRepo(db).create(name: 'Faschiertes', baseUnit: 'kg', packSize: 0.5);
      final repo = inventoryRepo(db);
      final s = await repo.createSuggestionFromReceipt(productId: p.id, receiptItemId: 'r1', quantity: 1, unit: 'piece', purchasedOn: DateTime.utc(2026, 11, 2));
      await repo.recordFromScan(productId: p.id, ean: '1', quantity: 0.5, unit: 'kg', now: DateTime.utc(2026, 11, 2));

      final ledger = await movements(s.id);
      expect(ledger.single.quantityDelta, 0.5);
      expect(ledger.single.unit, 'kg');
      expect((await row(s.id)).isSuggestion, isFalse);
    });
  });

  group('Bon', () {
    test('neues Produkt mit Mehrfachpackung im Text ist gleich richtig angelegt', () async {
      final p = await productRepo(db).findOrCreateForReceiptItem('Tyrolini mild 4x40g');
      expect((p.baseUnit, p.packSize, p.piecesPerPack), ('kg', 0.16, 4));
    });

    test('Gewogenes und Text ohne Inhalt aendern nichts', () async {
      final weighed = await productRepo(db).findOrCreateForReceiptItem('Bananen 1kg', baseUnit: 'kg');
      expect((weighed.baseUnit, weighed.packSize), ('kg', null));
      final plain = await productRepo(db).findOrCreateForReceiptItem('Yakult Drink');
      expect((plain.baseUnit, plain.packSize), ('piece', null));
    });

    test('eine Position wird zur Menge im Bestand', () async {
      await seedCategories(db);
      final text = File('test/fixtures/receipts/billa_digital_04.txt').readAsStringSync();
      final products = productRepo(db);
      // Wie Yakult: das Produkt ist schon bekannt und hat einen Inhalt, der Bon nennt nur "1 ×"
      final known = await products.findOrCreateForReceiptItem('Clever Champignon weiß');
      await products.update(known.copyWith(baseUnit: 'kg', packSize: const Value(0.25)));

      await receiptRepo(db, productRepo: products, inventoryRepo: inventoryRepo(db)).saveParsed(const BillaTextParser().parse(text));

      final suggestion = await (db.select(db.inventoryItems)..where((i) => i.productId.equals(known.id))).getSingle();
      expect((suggestion.quantity, suggestion.unit), (0.25, 'kg'));
      final purchase = (await movements(suggestion.id)).single;
      expect((purchase.type, purchase.quantityDelta, purchase.unit), ('purchase', 0.25, 'kg'));
    });
  });

  group('Seiten', () {
    Widget page(InventoryItem item, Product p) => ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            inventoryRepositoryProvider.overrideWithValue(inventoryRepo(db)),
            inventoryMovementsStreamProvider.overrideWith((ref, _) => Stream.value(const <InventoryMovement>[])),
            productRepositoryProvider.overrideWithValue(productRepo(db)),
          ],
          child: MaterialApp.router(
            routerConfig: GoRouter(initialLocation: '/', routes: [
              GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('START'))),
              GoRoute(path: '/item', builder: (_, _) => InventoryItemDetailPage(item: item, product: p)),
            ]),
          ),
        );

    Future<void> open(WidgetTester tester, InventoryItem item, Product p) async {
      tester.view.physicalSize = const Size(1080, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(page(item, p));
      await tester.pumpAndSettle();
      GoRouter.of(tester.element(find.text('START'))).push('/item');
      await tester.pumpAndSettle();
    }

    testWidgets('Yakult im Inventar: zeigt Flaeschchen, Minus nimmt eines', (tester) async {
      final p = await yakult();
      final item = await inventoryRepo(db).recordFromScan(productId: p.id, ean: '1', quantity: 0.39, unit: 'l');
      await open(tester, item, p);
      expect(find.text('6 Fläschchen · 390 ml'), findsOneWidget);

      await tester.tap(find.byKey(const Key('quantity-minus')));
      await tester.pumpAndSettle();
      expect(find.text('5 Fläschchen · 325 ml'), findsOneWidget);
    });

    testWidgets('Yakult im Dialog: Packung umschalten rechnet die Zahl um, eingegebene Flaeschchen werden zur Menge', (tester) async {
      final p = await yakult();
      final item = await inventoryRepo(db).recordFromScan(productId: p.id, ean: '1', quantity: 0.39, unit: 'l');
      await open(tester, item, p);
      await tester.tap(find.byKey(const Key('quantity-tap')));
      await tester.pumpAndSettle();

      TextField input() => tester.widget<TextField>(find.byKey(const Key('quantity-input')));
      expect(input().controller!.text, '1', reason: 'eine ganze Packung');
      expect(find.text('Das sind 6 Fläschchen · 390 ml'), findsOneWidget);

      await tester.tap(find.byKey(const Key('quantity-unit')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fläschchen').last);
      await tester.pumpAndSettle();
      expect(input().controller!.text, '6');

      await tester.enterText(find.byKey(const Key('quantity-input')), '4');
      await tester.pumpAndSettle();
      expect(find.text('Das sind 4 Fläschchen · 260 ml'), findsOneWidget);
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      expect((await row(item.id)).quantity, 0.26);
      expect(find.text('4 Fläschchen · 260 ml'), findsOneWidget);
    });

    testWidgets('0 eingeben heisst aufgebraucht, mit Rueckgaengig; Unsinn wird abgelehnt', (tester) async {
      final p = await yakult();
      final item = await inventoryRepo(db).recordFromScan(productId: p.id, ean: '1', quantity: 0.39, unit: 'l');
      await open(tester, item, p);
      await tester.tap(find.byKey(const Key('quantity-tap')));
      await tester.pumpAndSettle();

      for (final bad in ['abc', '-1', '']) {
        await tester.enterText(find.byKey(const Key('quantity-input')), bad);
        await tester.tap(find.text('Übernehmen'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Bitte eine Menge'), findsOneWidget, reason: bad);
      }

      await tester.enterText(find.byKey(const Key('quantity-input')), '0');
      await tester.pumpAndSettle();
      expect(find.text('Der Eintrag gilt dann als aufgebraucht'), findsOneWidget);
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();

      expect((await row(item.id)).status, 'consumed');
      expect(find.text('START'), findsOneWidget);
      await tester.tap(find.text('Rückgängig'));
      await tester.pumpAndSettle();
      expect((await row(item.id)).status, 'sealed');
    });

    testWidgets('Produktformular: Mehrfachpackung anlegen, der Bestand zieht mit', (tester) async {
      tester.view.physicalSize = const Size(1080, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final existing = await productRepo(db).create(name: 'Yakult Drink', packSize: 0.39);
      final item = await inventoryRepo(db).recordFromScan(productId: existing.id, ean: '1', quantity: 6);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          productRepositoryProvider.overrideWithValue(productRepo(db)),
          inventoryRepositoryProvider.overrideWithValue(inventoryRepo(db)),
          categoriesStreamProvider.overrideWith((ref) => Stream.value(const <Category>[])),
          productAliasesStreamProvider.overrideWith((ref, _) => Stream.value(const <ProductAlias>[])),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(initialLocation: '/start', routes: [
            GoRoute(path: '/start', builder: (context, _) => Scaffold(body: TextButton(onPressed: () => context.push('/form'), child: const Text('OEFFNEN')))),
            GoRoute(path: '/form', builder: (_, _) => ProductFormPage(existing: existing)),
          ]),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OEFFNEN'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('product-kind')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mehrfachpackung').last);
      await tester.pumpAndSettle();

      // Ohne Stueckzahl geht es nicht
      await tester.tap(find.byKey(const Key('product-save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Stück in einer Packung'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('product-piece-count')), '6');
      await tester.enterText(find.byKey(const Key('product-pack-size')), '65');
      await tester.tap(find.byKey(const Key('product-amount-unit')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ml').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('product-piece-label')), 'Fläschchen');
      await tester.pumpAndSettle();
      expect(find.text('Eine Packung: 6 Fläschchen zu je 65 ml, zusammen 390 ml'), findsOneWidget);

      await tester.tap(find.byKey(const Key('product-save')));
      await tester.pumpAndSettle();

      final saved = await (db.select(db.products)..where((p) => p.id.equals(existing.id))).getSingle();
      expect((saved.baseUnit, saved.packSize, saved.piecesPerPack, saved.pieceLabel), ('l', 0.39, 6, 'Fläschchen'));
      expect(saved.unitWeightG, closeTo(65, 1e-9), reason: 'damit das Tagebuch 1 Stk versteht');
      final stock = await row(item.id);
      expect((stock.quantity, stock.unit), (0.39, 'l'));
    });

    testWidgets('Produktformular zeigt eine bestehende Packung in handlichen Einheiten', (tester) async {
      tester.view.physicalSize = const Size(1080, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final existing = await productRepo(db).create(name: 'Nudeln', baseUnit: 'kg', packSize: 0.5);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          productRepositoryProvider.overrideWithValue(productRepo(db)),
          categoriesStreamProvider.overrideWith((ref) => Stream.value(const <Category>[])),
          productAliasesStreamProvider.overrideWith((ref, _) => Stream.value(const <ProductAlias>[])),
        ],
        child: MaterialApp(home: ProductFormPage(existing: existing)),
      ));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('product-pack-size'))).controller!.text, '500');
      expect(find.text('Eine Packung: 500 g'), findsOneWidget);
    });
  });
}
