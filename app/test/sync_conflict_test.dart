import 'dart:io';

import 'package:einkaufstracker/core/clock.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Konflikterkennung beim Senden (ADR-018, Phase 6): Last-write-wins bleibt, aber eine Aenderung, die eine neuere fremde
/// Aenderung ueberschreibt, wird gemeldet. Zwei Geraete (a und b) arbeiten gegen denselben Server.
void main() {
  late AppDatabase a;
  late AppDatabase b;
  late FakeRemoteStore remote;
  late SyncEngine engineA;
  late SyncEngine engineB;

  setUp(() {
    a = memoryDb();
    b = memoryDb();
    remote = FakeRemoteStore();
    engineA = SyncEngine(a, remote);
    engineB = SyncEngine(b, remote);
  });
  tearDown(() async {
    await a.close();
    await b.close();
  });

  Future<String> addCategory(AppDatabase db, String name) async {
    await categoryRepo(db).add(name);
    return (await db.select(db.categories).get()).firstWhere((c) => c.name == name).id;
  }

  /// A legt "Obst" an, beide Geraete kennen es danach.
  Future<String> shared() async {
    final id = await addCategory(a, 'Obst');
    await engineA.sync();
    await engineB.sync();
    return id;
  }

  test('allein: eigene Aenderungen sind nie ein Konflikt, auch nicht bei wiederholtem Aendern', () async {
    final id = await shared();
    for (final name in ['Früchte', 'Obst & Gemüse', 'Gemüse']) {
      await categoryRepo(a).rename(id, name);
      final r = await engineA.sync();
      expect(r.conflicts, isEmpty, reason: name);
    }
  });

  test('erster Sync (Tabelle noch nie geholt): kein Konflikt und keine zusaetzliche Anfrage', () async {
    await addCategory(a, 'Obst');
    final r = await engineA.sync();
    expect(r.conflicts, isEmpty);
    expect(remote.updatedAtLookups, 0);
  });

  test('neu angelegte Zeilen (gibt es beim Server noch nicht) sind kein Konflikt', () async {
    await shared();
    await addCategory(a, 'Gemüse');
    expect((await engineA.sync()).conflicts, isEmpty);
  });

  test('jemand anderes hat dieselbe Zeile seit dem letzten Holen geaendert: Konflikt, die eigene Aenderung gewinnt trotzdem', () async {
    final id = await shared();
    await categoryRepo(a).rename(id, 'Früchte');
    await engineA.sync(); // A schreibt zuerst

    await categoryRepo(b).rename(id, 'Fruits'); // B hat A's Aenderung noch nicht geholt
    final r = await engineB.sync();

    expect(r.conflicts, [(table: 'categories', rowId: id)]);
    expect(remote.table('categories')[id]!['name'], 'Fruits', reason: 'Last-write-wins: die spaetere Aenderung gilt');
    expect(r.pushed, 1, reason: 'der Konflikt blockiert das Senden nicht');
    expect((await b.select(b.outbox).get()), isEmpty);
  });

  test('wer vorher geholt hat, ueberschreibt nichts Unbekanntes: kein Konflikt', () async {
    final id = await shared();
    await categoryRepo(a).rename(id, 'Früchte');
    await engineA.sync();

    await engineB.sync(); // B holt A's Aenderung zuerst
    await categoryRepo(b).rename(id, 'Fruits');
    expect((await engineB.sync()).conflicts, isEmpty);
    expect(remote.table('categories')[id]!['name'], 'Fruits');
  });

  test('Konflikt auch, wenn die fremde Aenderung ein Loeschen war', () async {
    final id = await shared();
    await categoryRepo(a).softDelete(id);
    await engineA.sync();

    await categoryRepo(b).rename(id, 'Fruits');
    expect((await engineB.sync()).conflicts, [(table: 'categories', rowId: id)]);
  });

  test('derselbe Konflikt wird nur einmal gemeldet, auch bei mehreren wartenden Aenderungen derselben Zeile', () async {
    final id = await shared();
    await categoryRepo(a).rename(id, 'Früchte');
    await engineA.sync();

    await categoryRepo(b).rename(id, 'Fruits');
    await categoryRepo(b).rename(id, 'Fruit');
    final r = await engineB.sync();
    expect(r.conflicts, hasLength(1));
    expect(r.pushed, 2);
  });

  test('mehrere betroffene Zeilen werden alle gemeldet', () async {
    final o = await addCategory(a, 'Obst');
    final g = await addCategory(a, 'Gemüse');
    await engineA.sync();
    await engineB.sync();
    await categoryRepo(a).rename(o, 'Früchte');
    await categoryRepo(a).rename(g, 'Grünzeug');
    await engineA.sync();

    await categoryRepo(b).rename(o, 'Fruits');
    await categoryRepo(b).rename(g, 'Greens');
    final r = await engineB.sync();
    expect({for (final c in r.conflicts) c.rowId}, {o, g});
  });

  test('je Tabelle mit wartenden Aenderungen genau eine Anfrage, nicht je Zeile', () async {
    final ids = [for (var i = 0; i < 5; i++) await addCategory(a, 'K$i')];
    await engineA.sync();
    remote.updatedAtLookups = 0;
    for (final id in ids) {
      await categoryRepo(a).rename(id, 'neu-$id');
    }
    await engineA.sync();
    expect(remote.updatedAtLookups, 1);
  });

  test('ohne wartende Aenderungen gibt es keine Anfrage', () async {
    await shared();
    remote.updatedAtLookups = 0;
    await engineA.sync();
    expect(remote.updatedAtLookups, 0);
  });

  test('mehr als 100 Zeilen werden in Stuecken abgefragt', () async {
    final ids = <String>[];
    for (var i = 0; i < 120; i++) {
      ids.add(await addCategory(a, 'K$i'));
    }
    await engineA.sync();
    remote.updatedAtLookups = 0;
    for (final id in ids) {
      await categoryRepo(a).rename(id, 'n-$id');
    }
    final r = await engineA.sync();
    expect(remote.updatedAtLookups, 2, reason: '100 + 20');
    expect(r.conflicts, isEmpty);
    expect(r.pushed, 120);
  });

  test('Tabellen mit zusammengesetztem Schluessel (Barcodes) werden nicht nachgeschlagen', () async {
    final product = await productRepo(a).create(name: 'Reis', baseUnit: 'kg');
    await engineA.sync();
    remote.updatedAtLookups = 0;
    await productRepo(a).linkBarcode('9001234567890', product.id);
    final r = await engineA.sync();
    expect(r.conflicts, isEmpty);
    expect(remote.updatedAtLookups, 0, reason: 'nur product_barcodes wartet, und die hat keine Spalte id');
  });

  test('scheitert nur die Abfrage der Zeitstempel (unerwartete Antwort, Rechte): gesendet wird trotzdem, kein Konflikt gemeldet', () async {
    final id = await shared();
    await categoryRepo(a).rename(id, 'Früchte');
    await engineA.sync();
    await categoryRepo(b).rename(id, 'Fruits'); // waere ein Konflikt
    remote.failLookupFor.add('categories');
    final r = await engineB.sync();
    expect(r.pushed, 1, reason: 'die Erkennung darf das Senden nie verhindern');
    expect(r.conflicts, isEmpty);
    expect(remote.table('categories')[id]!['name'], 'Fruits');
    expect(await b.select(b.outbox).get(), isEmpty);
  });

  test('scheitert die Abfrage nur bei einer Tabelle, bleiben die Konflikte der anderen erhalten', () async {
    final id = await shared();
    await productRepo(a).create(name: 'Reis', baseUnit: 'kg');
    await engineA.sync();
    await engineB.sync();
    final onA = (await a.select(a.products).get()).single;
    await categoryRepo(a).rename(id, 'Früchte');
    await productRepo(a).update(onA.copyWith(name: 'Basmati', updatedAt: appClock.now().toUtc()));
    await engineA.sync();

    await categoryRepo(b).rename(id, 'Fruits');
    final onB = (await b.select(b.products).get()).single;
    await productRepo(b).update(onB.copyWith(name: 'Langkorn', updatedAt: appClock.now().toUtc()));
    remote.failLookupFor.add('products');
    final r = await engineB.sync();

    expect({for (final c in r.conflicts) c.table}, {'categories'});
    expect(r.pushed, 2);
  });

  test('Netzfehler bei der Abfrage bricht den Sync ab wie jeder andere, die Aenderung bleibt in der Outbox', () async {
    final id = await shared();
    await categoryRepo(a).rename(id, 'Früchte');
    remote.offline = true;
    await expectLater(engineA.sync(), throwsA(isA<SocketException>()));
    expect(await a.select(a.outbox).get(), hasLength(1));
    remote.offline = false;
    final r = await engineA.sync();
    expect(r.pushed, 1);
  });

  test('eigener Schreibvorgang gilt als bekannt, auch wenn das Holen danach scheiterte', () async {
    final id = await shared();
    await categoryRepo(a).rename(id, 'Früchte');
    // A sendet, aber das Holen schlaegt fehl: lastPulledAt bleibt auf dem alten Stand
    remote.failFetch = true;
    await expectLater(engineA.sync(), throwsA(isA<SocketException>()));
    remote.failFetch = false;
    expect(remote.table('categories')[id]!['name'], 'Früchte', reason: 'gesendet wurde trotzdem');

    await categoryRepo(a).rename(id, 'Obst & Gemüse');
    final r = await engineA.sync();
    expect(r.conflicts, isEmpty, reason: 'die Zeile ist beim Server nur durch A selbst neuer');
  });
}
