import 'package:drift/drift.dart' show Value;
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/products/off_client.dart';
import 'package:einkaufstracker/data/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

class _FakeOff implements OffClient {
  _FakeOff(this.result);
  OffProduct? result;
  int calls = 0;

  @override
  Future<OffProduct?> lookup(String ean) async {
    calls++;
    return result;
  }
}

void main() {
  late AppDatabase db;

  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  group('create und Suche', () {
    test('legt ein Produkt an, landet in der Outbox, ist per Suche zu finden', () async {
      var changed = 0;
      final repo = productRepo(db, onChanged: () => changed++);
      final p = await repo.create(name: '  Vollmilch 3,5%  ', brand: 'Clever', baseUnit: 'l', packSize: 1);
      expect(p.name, 'Vollmilch 3,5%');
      expect(changed, 1);
      expect((await db.select(db.outbox).get()).map((o) => o.remoteTable), contains('products'));

      expect((await repo.search('vollmilch')).map((p) => p.id), [p.id]); // Suche ist case-insensitiv
      expect(await repo.search('   '), isEmpty);
      expect(await repo.search('erdbeere'), isEmpty);
    });

    test('leerer Name wird abgelehnt', () {
      expect(() => productRepo(db).create(name: '   '), throwsArgumentError);
    });

    test('Marke ist leer/whitespace: wird zu null', () async {
      final p = await productRepo(db).create(name: 'X', brand: '   ');
      expect(p.brand, isNull);
    });
  });

  group('lookup (Barcode)', () {
    test('bereits verknuepfter Barcode: lokales Produkt ohne OFF-Aufruf', () async {
      final off = _FakeOff(null);
      final repo = productRepo(db, off: off);
      final p = await repo.create(name: 'Paprika rot', ean: '9008700000001');

      final result = await repo.lookup('9008700000001');
      expect(result.isKnown, isTrue);
      expect(result.product!.id, p.id);
      expect(off.calls, 0);
    });

    test('unbekannter Barcode: OFF wird befragt', () async {
      const off = OffProduct(name: 'Bio-Joghurt', categoryTags: ['en:yogurts']);
      final repo = productRepo(db, off: _FakeOff(off));
      final result = await repo.lookup('9008700000002');
      expect(result.isKnown, isFalse);
      expect(result.offSuggestion!.name, 'Bio-Joghurt');
    });

    test('unbekannter Barcode, auch OFF kennt ihn nicht: beides null', () async {
      final repo = productRepo(db, off: _FakeOff(null));
      final result = await repo.lookup('0');
      expect(result.isKnown, isFalse);
      expect(result.offSuggestion, isNull);
    });

    test('ohne OffClient (z.B. offline): kein Absturz, kein Vorschlag', () async {
      final result = await productRepo(db).lookup('123');
      expect(result.offSuggestion, isNull);
    });

    test('geloeschtes Produkt zaehlt nicht als bekannt', () async {
      final repo = productRepo(db);
      final p = await repo.create(name: 'X', ean: '1');
      await repo.update(p.copyWith(deletedAt: Value(DateTime.utc(2026))));
      final result = await repo.lookup('1');
      expect(result.isKnown, isFalse);
    });
  });

  group('softDelete (Fehlerbericht "Produkt löschen", 2026-09-28)', () {
    test('setzt deletedAt, landet in der Outbox, erscheint nicht mehr in watchAll', () async {
      final repo = productRepo(db);
      final p = await repo.create(name: 'Auslaufmodell');
      await repo.softDelete(p.id);
      final row = await (db.select(db.products)..where((x) => x.id.equals(p.id))).getSingle();
      expect(row.deletedAt, isNotNull);
      expect(await repo.watchAll().first, isEmpty);
      final outbox = await db.select(db.outbox).get();
      expect(outbox.where((o) => o.remoteTable == 'products' && o.rowId == p.id), isNotEmpty);
    });

    test('unbekanntes Produkt: kein Absturz', () async {
      await productRepo(db).softDelete('does-not-exist');
    });
  });

  group('findOrCreateForReceiptItem', () {
    test('uebernimmt die Grundeinheit des Bon-Artikels bei der Neuanlage (Waegware)', () async {
      final repo = productRepo(db);
      final p = await repo.findOrCreateForReceiptItem('DKIH Paprika Tricolore', baseUnit: 'kg');
      expect(p.baseUnit, 'kg');
    });

    test('ein bereits gelerntes Produkt behaelt seine (ggf. spaeter korrigierte) Einheit', () async {
      final repo = productRepo(db);
      final first = await repo.findOrCreateForReceiptItem('DKIH Paprika Tricolore', baseUnit: 'kg');
      await repo.update(first.copyWith(baseUnit: 'piece')); // Nutzer korrigiert
      final second = await repo.findOrCreateForReceiptItem('IC DKIH Paprika Tricolore', baseUnit: 'kg');
      expect(second.id, first.id);
      expect(second.baseUnit, 'piece'); // wird nicht von der Bon-Einheit ueberschrieben
    });

    test('erkannter Produkttyp: Haltbarkeit-nach-Oeffnen, Lagerort und Datumsart werden vorbelegt (Roadmap Phase 3, Doku 06 §3.2)', () async {
      final repo = productRepo(db);
      final milk = await repo.findOrCreateForReceiptItem('H-VOLLMILCH 1L');
      expect(milk.openedShelfLifeDays, 3);
      expect(milk.defaultLocation, 'fridge');

      final meat = await repo.findOrCreateForReceiptItem('Rind Hackfleisch');
      expect(meat.defaultDateKind, 'use_by');
    });

    test('unbekannter Produkttyp: generische Standardwerte statt Rateversuch', () async {
      final repo = productRepo(db);
      final p = await repo.findOrCreateForReceiptItem('Klopapier 8 Rollen');
      expect(p.openedShelfLifeDays, isNull);
      expect(p.defaultLocation, 'pantry');
      expect(p.defaultDateKind, 'best_before');
    });

    test('ADR-023: ein OCR-Leerzeichen mitten im Wort legt kein Duplikat an (Fehlerbericht "Faschiertes", 2026-10-01)', () async {
      final repo = productRepo(db);
      final first = await repo.findOrCreateForReceiptItem('Faschiertes 1kg');
      final second = await repo.findOrCreateForReceiptItem('Faschi ertes 1kg'); // kaputtes Leerzeichen
      expect(second.id, first.id);

      // Der kaputte Text wurde als zusaetzlicher Alias gelernt: ein drittes Mal trifft schon Stufe 1 (exakt).
      final aliases = await repo.watchAliasesFor(first.id).first;
      expect(aliases.map((a) => a.aliasText), containsAll(['faschiertes', 'faschi ertes']));
    });

    test('ADR-023: aehnliche, aber tatsaechlich unterschiedliche Produkte bleiben getrennt', () async {
      final repo = productRepo(db);
      final red = await repo.findOrCreateForReceiptItem('Paprika rot');
      final yellow = await repo.findOrCreateForReceiptItem('Paprika gelb');
      expect(yellow.id, isNot(red.id));
    });
  });

  group('watchAliasesFor / removeAlias (Fehlerbericht "Alias ändern")', () {
    test('zeigt gelernte Aliase, geloeste erscheinen nicht mehr', () async {
      final repo = productRepo(db);
      final p = await repo.findOrCreateForReceiptItem('DKIH Paprika Tricolore');
      final aliases = await repo.watchAliasesFor(p.id).first;
      expect(aliases, hasLength(1));
      expect(aliases.single.aliasText, isNotEmpty);

      await repo.removeAlias(aliases.single.id);
      expect(await repo.watchAliasesFor(p.id).first, isEmpty);
    });

    test('geloester Alias: der Bon-Text wird nicht mehr automatisch zugeordnet', () async {
      final repo = productRepo(db);
      final first = await repo.findOrCreateForReceiptItem('DKIH Paprika Tricolore');
      final aliases = await repo.watchAliasesFor(first.id).first;
      await repo.removeAlias(aliases.single.id);

      final second = await repo.findOrCreateForReceiptItem('DKIH Paprika Tricolore');
      expect(second.id, isNot(first.id)); // wird neu angelegt statt wiederverknuepft
    });
  });

  group('recentUnlinked', () {
    test('nur Produkte ohne Barcode, zuletzt geaendert zuerst', () async {
      final repo = productRepo(db);
      final a = await repo.create(name: 'A');
      await repo.create(name: 'B', ean: '1');
      final c = await repo.findOrCreateForReceiptItem('C'); // aus einem Bon, ohne Barcode

      final unlinked = await repo.recentUnlinked();
      expect(unlinked.map((p) => p.id).toSet(), {a.id, c.id});
    });

    test('begrenzt auf limit', () async {
      final repo = productRepo(db);
      for (var i = 0; i < 5; i++) {
        await repo.create(name: 'P$i');
      }
      expect(await repo.recentUnlinked(limit: 3), hasLength(3));
    });
  });

  group('matchByLearnedName / lookup ordnet automatisch zu', () {
    test('OFF-Name entspricht (normalisiert) einem gelernten Bon-Alias: automatisch verknuepft', () async {
      final repo = productRepo(db);
      final product = await repo.findOrCreateForReceiptItem('Clever Champignon weiß');
      final matched = await repo.matchByLearnedName('Clever Champignon weiss');
      expect(matched?.id, product.id);
    });

    test('kein Treffer fuer einen unbekannten Namen', () async {
      expect(await productRepo(db).matchByLearnedName('Irgendein Joghurt'), isNull);
    });

    test('lookup: unbekannter Barcode wird automatisch verknuepft, wenn OFF den Bon-Namen trifft', () async {
      final product = await productRepo(db).findOrCreateForReceiptItem('Clever Champignon weiß');
      final repo = productRepo(db, off: _FakeOff(const OffProduct(name: 'Clever Champignon weiss')));
      final result = await repo.lookup('9008700000042');
      expect(result.isKnown, isTrue);
      expect(result.product!.id, product.id);
      expect((await db.select(db.productBarcodes).getSingle()).ean, '9008700000042'); // dauerhaft gemerkt
    });

    test('lookup: kein automatischer Treffer, wenn der OFF-Name nicht passt', () async {
      await productRepo(db).findOrCreateForReceiptItem('Clever Champignon weiß');
      final repo = productRepo(db, off: _FakeOff(const OffProduct(name: 'Ganz anderes Produkt')));
      final result = await repo.lookup('9008700000043');
      expect(result.isKnown, isFalse);
      expect(result.offSuggestion?.name, 'Ganz anderes Produkt');
    });
  });

  group('linkBarcode', () {
    test('verknuepft nachtraeglich, landet in der Outbox mit zusammengesetztem Schluessel', () async {
      final repo = productRepo(db);
      final p = await repo.create(name: 'Paprika rot');
      await repo.linkBarcode('9008700000009', p.id);
      final mapping = await db.select(db.productBarcodes).getSingle();
      expect(mapping.productId, p.id);
      final outboxRow = (await db.select(db.outbox).get()).firstWhere((o) => o.remoteTable == 'product_barcodes');
      expect(outboxRow.rowId, 'h1:9008700000009');
    });
  });

  group('Sync', () {
    test('Produkt und Barcode kommen auf einem zweiten Geraet an (product_barcodes hat keine id-Spalte)', () async {
      final remote = FakeRemoteStore();
      final repo = productRepo(db);
      final p = await repo.create(name: 'Paprika rot', ean: '9008700000005', packSize: 0.5, baseUnit: 'kg');
      await SyncEngine(db, remote).sync();

      expect(remote.table('products').values.single['name'], 'Paprika rot');
      expect(remote.table('product_barcodes').values.single['ean'], '9008700000005');

      final db2 = memoryDb();
      addTearDown(db2.close);
      await SyncEngine(db2, remote).sync();
      final result = await productRepo(db2).lookup('9008700000005');
      expect(result.product!.id, p.id);
      expect(result.product!.packSize, 0.5);
    });

    test('zweiter Barcode fuer dasselbe Produkt ueberschreibt die erste Zeile nicht (unterschiedlicher Schluessel)', () async {
      final remote = FakeRemoteStore();
      final repo = productRepo(db);
      final p = await repo.create(name: 'Paprika rot');
      await repo.linkBarcode('1111111111111', p.id);
      await repo.linkBarcode('2222222222222', p.id);
      await SyncEngine(db, remote).sync();
      expect(remote.table('product_barcodes'), hasLength(2));
    });
  });
}
