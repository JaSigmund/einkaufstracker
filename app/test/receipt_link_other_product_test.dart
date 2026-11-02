import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/inventory_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Fehlerbericht "Bon Zuordnung" (2026-11-02) mit den echten Namen: "CV Champig. 3.Wahl" hing beim Import an den frischen
/// "Champignons", der Scan der Dose legte "Champinions Dose" an, und die Position liess sich der Dose nicht zuordnen.
void main() {
  late AppDatabase db;
  late String fresh;
  late String can;
  late InventoryRepository repo;

  setUp(() async {
    db = memoryDb();
    fresh = (await productRepo(db).create(name: 'Champignons', baseUnit: 'kg', packSize: 0.5)).id;
    can = (await productRepo(db).create(name: 'Champinions Dose', baseUnit: 'kg', packSize: 0.4)).id;
    repo = InventoryRepository(db, householdId: () async => 'h1', relearnReceiptText: productRepo(db).relearnReceiptText);
    await db.into(db.receipts).insert(Receipt(
          id: 'r1',
          householdId: 'h1',
          purchasedAt: DateTime.utc(2026, 11, 2),
          totalCents: 99,
          status: 'confirmed',
          source: 'pdf_text',
          sumMismatch: false,
          updatedAt: DateTime.utc(2026),
        ));
    await db.into(db.receiptItems).insert(ReceiptItem(
          id: 'ri1',
          householdId: 'h1',
          receiptId: 'r1',
          lineNo: 1,
          kind: 'article',
          rawText: 'IC CV Champig. 3.Wahl',
          productId: fresh,
          quantity: 1,
          quantityUnit: 'piece',
          lineTotalCents: 99,
          unitPriceNormCents: 198,
          needsReview: false,
          excluded: false,
          updatedAt: DateTime.utc(2026),
        ));
  });
  tearDown(() => db.close());

  Future<ReceiptItem> position() => (db.select(db.receiptItems)..where((i) => i.id.equals('ri1'))).getSingle();

  test('die Position eines anderen Produkts ist auswaehlbar, mit dem bisherigen Produkt als Hinweis', () async {
    expect(await repo.candidateReceiptLinksFor(can), isEmpty);
    final others = await repo.otherReceiptLinksFor(can);
    expect(others.map((c) => c.receiptItemId), ['ri1']);
    expect(others.single.productName, 'Champignons');
    expect(await repo.otherReceiptLinksFor(fresh), isEmpty);
  });

  test('Positionen ohne Produkt zaehlen mit, Pfand und bereits zugeordnete nicht', () async {
    await db.into(db.receiptItems).insert(ReceiptItem(
          id: 'ri2',
          householdId: 'h1',
          receiptId: 'r1',
          lineNo: 2,
          kind: 'article',
          rawText: 'Unbekannt',
          quantity: 1,
          quantityUnit: 'piece',
          lineTotalCents: 10,
          needsReview: false,
          excluded: false,
          updatedAt: DateTime.utc(2026),
        ));
    await db.into(db.receiptItems).insert(ReceiptItem(
          id: 'ri3',
          householdId: 'h1',
          receiptId: 'r1',
          lineNo: 3,
          kind: 'deposit',
          rawText: 'Pfand',
          quantity: 1,
          quantityUnit: 'piece',
          lineTotalCents: 25,
          needsReview: false,
          excluded: false,
          updatedAt: DateTime.utc(2026),
        ));
    final item = await repo.recordFromScan(productId: can, ean: '9009865001604', quantity: 0.4, unit: 'kg');
    await repo.setReceiptLink(item.id, 'ri1');

    expect((await repo.otherReceiptLinksFor(can)).map((c) => c.receiptItemId), ['ri2']);
  });

  test('Zuordnen haengt die Position um, rechnet den Grundpreis neu und lernt den Bon-Text um', () async {
    await productRepo(db).findOrCreateForReceiptItem('IC CV Champig. 3.Wahl'); // Alias zeigt noch auf ein anderes Produkt
    final item = await repo.recordFromScan(productId: can, ean: '9009865001604', quantity: 0.4, unit: 'kg');

    await repo.setReceiptLink(item.id, 'ri1');

    final moved = await position();
    expect(moved.productId, can);
    expect(moved.unitPriceNormCents, 248, reason: '0,99 EUR je 0,4 kg');
    final aliases = await (db.select(db.productAliases)..where((a) => a.deletedAt.isNull())).get();
    expect(aliases.map((a) => a.productId), [can]);
    final next = await productRepo(db).findOrCreateForReceiptItem('IC CV Champig. 3.Wahl');
    expect(next.id, can, reason: 'der naechste Bon stimmt gleich');
  });

  test('ein Vorschlag der Position wird aufgenommen, die Ware steht nicht doppelt im Bestand', () async {
    final suggestion = await repo.createSuggestionFromReceipt(productId: fresh, receiptItemId: 'ri1', quantity: 0.5, unit: 'kg', purchasedOn: DateTime.utc(2026, 11, 2));
    final item = await repo.recordFromScan(productId: can, ean: '9009865001604', quantity: 0.4, unit: 'kg');

    await repo.setReceiptLink(item.id, 'ri1');

    final gone = await (db.select(db.inventoryItems)..where((i) => i.id.equals(suggestion.id))).getSingle();
    expect(gone.deletedAt, isNotNull);
    final link = await repo.receiptLinkFor('ri1');
    expect(link?.rawText, 'IC CV Champig. 3.Wahl');
  });

  test('bei gleichem Produkt bleibt alles beim Alten', () async {
    final item = await repo.recordFromScan(productId: fresh, ean: '1', quantity: 0.5, unit: 'kg');

    await repo.setReceiptLink(item.id, 'ri1');

    final same = await position();
    expect(same.productId, fresh);
    expect(same.unitPriceNormCents, 198);
    expect(await db.select(db.productAliases).get(), isEmpty);
  });
}
