import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/features/inventory/inventory_item_detail_page.dart';
import 'package:einkaufstracker/features/products/product_form_page.dart';
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
    product = await productRepo(db).create(name: 'Vollmilch');
  });
  tearDown(() => db.close());

  Widget app(InventoryItem item, {Product? p}) => ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          inventoryRepositoryProvider.overrideWithValue(inventoryRepo(db)),
          inventoryMovementsStreamProvider.overrideWith((ref, _) => Stream.value(const <InventoryMovement>[])),
          productRepositoryProvider.overrideWithValue(productRepo(db)),
          categoriesStreamProvider.overrideWith((ref) => Stream.value(const <Category>[])),
          productAliasesStreamProvider.overrideWith((ref, _) => Stream.value(const <ProductAlias>[])),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(initialLocation: '/', routes: [
            GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('START'))),
            GoRoute(path: '/item', builder: (_, _) => InventoryItemDetailPage(item: item, product: p ?? product)),
            GoRoute(path: '/product/:id', builder: (_, s) => Scaffold(body: Text('PRODUKTSEITE ${s.pathParameters['id']}'))),
            GoRoute(
              path: '/product-form',
              builder: (_, s) {
                final a = s.extra as ProductFormArgs?;
                return ProductFormPage(ean: a?.ean, suggestion: a?.suggestion, existing: a?.existing);
              },
            ),
          ]),
        ),
      );

  testWidgets('Menge per +/- und per Eingabe aendern, mit Ledger-Bewegung', (tester) async {
    final item = await inventoryRepo(db).recordFromScan(productId: product.id, ean: '1', quantity: 2, now: DateTime.utc(2026, 9, 27));
    await tester.pumpWidget(app(item));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('START'))).push('/item');
    await tester.pumpAndSettle();
    expect(find.text('2 Stk'), findsOneWidget);

    await tester.tap(find.byKey(const Key('quantity-plus')));
    await tester.pumpAndSettle();
    expect(find.text('3 Stk'), findsOneWidget);
    expect((await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle()).quantity, 3);

    await tester.tap(find.byKey(const Key('quantity-tap')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('quantity-input')), '5');
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(find.text('5 Stk'), findsOneWidget);

    final movements = await db.select(db.inventoryMovements).get();
    expect(movements.where((m) => m.type == 'adjustment'), hasLength(2));
  });

  testWidgets('zeigt den zugeordneten Bon an (Fehlerbericht "Bonzuordnung anzeigen")', (tester) async {
    await db.into(db.stores).insert(Store(id: 'store1', householdId: 'h1', chain: 'Billa', updatedAt: DateTime.utc(2026)));
    await db.into(db.receipts).insert(Receipt(
          id: 'r1',
          householdId: 'h1',
          storeId: 'store1',
          purchasedAt: _d(2026, 9, 20),
          totalCents: 500,
          status: 'confirmed',
          source: 'manual',
          sumMismatch: false,
          updatedAt: DateTime.utc(2026),
        ));
    await db.into(db.receiptItems).insert(ReceiptItem(
          excluded: false,
          id: 'ri1',
          householdId: 'h1',
          receiptId: 'r1',
          lineNo: 1,
          kind: 'article',
          rawText: 'H-VOLLMILCH 1L',
          quantity: 1,
          quantityUnit: 'piece',
          lineTotalCents: 129,
          needsReview: false,
          updatedAt: DateTime.utc(2026),
        ));
    final repo = inventoryRepo(db);
    final suggestion = await repo.createSuggestionFromReceipt(
      productId: product.id, receiptItemId: 'ri1', quantity: 1, unit: 'l', purchasedOn: _d(2026, 9, 20),
    );
    final item = await repo.recordFromScan(productId: product.id, ean: '1', now: DateTime.utc(2026, 9, 21));
    expect(item.id, suggestion.id);

    await tester.pumpWidget(app(item));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('START'))).push('/item');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('receipt-link')), findsOneWidget);
    expect(find.text('Billa'), findsOneWidget);
    expect(find.textContaining('H-VOLLMILCH 1L'), findsOneWidget);
    expect(find.text('1,29 €'), findsOneWidget);
  });

  testWidgets('ohne Bon-Zuordnung: kein Hinweis auf einen Bon', (tester) async {
    final item = await inventoryRepo(db).recordFromScan(productId: product.id, ean: '1', now: DateTime.utc(2026, 9, 27));
    await tester.pumpWidget(app(item));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('START'))).push('/item');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('receipt-link')), findsNothing);
  });

  testWidgets('Produktname direkt umbenennen (Wunsch "intuitiver", 2026-09-28)', (tester) async {
    final item = await inventoryRepo(db).recordFromScan(productId: product.id, ean: '1', now: DateTime.utc(2026, 9, 27));
    await tester.pumpWidget(app(item));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('START'))).push('/item');
    await tester.pumpAndSettle();
    expect(find.text('Vollmilch'), findsOneWidget);

    await tester.tap(find.byKey(const Key('product-name-tap')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('product-name-input')), 'Vollmilch 3,5%');
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();

    expect(find.text('Vollmilch 3,5%'), findsOneWidget);
    final row = await (db.select(db.products)..where((p) => p.id.equals(product.id))).getSingle();
    expect(row.name, 'Vollmilch 3,5%');
  });

  testWidgets('weitere Produktdetails: oeffnet das volle Formular, Aenderung kommt zurueck', (tester) async {
    tester.view.physicalSize = const Size(1080, 3400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final item = await inventoryRepo(db).recordFromScan(productId: product.id, ean: '1', now: DateTime.utc(2026, 9, 27));
    await tester.pumpWidget(app(item));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('START'))).push('/item');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('action-edit-product')));
    await tester.pumpAndSettle();
    expect(find.text('PRODUKTSEITE ${product.id}'), findsOneWidget);

    // Auf der Produktseite kann sich alles aendern, der Eintrag zeigt danach den neuen Stand
    await productRepo(db).update(product.copyWith(name: 'Bio-Vollmilch'));
    GoRouter.of(tester.element(find.text('PRODUKTSEITE ${product.id}'))).pop();
    await tester.pumpAndSettle();

    expect(find.text('Bio-Vollmilch'), findsOneWidget);
  });

  group('Bonzuordnung aendern (2026-09-28)', () {
    Future<void> makeReceiptItem(String id, String rawText) async {
      await db.into(db.receipts).insertOnConflictUpdate(Receipt(
            id: 'r-$id',
            householdId: 'h1',
            purchasedAt: _d(2026, 9, 20),
            totalCents: 500,
            status: 'confirmed',
            source: 'manual',
            sumMismatch: false,
            updatedAt: DateTime.utc(2026),
          ));
      await db.into(db.receiptItems).insert(ReceiptItem(
            excluded: false,
            id: id,
            householdId: 'h1',
            receiptId: 'r-$id',
            lineNo: 1,
            kind: 'article',
            rawText: rawText,
            productId: product.id,
            quantity: 1,
            quantityUnit: 'piece',
            lineTotalCents: 129,
            needsReview: false,
            updatedAt: DateTime.utc(2026),
          ));
    }

    testWidgets('reiner Scan: Bon nachtraeglich zuordnen', (tester) async {
      await makeReceiptItem('ri1', 'H-VOLLMILCH 1L');
      final item = await inventoryRepo(db).recordFromScan(productId: product.id, ean: '1', now: DateTime.utc(2026, 9, 27));
      await tester.pumpWidget(app(item));
      await tester.pumpAndSettle();
      GoRouter.of(tester.element(find.text('START'))).push('/item');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('receipt-link-add')), findsOneWidget);
      await tester.tap(find.byKey(const Key('receipt-link-add')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('receipt-link-candidate-ri1')), findsOneWidget);
      await tester.tap(find.byKey(const Key('receipt-link-candidate-ri1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('receipt-link')), findsOneWidget);
      final row = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
      expect(row.receiptItemId, 'ri1');
    });

    // Fehlerbericht "Bon Zuordnung" (2026-11-02): die Position haengt beim Import an einem anderen Produkt.
    testWidgets('Position eines anderen Produkts: per Suche findbar, Zuordnen haengt sie um', (tester) async {
      await makeReceiptItem('ri1', 'CV Champig. 3.Wahl');
      final can = await productRepo(db).create(name: 'Champinions Dose');
      final item = await inventoryRepo(db).recordFromScan(productId: can.id, ean: '1', now: DateTime.utc(2026, 9, 27));
      await tester.pumpWidget(app(item, p: can));
      await tester.pumpAndSettle();
      GoRouter.of(tester.element(find.text('START'))).push('/item');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('receipt-link-add')));
      await tester.pumpAndSettle();
      expect(find.textContaining('bisher bei Vollmilch'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('receipt-link-search')), 'tomaten');
      await tester.pump();
      expect(find.byKey(const Key('receipt-link-candidate-ri1')), findsNothing);
      expect(find.text('Nichts gefunden.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('receipt-link-search')), 'champig');
      await tester.pump();
      await tester.tap(find.byKey(const Key('receipt-link-candidate-ri1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('receipt-link')), findsOneWidget);
      final position = await (db.select(db.receiptItems)..where((i) => i.id.equals('ri1'))).getSingle();
      expect(position.productId, can.id);
    });

    // Fehlerbericht "kein passender Bon bei Inventarartikel gefunden" (2026-10-01): "Bergbauern Milch" war
    // schon gescannt, der Bon kam danach als Vorschlag dazu -- die Liste zeigte trotzdem "keine passende
    // Bon-Position", weil der Vorschlag die Position fuer "schon zugeordnet" hielt.
    testWidgets('Bon liegt bereits als Vorschlag vor: er ist waehlbar und wird beim Zuordnen aufgenommen', (tester) async {
      await makeReceiptItem('ri1', 'BERGBAUERN MILCH');
      final repo = inventoryRepo(db);
      final scanned = await repo.recordFromScan(productId: product.id, ean: '1', now: DateTime.utc(2026, 9, 10));
      final suggestion = await repo.createSuggestionFromReceipt(
        productId: product.id, receiptItemId: 'ri1', quantity: 1, unit: 'piece', purchasedOn: _d(2026, 9, 20),
      );

      await tester.pumpWidget(app(scanned));
      await tester.pumpAndSettle();
      GoRouter.of(tester.element(find.text('START'))).push('/item');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('receipt-link-add')));
      await tester.pumpAndSettle();
      expect(find.text('Keine passenden Bon-Positionen gefunden.'), findsNothing);
      expect(find.byKey(const Key('receipt-link-candidate-ri1')), findsOneWidget);
      await tester.tap(find.byKey(const Key('receipt-link-candidate-ri1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('receipt-link')), findsOneWidget);
      final row = await (db.select(db.inventoryItems)..where((i) => i.id.equals(scanned.id))).getSingle();
      expect(row.receiptItemId, 'ri1');
      final absorbed = await (db.select(db.inventoryItems)..where((i) => i.id.equals(suggestion.id))).getSingle();
      expect(absorbed.deletedAt, isNotNull);
    });

    testWidgets('bereits zugeordnet: loesen macht den Eintrag zum reinen Scan', (tester) async {
      await makeReceiptItem('ri1', 'H-VOLLMILCH 1L');
      final repo = inventoryRepo(db);
      final created = await repo.recordFromScan(productId: product.id, ean: '1', now: DateTime.utc(2026, 9, 27));
      await repo.setReceiptLink(created.id, 'ri1');
      final item = await (db.select(db.inventoryItems)..where((i) => i.id.equals(created.id))).getSingle();

      await tester.pumpWidget(app(item));
      await tester.pumpAndSettle();
      GoRouter.of(tester.element(find.text('START'))).push('/item');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('receipt-link')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('receipt-link-remove')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('receipt-link-add')), findsOneWidget);
      final row = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
      expect(row.receiptItemId, isNull);
    });
  });

  testWidgets('Der letzte Rest macht den Eintrag zu "Aufgebraucht" statt zu einem aktiven Eintrag mit Menge 0', (tester) async {
    final item = await inventoryRepo(db).recordFromScan(productId: product.id, ean: '1', quantity: 1, now: DateTime.utc(2026, 9, 27));
    await tester.pumpWidget(app(item));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('START'))).push('/item');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quantity-minus')));
    await tester.pumpAndSettle();
    expect(find.text('START'), findsOneWidget);
    expect(find.text('Als aufgebraucht markiert'), findsOneWidget);
    final row = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
    expect(row.status, 'consumed');
    expect(row.quantity, 1, reason: 'Stand fuer Rueckgaengig');
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
    tester.view.physicalSize = const Size(1080, 3400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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

  testWidgets('Loeschen (falsch erfasst): Rueckfrage, dann sind Eintrag und Kaufbewegung weg', (tester) async {
    final item = await inventoryRepo(db).recordFromScan(productId: product.id, ean: '1', now: DateTime.utc(2026, 9, 27));
    await tester.pumpWidget(app(item));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('START'))).push('/item');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('action-delete')));
    await tester.pumpAndSettle();
    expect(find.text('Eintrag löschen?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect((await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle()).deletedAt, isNull);

    await tester.tap(find.byKey(const Key('action-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Löschen'));
    await tester.pumpAndSettle();

    expect((await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle()).deletedAt, isNotNull);
    expect(await (db.select(db.inventoryMovements)..where((m) => m.deletedAt.isNull())).get(), isEmpty);
  });
}
