import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/nutrition/bls_food_search.dart';
import 'package:einkaufstracker/data/products/off_client.dart';
import 'package:einkaufstracker/data/repositories/household_prefs_repository.dart';
import 'package:einkaufstracker/data/repositories/inventory_repository.dart';
import 'package:einkaufstracker/data/repositories/product_repository.dart';
import 'package:einkaufstracker/domain/nutrition/nutrient_scaling.dart';
import 'package:einkaufstracker/domain/receipt/billa_text_parser.dart';
import 'package:einkaufstracker/features/products/learned_terms_page.dart';
import 'package:einkaufstracker/features/products/product_page.dart';
import 'package:einkaufstracker/features/receipts/receipt_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';

InventoryRepository inventoryRepoWithRelearn(AppDatabase db, ProductRepository products) =>
    InventoryRepository(db, householdId: () async => 'h1', relearnReceiptText: products.relearnReceiptText);

void pageTest(String name, Future<void> Function(WidgetTester tester) body) => testWidgets(name, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

/// Etappen E3 und E4 aus Doku 27 (ADR-052): Korrektur an der Quelle, Barcodes verwalten, gelernte Begriffe, Kategorie fuehrt vom Produkt.
void main() {
  late AppDatabase db;
  late Map<String, String> cat;

  setUp(() async {
    db = memoryDb();
    cat = await seedCategories(db);
  });
  tearDown(() => db.close());

  Future<ReceiptItem> position(String id, String rawText, {String? productId, String? categoryId}) async {
    await db.into(db.receipts).insertOnConflictUpdate(Receipt(
          id: 'r1',
          householdId: 'h1',
          purchasedAt: DateTime.utc(2026, 11, 1, 10),
          totalCents: 500,
          status: 'confirmed',
          source: 'manual',
          sumMismatch: false,
          updatedAt: DateTime.utc(2026),
        ));
    final item = ReceiptItem(
      excluded: false,
      id: id,
      householdId: 'h1',
      receiptId: 'r1',
      lineNo: 1,
      kind: 'article',
      rawText: rawText,
      productId: productId,
      quantity: 1,
      quantityUnit: 'piece',
      lineTotalCents: 129,
      categoryId: categoryId,
      needsReview: false,
      updatedAt: DateTime.utc(2026),
    );
    await db.into(db.receiptItems).insert(item);
    return item;
  }

  group('Barcodes', () {
    test('Loesen versteckt den Barcode, erneutes Zuordnen holt ihn zurueck', () async {
      final repo = productRepo(db);
      final milch = await repo.create(name: 'Milch', ean: '90012345');
      expect((await repo.lookup('90012345')).product?.id, milch.id);

      await repo.unlinkBarcode('90012345');
      final row = await db.select(db.productBarcodes).getSingle();
      expect(row.deletedAt, isNotNull);
      expect((await repo.lookup('90012345')).product, isNull);
      expect(await repo.productForBarcode('90012345'), isNull);
      expect(await repo.watchAllBarcodes().first, isEmpty);
      expect((await repo.recentUnlinked()).map((p) => p.id), contains(milch.id));
      expect(jsonDecode((await db.select(db.outbox).get()).last.payload)['deleted_at'], isNotNull);

      await repo.linkBarcode('90012345', milch.id);
      expect((await db.select(db.productBarcodes).getSingle()).deletedAt, isNull);
      expect((await repo.productForBarcode('90012345'))?.id, milch.id);
    });

    test('Open-Food-Facts-Profil ersetzt ein BLS-Profil und loescht den BLS-Code', () async {
      final repo = productRepo(db);
      final p = await repo.create(name: 'Joghurt');
      await repo.setBlsProfile(p.id, const BlsFood(code: 'M1', nameDe: 'Joghurt', per100: NutrientsPer100(kcal: 60)));
      final updated = await repo.setOffProfile(p.id, {'kcal': 72, 'protein_g': 4}, basis: 'g');
      expect(updated!.nutrientsSource, 'off');
      expect(updated.blsCode, isNull);
      expect(jsonDecode(updated.nutrientsPer100!)['kcal'], 72);
    });
  });

  group('Bon-Position umhaengen', () {
    test('Position, Grundpreis-Produkt, gelernter Bon-Text und ein offener Vorschlag ziehen mit', () async {
      final products = productRepo(db);
      final frisch = await products.findOrCreateForReceiptItem('CV Champig. 3.Wahl');
      final dose = await products.create(name: 'Champignons Dose');
      await position('i1', 'CV Champig. 3.Wahl', productId: frisch.id);
      final inv = inventoryRepo(db);
      await inv.createSuggestionFromReceipt(receiptItemId: 'i1', productId: frisch.id, quantity: 1, unit: 'piece', purchasedOn: DateTime.utc(2026, 11, 1));

      await inventoryRepoWithRelearn(db, products).moveReceiptItemTo('i1', dose.id);

      expect((await (db.select(db.receiptItems)..where((i) => i.id.equals('i1'))).getSingle()).productId, dose.id);
      final suggestion = await (db.select(db.inventoryItems)..where((i) => i.receiptItemId.equals('i1'))).getSingle();
      expect(suggestion.productId, dose.id);
      final moves = await (db.select(db.inventoryMovements)..where((m) => m.inventoryItemId.equals(suggestion.id))).get();
      expect(moves.every((m) => m.productId == dose.id), isTrue);
      final aliases = await (db.select(db.productAliases)..where((a) => a.deletedAt.isNull())).get();
      expect({for (final a in aliases) a.productId}, {dose.id});
    });

    test('eine bestaetigte Bonzuordnung eines anderen Produkts wird geloest', () async {
      final products = productRepo(db);
      final a = await products.create(name: 'A');
      final b = await products.create(name: 'B');
      await position('i1', 'TEXT A', productId: a.id);
      final inv = inventoryRepo(db);
      final scanned = await inv.recordFromScan(productId: a.id, ean: '1', now: DateTime.utc(2026, 11, 1));
      await inv.setReceiptLink(scanned.id, 'i1');

      await inv.moveReceiptItemTo('i1', b.id);

      expect((await (db.select(db.inventoryItems)..where((i) => i.id.equals(scanned.id))).getSingle()).receiptItemId, isNull);
    });
  });

  group('Kategorie fuehrt vom Produkt (Q-37)', () {
    test('Kategorie an der Position gilt auch fuer das Produkt', () async {
      final products = productRepo(db);
      final p = await products.create(name: 'Aufstrich');
      await position('i1', 'scharfer Aufstrich', productId: p.id);
      await receiptRepo(db).setItemCategory('i1', cat['Öle, Gewürze & Saucen']!);
      expect((await products.byId(p.id))!.categoryId, cat['Öle, Gewürze & Saucen']);
    });

    test('Kategorie am Produkt zieht die Positionen nach, Rueckgaengig stellt sie wieder her', () async {
      final p = await productRepo(db).create(name: 'Aufstrich');
      await position('i1', 'scharfer Aufstrich', productId: p.id, categoryId: cat['Gemüse']);
      final repo = receiptRepo(db);

      final previous = await repo.setProductItemsCategory(p.id, cat['Öle, Gewürze & Saucen']);
      expect(previous, {'i1': cat['Gemüse']});
      expect((await db.select(db.receiptItems).getSingle()).categoryId, cat['Öle, Gewürze & Saucen']);

      await repo.restoreItemCategories(previous);
      expect((await db.select(db.receiptItems).getSingle()).categoryId, cat['Gemüse']);
    });

    test('beim Import gilt die Kategorie des Produkts vor der Stichwortregel', () async {
      final products = productRepo(db);
      final known = await products.findOrCreateForReceiptItem('Clever Champignon weiß');
      await products.update(known.copyWith(categoryId: Value(cat['Öle, Gewürze & Saucen'])));
      final text = File('test/fixtures/receipts/billa_digital_04.txt').readAsStringSync();

      await receiptRepo(db, productRepo: products).saveParsed(const BillaTextParser().parse(text));

      final item = (await db.select(db.receiptItems).get()).firstWhere((i) => i.rawText == 'Clever Champignon weiß');
      expect(item.categoryId, cat['Öle, Gewürze & Saucen'], reason: 'ohne Produkt-Kategorie waere es Gemüse');
    });
  });

  group('Gelernte Bon-Texte', () {
    test('aendern und vergessen', () async {
      final p = await productRepo(db).create(name: 'Aufstrich');
      await position('i1', 'scharfer Aufstrich', productId: p.id);
      final repo = receiptRepo(db);
      await repo.setItemCategory('i1', cat['Gemüse']!);
      final alias = (await repo.watchCategoryAliases().first).single;

      await repo.setCategoryAlias(alias.id, cat['Öle, Gewürze & Saucen']!);
      expect((await repo.watchCategoryAliases().first).single.categoryId, cat['Öle, Gewürze & Saucen']);

      await repo.forgetCategoryAlias(alias.id);
      expect(await repo.watchCategoryAliases().first, isEmpty);
    });
  });

  group('Oberflaeche', () {
    List<dynamic> overrides({String? scan, OffProduct? off}) => [
          databaseProvider.overrideWithValue(db),
          productRepositoryProvider.overrideWithValue(productRepo(db, off: FakeOffClient(off))),
          inventoryRepositoryProvider.overrideWithValue(inventoryRepoWithRelearn(db, productRepo(db))),
          receiptRepositoryProvider.overrideWithValue(receiptRepo(db)),
          foodLinkRepositoryProvider.overrideWithValue(foodLinkRepo(db)),
          blsFoodSearchProvider.overrideWithValue(FakeBlsFoodSearch(foods: const [BlsFood(code: 'F1', nameDe: 'Banane roh', per100: NutrientsPer100(kcal: 95))])),
          householdPrefsRepositoryProvider.overrideWithValue(HouseholdPrefsRepository(db, householdId: () async => 'h1')),
          householdPrefsOnceProvider.overrideWith((ref) async => const <String, Object?>{}),
          barcodeScannerProvider.overrideWithValue(FakeBarcodeScanner(scan)),
          onlinePriceRepositoryProvider.overrideWithValue(onlinePriceRepo(db, FakeOnlinePriceRemote())),
          onlineLinksStreamProvider.overrideWith((ref, _) => Stream.value(const <ProductOnlineLink>[])),
          onlinePriceCacheStreamProvider.overrideWith((ref) => Stream.value(const <OnlinePriceCacheRow>[])),
          activeInventoryStreamProvider.overrideWith((ref) => Stream.value(const <InventoryItem>[])),
          allItemsStreamProvider.overrideWith((ref) => Stream.value(const <ReceiptItem>[])),
          receiptsStreamProvider.overrideWith((ref) => Stream.value(const <Receipt>[])),
          storesStreamProvider.overrideWith((ref) => Stream.value(const <Store>[])),
        ];

    Future<void> open(WidgetTester tester, Widget page, {String? scan, OffProduct? off}) async {
      tester.view.physicalSize = const Size(900, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('START'))),
        GoRoute(path: '/page', builder: (_, _) => page),
        GoRoute(path: '/product-form', builder: (_, _) => const Scaffold(body: Text('FORMULAR'))),
      ]);
      await tester.pumpWidget(ProviderScope(overrides: overrides(scan: scan, off: off).cast(), child: MaterialApp.router(routerConfig: router)));
      await tester.pumpAndSettle();
      router.push('/page');
      await tester.pumpAndSettle();
    }

    pageTest('Bon-Detail: Position einem anderen Produkt zuordnen', (tester) async {
      final products = productRepo(db);
      final frisch = await products.create(name: 'Champignons frisch');
      final dose = await products.create(name: 'Champignons Dose');
      await position('i1', 'CV Champig. 3.Wahl', productId: frisch.id);
      await open(tester, const ReceiptDetailPage(receiptId: 'r1'));

      await tester.tap(find.text('CV Champig. 3.Wahl'));
      await tester.pumpAndSettle();
      expect(find.text('Champignons frisch'), findsOneWidget);
      await tester.tap(find.byKey(const Key('item-product')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('pick-product-search')), 'dose');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('pick-product-${dose.id}')));
      await tester.pumpAndSettle();

      expect((await db.select(db.receiptItems).getSingle()).productId, dose.id);
    });

    pageTest('Bon-Detail: Kategorie ueber die eigene Zeile, das Produkt bekommt sie mit', (tester) async {
      final p = await productRepo(db).create(name: 'Aufstrich');
      await position('i1', 'scharfer Aufstrich', productId: p.id);
      await open(tester, const ReceiptDetailPage(receiptId: 'r1'));

      await tester.tap(find.text('scharfer Aufstrich'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('item-category')));
      await tester.pumpAndSettle();
      final pick = find.byKey(const Key('pick-Gemüse'));
      await tester.scrollUntilVisible(pick, 100, scrollable: find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)));
      await tester.tap(pick);
      await tester.pumpAndSettle();

      expect((await productRepo(db).byId(p.id))!.categoryId, cat['Gemüse']);
    });

    pageTest('Produktseite: Barcode scannen, umhaengen nach Rueckfrage, Naehrwerte von Open Food Facts anbieten', (tester) async {
      final products = productRepo(db);
      final alt = await products.create(name: 'Alt', ean: '90012345');
      final neu = await products.create(name: 'Neu');
      await open(tester, ProductPage(productId: neu.id), scan: '90012345', off: const OffProduct(name: 'Joghurt', nutrientsPer100: {'kcal': 72}, nutrientsBasis: 'g'));

      await tester.tap(find.byKey(const Key('product-barcode-add')));
      await tester.pumpAndSettle();
      expect(find.textContaining('gehört bisher zu „Alt“'), findsOneWidget);
      await tester.tap(find.byKey(const Key('barcode-move-confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('off-nutrients-accept')));
      await tester.pumpAndSettle();

      expect((await products.productForBarcode('90012345'))!.id, neu.id);
      expect((await products.byId(neu.id))!.nutrientsSource, 'off');
      expect(find.byKey(const Key('product-barcode-90012345')), findsOneWidget);
      expect(alt.id, isNot(neu.id));
    });

    pageTest('Produktseite: Barcode loesen', (tester) async {
      final p = await productRepo(db).create(name: 'Milch', ean: '90012345');
      await open(tester, ProductPage(productId: p.id));
      await tester.tap(find.byKey(const Key('barcode-unlink-90012345')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('barcode-unlink-confirm')));
      await tester.pumpAndSettle();
      expect(await productRepo(db).productForBarcode('90012345'), isNull);
      expect(find.byKey(const Key('product-barcodes-empty')), findsOneWidget);
    });

    pageTest('Produktseite: Bon-Position zuordnen', (tester) async {
      final products = productRepo(db);
      final frisch = await products.create(name: 'Champignons frisch');
      final dose = await products.create(name: 'Champignons Dose');
      await position('i1', 'CV Champig. 3.Wahl', productId: frisch.id);
      await open(tester, ProductPage(productId: dose.id));

      await tester.tap(find.byKey(const Key('product-receipt-add')));
      await tester.pumpAndSettle();
      expect(find.textContaining('bisher bei Champignons frisch'), findsOneWidget);
      await tester.tap(find.byKey(const Key('receipt-position-i1')));
      await tester.pumpAndSettle();

      expect((await db.select(db.receiptItems).getSingle()).productId, dose.id);
    });

    pageTest('Produktseite: Kategorie zieht die Positionen nach, Rueckgaengig in der Meldung', (tester) async {
      final p = await productRepo(db).create(name: 'Aufstrich');
      await position('i1', 'scharfer Aufstrich', productId: p.id, categoryId: cat['Gemüse']);
      await open(tester, ProductPage(productId: p.id));

      await tester.tap(find.byKey(const Key('product-category')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('pick-category-${cat['Öle, Gewürze & Saucen']}')));
      await tester.pumpAndSettle();
      expect(find.text('Auch 1 Bon-Position geändert'), findsOneWidget);
      expect((await db.select(db.receiptItems).getSingle()).categoryId, cat['Öle, Gewürze & Saucen']);

      await tester.tap(find.text('Rückgängig'));
      await tester.pumpAndSettle();
      expect((await db.select(db.receiptItems).getSingle()).categoryId, cat['Gemüse']);
      expect((await productRepo(db).byId(p.id))!.categoryId, isNull);
    });

    pageTest('Gelernte Begriffe: Zutat und Bon-Text, aendern und vergessen', (tester) async {
      await foodLinkRepo(db).learn('Banane', 'F1');
      final p = await productRepo(db).create(name: 'Aufstrich');
      await position('i1', 'scharfer Aufstrich', productId: p.id);
      await receiptRepo(db).setItemCategory('i1', cat['Gemüse']!);
      final alias = await db.select(db.categoryAliases).getSingle();
      final link = (await foodLinkRepo(db).all()).single;
      await open(tester, const LearnedTermsPage());

      expect(find.text('Banane'), findsOneWidget);
      expect(find.text('Banane roh'), findsOneWidget);
      expect(find.text('scharfer aufstrich'), findsOneWidget);

      await tester.tap(find.byKey(Key('learned-category-${alias.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('learned-pick-${cat['Öle, Gewürze & Saucen']}')));
      await tester.pumpAndSettle();
      expect((await db.select(db.categoryAliases).getSingle()).categoryId, cat['Öle, Gewürze & Saucen']);

      await tester.tap(find.byKey(Key('learned-category-forget-${alias.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('learned-category-empty')), findsOneWidget);

      await tester.tap(find.byKey(Key('learned-food-menu-${link.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vergessen'));
      await tester.pumpAndSettle();
      expect(await foodLinkRepo(db).all(), isEmpty);
    });
  });
}
