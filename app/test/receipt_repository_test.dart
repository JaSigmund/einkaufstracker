import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/receipt_repository.dart';
import 'package:einkaufstracker/data/sync/sync_engine.dart';
import 'package:einkaufstracker/domain/receipt/billa_text_parser.dart';
import 'package:einkaufstracker/domain/receipt/parsed_receipt.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

ParsedReceipt _parse(String fixture) =>
    const BillaTextParser().parse(File('test/fixtures/receipts/$fixture.txt').readAsStringSync());

void main() {
  late AppDatabase db;
  late FakeRemoteStore remote;

  setUp(() {
    db = memoryDb();
    remote = FakeRemoteStore();
  });
  tearDown(() => db.close());

  Future<int> outboxCount() async => (await db.select(db.outbox).get()).length;
  Future<int> sumOfItems(String receiptId) async =>
      (await (db.select(db.receiptItems)..where((i) => i.receiptId.equals(receiptId) & i.deletedAt.isNull())).get())
          .fold<int>(0, (s, i) => s + i.lineTotalCents);

  group('Speichern', () {
    test('Bon wird mit Filiale und allen Positionen gespeichert, Summe der Positionen = Bon-Summe', () async {
      final repo = receiptRepo(db);
      final result = await repo.saveParsed(_parse('billa_digital_04'));
      expect(result.outcome, ReceiptSaveOutcome.saved);

      final receipt = await db.select(db.receipts).getSingle();
      expect(receipt.totalCents, 2900);
      expect(receipt.externalId, '0643-20260702-03-4852');
      expect(receipt.source, 'pdf_text');
      expect(receipt.status, 'confirmed');
      expect(receipt.sumMismatch, isFalse);
      expect(receipt.confidence, 1.0);
      expect(receipt.purchasedAt.toUtc(), DateTime.utc(2026, 7, 2, 17, 51));

      final store = await db.select(db.stores).getSingle();
      expect(store.chain, 'Billa');
      expect(store.branch, '0643');
      expect(receipt.storeId, store.id);

      expect((await db.select(db.receiptItems).get()).length, 10);
      expect(await sumOfItems(receipt.id), 2900);
    });

    test('Jede Aenderung landet in der Outbox: Filiale, Bon und zehn Positionen', () async {
      await receiptRepo(db).saveParsed(_parse('billa_digital_04'));
      final entries = await (db.select(db.outbox)..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
      expect(entries.length, 12);
      expect(entries.map((e) => e.remoteTable).toList(), ['stores', 'receipts', ...List.filled(10, 'receipt_items')]);
    });

    test('Derselbe Bon (gleiche Re-Nr) wird kein zweites Mal gespeichert', () async {
      final repo = receiptRepo(db);
      final first = await repo.saveParsed(_parse('billa_digital_04'));
      final outboxAfterFirst = await outboxCount();
      final second = await repo.saveParsed(_parse('billa_digital_04'));
      expect(second.outcome, ReceiptSaveOutcome.duplicate);
      expect(second.receiptId, first.receiptId);
      expect((await db.select(db.receipts).get()).length, 1);
      expect(await outboxCount(), outboxAfterFirst);
    });

    test('Bons aus derselben Filiale teilen sich eine Filiale', () async {
      final repo = receiptRepo(db);
      await repo.saveParsed(_parse('billa_digital_03')); // Filiale 0643
      await repo.saveParsed(_parse('billa_digital_04')); // Filiale 0643
      await repo.saveParsed(_parse('billa_digital_06')); // Filiale 0943
      final stores = await db.select(db.stores).get();
      expect(stores.map((s) => s.branch).toSet(), {'0643', '0943'});
      expect(stores.length, 2);
    });

    test('Bon-Rabatt (Rabattsammler) wird als eigene Position gespeichert, die Summen stimmen', () async {
      final result = await receiptRepo(db).saveParsed(_parse('billa_digital_03'));
      final items = await (db.select(db.receiptItems)..where((i) => i.receiptId.equals(result.receiptId))).get();
      expect(items.length, 25); // 24 Positionen + 1 Bon-Rabatt
      final bon = items.firstWhere((i) => i.rawText.contains('Rabattsammler'));
      expect(bon.kind, 'discount');
      expect(bon.taxCode, isNull);
      expect(bon.lineTotalCents, -451);
      expect(bon.rawText, contains('20%'));
      expect(await sumOfItems(result.receiptId), 4879);
    });

    test('Mengenzeile: Menge und Einzelpreis stehen an der Artikelzeile', () async {
      await receiptRepo(db).saveParsed(_parse('billa_digital_03'));
      final tomaten = await (db.select(db.receiptItems)..where((i) => i.rawText.like('%Cherrytomaten%'))).getSingle();
      expect(tomaten.quantity, 2);
      expect(tomaten.unitPriceCents, 285);
      expect(tomaten.lineTotalCents, 570);
    });

    test('Bon, der die Pruefungen nicht besteht, wird mit sumMismatch gespeichert', () async {
      final lines = File('test/fixtures/receipts/billa_digital_04.txt').readAsStringSync().split('\n')
        ..removeWhere((l) => l.contains('Clever Champignon'));
      final bad = const BillaTextParser().parse(lines.join('\n'));
      final result = await receiptRepo(db).saveParsed(bad);
      final r = await (db.select(db.receipts)..where((x) => x.id.equals(result.receiptId))).getSingle();
      expect(r.sumMismatch, isTrue);
      expect(r.confidence, isNull);
    });

    test('Nicht gelesener Bon wird abgelehnt', () async {
      final r = const BillaTextParser().parse('kein Bon');
      expect(() => receiptRepo(db).saveParsed(r), throwsArgumentError);
    });

    test('onChanged loest den Sync aus', () async {
      var calls = 0;
      await receiptRepo(db, onChanged: () => calls++).saveParsed(_parse('billa_digital_04'));
      expect(calls, 1);
    });
  });

  group('Loeschen und erneut importieren', () {
    test('Geloeschter Bon verschwindet aus der Liste, Positionen ebenfalls', () async {
      final repo = receiptRepo(db);
      final saved = await repo.saveParsed(_parse('billa_digital_04'));
      expect(await repo.watchAll().first, hasLength(1));
      await repo.softDelete(saved.receiptId);
      expect(await repo.watchAll().first, isEmpty);
      expect(await repo.watchItems(saved.receiptId).first, isEmpty);
    });

    test('Nach dem Loeschen kann derselbe Bon wieder importiert werden, mit denselben IDs (reaktiviert)', () async {
      final repo = receiptRepo(db);
      final first = await repo.saveParsed(_parse('billa_digital_04'));
      await repo.softDelete(first.receiptId);
      final again = await repo.saveParsed(_parse('billa_digital_04'));
      expect(again.outcome, ReceiptSaveOutcome.saved);
      expect(again.receiptId, first.receiptId);
      expect(await repo.watchAll().first, hasLength(1));
      expect(await repo.watchItems(first.receiptId).first, hasLength(10));
      expect((await db.select(db.receipts).get()).length, 1);
    });
  });

  group('Sync', () {
    test('Bon kommt komplett beim Server an und ein zweites Geraet sieht ihn', () async {
      await receiptRepo(db).saveParsed(_parse('billa_digital_04'));
      final result = await SyncEngine(db, remote).sync();
      expect(result.pushed, 12);
      expect(await outboxCount(), 0);
      expect(remote.table('stores').length, 1);
      expect(remote.table('receipts').length, 1);
      expect(remote.table('receipt_items').length, 10);
      final row = remote.table('receipts').values.single;
      expect(row['external_id'], '0643-20260702-03-4852');
      expect(row['source'], 'pdf_text');

      final db2 = memoryDb();
      addTearDown(db2.close);
      await SyncEngine(db2, remote).sync();
      final repo2 = receiptRepo(db2);
      final list = await repo2.watchAll().first;
      expect(list, hasLength(1));
      expect(list.single.totalCents, 2900);
      expect(await repo2.watchItems(list.single.id).first, hasLength(10));
    });

    test('Zwei Geraete importieren denselben Bon offline: kein Konflikt, nur ein Bon auf dem Server', () async {
      final db2 = memoryDb();
      addTearDown(db2.close);
      await receiptRepo(db).saveParsed(_parse('billa_digital_04'));
      await receiptRepo(db2).saveParsed(_parse('billa_digital_04'));

      final r1 = await SyncEngine(db, remote).sync();
      final r2 = await SyncEngine(db2, remote).sync();
      expect(r1.skipped, 0);
      expect(r2.skipped, 0, reason: 'deterministische IDs: derselbe Bon ist dieselbe Zeile');
      expect(remote.table('receipts').length, 1);
      expect(remote.table('receipt_items').length, 10);
      expect(remote.table('stores').length, 1);
    });

    test('Bon loeschen kommt als Aenderung beim Server an', () async {
      final repo = receiptRepo(db);
      final saved = await repo.saveParsed(_parse('billa_digital_04'));
      final engine = SyncEngine(db, remote);
      await engine.sync();
      await repo.softDelete(saved.receiptId);
      await engine.sync();
      expect(remote.table('receipts')[saved.receiptId]!['deleted_at'], isNotNull);
      expect(remote.table('receipt_items').values.every((r) => r['deleted_at'] != null), isTrue);
    });
  });
}
