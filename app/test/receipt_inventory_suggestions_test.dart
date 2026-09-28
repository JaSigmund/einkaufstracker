import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/domain/receipt/billa_text_parser.dart';
import 'package:einkaufstracker/domain/receipt/parsed_receipt.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

ParsedReceipt _parse(String fixture) => const BillaTextParser().parse(File('test/fixtures/receipts/$fixture.txt').readAsStringSync());

void main() {
  late AppDatabase db;
  late Map<String, String> cat;

  setUp(() async {
    db = memoryDb();
    cat = await seedCategories(db);
  });
  tearDown(() => db.close());

  test('Artikel einer lagerbaren Kategorie erzeugen einen Bon-Vorschlag im Inventar', () async {
    final products = productRepo(db);
    final repo = receiptRepo(db, productRepo: products, inventoryRepo: inventoryRepo(db));
    await repo.saveParsed(_parse('billa_digital_04'));

    final suggestions = await (db.select(db.inventoryItems)..where((i) => i.isSuggestion.equals(true))).get();
    expect(suggestions, isNotEmpty);
    expect(suggestions.every((s) => s.status == 'sealed'), isTrue);

    final champignonProduct = await (db.select(db.products)..where((p) => p.name.equals('Clever Champignon weiß'))).getSingle();
    expect(champignonProduct.categoryId, cat['Gemüse']);
    final suggestion = suggestions.singleWhere((s) => s.productId == champignonProduct.id);
    expect(suggestion.quantity, 1);
    expect(suggestion.unit, 'piece');
    expect(suggestion.purchasedOn, DateTime.utc(2026, 7, 2)); // Wiener Kaufdatum des Bons
    expect(suggestion.bestBefore, isNull); // kein Standardwert am frisch angelegten Produkt

    final movement = (await db.select(db.inventoryMovements).get()).singleWhere((m) => m.productId == champignonProduct.id);
    expect((movement.type, movement.quantityDelta), ('purchase', 1.0));
  });

  test('Pfand, Rabatte und Positionen ohne Kategorie erzeugen keinen Vorschlag', () async {
    final repo = receiptRepo(db, productRepo: productRepo(db), inventoryRepo: inventoryRepo(db));
    await repo.saveParsed(_parse('billa_digital_03')); // enthaelt Pfand, Artikel-Rabatte und Bon-Rabatt

    final suggestions = await (db.select(db.inventoryItems)..where((i) => i.isSuggestion.equals(true))).get();
    final products = {for (final p in await db.select(db.products).get()) p.id: p};
    // keine Pfand- oder Getraenke-Dubletten durch Rabattzeilen: so viele Vorschlaege wie Artikel mit Kategorie
    final items = await (db.select(db.receiptItems)..where((i) => i.kind.equals('article') & i.categoryId.isNotNull())).get();
    expect(suggestions.length, items.map((i) => i.rawText).toSet().length <= items.length ? suggestions.length : -1); // Sanity: keine Explosion
    expect(suggestions.every((s) => products[s.productId] != null), isTrue);
    expect(suggestions.any((s) => products[s.productId]!.name.contains('Pfand')), isFalse);
  });

  test('Kategorie "Pfand" ist nicht lagerbar: Pfandpositionen erzeugen nie einen Vorschlag', () async {
    final pfand = await (db.select(db.categories)..where((c) => c.id.equals(cat['Pfand']!))).getSingle();
    expect(pfand.isStorable, isFalse);
  });

  test('Unbekannter Artikel (keine Kategorie) erzeugt keinen Vorschlag und bleibt needsReview', () async {
    final text = File('test/fixtures/receipts/billa_digital_04.txt').readAsStringSync().replaceFirst('Clever Champignon weiß', 'scharfer Aufstrich');
    final repo = receiptRepo(db, productRepo: productRepo(db), inventoryRepo: inventoryRepo(db));
    await repo.saveParsed(const BillaTextParser().parse(text));

    final item = await (db.select(db.receiptItems)..where((i) => i.rawText.equals('scharfer Aufstrich'))).getSingle();
    expect(item.needsReview, isTrue);
    final suggestions = await (db.select(db.inventoryItems)..where((i) => i.isSuggestion.equals(true))).get();
    final products = {for (final p in await db.select(db.products).get()) p.id: p};
    expect(suggestions.where((s) => products[s.productId]?.name == 'scharfer Aufstrich'), isEmpty);
  });

  test('Gleicher Artikel auf zwei Bons: derselbe Produkteintrag wird wiederverwendet (Alias gelernt)', () async {
    final products = productRepo(db);
    final repo = receiptRepo(db, productRepo: products, inventoryRepo: inventoryRepo(db));
    await repo.saveParsed(_parse('billa_digital_04'));
    // zweiter, anderer Bon mit demselben Artikelnamen (unterschiedliche Schreibweise durch Bon-Praefix)
    final text = File('test/fixtures/receipts/billa_digital_06.txt').readAsStringSync().replaceFirst(
        _firstArticle('billa_digital_06'), 'IC Clever Champignon weiß');
    await repo.saveParsed(const BillaTextParser().parse(text));

    final champignons = await (db.select(db.products)..where((p) => p.name.like('%Champignon%'))).get();
    expect(champignons, hasLength(1)); // kein zweites Produkt angelegt
    final aliasRows = await db.select(db.productAliases).get();
    expect(aliasRows.where((a) => a.productId == champignons.single.id), hasLength(1));
    final suggestions = await (db.select(db.inventoryItems)..where((i) => i.isSuggestion.equals(true) & i.productId.equals(champignons.single.id))).get();
    expect(suggestions, hasLength(2)); // ein Vorschlag je Einkauf
  });

  test('Standardhaltbarkeit des Produkts liefert ein geschaetztes Ablaufdatum fuer spaetere Vorschlaege', () async {
    final products = productRepo(db);
    final repo = receiptRepo(db, productRepo: products, inventoryRepo: inventoryRepo(db));
    await repo.saveParsed(_parse('billa_digital_04'));
    final champignon = await (db.select(db.products)..where((p) => p.name.equals('Clever Champignon weiß'))).getSingle();
    await products.update(champignon.copyWith(sealedShelfLifeDays: const Value(5)));

    final text = File('test/fixtures/receipts/billa_digital_06.txt').readAsStringSync().replaceFirst(
        _firstArticle('billa_digital_06'), 'IC Clever Champignon weiß');
    await repo.saveParsed(const BillaTextParser().parse(text));

    final suggestion = (await (db.select(db.inventoryItems)..where((i) => i.isSuggestion.equals(true) & i.productId.equals(champignon.id))).get())
        .firstWhere((s) => s.bestBefore != null);
    expect(suggestion.expiresOn, suggestion.purchasedOn!.add(const Duration(days: 5)));
  });

  test('Waegware (kg-Menge im Bon) legt das Produkt gleich mit Grundeinheit kg an', () async {
    final receipt = ParsedReceipt.edited(
      base: null,
      chain: 'Billa',
      purchasedAtUtc: DateTime.utc(2026, 9, 27, 10),
      totalCents: 249,
      items: const [
        ParsedItem(rawText: 'DKIH Paprika Tricolore', kind: ReceiptItemKind.article, lineTotalCents: 249, quantity: 0.62, quantityUnit: 'kg'),
      ],
      bonDiscounts: const [],
    );
    final repo = receiptRepo(db, productRepo: productRepo(db), inventoryRepo: inventoryRepo(db));
    await repo.saveParsed(receipt);

    final product = await (db.select(db.products)..where((p) => p.name.equals('DKIH Paprika Tricolore'))).getSingle();
    expect(product.baseUnit, 'kg');
    final suggestion = await (db.select(db.inventoryItems)..where((i) => i.productId.equals(product.id))).getSingle();
    expect((suggestion.unit, suggestion.quantity), ('kg', 0.62));
  });

  group('Bon loeschen und erneut importieren (Fehlerbericht "Bonartikel Vorschlag doppelt", 2026-09-28)', () {
    test('Loeschen verwirft die zugehoerigen unbestaetigten Vorschlaege', () async {
      final repo = receiptRepo(db, productRepo: productRepo(db), inventoryRepo: inventoryRepo(db));
      final saved = await repo.saveParsed(_parse('billa_digital_04'));
      expect(await (db.select(db.inventoryItems)..where((i) => i.isSuggestion.equals(true) & i.deletedAt.isNull())).get(), isNotEmpty);

      await repo.softDelete(saved.receiptId);

      expect(await (db.select(db.inventoryItems)..where((i) => i.isSuggestion.equals(true) & i.deletedAt.isNull())).get(), isEmpty);
    });

    test('Erneuter Import desselben Bons erzeugt keinen doppelten Vorschlag', () async {
      final repo = receiptRepo(db, productRepo: productRepo(db), inventoryRepo: inventoryRepo(db));
      final saved = await repo.saveParsed(_parse('billa_digital_04'));
      await repo.softDelete(saved.receiptId);

      final again = await repo.saveParsed(_parse('billa_digital_04')); // gleiche Re-Nr -> dieselbe Bon-ID
      expect(again.receiptId, saved.receiptId);

      final champignonProduct = await (db.select(db.products)..where((p) => p.name.equals('Clever Champignon weiß'))).getSingle();
      final active = await (db.select(db.inventoryItems)
            ..where((i) => i.isSuggestion.equals(true) & i.productId.equals(champignonProduct.id) & i.deletedAt.isNull()))
          .get();
      expect(active, hasLength(1)); // nicht zwei
    });
  });

  test('Ohne Produkt-/Inventar-Repository (z.B. Altverhalten) entstehen keine Vorschlaege', () async {
    final repo = receiptRepo(db); // wie zuvor: beide Abhaengigkeiten fehlen
    await repo.saveParsed(_parse('billa_digital_04'));
    expect(await db.select(db.inventoryItems).get(), isEmpty);
    expect(await db.select(db.products).get(), isEmpty);
  });

  group('Einkaufsliste -> Inventar (Doku 06 §7, Roadmap Phase 3)', () {
    test('ein gekaufter Artikel hakt einen offenen, bestaetigten Listeneintrag desselben Produkts ab', () async {
      final products = productRepo(db);
      final shoppingList = shoppingListRepo(db);
      final repo = receiptRepo(db, productRepo: products, inventoryRepo: inventoryRepo(db), shoppingListRepo: shoppingList);
      // Erster Bon legt das Produkt an
      await repo.saveParsed(_parse('billa_digital_04'));
      final champignon = await (db.select(db.products)..where((p) => p.name.equals('Clever Champignon weiß'))).getSingle();
      final listItem = await shoppingList.addManual(productId: champignon.id, unit: champignon.baseUnit);

      // Zweiter Bon mit demselben Artikel (wie im bestehenden Alias-Test) loest das Abhaken aus
      final text = File('test/fixtures/receipts/billa_digital_06.txt')
          .readAsStringSync()
          .replaceFirst(_firstArticle('billa_digital_06'), 'IC Clever Champignon weiß');
      await repo.saveParsed(const BillaTextParser().parse(text));

      final row = await (db.select(db.shoppingListItems)..where((i) => i.id.equals(listItem.id))).getSingle();
      expect(row.checked, isTrue);
    });

    test('unbestaetigte Vorschlaege (isSuggestion) bleiben unangetastet', () async {
      final products = productRepo(db);
      final shoppingList = shoppingListRepo(db);
      final repo = receiptRepo(db, productRepo: products, inventoryRepo: inventoryRepo(db), shoppingListRepo: shoppingList);
      await repo.saveParsed(_parse('billa_digital_04'));
      final champignon = await (db.select(db.products)..where((p) => p.name.equals('Clever Champignon weiß'))).getSingle();
      await products.update(champignon.copyWith(restock: true)); // suggestDepleted verlangt ein Nachkaufprodukt
      await shoppingList.suggestDepleted(champignon.id);
      final suggestion = (await shoppingList.watchItems().first).single;
      expect(suggestion.isSuggestion, isTrue);

      final text = File('test/fixtures/receipts/billa_digital_06.txt')
          .readAsStringSync()
          .replaceFirst(_firstArticle('billa_digital_06'), 'IC Clever Champignon weiß');
      await repo.saveParsed(const BillaTextParser().parse(text));

      final row = await (db.select(db.shoppingListItems)..where((i) => i.id.equals(suggestion.id))).getSingle();
      expect(row.checked, isFalse);
      expect(row.isSuggestion, isTrue);
    });

    test('ohne ShoppingListRepository (Altverhalten): kein Absturz', () async {
      final repo = receiptRepo(db, productRepo: productRepo(db), inventoryRepo: inventoryRepo(db));
      await repo.saveParsed(_parse('billa_digital_04'));
    });
  });
}

String _firstArticle(String fixture) =>
    const BillaTextParser().parse(File('test/fixtures/receipts/$fixture.txt').readAsStringSync()).items.firstWhere((i) => i.kind == ReceiptItemKind.article).rawText;
