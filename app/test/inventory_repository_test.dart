import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

DateTime _d(int y, int m, int d) => DateTime.utc(y, m, d);

void main() {
  late AppDatabase db;
  late String productId;

  setUp(() async {
    db = memoryDb();
    productId = (await productRepo(db).create(name: 'Vollmilch 1l', baseUnit: 'l', packSize: 1)).id;
  });
  tearDown(() => db.close());

  group('recordFromScan: neuer Bestand', () {
    test('legt einen versiegelten Eintrag an, Ablaufdatum aus MHD, Kaufbewegung im Ledger', () async {
      var changed = 0;
      final repo = inventoryRepo(db, onChanged: () => changed++);
      final item = await repo.recordFromScan(
        productId: productId,
        ean: '9008700000001',
        bestBefore: _d(2026, 10, 15),
        now: DateTime.utc(2026, 9, 27, 10),
      );
      expect(item.status, 'sealed');
      expect(item.isSuggestion, isFalse);
      expect(item.expiresOn, _d(2026, 10, 15));
      expect(item.purchasedOn, _d(2026, 9, 27));
      expect(changed, 1);

      final movements = await db.select(db.inventoryMovements).get();
      expect(movements, hasLength(1));
      expect((movements.single.type, movements.single.quantityDelta), ('purchase', 1.0));
      expect((await db.select(db.outbox).get()).map((o) => o.remoteTable), containsAll(['inventory_items', 'inventory_movements']));
    });

    test('ohne MHD und ohne Standardfrist bleibt der Ablauf unbekannt', () async {
      final item = await inventoryRepo(db).recordFromScan(productId: productId, ean: '1');
      expect(item.expiresOn, isNull);
    });

    test('Verbrauchsdatum wird uebernommen', () async {
      final item = await inventoryRepo(db).recordFromScan(productId: productId, ean: '1', bestBefore: _d(2026, 10, 1), dateKind: 'use_by');
      expect(item.dateKind, 'use_by');
    });
  });

  group('recordFromScan: verfeinert einen Bon-Vorschlag statt zu duplizieren (Doku 06 §2)', () {
    Future<String> makeSuggestion(DateTime purchasedOn) async {
      final id = 'sugg-${purchasedOn.toIso8601String()}';
      await db.into(db.inventoryItems).insert(InventoryItem(
            id: id,
            householdId: 'h1',
            productId: productId,
            quantity: 2,
            unit: 'piece',
            location: 'pantry',
            purchasedOn: purchasedOn,
            dateKind: 'best_before',
            status: 'sealed',
            isSuggestion: true,
            updatedAt: DateTime.utc(2026),
          ));
      return id;
    }

    test('Vorschlag der letzten 7 Tage wird verfeinert, kein zweiter Eintrag, keine zweite Kaufbewegung', () async {
      final id = await makeSuggestion(_d(2026, 9, 25));
      final item = await inventoryRepo(db).recordFromScan(
        productId: productId,
        ean: '9008700000002',
        bestBefore: _d(2026, 10, 10),
        location: 'fridge',
        now: DateTime.utc(2026, 9, 27),
      );
      expect(item.id, id);
      expect(item.isSuggestion, isFalse);
      expect(item.ean, '9008700000002');
      expect(item.location, 'fridge');
      expect(item.quantity, 2); // Menge des Vorschlags bleibt
      expect(await db.select(db.inventoryItems).get(), hasLength(1));
      expect(await db.select(db.inventoryMovements).get(), isEmpty); // der Bon hat die Kaufbewegung schon erzeugt
    });

    test('Vorschlag ist aelter als 7 Tage: neuer Eintrag statt Verfeinerung', () async {
      await makeSuggestion(_d(2026, 9, 1));
      await inventoryRepo(db).recordFromScan(productId: productId, ean: '1', now: DateTime.utc(2026, 9, 27));
      final items = await db.select(db.inventoryItems).get();
      expect(items, hasLength(2));
      expect(items.where((i) => i.isSuggestion), hasLength(1)); // der alte Vorschlag bleibt unangetastet
    });

    test('mehrere passende Vorschlaege: der juengste wird verfeinert', () async {
      await makeSuggestion(_d(2026, 9, 20));
      final newer = await makeSuggestion(_d(2026, 9, 26));
      final item = await inventoryRepo(db).recordFromScan(productId: productId, ean: '1', now: DateTime.utc(2026, 9, 27));
      expect(item.id, newer);
    });
  });

  group('open', () {
    test('setzt Oeffnungsdatum und uebernimmt die Standardfrist, wenn keine eigene gesetzt ist', () async {
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: productId, ean: '1', bestBefore: _d(2026, 10, 15), now: DateTime.utc(2026, 9, 27));
      await repo.open(item.id, productDefaultOpenShelfLifeDays: 3, now: DateTime.utc(2026, 9, 28));
      final updated = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
      expect(updated.status, 'opened');
      expect(updated.openedOn, _d(2026, 9, 28));
      expect(updated.openShelfLifeDays, 3);
      expect(updated.expiresOn, _d(2026, 10, 1)); // Oeffnungsfrist vor MHD
    });

    test('bereits geoeffnet oder aufgebraucht: kein Effekt', () async {
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: productId, ean: '1', now: DateTime.utc(2026, 9, 27));
      await repo.open(item.id);
      final afterFirst = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
      await repo.open(item.id, productDefaultOpenShelfLifeDays: 99);
      final afterSecond = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
      expect(afterSecond.openedOn, afterFirst.openedOn);
      expect(afterSecond.openShelfLifeDays, isNull);
    });
  });

  group('markConsumed / markDiscarded', () {
    test('schliesst den Eintrag und bucht die Restmenge negativ ins Ledger', () async {
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: productId, ean: '1', quantity: 3, now: DateTime.utc(2026, 9, 27));
      await repo.markConsumed(item.id, now: DateTime.utc(2026, 9, 28));
      final updated = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
      expect(updated.status, 'consumed');
      expect(updated.closedAt, isNotNull);
      final consumedMovement = (await db.select(db.inventoryMovements).get()).firstWhere((m) => m.type == 'consumed');
      expect(consumedMovement.quantityDelta, -3.0);
    });

    test('discarded verhaelt sich gleich, mit type discarded', () async {
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: productId, ean: '1', quantity: 1, now: DateTime.utc(2026, 9, 27));
      await repo.markDiscarded(item.id);
      final movement = (await db.select(db.inventoryMovements).get()).firstWhere((m) => m.type == 'discarded');
      expect(movement.quantityDelta, -1.0);
    });

    test('doppeltes Schliessen bucht nicht zweimal', () async {
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: productId, ean: '1', now: DateTime.utc(2026, 9, 27));
      await repo.markConsumed(item.id);
      await repo.markDiscarded(item.id); // schon konsumiert: kein Effekt
      final updated = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
      expect(updated.status, 'consumed');
      expect(await db.select(db.inventoryMovements).get(), hasLength(2)); // Kauf + ein Abgang
    });
  });

  group('updateDetails', () {
    test('aendert MHD, Datumsart und Lagerort, ohne Ledger-Bewegung', () async {
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: productId, ean: '1', bestBefore: _d(2026, 10, 1), now: DateTime.utc(2026, 9, 27));
      await repo.updateDetails(item.id, bestBefore: _d(2026, 10, 20), dateKind: 'use_by', location: 'fridge');
      final updated = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
      expect(updated.bestBefore, _d(2026, 10, 20));
      expect(updated.expiresOn, _d(2026, 10, 20));
      expect(updated.dateKind, 'use_by');
      expect(updated.location, 'fridge');
      expect(await db.select(db.inventoryMovements).get(), hasLength(1)); // nur der Kauf, keine neue Bewegung
    });

    test('MHD entfernen (clearBestBefore)', () async {
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: productId, ean: '1', bestBefore: _d(2026, 10, 1), now: DateTime.utc(2026, 9, 27));
      await repo.updateDetails(item.id, clearBestBefore: true);
      final updated = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
      expect(updated.bestBefore, isNull);
      expect(updated.expiresOn, isNull);
    });

    test('MHD-Aenderung wirkt sich auf einen bereits geoeffneten Eintrag aus (Oeffnungsfrist bleibt massgeblich)', () async {
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: productId, ean: '1', bestBefore: _d(2026, 10, 20), now: DateTime.utc(2026, 9, 27));
      await repo.open(item.id, productDefaultOpenShelfLifeDays: 3, now: DateTime.utc(2026, 9, 28));
      await repo.updateDetails(item.id, bestBefore: _d(2026, 9, 29)); // MHD jetzt vor der Oeffnungsfrist
      final updated = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
      expect(updated.expiresOn, _d(2026, 9, 29));
    });
  });

  group('adjustQuantity', () {
    test('bucht die Differenz als adjustment', () async {
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: productId, ean: '1', quantity: 5, now: DateTime.utc(2026, 9, 27));
      await repo.adjustQuantity(item.id, 3);
      final updated = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
      expect(updated.quantity, 3);
      final adj = (await db.select(db.inventoryMovements).get()).firstWhere((m) => m.type == 'adjustment');
      expect(adj.quantityDelta, -2.0);
    });

    test('gleiche Menge: keine Bewegung', () async {
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: productId, ean: '1', quantity: 5, now: DateTime.utc(2026, 9, 27));
      await repo.adjustQuantity(item.id, 5);
      expect(await db.select(db.inventoryMovements).get(), hasLength(1)); // nur der Kauf
    });
  });

  group('watchActive / watchSuggestions', () {
    test('Vorschlaege erscheinen nicht in watchActive, sortiert nach Ablauf', () async {
      final repo = inventoryRepo(db);
      final a = await repo.recordFromScan(productId: productId, ean: '1', bestBefore: _d(2026, 10, 20), now: DateTime.utc(2026, 9, 27));
      final b = await repo.recordFromScan(productId: productId, ean: '2', bestBefore: _d(2026, 10, 5), now: DateTime.utc(2026, 9, 27));
      await db.into(db.inventoryItems).insert(InventoryItem(
            id: 'sugg', householdId: 'h1', productId: productId, quantity: 1, unit: 'piece', location: 'pantry',
            purchasedOn: _d(2026, 9, 27), dateKind: 'best_before', status: 'sealed', isSuggestion: true, updatedAt: DateTime.utc(2026),
          ));
      final active = await repo.watchActive().first;
      expect(active.map((i) => i.id), [b.id, a.id]); // frueheres Ablaufdatum zuerst
      final suggestions = await repo.watchSuggestions().first;
      expect(suggestions.map((i) => i.id), ['sugg']);
    });

    test('geschlossene und geloeschte Eintraege erscheinen nicht', () async {
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: productId, ean: '1', now: DateTime.utc(2026, 9, 27));
      await repo.markConsumed(item.id);
      expect(await repo.watchActive().first, isEmpty);
    });
  });

  test('discardSuggestion loescht nur Vorschlaege', () async {
    final repo = inventoryRepo(db);
    await db.into(db.inventoryItems).insert(InventoryItem(
          id: 'sugg', householdId: 'h1', productId: productId, quantity: 1, unit: 'piece', location: 'pantry',
          purchasedOn: _d(2026, 9, 27), dateKind: 'best_before', status: 'sealed', isSuggestion: true, updatedAt: DateTime.utc(2026),
        ));
    await repo.discardSuggestion('sugg');
    expect((await (db.select(db.inventoryItems)..where((i) => i.id.equals('sugg'))).getSingle()).deletedAt, isNotNull);

    final real = await repo.recordFromScan(productId: productId, ean: '1', now: DateTime.utc(2026, 9, 27));
    await repo.discardSuggestion(real.id); // kein Vorschlag: kein Effekt
    expect((await (db.select(db.inventoryItems)..where((i) => i.id.equals(real.id))).getSingle()).deletedAt, isNull);
  });

  group('deleteItem', () {
    test('loescht den Eintrag und seine Kaufbewegung, so als waere der Scan nie passiert', () async {
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: productId, ean: '1', quantity: 2, now: DateTime.utc(2026, 9, 27));
      expect(await db.select(db.inventoryMovements).get(), hasLength(1));

      await repo.deleteItem(item.id);
      final row = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
      expect(row.deletedAt, isNotNull);
      expect(await (db.select(db.inventoryMovements)..where((m) => m.deletedAt.isNull())).get(), isEmpty);
      expect(await repo.watchActive().first, isEmpty);
    });

    test('spaetere Bewegungen (z.B. eine Korrektur) werden ebenfalls entfernt', () async {
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: productId, ean: '1', quantity: 2, now: DateTime.utc(2026, 9, 27));
      await repo.adjustQuantity(item.id, 5);
      expect(await db.select(db.inventoryMovements).get(), hasLength(2));

      await repo.deleteItem(item.id);
      expect(await (db.select(db.inventoryMovements)..where((m) => m.deletedAt.isNull())).get(), isEmpty);
    });

    test('landet in der Outbox (Eintrag und Bewegung)', () async {
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: productId, ean: '1', now: DateTime.utc(2026, 9, 27));
      await db.delete(db.outbox).go();
      await repo.deleteItem(item.id);
      final tables = (await db.select(db.outbox).get()).map((o) => o.remoteTable).toSet();
      expect(tables, {'inventory_items', 'inventory_movements'});
    });
  });

  group('Sync', () {
    test('Inventareintrag und Bewegung kommen auf einem zweiten Geraet an', () async {
      final remote = FakeRemoteStore();
      final repo = inventoryRepo(db);
      await productRepo(db).linkBarcode('9008700000003', productId); // damit db2 dasselbe Produkt kennt
      await SyncEngine(db, remote).sync();
      final item = await repo.recordFromScan(productId: productId, ean: '9008700000003', bestBefore: _d(2026, 10, 10), now: DateTime.utc(2026, 9, 27));
      await SyncEngine(db, remote).sync();

      final db2 = memoryDb();
      addTearDown(db2.close);
      await SyncEngine(db2, remote).sync();
      final synced = await (db2.select(db2.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
      expect(synced.expiresOn, _d(2026, 10, 10));
      expect(await db2.select(db2.inventoryMovements).get(), hasLength(1));
    });
  });
}
