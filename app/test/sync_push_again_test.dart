import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Haelt das erste Senden an, damit waehrend des Laufs eine neue Aenderung entstehen kann.
class _GatedRemote extends FakeRemoteStore {
  final gate = Completer<void>();
  final reached = Completer<void>();

  @override
  Future<String?> upsert(String table, Map<String, dynamic> row) async {
    if (!reached.isCompleted) reached.complete();
    await gate.future;
    return super.upsert(table, row);
  }
}

/// Die Konflikterkennung laeuft in das Zeitlimit, das Senden selbst geht.
class _HangingLookupRemote extends FakeRemoteStore {
  int lookups = 0;

  @override
  Future<Map<String, String>> fetchUpdatedAt(String table, List<String> ids) async {
    lookups++;
    throw TimeoutException('haengt');
  }
}

/// Fehlerbericht "Synchronisierung" (2026-11-02).
void main() {
  late AppDatabase db;
  late String productId;

  setUp(() async {
    db = memoryDb();
    productId = (await productRepo(db).create(name: 'Milch')).id;
  });
  tearDown(() => db.close());

  test('eine Aenderung waehrend des Laufs geht noch im selben Lauf raus', () async {
    final remote = _GatedRemote();
    final engine = SyncEngine(db, remote);
    final run = engine.sync();
    await remote.reached.future;

    final item = await inventoryRepo(db).recordFromScan(productId: productId, ean: '1');
    engine.requestAnotherPush();
    remote.gate.complete();
    await run;

    expect(await db.select(db.outbox).get(), isEmpty);
    expect(remote.table('inventory_items').keys, contains(item.id));
  });

  test('ohne neue Anfrage laeuft nur ein Durchgang, ausserhalb eines Laufs ist die Anfrage wirkungslos', () async {
    final remote = FakeRemoteStore();
    final engine = SyncEngine(db, remote);
    engine.requestAnotherPush();
    await engine.sync();
    final calls = remote.upsertCalls;

    await inventoryRepo(db).recordFromScan(productId: productId, ean: '1');
    expect(remote.upsertCalls, calls);
    expect(await db.select(db.outbox).get(), isNotEmpty);
  });

  test('haengt die Konflikterkennung, wird die restliche Pruefung uebersprungen und trotzdem gesendet', () async {
    await inventoryRepo(db).recordFromScan(productId: productId, ean: '1');
    for (final table in ['products', 'inventory_items', 'inventory_movements']) {
      await db.into(db.syncStates).insert(SyncStatesCompanion.insert(remoteTable: table, lastPulledAt: const Value('2026-01-01T00:00:00Z')));
    }
    final remote = _HangingLookupRemote();

    await SyncEngine(db, remote).sync();

    expect(remote.lookups, 1, reason: 'nicht je Tabelle das ganze Zeitlimit warten');
    expect(await db.select(db.outbox).get(), isEmpty);
  });
}
