import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/core/clock.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/features/inventory/inventory_item_detail_page.dart';
import 'package:einkaufstracker/features/inventory/inventory_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';

DateTime _d(int y, int m, int d) => DateTime.utc(y, m, d);

InventoryItem _item(
  String id,
  String productId, {
  DateTime? expiresOn,
  String dateKind = 'best_before',
  String status = 'sealed',
  String location = 'pantry',
  double quantity = 1,
}) =>
    InventoryItem(
      id: id,
      householdId: 'h1',
      productId: productId,
      quantity: quantity,
      unit: 'piece',
      location: location,
      dateKind: dateKind,
      status: status,
      isSuggestion: false,
      expiresOn: expiresOn,
      updatedAt: DateTime.utc(2026),
    );

Product _product(String id, String name, {String? categoryId, String? brand}) => Product(
      id: id,
      householdId: 'h1',
      name: name,
      categoryId: categoryId,
      brand: brand,
      baseUnit: 'piece',
      defaultDateKind: 'best_before',
      defaultLocation: 'pantry',
      restock: false,
      updatedAt: DateTime.utc(2026),
    );

void main() {
  late AppDatabase db;
  setUp(() async {
    db = memoryDb();
    // die bisherigen Tests pruefen die Ablauf-Ansicht; die Kategorie-Ansicht (Standard) hat eine eigene Gruppe
    await db.setKv(inventoryViewKey, InventoryView.expiry.name);
  });
  tearDown(() => db.close());

  final today = DateTime.utc(2026, 9, 27);

  Widget app({
    List<InventoryItem> active = const [],
    List<InventoryItem> suggestions = const [],
    List<Product> products = const [],
    List<InventoryMovement> movements = const [],
    List<Category> categories = const [],
    FakeBarcodeScanner? scanner,
  }) =>
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          inventoryRepositoryProvider.overrideWithValue(inventoryRepo(db)),
          activeInventoryStreamProvider.overrideWith((ref) => Stream.value(active)),
          inventorySuggestionsStreamProvider.overrideWith((ref) => Stream.value(suggestions)),
          productsStreamProvider.overrideWith((ref) => Stream.value(products)),
          categoriesStreamProvider.overrideWith((ref) => Stream.value(categories)),
          inventoryMovementsStreamProvider.overrideWith((ref, _) => Stream.value(const <InventoryMovement>[])),
          balanceMovementsProvider.overrideWith((ref) => Stream.value(movements)),
          if (scanner != null) barcodeScannerProvider.overrideWithValue(scanner),
          productRepositoryProvider.overrideWithValue(productRepo(db)),
          householdPrefsProvider.overrideWith((ref) => Stream.value(const <String, Object?>{})),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(initialLocation: '/', routes: [
            GoRoute(path: '/', builder: (_, _) => Scaffold(body: InventoryPage(now: today))),
            GoRoute(
              path: '/inventory-item',
              builder: (_, s) {
                final a = s.extra as InventoryItemArgs;
                return InventoryItemDetailPage(item: a.item, product: a.product);
              },
            ),
            GoRoute(path: '/product-form', builder: (_, _) => const Scaffold(body: Text('PRODUCT-FORM'))),
            GoRoute(path: '/stock-entry', builder: (_, _) => const Scaffold(body: Text('STOCK-ENTRY'))),
          ]),
        ),
      );

  testWidgets('leeres Inventar: Hinweistext, FAB startet den Barcode-Scan', (tester) async {
    await tester.pumpWidget(app(scanner: FakeBarcodeScanner('9008700000001')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('inventory-empty')), findsOneWidget);
    await tester.tap(find.byKey(const Key('inventory-scan-fab')));
    await tester.pumpAndSettle();
    expect(find.text('PRODUCT-FORM'), findsOneWidget); // unbekannter Barcode: Anlageformular
  });

  testWidgets('sortiert nach Ablaufdatum, Name und Menge werden angezeigt', (tester) async {
    final milk = _product('p1', 'Vollmilch');
    final yog = _product('p2', 'Joghurt');
    await tester.pumpWidget(app(
      products: [milk, yog],
      active: [
        _item('a', 'p1', expiresOn: _d(2026, 10, 10)),
        _item('b', 'p2', expiresOn: _d(2026, 9, 28), quantity: 2),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.text('Joghurt'), findsOneWidget);
    expect(find.text('Vollmilch'), findsOneWidget);
    expect(find.textContaining('2 Stk'), findsOneWidget);
  });

  testWidgets('Ampeltexte: morgen, heute, abgelaufen, kein Datum, in Gruppen', (tester) async {
    await tester.pumpWidget(app(
      products: [_product('p1', 'A'), _product('p2', 'B'), _product('p3', 'C'), _product('p4', 'D')],
      active: [
        _item('a', 'p1', expiresOn: _d(2026, 9, 28)),
        _item('b', 'p2', expiresOn: _d(2026, 9, 27)),
        _item('c', 'p3', expiresOn: _d(2026, 9, 20)),
        _item('d', 'p4'),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('MHD: morgen'), findsOneWidget);
    expect(find.textContaining('MHD: heute'), findsOneWidget);
    expect(find.textContaining('abgelaufen'), findsOneWidget);
    expect(find.textContaining('Kein Ablaufdatum'), findsOneWidget);
    expect(find.textContaining('Läuft bald ab'), findsOneWidget);
    expect(find.textContaining('Abgelaufen (1)'), findsOneWidget);
    expect(find.textContaining('Ohne Ablaufdatum'), findsOneWidget);
  });

  testWidgets('geoeffnete Position zeigt "geöffnet"', (tester) async {
    await tester.pumpWidget(app(products: [_product('p1', 'Käse')], active: [_item('a', 'p1', status: 'opened')]));
    await tester.pumpAndSettle();
    expect(find.textContaining('geöffnet'), findsOneWidget);
  });

  testWidgets('Wischen nach rechts: aufgebraucht', (tester) async {
    final product = _product('p1', 'Käse');
    await inventoryRepo(db).recordFromScan(productId: 'p1', ean: '1', now: today);
    final real = await db.select(db.inventoryItems).getSingle();
    await tester.pumpWidget(app(products: [product], active: [real]));
    await tester.pumpAndSettle();

    await tester.drag(find.byKey(Key('inventory-item-${real.id}')), const Offset(500, 0));
    await tester.pumpAndSettle();
    final updated = await (db.select(db.inventoryItems)..where((i) => i.id.equals(real.id))).getSingle();
    expect(updated.status, 'consumed');
    expect(find.text('Rückgängig'), findsOneWidget); // sofortiger Rueckweg fuer einen Fehlgriff
    expect(tester.widget<SnackBar>(find.byType(SnackBar)).persist, isFalse);

    await tester.tap(find.text('Rückgängig'));
    await tester.pumpAndSettle();
    final reopened = await (db.select(db.inventoryItems)..where((i) => i.id.equals(real.id))).getSingle();
    expect(reopened.status, 'sealed');
  });

  testWidgets('Wischen nach links: weggeworfen', (tester) async {
    await inventoryRepo(db).recordFromScan(productId: 'p1', ean: '1', now: today);
    final real = await db.select(db.inventoryItems).getSingle();
    await tester.pumpWidget(app(products: [_product('p1', 'Käse')], active: [real]));
    await tester.pumpAndSettle();

    await tester.drag(find.byKey(Key('inventory-item-${real.id}')), const Offset(-500, 0));
    await tester.pumpAndSettle();
    final updated = await (db.select(db.inventoryItems)..where((i) => i.id.equals(real.id))).getSingle();
    expect(updated.status, 'discarded');
  });

  testWidgets('Tippen oeffnet die Detailseite mit Schnellaktionen', (tester) async {
    await inventoryRepo(db).recordFromScan(productId: 'p1', ean: '1', now: today);
    final real = await db.select(db.inventoryItems).getSingle();
    await tester.pumpWidget(app(products: [_product('p1', 'Käse')], active: [real]));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('inventory-item-${real.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('action-open')), findsOneWidget);

    await tester.tap(find.byKey(const Key('action-open')));
    await tester.pumpAndSettle();
    final opened = await (db.select(db.inventoryItems)..where((i) => i.id.equals(real.id))).getSingle();
    expect(opened.status, 'opened');
  });

  testWidgets('Vorschlaege: einklappbar, Verwerfen entfernt den Vorschlag', (tester) async {
    await db.into(db.inventoryItems).insert(InventoryItem(
          id: 'sugg', householdId: 'h1', productId: 'p1', quantity: 1, unit: 'piece', location: 'pantry',
          dateKind: 'best_before', status: 'sealed', isSuggestion: true, updatedAt: DateTime.utc(2026),
        ));
    await tester.pumpWidget(app(products: [_product('p1', 'Karotten')], suggestions: [await db.select(db.inventoryItems).getSingle()]));
    await tester.pumpAndSettle();
    expect(find.textContaining('Noch nicht gescannt (1)'), findsOneWidget);
    expect(find.text('Karotten'), findsOneWidget);

    await tester.tap(find.byKey(const Key('suggestions-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Karotten'), findsNothing); // eingeklappt

    await tester.tap(find.byKey(const Key('suggestions-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('discard-suggestion-sugg')));
    await tester.pumpAndSettle();
    final row = await (db.select(db.inventoryItems)..where((i) => i.id.equals('sugg'))).getSingle();
    expect(row.deletedAt, isNotNull);
  });

  testWidgets('Filter nach Lagerort', (tester) async {
    await tester.pumpWidget(app(
      products: [_product('p1', 'A'), _product('p2', 'B')],
      active: [_item('a', 'p1', location: 'fridge'), _item('b', 'p2', location: 'pantry')],
    ));
    await tester.pumpAndSettle();
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);

    await tester.tap(find.byKey(const Key('filter-location-fridge')));
    await tester.pumpAndSettle();
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsNothing);

    await tester.tap(find.byKey(const Key('filter-location-fridge'))); // aufheben
    await tester.pumpAndSettle();
    expect(find.text('B'), findsOneWidget);
  });

  group('Ansicht Kategorien (1.22)', () {
    Category cat(String id, String name, int sort) => Category(id: id, householdId: 'h1', name: name, sortOrder: sort, isStorable: true, updatedAt: DateTime.utc(2026));
    final cats = [cat('c-milch', 'Milchprodukte', 1), cat('c-obst', 'Obst & Gemüse', 2), cat('c-nudel', 'Nudeln', 3)];
    final prods = [
      _product('p1', 'Käse', categoryId: 'c-milch'),
      _product('p2', 'Joghurt', categoryId: 'c-milch'),
      _product('p3', 'Äpfel', categoryId: 'c-obst'),
      _product('p4', 'Spaghetti', categoryId: 'c-nudel', brand: 'Barilla'),
      _product('p5', 'Kerzen'),
    ];
    final items = [
      _item('a', 'p1', expiresOn: _d(2026, 10, 20)),
      _item('b', 'p2', expiresOn: _d(2026, 9, 25)), // abgelaufen
      _item('c', 'p3', expiresOn: _d(2026, 9, 28)), // bald
      _item('d', 'p4'),
      _item('e', 'p5'),
    ];

    Future<void> openCategories(WidgetTester tester) async {
      await (db.delete(db.keyValues)..where((k) => k.key.equals(inventoryViewKey))).go(); // ohne Einstellung gilt der Standard
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(products: prods, active: items, categories: cats));
      await tester.pumpAndSettle();
    }

    testWidgets('Standard: zugeklappte Abschnitte in Kategorie-Reihenfolge mit Anzahl, Dringendes sichtbar', (tester) async {
      await openCategories(tester);
      final headers = tester.widgetList<ListTile>(find.byWidgetPredicate((w) => w is ListTile && w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('inventory-category-')));
      expect(headers.map((h) => (h.key! as ValueKey<String>).value), [
        'inventory-category-c-milch',
        'inventory-category-c-obst',
        'inventory-category-c-nudel',
        'inventory-category-_none',
      ]);
      expect(find.descendant(of: find.byKey(const Key('inventory-category-_none')), matching: find.text('Ohne Kategorie')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('inventory-category-count-c-milch'))).data, '2');
      expect(find.text('Käse'), findsNothing, reason: 'zugeklappt');
      expect(find.byKey(const Key('inventory-urgent')), findsOneWidget);
      expect(find.text('1 abgelaufen, 1 läuft bald ab'), findsOneWidget);
    });

    testWidgets('Aufklappen zeigt das Dringende zuerst und wird gemerkt', (tester) async {
      await openCategories(tester);
      await tester.tap(find.byKey(const Key('inventory-category-c-milch')));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Joghurt')).dy, lessThan(tester.getTopLeft(find.text('Käse')).dy), reason: 'abgelaufen vor gut');
      expect(find.text('Äpfel'), findsNothing);
      expect(await db.getKv(inventoryOpenCategoriesKey), '["c-milch"]');

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(products: prods, active: items, categories: cats));
      await tester.pumpAndSettle();
      expect(find.text('Käse'), findsOneWidget, reason: 'beim naechsten Oeffnen noch offen');
    });

    testWidgets('Alle aufklappen und zuklappen', (tester) async {
      await openCategories(tester);
      await tester.tap(find.byKey(const Key('inventory-toggle-all')));
      await tester.pumpAndSettle();
      for (final name in ['Käse', 'Joghurt', 'Äpfel', 'Spaghetti', 'Kerzen']) {
        expect(find.text(name), findsOneWidget);
      }
      await tester.tap(find.byKey(const Key('inventory-toggle-all')));
      await tester.pumpAndSettle();
      expect(find.text('Käse'), findsNothing);
    });

    testWidgets('Suche ohne Umlaute, auch nach Marke und Kategorie, oeffnet die Treffer', (tester) async {
      await openCategories(tester);
      await tester.enterText(find.byKey(const Key('inventory-search')), 'kase');
      await tester.pumpAndSettle();
      expect(find.text('Käse'), findsOneWidget);
      expect(find.text('Joghurt'), findsNothing);
      expect(find.byKey(const Key('inventory-category-c-obst')), findsNothing);

      await tester.enterText(find.byKey(const Key('inventory-search')), 'barilla');
      await tester.pumpAndSettle();
      expect(find.text('Spaghetti'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('inventory-search')), 'obst');
      await tester.pumpAndSettle();
      expect(find.text('Äpfel'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('inventory-search')), 'xyz');
      await tester.pumpAndSettle();
      expect(find.text('Nichts im Bestand passt zu „xyz“'), findsOneWidget);

      await tester.tap(find.byKey(const Key('inventory-search-clear')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('inventory-category-c-obst')), findsOneWidget);
    });

    testWidgets('"Zuerst verbrauchen" wechselt zur Ablauf-Ansicht und merkt sie', (tester) async {
      await openCategories(tester);
      await tester.tap(find.byKey(const Key('inventory-urgent')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Abgelaufen (1)'), findsOneWidget);
      expect(find.text('Käse'), findsOneWidget);
      expect(await db.getKv(inventoryViewKey), 'expiry');

      await tester.tap(find.text('Kategorien'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('inventory-category-c-milch')), findsOneWidget);
      expect(await db.getKv(inventoryViewKey), 'categories');
    });
  });

  group('Verbrauchsvorhersage (Ausbau 1.14)', () {
    final now = appClock.now().toUtc();

    InventoryMovement move(String id, String type, double delta, int daysAgo) => InventoryMovement(
          id: id, householdId: 'h1', productId: 'p1', occurredAt: now.subtract(Duration(days: daysAgo)), type: type, quantityDelta: delta, unit: 'piece', updatedAt: now,
        );

    /// Vor 20 Tagen gekauft, in 20 Tagen vier Mal eine Einheit verbraucht: rund 0,19 je Tag.
    List<InventoryMovement> history() => [move('m0', 'purchase', 5, 20), move('m1', 'meal', -1, 16), move('m2', 'meal', -1, 12), move('m3', 'consumed', -1, 8), move('m4', 'meal', -1, 3)];

    testWidgets('wird es bald knapp, steht die Reichweite in der Zeile', (tester) async {
      await tester.pumpWidget(app(products: [_product('p1', 'Vollmilch')], active: [_item('a', 'p1')], movements: history()));
      await tester.pumpAndSettle();
      expect(find.textContaining('reicht voraussichtlich noch etwa 5 Tage'), findsOneWidget);
    });

    testWidgets('reicht der Bestand noch lange, steht dort nichts', (tester) async {
      await tester.pumpWidget(app(products: [_product('p1', 'Vollmilch')], active: [_item('a', 'p1', quantity: 20)], movements: history()));
      await tester.pumpAndSettle();
      expect(find.textContaining('reicht voraussichtlich'), findsNothing);
    });

    testWidgets('ohne ausreichenden Verlauf keine Zahl', (tester) async {
      await tester.pumpWidget(app(products: [_product('p1', 'Vollmilch')], active: [_item('a', 'p1')], movements: [move('m0', 'purchase', 5, 20), move('m1', 'meal', -1, 3)]));
      await tester.pumpAndSettle();
      expect(find.textContaining('reicht voraussichtlich'), findsNothing);
    });
  });
}
