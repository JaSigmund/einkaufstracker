import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  late AppDatabase db;
  late FakeRemoteStore remote;
  late SyncEngine engine;

  setUp(() {
    db = memoryDb();
    remote = FakeRemoteStore();
    engine = SyncEngine(db, remote);
  });
  tearDown(() => db.close());

  Future<int> outboxCount() async => (await db.select(db.outbox).get()).length;
  Future<List<String>> names() async => (await categoryRepo(db).watchAll().first).map((c) => c.name).toList();

  group('Offline schreiben (Repository)', () {
    test('Anlegen wirkt sofort lokal und landet in der Outbox, ohne dass ein Server noetig ist', () async {
      final repo = categoryRepo(db);
      await repo.add('Obst');
      await repo.add('Gemüse');
      expect(await names(), ['Obst', 'Gemüse']); // Reihenfolge nach sortOrder
      expect(await outboxCount(), 2);
      expect(remote.table('categories'), isEmpty);
    });

    test('Doppelter Name wird abgelehnt, leerer Name ebenso', () async {
      final repo = categoryRepo(db);
      await repo.add('Obst');
      expect(() => repo.add('Obst'), throwsA(isA<Exception>()));
      expect(() => repo.add('   '), throwsArgumentError);
    });

    test('onChanged wird nach jeder Aenderung aufgerufen (loest den Sync aus)', () async {
      var calls = 0;
      final repo = categoryRepo(db, onChanged: () => calls++);
      await repo.add('Obst');
      final c = (await repo.watchAll().first).single;
      await repo.rename(c.id, 'Früchte');
      await repo.softDelete(c.id);
      expect(calls, 3);
    });

    test('Geloeschte Kategorie gleichen Namens wird wieder aktiviert statt doppelt angelegt', () async {
      final repo = categoryRepo(db);
      await repo.add('Obst');
      final id = (await repo.watchAll().first).single.id;
      await repo.softDelete(id);
      expect(await names(), isEmpty);
      await repo.add('Obst');
      expect(await names(), ['Obst']);
      expect((await db.select(db.categories).get()).length, 1); // keine zweite Zeile
    });
  });

  group('Push', () {
    test('Outbox wird zum Server geschickt und danach geleert', () async {
      final repo = categoryRepo(db);
      await repo.add('Obst');
      final result = await engine.sync();
      expect(result.pushed, 1);
      expect(await outboxCount(), 0);
      final row = remote.table('categories').values.single;
      expect(row['name'], 'Obst');
      expect(row['household_id'], 'h1');
      expect(row['deleted_at'], isNull);
    });

    test('Netzfehler: Outbox bleibt erhalten, spaeter geht alles in der richtigen Reihenfolge durch', () async {
      final repo = categoryRepo(db);
      await repo.add('A');
      await repo.add('B');
      remote.offline = true;
      await expectLater(engine.sync(), throwsA(isA<Exception>()));
      expect(await outboxCount(), 2);
      expect(engine.isRunning, isFalse); // Sperre wird auch nach Fehler freigegeben

      remote.offline = false;
      await engine.sync();
      expect(await outboxCount(), 0);
      expect(remote.table('categories').values.map((r) => r['name']).toSet(), {'A', 'B'});
    });

    test('Datenfehler (Unique-Verletzung) blockiert die Queue nicht und wird markiert', () async {
      // Auf dem Server gibt es "Obst" schon unter anderer ID (z.B. von einem anderen Geraet)
      await remote.upsert('categories', {
        'id': 'fremd', 'household_id': 'h1', 'name': 'Obst', 'sort_order': 0, 'is_storable': true,
        'updated_at': '2026-01-01T00:00:00Z', 'deleted_at': null, 'parent_id': null, 'icon': null,
      });
      final repo = categoryRepo(db);
      await repo.add('Obst'); // lokal noch unbekannt, kollidiert beim Senden
      await repo.add('Gemüse');
      final result = await engine.sync();
      expect(result.pushed, 1);
      expect(result.skipped, 1);
      final left = await db.select(db.outbox).get();
      expect(left.length, 1);
      expect(left.single.lastError, contains('23505'));
      expect(left.single.attempts, 1);
      expect(remote.table('categories').values.any((r) => r['name'] == 'Gemüse'), isTrue);
    });

    test('Umbenennen und Loeschen kommen als Aenderung beim Server an', () async {
      final repo = categoryRepo(db);
      await repo.add('Obst');
      await engine.sync();
      final c = (await repo.watchAll().first).single;
      await repo.rename(c.id, 'Früchte');
      await engine.sync();
      expect(remote.table('categories')[c.id]!['name'], 'Früchte');
      await repo.softDelete(c.id);
      await engine.sync();
      expect(remote.table('categories')[c.id]!['deleted_at'], isNotNull);
    });
  });

  group('Pull', () {
    test('Zweites Geraet (Neuinstallation) findet die Daten des ersten wieder', () async {
      final repo = categoryRepo(db);
      await repo.add('Obst');
      await repo.add('Gemüse');
      await engine.sync();

      final db2 = memoryDb();
      addTearDown(db2.close);
      final result = await SyncEngine(db2, remote).sync();
      expect(result.pulled, 2);
      expect((await categoryRepo(db2).watchAll().first).map((c) => c.name), containsAll(['Obst', 'Gemüse']));
    });

    test('Folge-Sync holt nur neue Aenderungen und merkt sich den Stand je Tabelle', () async {
      final repo = categoryRepo(db);
      await repo.add('Obst');
      await engine.sync();
      final db2 = memoryDb();
      addTearDown(db2.close);
      final e2 = SyncEngine(db2, remote);
      await e2.sync();
      final state = await (db2.select(db2.syncStates)..where((t) => t.remoteTable.equals('categories'))).getSingle();
      expect(state.lastPulledAt, isNotNull);

      await repo.add('Fleisch');
      await engine.sync();
      final r = await e2.sync();
      // wegen >= wird die zuletzt gesehene Zeile nochmal geliefert, idempotent, keine Duplikate
      expect((await categoryRepo(db2).watchAll().first).map((c) => c.name).toSet(), {'Obst', 'Fleisch'});
      expect(r.pulled, greaterThanOrEqualTo(1));
    });

    test('Geloeschte Zeilen vom Server werden lokal ausgeblendet', () async {
      final repo = categoryRepo(db);
      await repo.add('Obst');
      await engine.sync();
      final db2 = memoryDb();
      addTearDown(db2.close);
      final e2 = SyncEngine(db2, remote);
      await e2.sync();

      final c = (await repo.watchAll().first).single;
      await repo.softDelete(c.id);
      await engine.sync();
      await e2.sync();
      expect(await categoryRepo(db2).watchAll().first, isEmpty);
    });

    test('Lokale, noch nicht gesendete Aenderung wird vom Pull nicht ueberschrieben', () async {
      final repo = categoryRepo(db);
      await repo.add('Obst');
      await engine.sync();
      final c = (await repo.watchAll().first).single;

      // anderes Geraet aendert den Namen auf dem Server
      final db2 = memoryDb();
      addTearDown(db2.close);
      final e2 = SyncEngine(db2, remote);
      await e2.sync();
      await categoryRepo(db2).rename(c.id, 'Von Geraet B');
      await e2.sync();

      // dieses Geraet aendert offline ebenfalls (noch in der Outbox) und holt dann
      await repo.rename(c.id, 'Von Geraet A');
      remote.offline = false;
      await engine.sync(); // Push zuerst: Geraet A gewinnt (Last-write-wins), danach Pull
      expect(remote.table('categories')[c.id]!['name'], 'Von Geraet A');
      expect(await names(), ['Von Geraet A']);
    });

    test('Pull ohne Netz wirft und laesst lokale Daten unberuehrt', () async {
      final repo = categoryRepo(db);
      await repo.add('Obst');
      remote.offline = true;
      await expectLater(engine.sync(), throwsA(isA<Exception>()));
      expect(await names(), ['Obst']);
    });
  });

  group('Produkte (Pilot-Tabelle)', () {
    test('Produkt vom Server wird lokal gespeichert', () async {
      await remote.upsert('products', {
        'id': 'p1', 'household_id': 'h1', 'name': 'Paprika rot', 'brand': null, 'category_id': null,
        'base_unit': 'kg', 'pack_size': null, 'deleted_at': null,
      });
      await engine.sync();
      final p = await db.select(db.products).getSingle();
      expect(p.name, 'Paprika rot');
      expect(p.baseUnit, 'kg');
    });
  });

  test('wipe() entfernt alle lokalen Daten (Abmelden)', () async {
    final repo = categoryRepo(db);
    await repo.add('Obst');
    await db.setKv('household_id', 'h1');
    await db.wipe();
    expect(await names(), isEmpty);
    expect(await outboxCount(), 0);
    expect(await db.getKv('household_id'), isNull);
  });
}
