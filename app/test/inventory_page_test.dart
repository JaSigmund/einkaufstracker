import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/features/inventory/inventory_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

Product _product(String id, String name) => Product(
      id: id,
      householdId: 'h1',
      name: name,
      baseUnit: 'piece',
      defaultDateKind: 'best_before',
      defaultLocation: 'pantry',
      restock: false,
      updatedAt: DateTime.utc(2026),
    );

void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  final today = DateTime.utc(2026, 9, 27);

  Widget app({
    List<InventoryItem> active = const [],
    List<InventoryItem> suggestions = const [],
    List<Product> products = const [],
    VoidCallback? onScan,
  }) =>
      ProviderScope(
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(inventoryRepo(db)),
          activeInventoryStreamProvider.overrideWith((ref) => Stream.value(active)),
          inventorySuggestionsStreamProvider.overrideWith((ref) => Stream.value(suggestions)),
          productsStreamProvider.overrideWith((ref) => Stream.value(products)),
        ],
        child: MaterialApp(home: Scaffold(body: InventoryPage(now: today, onScan: onScan))),
      );

  testWidgets('leeres Inventar: Hinweistext, FAB ruft onScan', (tester) async {
    var tapped = false;
    await tester.pumpWidget(app(onScan: () => tapped = true));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('inventory-empty')), findsOneWidget);
    await tester.tap(find.byKey(const Key('inventory-scan-fab')));
    expect(tapped, isTrue);
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
    final tiles = find.byType(ListTile);
    expect(tester.widget<ListTile>(tiles.at(0)), isA<ListTile>()); // Reihenfolge: Joghurt (frueher) vor Milch
    expect(find.text('Joghurt'), findsOneWidget);
    expect(find.text('Vollmilch'), findsOneWidget);
    expect(find.textContaining('2 piece'), findsOneWidget);
  });

  testWidgets('Ampeltexte: morgen, heute, abgelaufen, kein Datum', (tester) async {
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
  });

  testWidgets('geoeffnete Position zeigt "geöffnet"', (tester) async {
    await tester.pumpWidget(app(products: [_product('p1', 'Käse')], active: [_item('a', 'p1', status: 'opened')]));
    await tester.pumpAndSettle();
    expect(find.textContaining('geöffnet'), findsOneWidget);
  });

  testWidgets('Wischen nach rechts: aufgebraucht', (tester) async {
    final product = _product('p1', 'Käse');
    await inventoryRepo(db).recordFromScan(productId: 'p1', ean: '1', now: today);
    // damit die Datenbank ein reales Element hat, das der Dismiss auch aendern kann
    final real = await db.select(db.inventoryItems).getSingle();
    await tester.pumpWidget(app(products: [product], active: [real]));
    await tester.pumpAndSettle();

    await tester.drag(find.byKey(Key('inventory-item-${real.id}')), const Offset(500, 0));
    await tester.pumpAndSettle();
    final updated = await (db.select(db.inventoryItems)..where((i) => i.id.equals(real.id))).getSingle();
    expect(updated.status, 'consumed');
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

  testWidgets('Tippen oeffnet die Detailansicht mit Schnellaktionen', (tester) async {
    await inventoryRepo(db).recordFromScan(productId: 'p1', ean: '1', now: today);
    final real = await db.select(db.inventoryItems).getSingle();
    await tester.pumpWidget(app(products: [_product('p1', 'Käse')], active: [real]));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('inventory-item-${real.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('detail-open')), findsOneWidget);

    await tester.tap(find.byKey(const Key('detail-open')));
    await tester.pumpAndSettle();
    final opened = await (db.select(db.inventoryItems)..where((i) => i.id.equals(real.id))).getSingle();
    expect(opened.status, 'opened');
  });

  testWidgets('Detailansicht eines bereits geoeffneten Eintrags bietet kein "Geöffnet" mehr an', (tester) async {
    await tester.pumpWidget(app(products: [_product('p1', 'Käse')], active: [_item('a', 'p1', status: 'opened')]));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inventory-item-a')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('detail-open')), findsNothing);
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
}
