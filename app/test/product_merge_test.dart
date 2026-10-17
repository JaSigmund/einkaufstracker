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

  test('gleiche Quelle und Ziel: keine Aenderung', () async {
    final products = productRepo(db);
    final p = await products.create(name: 'Butter');
    await products.mergeInto(p.id, p.id);
    final stillThere = await products.byId(p.id);
    expect(stillThere!.deletedAt, isNull);
  });
}
