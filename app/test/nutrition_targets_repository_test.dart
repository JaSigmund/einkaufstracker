import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/sync/sync_engine.dart';
import 'package:einkaufstracker/domain/nutrition/nutrition_targets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Richtwerte (LH-MEAL-09): offline gespeichert, ueber die Outbox synchronisiert, nie vorbelegt.
void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  const kcal = NutrientTarget(min: 1800, max: 2200);
  const protein = NutrientTarget(min: 60);

  test('ohne gespeicherte Richtwerte: leer, die App setzt keine Vorgaben', () async {
    final repo = nutritionTargetsRepo(db);
    expect((await repo.load()).isEmpty, isTrue);
    expect((await repo.watch().first).isEmpty, isTrue);
  });

  test('speichern und wieder laden', () async {
    final repo = nutritionTargetsRepo(db);
    await repo.save(const NutritionTargets().withTarget(NutrientKey.kcal, kcal).withTarget(NutrientKey.proteinG, protein));
    final loaded = await repo.load();
    expect(loaded[NutrientKey.kcal], kcal);
    expect(loaded[NutrientKey.proteinG], protein);
    expect(loaded[NutrientKey.saltG], isNull);
  });

  test('erneutes Speichern ersetzt die Richtwerte und legt keine zweite Zeile an', () async {
    final repo = nutritionTargetsRepo(db);
    await repo.save(const NutritionTargets().withTarget(NutrientKey.kcal, kcal));
    await repo.save(const NutritionTargets().withTarget(NutrientKey.saltG, const NutrientTarget(max: 6)));
    expect(await db.select(db.nutritionTargetRows).get(), hasLength(1));
    final loaded = await repo.load();
    expect(loaded[NutrientKey.kcal], isNull);
    expect(loaded[NutrientKey.saltG], const NutrientTarget(max: 6));
  });

  test('alle Richtwerte entfernen speichert leeres JSON statt die Zeile zu loeschen (damit es synct)', () async {
    final repo = nutritionTargetsRepo(db);
    await repo.save(const NutritionTargets().withTarget(NutrientKey.kcal, kcal));
    await repo.save(const NutritionTargets());
    final rows = await db.select(db.nutritionTargetRows).get();
    expect(rows, hasLength(1));
    expect(jsonDecode(rows.single.targets), isEmpty);
    final pending = await db.select(db.outbox).get();
    expect(pending, hasLength(2));
    expect(jsonDecode(pending.last.payload)['targets'], isEmpty);
  });

  test('Speichern schreibt genau einen Outbox-Eintrag je Aufruf, Schluessel ist der Haushalt', () async {
    var changed = 0;
    final repo = nutritionTargetsRepo(db, household: 'hX', onChanged: () => changed++);
    await repo.save(const NutritionTargets().withTarget(NutrientKey.kcal, kcal));
    final pending = await db.select(db.outbox).get();
    expect(pending, hasLength(1));
    expect(pending.single.remoteTable, 'nutrition_targets');
    expect(pending.single.rowId, 'hX');
    final payload = jsonDecode(pending.single.payload) as Map<String, dynamic>;
    expect(payload['household_id'], 'hX');
    expect(payload['targets'], {
      'kcal': {'min': 1800.0, 'max': 2200.0},
    });
    expect(changed, 1);
  });

  test('watch meldet Aenderungen', () async {
    final repo = nutritionTargetsRepo(db);
    final seen = <bool>[];
    final sub = repo.watch().listen((t) => seen.add(t.isEmpty));
    await Future<void>.delayed(Duration.zero);
    await repo.save(const NutritionTargets().withTarget(NutrientKey.kcal, kcal));
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(seen, [true, false]);
  });

  test('beschaedigter Zeileninhalt ergibt leere Richtwerte statt eines Absturzes', () async {
    await db.into(db.nutritionTargetRows).insert(NutritionTargetRowsCompanion.insert(
          householdId: 'h1',
          targets: const Value('{kaputt'),
          updatedAt: DateTime.utc(2026),
        ));
    expect((await nutritionTargetsRepo(db).load()).isEmpty, isTrue);
  });

  group('Sync', () {
    test('Richtwerte von Geraet A kommen auf Geraet B an', () async {
      final b = memoryDb();
      addTearDown(b.close);
      final remote = FakeRemoteStore();
      await nutritionTargetsRepo(db)
          .save(const NutritionTargets().withTarget(NutrientKey.kcal, kcal).withTarget(NutrientKey.saltG, const NutrientTarget(max: 6)));
      await SyncEngine(db, remote).sync();
      await SyncEngine(b, remote).sync();

      final onB = await nutritionTargetsRepo(b).load();
      expect(onB[NutrientKey.kcal], kcal);
      expect(onB[NutrientKey.saltG], const NutrientTarget(max: 6));
    });

    test('Aenderung auf A ueberschreibt auf B, es bleibt eine Zeile je Haushalt', () async {
      final b = memoryDb();
      addTearDown(b.close);
      final remote = FakeRemoteStore();
      final repoA = nutritionTargetsRepo(db);
      await repoA.save(const NutritionTargets().withTarget(NutrientKey.kcal, kcal));
      await SyncEngine(db, remote).sync();
      await SyncEngine(b, remote).sync();

      await repoA.save(const NutritionTargets().withTarget(NutrientKey.kcal, const NutrientTarget(max: 2000)));
      await SyncEngine(db, remote).sync();
      await SyncEngine(b, remote).sync();

      expect((await nutritionTargetsRepo(b).load())[NutrientKey.kcal], const NutrientTarget(max: 2000));
      expect(await b.select(b.nutritionTargetRows).get(), hasLength(1));
      expect(remote.table('nutrition_targets'), hasLength(1));
    });

    test('der Abgleich mit der Outbox laeuft ueber den Haushalt (Tabelle hat keine Spalte "id")', () async {
      await nutritionTargetsRepo(db).save(const NutritionTargets().withTarget(NutrientKey.kcal, kcal));
      final def = syncTables.singleWhere((t) => t.remoteName == 'nutrition_targets');
      final pending = await db.select(db.outbox).getSingle();
      expect(def.idOf({'household_id': 'h1'}), pending.rowId, reason: 'sonst wuerde der Pull eine unsynchronisierte lokale Aenderung ueberschreiben');
    });
  });
}
