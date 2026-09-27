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
