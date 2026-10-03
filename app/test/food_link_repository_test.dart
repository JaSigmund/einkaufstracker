import 'dart:convert';

import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/nutrition/bls_food_search.dart';
import 'package:einkaufstracker/data/sync/sync_engine.dart';
import 'package:einkaufstracker/domain/nutrition/nutrient_scaling.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Gedaechtnis des Haushalts (Phase N1, ADR-031): Name -> BLS-Eintrag, offline-first ueber die Outbox. Dazu das Produktprofil
/// aus einem BLS-Eintrag (`setBlsProfile`).
void main() {
  late AppDatabase db;

  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  Future<List<Map<String, dynamic>>> queued() async =>
      [for (final e in await db.select(db.outbox).get()) if (e.remoteTable == 'household_food_links') jsonDecode(e.payload) as Map<String, dynamic>];

  group('learn', () {
    test('legt die Zuordnung an und stellt sie in die Outbox', () async {
      var changed = 0;
      final repo = foodLinkRepo(db, onChanged: () => changed++);
      await repo.learn('Quark', 'M713300');

      final links = await repo.all();
      expect(links, hasLength(1));
      expect(links.single.nameNorm, 'Quark', reason: 'lokal steht der Name, wie der Nutzer ihn sah');
      expect(links.single.blsCode, 'M713300');
      expect(links.single.householdId, 'h1');
      expect(links.single.deletedAt, isNull);

      final out = await queued();
      expect(out, hasLength(1));
      expect(out.single['name_norm'], 'Quark');
      expect(out.single['bls_code'], 'M713300');
      expect(out.single['household_id'], 'h1');
      expect(out.single['deleted_at'], isNull);
      expect(changed, 1);
    });

    test('Leerer Name oder leerer Code: nichts passiert', () async {
      var changed = 0;
      final repo = foodLinkRepo(db, onChanged: () => changed++);
      await repo.learn('   ', 'M713300');
      await repo.learn('Quark', '');
      expect(await repo.all(), isEmpty);
      expect(await queued(), isEmpty);
      expect(changed, 0);
    });

    test('derselbe Name mit anderem Eintrag ersetzt die Zuordnung (gleiche Zeile, kein Duplikat)', () async {
      final repo = foodLinkRepo(db);
      await repo.learn('Quark', 'M713300');
      final id = (await repo.all()).single.id;
      await repo.learn('Quark', 'M713100');

      final links = await repo.all();
      expect(links, hasLength(1));
      expect(links.single.id, id);
      expect(links.single.blsCode, 'M713100');
      expect(await queued(), hasLength(2));
    });

    test('gleiche Zuordnung noch einmal: nichts in der Outbox, kein Sync-Anstoss', () async {
      var changed = 0;
      final repo = foodLinkRepo(db, onChanged: () => changed++);
      await repo.learn('Quark', 'M713300');
      await repo.learn('Quark', 'M713300');
      expect(await queued(), hasLength(1));
      expect(changed, 1);
    });

    test('Gross- und Kleinschreibung zaehlt nicht: "quark" und "Quark" sind dieselbe Zuordnung', () async {
      final repo = foodLinkRepo(db);
      await repo.learn('Quark', 'M713300');
      await repo.learn('quark', 'M713100');
      final links = await repo.all();
      expect(links, hasLength(1));
      expect(links.single.blsCode, 'M713100');
      await repo.learn('QUARK', 'M713100');
      expect(await queued(), hasLength(2), reason: 'gleicher Code: nichts Neues');
    });

    test('Leerzeichen am Rand werden entfernt', () async {
      final repo = foodLinkRepo(db);
      await repo.learn('  Quark  ', 'M713300');
      expect((await repo.all()).single.nameNorm, 'Quark');
    });
  });

  group('forget', () {
    test('vergisst per Soft-Delete (der Sync bringt das auf andere Geraete) und meldet die Aenderung', () async {
      var changed = 0;
      final repo = foodLinkRepo(db, onChanged: () => changed++);
      await repo.learn('Quark', 'M713300');
      final id = (await repo.all()).single.id;
      await repo.forget(id);

      expect(await repo.all(), isEmpty);
      final row = await db.select(db.householdFoodLinks).getSingle();
      expect(row.deletedAt, isNotNull, reason: 'Zeile bleibt, damit der Sync sie weitergeben kann');
      final out = await queued();
      expect(out.last['deleted_at'], isNotNull);
      expect(changed, 2);
    });

    test('unbekannte oder schon vergessene Zuordnung: nichts passiert', () async {
      final repo = foodLinkRepo(db);
      await repo.forget('gibt-es-nicht');
      await repo.learn('Quark', 'M713300');
      final id = (await repo.all()).single.id;
      await repo.forget(id);
      final count = (await queued()).length;
      await repo.forget(id);
      expect((await queued()).length, count);
    });

    test('nach dem Vergessen laesst sich derselbe Name neu lernen', () async {
      final repo = foodLinkRepo(db);
      await repo.learn('Quark', 'M713300');
      await repo.forget((await repo.all()).single.id);
      await repo.learn('Quark', 'M713100');
      final links = await repo.all();
      expect(links, hasLength(1));
      expect(links.single.blsCode, 'M713100');
    });
  });

  test('watchAll liefert die aktiven Zuordnungen alphabetisch', () async {
    final repo = foodLinkRepo(db);
    await repo.learn('Skyr', 'M710100');
    await repo.learn('Quark', 'M713300');
    expect((await repo.watchAll().first).map((l) => l.nameNorm), ['Quark', 'Skyr']);
  });

  group('Sync', () {
    test('wandert zum Server und, mit der normalisierten Fassung des Servers, wieder zurueck', () async {
      final remote = FakeRemoteStore();
      final engine = SyncEngine(db, remote);
      final repo = foodLinkRepo(db);
      await repo.learn('Quark', 'M713300');
      await engine.sync();

      final stored = remote.table('household_food_links').values.single;
      expect(stored['name_norm'], 'Quark');
      expect(stored['bls_code'], 'M713300');
      expect(await db.select(db.outbox).get(), isEmpty);

      // der Server-Trigger macht aus dem Namen den Schluessel, ein anderes Geraet bringt neue Zeilen mit
      remote.simulateOtherEdit('household_food_links', stored['id'] as String, {'name_norm': 'quark'});
      remote.table('household_food_links')['x1'] = {
        'id': 'x1',
        'household_id': 'h1',
        'name_norm': 'skyr',
        'bls_code': 'M710100',
        'updated_at': DateTime.utc(2026, 10, 3).toIso8601String(),
        'deleted_at': null,
      };
      await engine.sync();

      final names = {for (final l in await repo.all()) l.nameNorm: l.blsCode};
      expect(names, {'quark': 'M713300', 'skyr': 'M710100'});
    });

    test('Vergessen auf einem Geraet wird auf dem anderen uebernommen', () async {
      final remote = FakeRemoteStore();
      final a = memoryDb();
      addTearDown(a.close);
      final repoA = foodLinkRepo(a);
      final engineA = SyncEngine(a, remote);
      final engineB = SyncEngine(db, remote);

      await repoA.learn('Quark', 'M713300');
      await engineA.sync();
      await engineB.sync();
      expect(await foodLinkRepo(db).all(), hasLength(1));

      await repoA.forget((await repoA.all()).single.id);
      await engineA.sync();
      await engineB.sync();
      expect(await foodLinkRepo(db).all(), isEmpty);
    });
  });

  group('setBlsProfile', () {
    const milch = BlsFood(
      code: 'M111300',
      nameDe: 'Vollmilch frisch, 3,5 % Fett',
      per100: NutrientsPer100(kcal: 65, proteinG: 3.4, fatG: 3.6, satFatG: 2.3, carbsG: 4.7, sugarG: 4.7, fiberG: 0, saltG: 0.1),
    );

    test('kopiert das Profil als Snapshot ins Produkt, setzt Herkunft, Basis und Code und stellt es in die Outbox', () async {
      var changed = 0;
      final products = productRepo(db, onChanged: () => changed++);
      final p = await products.create(name: 'Milch', baseUnit: 'l');
      final before = (await db.select(db.outbox).get()).length;

      final updated = await products.setBlsProfile(p.id, milch);

      expect(updated, isNotNull);
      final row = await products.byId(p.id);
      final profile = jsonDecode(row!.nutrientsPer100!) as Map<String, dynamic>;
      expect(profile['kcal'], 65);
      expect(profile['protein_g'], 3.4);
      expect(profile['sat_fat_g'], 2.3);
      expect(profile['salt_g'], 0.1);
      expect(row.nutrientsBasis, 'g');
      expect(row.nutrientsSource, 'bls');
      expect(row.blsCode, 'M111300');
      expect((await db.select(db.outbox).get()).length, before + 1);
      expect(changed, greaterThan(0));
    });

    test('ein vorhandenes Profil bleibt, ausser mit overwrite', () async {
      final products = productRepo(db);
      final p = await products.create(name: 'Reis', baseUnit: 'kg', nutrientsPer100: {'kcal': 350}, nutrientsBasis: 'g', nutrientsSource: 'off');

      expect(await products.setBlsProfile(p.id, milch), isNull);
      expect((await products.byId(p.id))!.nutrientsSource, 'off');
      expect(jsonDecode((await products.byId(p.id))!.nutrientsPer100!)['kcal'], 350);

      expect(await products.setBlsProfile(p.id, milch, overwrite: true), isNotNull);
      expect((await products.byId(p.id))!.nutrientsSource, 'bls');
      expect(jsonDecode((await products.byId(p.id))!.nutrientsPer100!)['kcal'], 65);
    });

    test('unbekanntes oder geloeschtes Produkt und Eintrag ohne Naehrwerte: null, nichts veraendert', () async {
      final products = productRepo(db);
      expect(await products.setBlsProfile('gibt-es-nicht', milch), isNull);

      final p = await products.create(name: 'Gewuerz', baseUnit: 'g');
      const leer = BlsFood(code: 'R1', nameDe: 'Leer', per100: NutrientsPer100());
      expect(await products.setBlsProfile(p.id, leer), isNull);
      expect((await products.byId(p.id))!.nutrientsPer100, isNull);

      await products.softDelete(p.id);
      expect(await products.setBlsProfile(p.id, milch), isNull);
    });

    test('nur die vorhandenen Werte stehen im Profil', () async {
      final products = productRepo(db);
      final p = await products.create(name: 'Wasser', baseUnit: 'l');
      await products.setBlsProfile(p.id, const BlsFood(code: 'N1', nameDe: 'Mineralwasser', per100: NutrientsPer100(kcal: 0, saltG: 0.01)));
      final profile = jsonDecode((await products.byId(p.id))!.nutrientsPer100!) as Map<String, dynamic>;
      expect(profile.keys.toSet(), {'kcal', 'salt_g'});
    });
  });

  group('Stueckgewicht (Phase N2)', () {
    test('setUnitWeight legt die Zuordnung samt Gewicht an und stellt sie in die Outbox', () async {
      var changed = 0;
      final repo = foodLinkRepo(db, onChanged: () => changed++);
      await repo.setUnitWeight('Banane', 'F503100', 135);

      final link = (await repo.all()).single;
      expect(link.nameNorm, 'Banane');
      expect(link.blsCode, 'F503100');
      expect(link.unitWeightG, 135);
      final out = await queued();
      expect(out.single['unit_weight_g'], 135);
      expect(out.single['bls_code'], 'F503100');
      expect(changed, 1);
    });

    test('unitWeightForCode: egal unter welchem Namen, das juengste Gewicht gilt, ohne Gewicht null', () async {
      final repo = foodLinkRepo(db);
      expect(await repo.unitWeightForCode('F503100'), isNull);
      await repo.learn('Banane', 'F503100');
      expect(await repo.unitWeightForCode('F503100'), isNull, reason: 'Zuordnung ohne Gewicht');
      await repo.setUnitWeight('Banane', 'F503100', 120);
      expect(await repo.unitWeightForCode('F503100'), 120);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repo.setUnitWeight('Bananen klein', 'F503100', 95);
      expect(await repo.unitWeightForCode('F503100'), 95, reason: 'das juengste gilt');
      expect(await repo.unitWeightForCode('B311000'), isNull);
    });

    test('dasselbe Gewicht noch einmal: nichts in der Outbox; ein anderes aendert dieselbe Zeile', () async {
      final repo = foodLinkRepo(db);
      await repo.setUnitWeight('Banane', 'F503100', 135);
      await repo.setUnitWeight('Banane', 'F503100', 135);
      expect(await queued(), hasLength(1));
      await repo.setUnitWeight('banane', 'F503100', 140);
      expect(await repo.all(), hasLength(1));
      expect((await repo.all()).single.unitWeightG, 140);
      expect(await queued(), hasLength(2));
    });

    test('bestehende Zuordnung ohne Gewicht bekommt das Gewicht, der Code bleibt', () async {
      final repo = foodLinkRepo(db);
      await repo.learn('Quark', 'M713300');
      await repo.setUnitWeight('Quark', 'M713300', 250);
      final link = (await repo.all()).single;
      expect([link.blsCode, link.unitWeightG], ['M713300', 250]);
    });

    test('learn mit demselben Code behaelt das Gewicht, mit anderem Code faellt es weg', () async {
      final repo = foodLinkRepo(db);
      await repo.setUnitWeight('Banane', 'F503100', 135);
      await repo.learn('Banane', 'F503100');
      expect((await repo.all()).single.unitWeightG, 135, reason: 'gleiche Zuordnung: nichts aendert sich');
      await repo.learn('Banane', 'F504100');
      final link = (await repo.all()).single;
      expect(link.blsCode, 'F504100');
      expect(link.unitWeightG, isNull, reason: 'das Gewicht galt dem alten Lebensmittel');
    });

    test('setUnitWeight mit anderem Code ersetzt Code und Gewicht', () async {
      final repo = foodLinkRepo(db);
      await repo.learn('Banane', 'F503100');
      await repo.setUnitWeight('Banane', 'F504100', 20);
      final link = (await repo.all()).single;
      expect([link.blsCode, link.unitWeightG], ['F504100', 20]);
    });

    test('Unsinn wird ignoriert: leerer Name oder Code, Gewicht 0, negativ oder ueber 5 kg', () async {
      final repo = foodLinkRepo(db);
      await repo.setUnitWeight('  ', 'F503100', 100);
      await repo.setUnitWeight('Banane', '', 100);
      await repo.setUnitWeight('Banane', 'F503100', 0);
      await repo.setUnitWeight('Banane', 'F503100', -5);
      await repo.setUnitWeight('Banane', 'F503100', 5001);
      expect(await repo.all(), isEmpty);
      expect(await queued(), isEmpty);
    });

    test('ein vergessenes Gewicht zaehlt nicht mehr', () async {
      final repo = foodLinkRepo(db);
      await repo.setUnitWeight('Banane', 'F503100', 135);
      await repo.forget((await repo.all()).single.id);
      expect(await repo.unitWeightForCode('F503100'), isNull);
    });

    test('das Gewicht wandert mit dem Sync auf das andere Geraet', () async {
      final remote = FakeRemoteStore();
      final other = memoryDb();
      addTearDown(other.close);
      final repoA = foodLinkRepo(db);
      await repoA.setUnitWeight('Banane', 'F503100', 135);
      await SyncEngine(db, remote).sync();
      expect(remote.table('household_food_links').values.single['unit_weight_g'], 135);

      await SyncEngine(other, remote).sync();
      expect(await foodLinkRepo(other).unitWeightForCode('F503100'), 135);
    });
  });

  group('Produkt-Stueckgewicht (Phase N2)', () {
    test('setUnitWeight speichert das Gewicht am Produkt und stellt es in die Outbox', () async {
      var changed = 0;
      final products = productRepo(db, onChanged: () => changed++);
      final p = await products.create(name: 'Ei', baseUnit: 'piece');
      final before = (await db.select(db.outbox).get()).length;

      final updated = await products.setUnitWeight(p.id, 58);

      expect(updated?.unitWeightG, 58);
      expect((await products.byId(p.id))!.unitWeightG, 58);
      expect((await db.select(db.outbox).get()).length, before + 1);
      expect(changed, greaterThan(0));
    });

    test('dasselbe Gewicht noch einmal: nichts in der Outbox', () async {
      final products = productRepo(db);
      final p = await products.create(name: 'Ei', baseUnit: 'piece');
      await products.setUnitWeight(p.id, 58);
      final count = (await db.select(db.outbox).get()).length;
      await products.setUnitWeight(p.id, 58);
      expect((await db.select(db.outbox).get()).length, count);
    });

    test('unbekanntes oder geloeschtes Produkt und sinnlose Gewichte: null', () async {
      final products = productRepo(db);
      expect(await products.setUnitWeight('gibt-es-nicht', 58), isNull);
      final p = await products.create(name: 'Ei', baseUnit: 'piece');
      expect(await products.setUnitWeight(p.id, 0), isNull);
      expect(await products.setUnitWeight(p.id, -1), isNull);
      expect(await products.setUnitWeight(p.id, 5001), isNull);
      expect((await products.byId(p.id))!.unitWeightG, isNull);
      await products.softDelete(p.id);
      expect(await products.setUnitWeight(p.id, 58), isNull);
    });
  });
}
