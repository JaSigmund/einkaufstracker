import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:einkaufstracker/core/clock.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/domain/receipt/parsed_receipt.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

ParsedReceipt _receipt(List<ParsedItem> items, {DateTime? purchasedAtUtc}) => ParsedReceipt.edited(
      base: null,
      chain: 'Billa',
      purchasedAtUtc: purchasedAtUtc ?? DateTime.utc(2026, 9, 28, 10),
      totalCents: items.fold(0, (s, i) => s + i.lineTotalCents),
      items: items,
      bonDiscounts: const [],
    );

void main() {
  late AppDatabase db;

  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  group('Produkt-Zuordnung und Grundpreis fuer JEDEN Artikel (Doku 07 §3.1, Phase 4)', () {
    test('Wiegeware: Grundpreis direkt aus der Bon-Menge in der Basiseinheit', () async {
      final repo = receiptRepo(db, productRepo: productRepo(db), inventoryRepo: inventoryRepo(db));
      await repo.saveParsed(_receipt([
        const ParsedItem(rawText: 'DKIH Paprika Tricolore', kind: ReceiptItemKind.article, lineTotalCents: 249, quantity: 0.62, quantityUnit: 'kg'),
      ]));

      final item = await (db.select(db.receiptItems)..where((i) => i.kind.equals('article'))).getSingle();
      expect(item.productId, isNotNull);
      expect(item.unitPriceNormCents, 402); // 249 / 0,62
    });

    test('nicht lagerbare Kategorie (z.B. Brot) bekommt trotzdem eine Produkt-Zuordnung', () async {
      final repo = receiptRepo(db, productRepo: productRepo(db), inventoryRepo: inventoryRepo(db));
      await repo.saveParsed(_receipt([
        const ParsedItem(rawText: 'Bauernbrot', kind: ReceiptItemKind.article, lineTotalCents: 289, quantity: 1, quantityUnit: 'piece'),
      ]));

      final item = await (db.select(db.receiptItems)..where((i) => i.kind.equals('article'))).getSingle();
      expect(item.productId, isNotNull);
      // Kein Inventar-Vorschlag, weil "Brot & Backwaren" nicht lagerbar ist (Doku 07 §1)
      expect(await db.select(db.inventoryItems).get(), isEmpty);
    });

    test('unbekannter Artikel ohne Kategorie bekommt trotzdem eine Produkt-Zuordnung', () async {
      final repo = receiptRepo(db, productRepo: productRepo(db), inventoryRepo: inventoryRepo(db));
      await repo.saveParsed(_receipt([
        const ParsedItem(rawText: 'ganz unbekannter artikel xyz', kind: ReceiptItemKind.article, lineTotalCents: 199, quantity: 1, quantityUnit: 'piece'),
      ]));

      final item = await (db.select(db.receiptItems)..where((i) => i.kind.equals('article'))).getSingle();
      expect(item.needsReview, isTrue);
      expect(item.productId, isNotNull);
    });

    test('Stueckware direkt beim ersten Kauf: Grundpreis ist der Stueckpreis (neues Produkt hat baseUnit piece)', () async {
      final repo = receiptRepo(db, productRepo: productRepo(db), inventoryRepo: inventoryRepo(db));
      await repo.saveParsed(_receipt([
        const ParsedItem(rawText: 'Ja! Natuerlich Champignons', kind: ReceiptItemKind.article, lineTotalCents: 199, quantity: 1, quantityUnit: 'piece'),
      ]));

      final item = await (db.select(db.receiptItems)..where((i) => i.kind.equals('article'))).getSingle();
      final product = await (db.select(db.products)..where((p) => p.id.equals(item.productId!))).getSingle();
      expect(product.baseUnit, 'piece'); // neu angelegt: uebernimmt die Bon-Einheit
      expect(item.unitPriceNormCents, 199); // Preis je Stueck, kein Packungsinhalt noetig
    });

    test('Produkt ist Gewicht/Volumen-basiert, aber ohne bekannten Packungsinhalt gekauft: kein Grundpreis', () async {
      final products = productRepo(db);
      final repo = receiptRepo(db, productRepo: products, inventoryRepo: inventoryRepo(db));
      await repo.saveParsed(_receipt([
        const ParsedItem(rawText: 'Champignons', kind: ReceiptItemKind.article, lineTotalCents: 199, quantity: 1, quantityUnit: 'piece'),
      ]));
      final first = await (db.select(db.receiptItems)..where((i) => i.kind.equals('article'))).getSingle();
      final product = await (db.select(db.products)..where((p) => p.id.equals(first.productId!))).getSingle();
      // Nutzer korrigiert nachtraeglich: eigentlich eine kg-Ware, Packungsinhalt aber noch unbekannt
      await products.update(product.copyWith(baseUnit: 'kg'));

      await repo.saveParsed(_receipt(
        [const ParsedItem(rawText: 'Champignons', kind: ReceiptItemKind.article, lineTotalCents: 199, quantity: 1, quantityUnit: 'piece')],
        purchasedAtUtc: DateTime.utc(2026, 9, 29, 10),
      ));
      final second = (await (db.select(db.receiptItems)..where((i) => i.kind.equals('article'))).get()).firstWhere((i) => i.id != first.id);
      expect(second.productId, first.productId); // dasselbe Produkt (Alias gelernt)
      expect(second.unitPriceNormCents, isNull); // kg-Ware als Stueck gekauft, Packungsinhalt unbekannt
    });

    test('Packware mit bekanntem Inhalt: Grundpreis wird berechnet', () async {
      final products = productRepo(db);
      final repo = receiptRepo(db, productRepo: products, inventoryRepo: inventoryRepo(db));
      await repo.saveParsed(_receipt([
        const ParsedItem(rawText: 'Champignons', kind: ReceiptItemKind.article, lineTotalCents: 199, quantity: 1, quantityUnit: 'piece'),
      ]));
      final first = await (db.select(db.receiptItems)..where((i) => i.kind.equals('article'))).getSingle();
      final product = await (db.select(db.products)..where((p) => p.id.equals(first.productId!))).getSingle();
      await products.update(product.copyWith(baseUnit: 'kg', packSize: const Value(0.15)));

      await repo.saveParsed(_receipt(
        [const ParsedItem(rawText: 'Champignons', kind: ReceiptItemKind.article, lineTotalCents: 199, quantity: 1, quantityUnit: 'piece')],
        purchasedAtUtc: DateTime.utc(2026, 9, 29, 10),
      ));
      final second = (await (db.select(db.receiptItems)..where((i) => i.kind.equals('article'))).get()).firstWhere((i) => i.id != first.id);
      expect(second.unitPriceNormCents, 1327); // 199 / 0,15
    });

    test('Packungsgroesse aus dem Bon-Text: zwei Groessen desselben Produkts ergeben je den richtigen Grundpreis', () async {
      final products = productRepo(db);
      final repo = receiptRepo(db, productRepo: products, inventoryRepo: inventoryRepo(db));
      final zwiebeln = await products.create(name: 'Zwiebeln gelb', baseUnit: 'kg', packSize: 1);
      // Der Alias-Schluessel enthaelt keine Gewichtsangabe: beide Bon-Texte landen beim selben Produkt
      await db.into(db.productAliases).insert(ProductAliasesCompanion.insert(
          id: 'a1', householdId: 'h1', aliasText: 'zwiebeln gelb', productId: zwiebeln.id, updatedAt: appClock.now().toUtc()));

      await repo.saveParsed(_receipt([
        const ParsedItem(rawText: 'Zwiebeln gelb 1kg', kind: ReceiptItemKind.article, lineTotalCents: 123, quantity: 1, quantityUnit: 'piece'),
        const ParsedItem(rawText: 'Zwiebeln gelb 3kg', kind: ReceiptItemKind.article, lineTotalCents: 199, quantity: 1, quantityUnit: 'piece'),
      ]));

      final items = await (db.select(db.receiptItems)..where((i) => i.kind.equals('article'))..orderBy([(i) => OrderingTerm.asc(i.lineNo)])).get();
      expect(items.map((i) => i.productId), everyElement(zwiebeln.id));
      expect(items.map((i) => i.unitPriceNormCents), [123, 66]);
    });

    test('Marke wird vom Produkt uebernommen', () async {
      final products = productRepo(db);
      final repo = receiptRepo(db, productRepo: products, inventoryRepo: inventoryRepo(db));
      await repo.saveParsed(_receipt([
        const ParsedItem(rawText: 'Vollmilch', kind: ReceiptItemKind.article, lineTotalCents: 99, quantity: 1, quantityUnit: 'piece'),
      ]));
      final first = await (db.select(db.receiptItems)..where((i) => i.kind.equals('article'))).getSingle();
      final product = await (db.select(db.products)..where((p) => p.id.equals(first.productId!))).getSingle();
      await products.update(product.copyWith(brand: const Value('Clever')));

      await repo.saveParsed(_receipt(
        [const ParsedItem(rawText: 'Vollmilch', kind: ReceiptItemKind.article, lineTotalCents: 99, quantity: 1, quantityUnit: 'piece')],
        purchasedAtUtc: DateTime.utc(2026, 9, 29, 10),
      ));
      final second = (await (db.select(db.receiptItems)..where((i) => i.kind.equals('article'))).get()).firstWhere((i) => i.id != first.id);
      expect(second.brand, 'Clever');
    });

    test('Pfand und Rabatte bekommen nie eine Produkt-Zuordnung oder einen Grundpreis', () async {
      final repo = receiptRepo(db, productRepo: productRepo(db), inventoryRepo: inventoryRepo(db));
      await repo.saveParsed(_receipt([
        const ParsedItem(rawText: 'Vollmilch', kind: ReceiptItemKind.article, lineTotalCents: 99, quantity: 1, quantityUnit: 'piece'),
        const ParsedItem(rawText: 'Pfand 0,25', kind: ReceiptItemKind.deposit, lineTotalCents: 25, quantity: 1, quantityUnit: 'piece'),
        const ParsedItem(rawText: 'Rabatt', kind: ReceiptItemKind.discount, lineTotalCents: -10, quantity: 1, quantityUnit: 'piece'),
      ]));

      final nonArticles = await (db.select(db.receiptItems)..where((i) => i.kind.equals('deposit') | i.kind.equals('discount'))).get();
      expect(nonArticles.every((i) => i.productId == null && i.unitPriceNormCents == null), isTrue);
    });

    test('ohne ProductRepository (Altverhalten): keine Zuordnung, kein Grundpreis, kein Absturz', () async {
      final repo = receiptRepo(db);
      await repo.saveParsed(_receipt([
        const ParsedItem(rawText: 'Vollmilch', kind: ReceiptItemKind.article, lineTotalCents: 99, quantity: 1, quantityUnit: 'piece'),
      ]));
      final item = await (db.select(db.receiptItems)..where((i) => i.kind.equals('article'))).getSingle();
      expect(item.productId, isNull);
      expect(item.unitPriceNormCents, isNull);
    });
  });
}
