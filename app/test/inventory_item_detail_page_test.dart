import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/features/inventory/inventory_item_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';

DateTime _d(int y, int m, int d) => DateTime.utc(y, m, d);

void main() {
  late AppDatabase db;
  late Product product;

  setUp(() async {
    db = memoryDb();
    product = await productRepo(db).create(name: 'Vollmilch', baseUnit: 'l');
  });
  tearDown(() => db.close());

  Widget app(InventoryItem item, {Product? p}) => ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          inventoryRepositoryProvider.overrideWithValue(inventoryRepo(db)),
          inventoryMovementsStreamProvider.overrideWith((ref, _) => Stream.value(const <InventoryMovement>[])),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(initialLocation: '/', routes: [
            GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('START'))),
            GoRoute(path: '/item', builder: (_, _) => InventoryItemDetailPage(item: item, product: p ?? product)),
          ]),
        ),
      );

  testWidgets('Menge per +/- und per Eingabe aendern, mit Ledger-Bewegung', (tester) async {
    final item = await inventoryRepo(db).recordFromScan(productId: product.id, ean: '1', quantity: 2, now: DateTime.utc(2026, 9, 27));
    await tester.pumpWidget(app(item));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('START'))).push('/item');
    await tester.pumpAndSettle();
    expect(find.textContaining('2 piece'), findsOneWidget);

    await tester.tap(find.byKey(const Key('quantity-plus')));
    await tester.pumpAndSettle();
    expect(find.textContaining('3 piece'), findsOneWidget);
    expect((await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle()).quantity, 3);

    await tester.tap(find.byKey(const Key('quantity-tap')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('quantity-input')), '5');
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('5 piece'), findsOneWidget);

    final movements = await db.select(db.inventoryMovements).get();
    expect(movements.where((m) => m.type == 'adjustment'), hasLength(2));
  });

  testWidgets('Menge kann nicht negativ werden', (tester) async {
    final item = await inventoryRepo(db).recordFromScan(productId: product.id, ean: '1', quantity: 1, now: DateTime.utc(2026, 9, 27));
    await tester.pumpWidget(app(item));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('START'))).push('/item');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quantity-minus')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quantity-minus')));
    await tester.pumpAndSettle();
    expect(find.textContaining('0 piece'), findsOneWidget);
    final row = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
    expect(row.quantity, 0);
  });

  testWidgets('Lagerort und Datumsart per Antippen wechseln, ohne Ledger-Bewegung', (tester) async {
    final item = await inventoryRepo(db).recordFromScan(productId: product.id, ean: '1', bestBefore: _d(2026, 10, 10), now: DateTime.utc(2026, 9, 27));
    await tester.pumpWidget(app(item));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('START'))).push('/item');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('location-fridge')));
    await tester.pumpAndSettle();
    var row = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
    expect(row.location, 'fridge');

    await tester.tap(find.text('Verbrauchsdatum'));
    await tester.pumpAndSettle();
    row = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
    expect(row.dateKind, 'use_by');

    expect(await db.select(db.inventoryMovements).get(), hasLength(1)); // nur der Kauf
  });

  testWidgets('Datum entfernen setzt auch das Ablaufdatum zurueck', (tester) async {
    final item = await inventoryRepo(db).recordFromScan(productId: product.id, ean: '1', bestBefore: _d(2026, 10, 10), now: DateTime.utc(2026, 9, 27));
    await tester.pumpWidget(app(item));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('START'))).push('/item');
    await tester.pumpAndSettle();
    expect(find.text('10.10.2026'), findsOneWidget);

    await tester.tap(find.byKey(const Key('date-clear')));
    await tester.pumpAndSettle();
    expect(find.text('Kein Datum hinterlegt'), findsOneWidget);
    expect(find.text('+7 Tage'), findsOneWidget); // Schnellwahl erscheint wieder
    final row = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
    expect(row.expiresOn, isNull);
  });

  testWidgets('Aufgebraucht/Weggeworfen schliessen den Eintrag und verlassen die Seite', (tester) async {
    final item = await inventoryRepo(db).recordFromScan(productId: product.id, ean: '1', now: DateTime.utc(2026, 9, 27));
    await tester.pumpWidget(app(item));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('START'))).push('/item');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('action-consumed')));
    await tester.pumpAndSettle();
    final row = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
    expect(row.status, 'consumed');
  });

  testWidgets('Geoeffnet-Knopf verschwindet nach dem Oeffnen, Verlauf zeigt beide Bewegungen', (tester) async {
    final item = await inventoryRepo(db).recordFromScan(productId: product.id, ean: '1', now: DateTime.utc(2026, 9, 27));
    await tester.pumpWidget(app(item));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('START'))).push('/item');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('action-open')), findsOneWidget);

    await tester.tap(find.byKey(const Key('action-open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('action-open')), findsNothing);
    expect(find.textContaining('Geöffnet seit'), findsOneWidget);

    await tester.tap(find.byKey(const Key('action-discarded')));
    await tester.pumpAndSettle();
    final row = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
    expect(row.status, 'discarded');
  });
}
