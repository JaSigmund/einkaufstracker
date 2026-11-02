import 'dart:convert';

import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/nutrition/bls_food_search.dart';
import 'package:einkaufstracker/data/repositories/household_prefs_repository.dart';
import 'package:einkaufstracker/domain/nutrition/nutrient_scaling.dart';
import 'package:einkaufstracker/domain/products/product_assignment.dart';
import 'package:einkaufstracker/features/inventory/inventory_page.dart';
import 'package:einkaufstracker/features/products/product_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';

void pageTest(String name, Future<void> Function(WidgetTester tester) body) => testWidgets(name, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

/// Die Drehscheibe aus Doku 27: alles zu einem Produkt auf einer Seite, und der Reiter "Produkte" im Inventar.
void main() {
  late AppDatabase db;
  late FakeBlsFoodSearch bls;
  late HouseholdPrefsRepository prefs;
  late Product milch;

  setUp(() async {
    db = memoryDb();
    bls = FakeBlsFoodSearch();
    prefs = HouseholdPrefsRepository(db, householdId: () async => 'h1');
    milch = await productRepo(db).create(name: 'Vollmilch', baseUnit: 'l', openedShelfLifeDays: 4, defaultLocation: 'fridge');
  });
  tearDown(() => db.close());

  List<dynamic> overrides({List<InventoryItem> stock = const []}) => [
        databaseProvider.overrideWithValue(db),
        productRepositoryProvider.overrideWithValue(productRepo(db)),
        foodLinkRepositoryProvider.overrideWithValue(foodLinkRepo(db)),
        blsFoodSearchProvider.overrideWithValue(bls),
        householdPrefsRepositoryProvider.overrideWithValue(prefs),
        householdPrefsOnceProvider.overrideWith((ref) async => const <String, Object?>{}),
        onlinePriceRepositoryProvider.overrideWithValue(onlinePriceRepo(db, FakeOnlinePriceRemote())),
        onlineLinksStreamProvider.overrideWith((ref, _) => Stream.value(const <ProductOnlineLink>[])),
        onlinePriceCacheStreamProvider.overrideWith((ref) => Stream.value(const <OnlinePriceCacheRow>[])),
        allOnlineLinksStreamProvider.overrideWith((ref) => Stream.value(const <ProductOnlineLink>[])),
        activeInventoryStreamProvider.overrideWith((ref) => Stream.value(stock)),
        inventorySuggestionsStreamProvider.overrideWith((ref) => Stream.value(const <InventoryItem>[])),
        balanceMovementsProvider.overrideWith((ref) => Stream.value(const <InventoryMovement>[])),
        allItemsStreamProvider.overrideWith((ref) => Stream.value(const <ReceiptItem>[])),
        receiptsStreamProvider.overrideWith((ref) => Stream.value(const <Receipt>[])),
        storesStreamProvider.overrideWith((ref) => Stream.value(const <Store>[])),
        categoriesStreamProvider.overrideWith((ref) => Stream.value([
              Category(id: 'c1', householdId: 'h1', name: 'Milchprodukte', sortOrder: 0, isStorable: true, updatedAt: DateTime.utc(2026)),
            ])),
      ];

  Future<void> open(WidgetTester tester, Widget home, {List<InventoryItem> stock = const []}) async {
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('START'))),
      GoRoute(path: '/page', builder: (_, _) => home),
      GoRoute(path: '/product/:id', builder: (_, s) => ProductPage(productId: s.pathParameters['id']!)),
      GoRoute(path: '/product-price', builder: (_, _) => const Scaffold(body: Text('PREISSEITE'))),
      GoRoute(path: '/product-form', builder: (_, _) => const Scaffold(body: Text('FORMULAR'))),
      GoRoute(path: '/inventory-item', builder: (_, _) => const Scaffold(body: Text('EINTRAG'))),
    ]);
    await tester.pumpWidget(ProviderScope(overrides: overrides(stock: stock).cast(), child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    router.push('/page');
    await tester.pumpAndSettle();
  }

  group('Produktseite', () {
    pageTest('zeigt jeden Abschnitt, ohne Zuordnungen mit Leer-Hinweisen', (tester) async {
      await open(tester, ProductPage(productId: milch.id));
      for (final heading in ['Bestand', 'Erkennung', 'Nährwerte', 'Preise', 'Einordnung', 'Lagerung']) {
        expect(find.text(heading), findsOneWidget, reason: heading);
      }
      expect(find.byKey(const Key('product-stock-empty')), findsOneWidget);
      expect(find.byKey(const Key('product-barcodes-empty')), findsOneWidget);
      expect(find.byKey(const Key('product-aliases-empty')), findsOneWidget);
      expect(find.byKey(const Key('product-nutrients-empty')), findsOneWidget);
      expect(find.text('Noch kein Kauf mit Grundpreis'), findsOneWidget);
      expect(find.text('Kühlschrank'), findsOneWidget);
      expect(find.text('Nach dem Öffnen 4 Tage'), findsOneWidget);
      expect(find.byKey(const Key('online-section')), findsOneWidget);
    });

    pageTest('unbekanntes Produkt: Hinweis statt Absturz', (tester) async {
      await open(tester, const ProductPage(productId: 'gibtsnicht'));
      expect(find.byKey(const Key('product-not-found')), findsOneWidget);
    });

    pageTest('zeigt Barcode und Bon-Text, Bon-Text laesst sich loesen', (tester) async {
      await productRepo(db).linkBarcode('9001234567890', milch.id);
      await productRepo(db).relearnReceiptText('JA NAT BIO VOLLM', milch.id);
      final alias = await (db.select(db.productAliases)..where((a) => a.productId.equals(milch.id))).getSingle();
      await open(tester, ProductPage(productId: milch.id));

      expect(find.byKey(const Key('product-barcode-9001234567890')), findsOneWidget);
      expect(find.byKey(Key('alias-${alias.id}')), findsOneWidget);

      await tester.tap(find.byKey(Key('alias-remove-${alias.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lösen'));
      await tester.pumpAndSettle();

      final row = await (db.select(db.productAliases)..where((a) => a.id.equals(alias.id))).getSingle();
      expect(row.deletedAt, isNotNull);
      expect(find.byKey(const Key('product-aliases-empty')), findsOneWidget);
    });

    pageTest('Naehrwerte: Name des Eintrags und Werte stehen da', (tester) async {
      bls.foods = const [BlsFood(code: 'M1', nameDe: 'Vollmilch 3,5 %', per100: NutrientsPer100(kcal: 64, proteinG: 3.3, fatG: 3.6, carbsG: 4.8))];
      await productRepo(db).setBlsProfile(milch.id, bls.foods.first);
      await open(tester, ProductPage(productId: milch.id));

      expect(tester.widget<Text>(find.byKey(const Key('product-nutrients-name'))).data, 'Vollmilch 3,5 %');
      final values = tester.widget<Text>(find.byKey(const Key('product-nutrients-values'))).data!;
      expect(values, contains('64 kcal'));
      expect(values, contains('Eiweiß'));
      expect(find.text('Ändern'), findsOneWidget);
    });

    pageTest('Naehrwerte aendern ueberschreibt das Profil', (tester) async {
      await productRepo(db).setBlsProfile(milch.id, const BlsFood(code: 'ALT', nameDe: 'Alt', per100: NutrientsPer100(kcal: 10)));
      bls.foods = const [BlsFood(code: 'NEU', nameDe: 'Vollmilch neu', per100: NutrientsPer100(kcal: 64))];
      await open(tester, ProductPage(productId: milch.id));

      await tester.tap(find.byKey(const Key('product-nutrients-change')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-bls-NEU')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nutrients-confirm-ok')));
      await tester.pumpAndSettle();

      final p = (await productRepo(db).byId(milch.id))!;
      expect(p.blsCode, 'NEU');
      expect(jsonDecode(p.nutrientsPer100!)['kcal'], 64);
    });

    pageTest('Nicht noetig entfernt nach Rueckfrage ein vorhandenes Profil, Zuruecknehmen hebt die Marke auf', (tester) async {
      await productRepo(db).setBlsProfile(milch.id, const BlsFood(code: 'ALT', nameDe: 'Alt', per100: NutrientsPer100(kcal: 10)));
      await open(tester, ProductPage(productId: milch.id));

      await tester.tap(find.byKey(const Key('product-nutrients-not-needed-action')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nutrients-remove-confirm')));
      await tester.pumpAndSettle();

      final p = (await productRepo(db).byId(milch.id))!;
      expect(p.nutrientsPer100, isNull);
      expect(p.blsCode, isNull);
      expect(p.nutrientsSource, isNull);
      expect(find.byKey(const Key('product-nutrients-not-needed')), findsOneWidget);

      await tester.tap(find.byKey(const Key('product-nutrients-needed')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('product-nutrients-empty')), findsOneWidget);
    });

    pageTest('Kategorie, Trinkbar und Nachkaufen wirken direkt', (tester) async {
      await open(tester, ProductPage(productId: milch.id));

      await tester.tap(find.byKey(const Key('product-category')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-category-c1')));
      await tester.pumpAndSettle();
      expect((await productRepo(db).byId(milch.id))!.categoryId, 'c1');
      expect(find.text('Milchprodukte'), findsOneWidget);

      await tester.tap(find.byKey(const Key('product-page-restock')));
      await tester.pumpAndSettle();
      expect((await productRepo(db).byId(milch.id))!.restock, isTrue);

      final before = tester.widget<SwitchListTile>(find.byKey(const Key('product-page-drink'))).value;
      await tester.tap(find.byKey(const Key('product-page-drink')));
      await tester.pumpAndSettle();
      expect((await productRepo(db).byId(milch.id))!.isDrink, !before);
    });

    pageTest('Stift oeffnet das Formular, Preiszeile die Preisseite', (tester) async {
      await open(tester, ProductPage(productId: milch.id));
      await tester.tap(find.byKey(const Key('product-page-edit')));
      await tester.pumpAndSettle();
      expect(find.text('FORMULAR'), findsOneWidget);
      GoRouter.of(tester.element(find.text('FORMULAR'))).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('product-price-open')));
      await tester.pumpAndSettle();
      expect(find.text('PREISSEITE'), findsOneWidget);
    });

    pageTest('Loeschen aus dem Menue schliesst die Seite', (tester) async {
      await open(tester, ProductPage(productId: milch.id));
      await tester.tap(find.byKey(const Key('product-page-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Löschen').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Löschen'));
      await tester.pumpAndSettle();

      expect((await productRepo(db).byId(milch.id))!.deletedAt, isNotNull);
      expect(find.text('START'), findsOneWidget);
    });
  });

  group('Reiter im Inventar', () {
    pageTest('Bestand ist Standard, Produkte zeigen die Liste, die Zahl nennt offene Naehrwerte und Kategorien', (tester) async {
      await open(tester, Scaffold(body: InventoryPage(now: DateTime.utc(2026, 11, 2))));

      expect(find.byKey(const Key('inventory-scan-fab')), findsOneWidget);
      expect(find.byKey(const Key('products-search')), findsNothing);
      expect(tester.widget<Badge>(find.byKey(const Key('inventory-products-badge'))).label, isA<Text>().having((t) => t.data, 'Zahl', '2'));

      await tester.tap(find.byKey(const Key('inventory-section-products')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('products-search')), findsOneWidget);
      expect(find.byKey(const Key('inventory-scan-fab')), findsNothing, reason: 'Erfassen gehoert zum Bestand');
      expect(find.byKey(Key('product-${milch.id}')), findsOneWidget);
      expect(find.byKey(Key('product-status-${milch.id}')), findsOneWidget);

      await tester.tap(find.byKey(Key('product-${milch.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Erkennung'), findsOneWidget);
    });

    pageTest('Filter bleibt beim Wechsel zwischen den Reitern erhalten', (tester) async {
      await open(tester, Scaffold(body: InventoryPage(now: DateTime.utc(2026, 11, 2))));
      await tester.tap(find.byKey(const Key('inventory-section-products')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('product-view-barcode')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('product-barcode-${milch.id}')), findsOneWidget);

      await tester.tap(find.byKey(const Key('inventory-section-stock')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('inventory-section-products')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('product-barcode-${milch.id}')), findsOneWidget);
    });

    pageTest('Nur offene: Produkt mit Barcode faellt aus der Barcode-Ansicht', (tester) async {
      final mitBarcode = await productRepo(db).create(name: 'Joghurt');
      await productRepo(db).linkBarcode('1234', mitBarcode.id);
      await open(tester, Scaffold(body: InventoryPage(now: DateTime.utc(2026, 11, 2))));
      await tester.tap(find.byKey(const Key('inventory-section-products')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('product-view-barcode')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('product-barcode-${mitBarcode.id}')), findsOneWidget);

      await tester.tap(find.byKey(const Key('products-open-only')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('product-barcode-${mitBarcode.id}')), findsNothing);
    });
  });

  group('Zusammenfuehren', () {
    test('"Nicht nötig" wandert mit, die Quelle verliert die Marke', () async {
      final repo = productRepo(db);
      final muell = await repo.create(name: 'Müllbeutel');
      final ziel = await repo.create(name: 'Bio-Müllbeutel');
      await prefs.setNutrientsNotNeeded(muell.id, true);

      await prefs.moveNutrientsNotNeeded(muell.id, ziel.id);

      final after = await prefs.load();
      expect(nutrientsNotNeeded(after, ziel.id), isTrue);
      expect(nutrientsNotNeeded(after, muell.id), isFalse);
    });

    test('ohne Marke an der Quelle aendert sich nichts', () async {
      await prefs.moveNutrientsNotNeeded('a', 'b');
      expect(await prefs.load(), isEmpty);
    });

    test('mergeInto ruft den Nachlauf erst nach dem Zusammenfuehren', () async {
      final calls = <(String, String)>[];
      final repo = productRepo(db, onMerged: (s, t) async => calls.add((s, t)));
      final a = await repo.create(name: 'A');
      final b = await repo.create(name: 'B');
      await repo.mergeInto(a.id, b.id);
      expect(calls, [(a.id, b.id)]);
      expect((await repo.byId(a.id))!.deletedAt, isNotNull);
    });
  });
}
