import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:einkaufstracker/core/clock.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Testet `ProductRepository.mergeInto` (Doku 07 §4.3): Duplikate zusammenfuehren, ohne die Kaufhistorie
/// zu verlieren.
void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  test('haengt Bons, Inventar, Einkaufsliste und Barcode auf das Zielprodukt um und loescht die Quelle', () async {
    final products = productRepo(db);
    final source = await products.create(name: 'Vollmilch Alt');
    final target = await products.create(name: 'Vollmilch');
    await products.linkBarcode('4001', source.id);

    final inv = inventoryRepo(db);
    await inv.recordFromScan(productId: source.id, ean: '4001');

    final list = shoppingListRepo(db);
    await list.addManual(productId: source.id, quantity: 2);

    await db.into(db.receiptItems).insert(ReceiptItemsCompanion.insert(
          id: 'ri1',
          householdId: 'h1',
          receiptId: 'r1',
          lineNo: 1,
          rawText: 'Vollmilch Alt',
          lineTotalCents: 99,
          productId: Value(source.id),
          updatedAt: appClock.now().toUtc(),
        ));

    await products.mergeInto(source.id, target.id);

    final movedInventory = await (db.select(db.inventoryItems)..where((i) => i.productId.equals(target.id))).get();
    expect(movedInventory, hasLength(1));

    final movedList = await (db.select(db.shoppingListItems)..where((i) => i.productId.equals(target.id))).get();
    expect(movedList, hasLength(1));

    final movedReceipt = await (db.select(db.receiptItems)..where((i) => i.id.equals('ri1'))).getSingle();
    expect(movedReceipt.productId, target.id);

    final barcode = await (db.select(db.productBarcodes)..where((b) => b.ean.equals('4001'))).getSingle();
    expect(barcode.productId, target.id);

    final deletedSource = await products.byId(source.id);
    expect(deletedSource!.deletedAt, isNotNull);
  });

  test('doppelter Alias-Text: statt zwei aktiven Zeilen wird der Alias der Quelle geloescht', () async {
    final products = productRepo(db);
    final source = await products.create(name: 'Bergkaese Alt');
    final target = await products.create(name: 'Bergkaese');
    // Simuliert zwei unabhaengig gelernte Alias-Zeilen mit demselben normalisierten Text (kann durch
    // parallele Geraete/Sync entstehen, auch wenn findOrCreateForReceiptItem das normalerweise verhindert).
    await db.into(db.productAliases).insert(ProductAliasesCompanion.insert(
          id: 'a-source', householdId: 'h1', aliasText: 'bergkaese', productId: source.id, updatedAt: appClock.now().toUtc()),
        );
    await db.into(db.productAliases).insert(ProductAliasesCompanion.insert(
          id: 'a-target', householdId: 'h1', aliasText: 'bergkaese', productId: target.id, updatedAt: appClock.now().toUtc()),
        );

    await products.mergeInto(source.id, target.id);

    // findOrCreateForReceiptItem darf jetzt nicht auf "zwei Zeilen gefunden" abstuerzen
    final resolved = await products.findOrCreateForReceiptItem('Bergkaese');
    expect(resolved.id, target.id);

    final activeAliases = await (db.select(db.productAliases)..where((a) => a.aliasText.equals('bergkaese') & a.deletedAt.isNull())).get();
    expect(activeAliases, hasLength(1));
    expect(activeAliases.single.productId, target.id);
  });

  test('haengt Bewegungen und Mahlzeiten-Zutaten um und stellt sie in die Outbox', () async {
    final products = productRepo(db);
    final source = await products.create(name: 'Vollmilch Alt');
    final target = await products.create(name: 'Vollmilch');
    final now = appClock.now().toUtc();
    await db.into(db.inventoryMovements).insert(InventoryMovementsCompanion.insert(
        id: 'm1', householdId: 'h1', productId: source.id, occurredAt: now, type: 'purchase', quantityDelta: 1, unit: 'piece', updatedAt: now));
    // Auch geloeschte Bewegungen: sonst blieben sie auf dem geloeschten Produkt stehen
    await db.into(db.inventoryMovements).insert(InventoryMovementsCompanion.insert(
        id: 'm2', householdId: 'h1', productId: source.id, occurredAt: now, type: 'consumed', quantityDelta: -1, unit: 'piece', updatedAt: now, deletedAt: Value(now)));
    await db.into(db.mealIngredients).insert(MealIngredientsCompanion.insert(
        id: 'i1', householdId: 'h1', mealId: 'meal1', productId: Value(source.id), quantity: 0.2, unit: 'l', updatedAt: now));
    await db.into(db.mealIngredients).insert(MealIngredientsCompanion.insert(
        id: 'i2', householdId: 'h1', mealId: 'meal1', freeText: const Value('Salz'), quantity: 1, unit: 'piece', updatedAt: now));

    await products.mergeInto(source.id, target.id);

    final movements = await db.select(db.inventoryMovements).get();
    expect(movements.map((m) => m.productId), everyElement(target.id));
    expect(movements.firstWhere((m) => m.id == 'm2').deletedAt, isNotNull);

    final ingredient = await (db.select(db.mealIngredients)..where((i) => i.id.equals('i1'))).getSingle();
    expect(ingredient.productId, target.id);
    final freeText = await (db.select(db.mealIngredients)..where((i) => i.id.equals('i2'))).getSingle();
    expect(freeText.productId, isNull);

    final queued = await db.select(db.outbox).get();
    for (final (table, rowId) in const [('inventory_movements', 'm1'), ('inventory_movements', 'm2'), ('meal_ingredients', 'i1')]) {
      final row = queued.singleWhere((o) => o.remoteTable == table && o.rowId == rowId);
      expect((jsonDecode(row.payload) as Map)['product_id'], target.id);
    }
    expect(queued.where((o) => o.rowId == 'i2'), isEmpty);
  });

  test('Online-Verknuepfungen: umhaengen, doppelte vermeiden, geloeschte nicht wiederbeleben', () async {
    final products = productRepo(db);
    final source = await products.create(name: 'Zwiebeln 3 kg');
    final target = await products.create(name: 'Zwiebeln');
    final now = appClock.now().toUtc();
    Future<void> link(String id, String productId, String store, String externalId, {DateTime? deletedAt}) =>
        db.into(db.productOnlineLinks).insert(ProductOnlineLinksCompanion.insert(
            id: id, householdId: 'h1', productId: productId, store: store, externalId: externalId, linkedName: externalId, updatedAt: now, deletedAt: Value(deletedAt)));
    await link('moved', source.id, 'billa', '00-1');
    await link('sameId-otherStore', source.id, 'spar', '00-2');
    await link('clash-source', source.id, 'billa', '00-2');
    await link('clash-target', target.id, 'billa', '00-2');
    await link('old', source.id, 'billa', '00-3', deletedAt: now);

    await products.mergeInto(source.id, target.id);

    final active = await (db.select(db.productOnlineLinks)..where((l) => l.deletedAt.isNull())).get();
    expect(active.map((l) => l.id), unorderedEquals(['moved', 'sameId-otherStore', 'clash-target']));
    expect(active.map((l) => l.productId), everyElement(target.id));

    final old = await (db.select(db.productOnlineLinks)..where((l) => l.id.equals('old'))).getSingle();
    expect(old.productId, source.id);

    final queued = await (db.select(db.outbox)..where((o) => o.remoteTable.equals('product_online_links'))).get();
    expect(queued.map((o) => o.rowId), unorderedEquals(['moved', 'sameId-otherStore', 'clash-source']));
    final clash = jsonDecode(queued.singleWhere((o) => o.rowId == 'clash-source').payload) as Map;
    expect(clash['deleted_at'], isNotNull);
  });

  test('gleiche Quelle und Ziel: keine Aenderung', () async {
    final products = productRepo(db);
    final p = await products.create(name: 'Butter');
    await products.mergeInto(p.id, p.id);
    final stillThere = await products.byId(p.id);
    expect(stillThere!.deletedAt, isNull);
  });
}
