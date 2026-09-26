import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/sync/sync_engine.dart';
import 'package:einkaufstracker/domain/receipt/billa_text_parser.dart';
import 'package:einkaufstracker/domain/receipt/parsed_receipt.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

String _fixtureText(String name) => File('test/fixtures/receipts/$name.txt').readAsStringSync();

/// Bon aus einer Fixture, in der Artikelnamen ersetzt wurden (bei gleichem Preis, Summe bleibt richtig).
ParsedReceipt _parse(String fixture, {Map<String, String> rename = const {}}) {
  var t = _fixtureText(fixture);
  rename.forEach((from, to) => t = t.replaceFirst(from, to));
  return const BillaTextParser().parse(t);
}

void main() {
  late AppDatabase db;
  late Map<String, String> cat; // Name -> ID

  setUp(() async {
    db = memoryDb();
    cat = await seedCategories(db);
  });
  tearDown(() => db.close());

  Future<Map<String, ReceiptItem>> itemsByName() async =>
      {for (final i in await db.select(db.receiptItems).get()) i.rawText: i};

  group('Automatische Zuordnung beim Import', () {
    test('Artikel eines echten Bons landen in den richtigen Kategorien', () async {
      await receiptRepo(db).saveParsed(_parse('billa_digital_04'));
      final items = await itemsByName();
      expect(items['Clever Champignon weiß']!.categoryId, cat['Gemüse']);
      expect(items['DKIH Cherrytomaten Sophie']!.categoryId, cat['Gemüse']);
      expect(items['SG RUCOLA SALAT 125G']!.categoryId, cat['Gemüse']);
      expect(items['Farmer Soft Sandwich']!.categoryId, cat['Brot & Backwaren']);
      expect(items['Clever Hirtenkäse']!.categoryId, cat['Käse']);
      expect(items['Clever Ung. Salami']!.categoryId, cat['Fleisch & Wurst']);
      expect(items['Nestlé Pirulo Kaktus Box']!.categoryId, cat['Süßes & Snacks']);
      expect(items['Clever Blütenhonig']!.categoryId, cat['Süßes & Snacks']);
      expect(items['Billa Spaghetti Bronze']!.categoryId, cat['Konserven & Trockenware']);
      expect(items['BARILLA PESTO RUSTICO BAS']!.categoryId, cat['Öle, Gewürze & Saucen']);
      expect(items.values.any((i) => i.needsReview), isFalse);
    });

    test('Rabatt uebernimmt die Kategorie des Artikels darueber, Pfand bekommt "Pfand", Bon-Rabatt keine', () async {
      await receiptRepo(db).saveParsed(_parse('billa_digital_03'));
      final all = await (db.select(db.receiptItems)..orderBy([(i) => OrderingTerm.asc(i.lineNo)])).get();

      // "DKIH Paprika Tricolore" (Gemuese) gefolgt von "EXTREM AKTION" (Rabatt)
      final paprikaIdx = all.indexWhere((i) => i.rawText == 'DKIH Paprika Tricolore');
      expect(all[paprikaIdx].categoryId, cat['Gemüse']);
      expect(all[paprikaIdx + 1].kind, 'discount');
      expect(all[paprikaIdx + 1].categoryId, cat['Gemüse']);

      // "NIMM MEHR" nach jedem "CV FASCHIERTES GEM.500G"
      final nimm = all.where((i) => i.rawText == 'NIMM MEHR').toList();
      expect(nimm, hasLength(3));
      expect(nimm.every((i) => i.categoryId == cat['Fleisch & Wurst']), isTrue);

      final deposits = all.where((i) => i.kind == 'deposit').toList();
      expect(deposits, isNotEmpty);
      expect(deposits.every((i) => i.categoryId == cat['Pfand']), isTrue);

      final bon = all.singleWhere((i) => i.rawText.contains('Rabattsammler'));
      expect(bon.categoryId, isNull);
      expect(bon.needsReview, isFalse); // Bon-Rabatt braucht keine Zuordnung
    });

    test('Unbekannter Artikel bleibt ohne Kategorie und wird zur Pruefung markiert', () async {
      await receiptRepo(db).saveParsed(_parse('billa_digital_04', rename: {'Clever Hirtenkäse': 'scharfer Aufstrich'}));
      final item = (await itemsByName())['scharfer Aufstrich']!;
      expect(item.categoryId, isNull);
      expect(item.needsReview, isTrue);
    });

    test('Ohne vorhandene Kategorien bleibt alles unzugeordnet, ohne Absturz', () async {
      final empty = memoryDb();
      addTearDown(empty.close);
      await receiptRepo(empty).saveParsed(_parse('billa_digital_04'));
      final items = await empty.select(empty.receiptItems).get();
      expect(items.every((i) => i.categoryId == null), isTrue);
      expect(items.every((i) => i.needsReview), isTrue);
    });
  });

  group('Lernen aus Korrekturen', () {
    test('Zuordnung wird als Alias gemerkt und beim naechsten Bon automatisch angewendet', () async {
      final repo = receiptRepo(db);
      await repo.saveParsed(_parse('billa_digital_04', rename: {'Clever Hirtenkäse': 'scharfer Aufstrich'}));
      final item = (await itemsByName())['scharfer Aufstrich']!;

      final changed = await repo.setItemCategory(item.id, cat['Öle, Gewürze & Saucen']!);
      expect(changed, 1);
      final alias = await db.select(db.categoryAliases).getSingle();
      expect(alias.aliasText, 'scharfer aufstrich');
      expect(alias.categoryId, cat['Öle, Gewürze & Saucen']);
      expect(alias.hits, 1);
      final corrected = (await itemsByName())['scharfer Aufstrich']!;
      expect(corrected.categoryId, cat['Öle, Gewürze & Saucen']);
      expect(corrected.needsReview, isFalse);

      // naechster Bon (anderer Kauf) mit demselben Artikel, jetzt automatisch zugeordnet
      await repo.saveParsed(_parse('billa_digital_06', rename: {_firstItemOf('billa_digital_06'): 'IC scharfer Aufstrich'}));
      final second = await (db.select(db.receiptItems)..where((i) => i.rawText.like('%scharfer Aufstrich%'))).get();
      expect(second.length, 2);
      expect(second.every((i) => i.categoryId == cat['Öle, Gewürze & Saucen']), isTrue,
          reason: 'auch mit Praefix "IC" derselbe Alias-Schluessel');
    });

    test('Gleiche Artikel auf anderen Bons werden mit korrigiert', () async {
      final repo = receiptRepo(db);
      await repo.saveParsed(_parse('billa_digital_04', rename: {'Clever Hirtenkäse': 'scharfer Aufstrich'}));
      await repo.saveParsed(_parse('billa_digital_06', rename: {_firstItemOf('billa_digital_06'): 'scharfer Aufstrich'}));
      final before = await (db.select(db.receiptItems)..where((i) => i.rawText.equals('scharfer Aufstrich'))).get();
      expect(before.length, 2);
      expect(before.every((i) => i.categoryId == null), isTrue);

      final changed = await repo.setItemCategory(before.first.id, cat['Süßes & Snacks']!);
      expect(changed, 2);
      final after = await (db.select(db.receiptItems)..where((i) => i.rawText.equals('scharfer Aufstrich'))).get();
      expect(after.every((i) => i.categoryId == cat['Süßes & Snacks'] && !i.needsReview), isTrue);
    });

    test('Erneute Bestaetigung zaehlt hits hoch, andere Kategorie ueberschreibt den Alias', () async {
      final repo = receiptRepo(db);
      await repo.saveParsed(_parse('billa_digital_04', rename: {'Clever Hirtenkäse': 'scharfer Aufstrich'}));
      final id = (await itemsByName())['scharfer Aufstrich']!.id;
      await repo.setItemCategory(id, cat['Öle, Gewürze & Saucen']!);
      await repo.setItemCategory(id, cat['Öle, Gewürze & Saucen']!);
      expect((await db.select(db.categoryAliases).getSingle()).hits, 2);
      await repo.setItemCategory(id, cat['Sonstiges']!);
      final alias = await db.select(db.categoryAliases).getSingle();
      expect(alias.categoryId, cat['Sonstiges']);
      expect(alias.hits, 1);
    });

    test('Alias auf eine geloeschte Kategorie wird ignoriert', () async {
      final repo = receiptRepo(db);
      await repo.saveParsed(_parse('billa_digital_04', rename: {'Clever Hirtenkäse': 'scharfer Aufstrich'}));
      await repo.setItemCategory((await itemsByName())['scharfer Aufstrich']!.id, cat['Sonstiges']!);
      await (db.update(db.categories)..where((c) => c.id.equals(cat['Sonstiges']!))).write(CategoriesCompanion(deletedAt: Value(DateTime.utc(2026, 9))));
      await repo.saveParsed(_parse('billa_digital_06', rename: {_firstItemOf('billa_digital_06'): 'scharfer Aufstrich'}));
      final second = (await db.select(db.receiptItems).get()).where((i) => i.rawText == 'scharfer Aufstrich' && i.needsReview);
      expect(second, hasLength(1)); // nicht zugeordnet, weil die Kategorie weg ist
    });

    test('Jede Korrektur landet in der Outbox (Positionen und Alias)', () async {
      final repo = receiptRepo(db);
      await repo.saveParsed(_parse('billa_digital_04', rename: {'Clever Hirtenkäse': 'scharfer Aufstrich'}));
      await db.delete(db.outbox).go();
      await repo.setItemCategory((await itemsByName())['scharfer Aufstrich']!.id, cat['Süßes & Snacks']!);
      final tables = (await db.select(db.outbox).get()).map((e) => e.remoteTable).toList();
      expect(tables, containsAll(['receipt_items', 'category_aliases']));
    });
  });

  group('Nachtraegliches Zuordnen (Bons vor der Kategorisierung importiert)', () {
    test('categorizeMissing ordnet zu, Rabatte erben, ein zweiter Lauf aendert nichts mehr', () async {
      final noCats = memoryDb();
      addTearDown(noCats.close);
      final repo0 = receiptRepo(noCats);
      await repo0.saveParsed(_parse('billa_digital_03'));
      expect((await noCats.select(noCats.receiptItems).get()).every((i) => i.categoryId == null), isTrue);

      final ids = await seedCategories(noCats);
      final changed = await repo0.categorizeMissing();
      expect(changed, greaterThan(15));

      final all = await (noCats.select(noCats.receiptItems)..orderBy([(i) => OrderingTerm.asc(i.lineNo)])).get();
      final idx = all.indexWhere((i) => i.rawText == 'DKIH Paprika Tricolore');
      expect(all[idx].categoryId, ids['Gemüse']);
      expect(all[idx + 1].categoryId, ids['Gemüse']); // EXTREM AKTION erbt
      expect(all.where((i) => i.kind == 'deposit').every((i) => i.categoryId == ids['Pfand']), isTrue);

      expect(await repo0.categorizeMissing(), 0);
    });

    test('Regression: Bon-Rabatt erbt nie die Kategorie des letzten Artikels (Coca-Cola war im Monat negativ)', () async {
      final repo = receiptRepo(db);
      await repo.saveParsed(_parse('billa_digital_03'));
      await repo.categorizeMissing(); // der Backfill lief frueher ueber den Bon-Rabatt und gab ihm "Getraenke"
      final bon = (await db.select(db.receiptItems).get()).singleWhere((i) => i.rawText.contains('Rabattsammler'));
      expect(bon.kind, 'bill_discount');
      expect(bon.categoryId, isNull);
      expect(bon.needsReview, isFalse);
    });

    test('Altbestand: als normaler Rabatt gespeicherter Bon-Rabatt (ohne Steuerbuchstaben) wird repariert', () async {
      final repo = receiptRepo(db);
      final result = await repo.saveParsed(_parse('billa_digital_03'));
      // Zustand vor der Korrektur nachstellen: Art 'discount' und die geerbte Kategorie
      final bon = (await db.select(db.receiptItems).get()).singleWhere((i) => i.rawText.contains('Rabattsammler'));
      await (db.update(db.receiptItems)..where((i) => i.id.equals(bon.id)))
          .write(ReceiptItemsCompanion(kind: const Value('discount'), categoryId: Value(cat['Getränke'])));
      await db.delete(db.outbox).go();

      final changed = await repo.categorizeMissing();
      expect(changed, 1);
      final fixed = await (db.select(db.receiptItems)..where((i) => i.id.equals(bon.id))).getSingle();
      expect(fixed.kind, 'bill_discount');
      expect(fixed.categoryId, isNull);
      expect((await db.select(db.outbox).get()).map((o) => o.remoteTable), ['receipt_items']); // wird synchronisiert

      // Artikel-Rabatte mit Steuerbuchstaben bleiben unberuehrt
      final items = await (db.select(db.receiptItems)..where((i) => i.receiptId.equals(result.receiptId))).get();
      expect(items.where((i) => i.kind == 'discount' && i.taxCode != null), isNotEmpty);
      expect(await repo.categorizeMissing(), 0); // zweiter Lauf: nichts mehr zu tun
    });

    test('Bereits vom Nutzer gesetzte Kategorien bleiben unangetastet', () async {
      final repo = receiptRepo(db);
      await repo.saveParsed(_parse('billa_digital_04'));
      final champignon = (await itemsByName())['Clever Champignon weiß']!;
      await repo.setItemCategory(champignon.id, cat['Sonstiges']!);
      await repo.categorizeMissing();
      expect((await itemsByName())['Clever Champignon weiß']!.categoryId, cat['Sonstiges']);
    });
  });

  group('Sync', () {
    test('Gelernter Alias kommt auf dem zweiten Geraet an und wirkt dort sofort', () async {
      final remote = FakeRemoteStore();
      final repo = receiptRepo(db);
      await repo.saveParsed(_parse('billa_digital_04', rename: {'Clever Hirtenkäse': 'scharfer Aufstrich'}));
      await repo.setItemCategory((await itemsByName())['scharfer Aufstrich']!.id, cat['Öle, Gewürze & Saucen']!);
      final r = await SyncEngine(db, remote).sync();
      expect(r.skipped, 0);
      expect(remote.table('category_aliases').length, 1);
      expect(remote.table('category_aliases').values.single['alias_text'], 'scharfer aufstrich');

      final db2 = memoryDb();
      addTearDown(db2.close);
      await seedCategories(db2); // dieselben Kategorien-IDs wie auf Geraet 1
      await SyncEngine(db2, remote).sync();
      expect((await db2.select(db2.categoryAliases).get()).length, 1);

      await receiptRepo(db2).saveParsed(_parse('billa_digital_06', rename: {_firstItemOf('billa_digital_06'): 'scharfer Aufstrich'}));
      // Geraet 2 hat den ersten Bon vom Server geholt und den zweiten selbst importiert
      final items = await (db2.select(db2.receiptItems)..where((i) => i.rawText.equals('scharfer Aufstrich'))).get();
      expect(items, hasLength(2));
      expect(items.every((i) => i.categoryId == cat['Öle, Gewürze & Saucen']), isTrue);
    });

    test('Kategorie der Position kommt beim Server an', () async {
      final remote = FakeRemoteStore();
      await receiptRepo(db).saveParsed(_parse('billa_digital_04'));
      await SyncEngine(db, remote).sync();
      final rows = remote.table('receipt_items').values;
      final champ = rows.firstWhere((r) => r['raw_text'] == 'Clever Champignon weiß');
      expect(champ['category_id'], cat['Gemüse']);
    });
  });
}

/// Name der ersten Artikelposition einer Fixture (zum gezielten Umbenennen).
String _firstItemOf(String fixture) =>
    const BillaTextParser().parse(_fixtureText(fixture)).items.firstWhere((i) => i.kind == ReceiptItemKind.article).rawText;
