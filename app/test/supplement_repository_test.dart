import 'dart:convert';

import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/household_prefs_repository.dart';
import 'package:einkaufstracker/data/repositories/supplement_repository.dart';
import 'package:einkaufstracker/domain/nutrition/micros.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Nahrungsergaenzung und gemeinsame Einstellungen (Phase N4, ADR-035).
void main() {
  late AppDatabase db;
  late SupplementRepository repo;
  var changed = 0;

  setUp(() {
    db = memoryDb();
    changed = 0;
    repo = SupplementRepository(db, householdId: () async => 'h1', onChanged: () => changed++);
  });
  tearDown(() => db.close());

  Future<List<OutboxEntry>> outbox(String table) async => (await db.select(db.outbox).get()).where((e) => e.remoteTable == table).toList();

  Future<Supplement> d3() => repo.save(name: 'Vitamin D3', servingLabel: 'Tablette', micros: const {'vit_d_ug': 25.0});

  group('save', () {
    test('legt eine Ergaenzung an und schickt sie mit jsonb-Werten in die Outbox', () async {
      final s = await repo.save(name: ' Multivitamin ', servingLabel: 'Kapsel', micros: const {'vit_c_mg': 80.0, 'iron_mg': 14.0}, note: ' mit dem Essen ');
      expect(s.name, 'Multivitamin');
      expect(s.servingLabel, 'Kapsel');
      expect(s.note, 'mit dem Essen');
      expect(parseMicros(s.micros), {'vit_c_mg': 80.0, 'iron_mg': 14.0});
      final box = await outbox('supplements');
      expect(box, hasLength(1));
      final payload = jsonDecode(box.single.payload) as Map<String, dynamic>;
      expect(payload['micros'], {'vit_c_mg': 80.0, 'iron_mg': 14.0}, reason: 'jsonb, nicht Text');
      expect(payload['household_id'], 'h1');
      expect(payload['deleted_at'], isNull);
      expect(changed, 1);
    });

    test('nur Schluessel des Registers mit endlichen, nicht negativen Werten zaehlen', () async {
      final s = await repo.save(name: 'Mix', servingLabel: 'Tablette', micros: const {'vit_c_mg': 80.0, 'gibts_nicht': 5.0, 'iron_mg': -1.0, 'zinc_mg': double.nan});
      expect(parseMicros(s.micros), {'vit_c_mg': 80.0});
    });

    test('ohne Namen, ohne Einheit oder ohne Wert wird abgelehnt', () async {
      expect(() => repo.save(name: ' ', servingLabel: 'Tablette', micros: const {'vit_c_mg': 1.0}), throwsArgumentError);
      expect(() => repo.save(name: 'X', servingLabel: ' ', micros: const {'vit_c_mg': 1.0}), throwsArgumentError);
      expect(() => repo.save(name: 'X', servingLabel: 'Tablette', micros: const {}), throwsArgumentError);
      expect(() => repo.save(name: 'X', servingLabel: 'Tablette', micros: const {'gibts_nicht': 1.0}), throwsArgumentError);
      expect(await db.select(db.supplements).get(), isEmpty);
    });

    test('mit id wird die Ergaenzung ersetzt, die id bleibt', () async {
      final a = await d3();
      final b = await repo.save(id: a.id, name: 'Vitamin D3 hochdosiert', servingLabel: 'Tablette', micros: const {'vit_d_ug': 50.0});
      expect(b.id, a.id);
      expect(await db.select(db.supplements).get(), hasLength(1));
      expect(parseMicros((await repo.get(a.id))!.micros), {'vit_d_ug': 50.0});
    });
  });

  group('Einnahmen', () {
    test('take speichert Name und absolute Mengen fuer die genommenen Einheiten', () async {
      final s = await d3();
      final i = await repo.take(s, at: DateTime.utc(2026, 10, 3, 8), servings: 2);
      expect(i.name, 'Vitamin D3');
      expect(i.servings, 2);
      expect(i.supplementId, s.id);
      expect(parseMicros(i.micros), {'vit_d_ug': 50.0});
      expect(i.takenAt, DateTime.utc(2026, 10, 3, 8));
      final payload = jsonDecode((await outbox('supplement_intakes')).single.payload) as Map<String, dynamic>;
      expect(payload['micros'], {'vit_d_ug': 50.0});
      expect(payload['servings'], 2);
      expect(payload['supplement_id'], s.id);
    });

    test('ohne Angaben: eine Einheit, jetzt', () async {
      final s = await d3();
      final before = DateTime.now().toUtc();
      final i = await repo.take(s);
      expect(i.servings, 1);
      expect(i.takenAt.isBefore(before), isFalse);
      expect(parseMicros(i.micros), {'vit_d_ug': 25.0});
    });

    test('eine Anzahl ohne Sinn wird abgelehnt', () async {
      final s = await d3();
      expect(() => repo.take(s, servings: 0), throwsArgumentError);
      expect(() => repo.take(s, servings: -1), throwsArgumentError);
      expect(() => repo.take(s, servings: double.infinity), throwsArgumentError);
    });

    test('eine spaetere Aenderung oder Loeschung der Ergaenzung veraendert die Einnahme nicht', () async {
      final s = await d3();
      final i = await repo.take(s);
      await repo.save(id: s.id, name: 'Anders', servingLabel: 'Tablette', micros: const {'vit_d_ug': 99.0});
      await repo.delete(s.id);
      final stored = (await db.select(db.supplementIntakes).get()).single;
      expect(stored.id, i.id);
      expect(stored.name, 'Vitamin D3');
      expect(parseMicros(stored.micros), {'vit_d_ug': 25.0});
      expect(stored.deletedAt, isNull);
    });

    test('deleteIntake nimmt eine Einnahme zurueck (Soft-Delete) und synchronisiert das', () async {
      final s = await d3();
      final i = await repo.take(s);
      await repo.deleteIntake(i.id);
      expect(await repo.watchIntakes().first, isEmpty);
      expect((await db.select(db.supplementIntakes).get()).single.deletedAt, isNotNull);
      final box = await outbox('supplement_intakes');
      expect(box, hasLength(2));
      expect((jsonDecode(box.last.payload) as Map)['deleted_at'], isNotNull);
      await repo.deleteIntake(i.id); // zweites Mal: nichts
      expect(await outbox('supplement_intakes'), hasLength(2));
    });
  });

  group('Listen', () {
    test('Ergaenzungen alphabetisch ohne geloeschte, Einnahmen neueste zuerst ohne zurueckgenommene', () async {
      final b = await repo.save(name: 'Zink', servingLabel: 'Tablette', micros: const {'zinc_mg': 10.0});
      final a = await repo.save(name: 'Eisen', servingLabel: 'Tablette', micros: const {'iron_mg': 14.0});
      final gone = await repo.save(name: 'Alt', servingLabel: 'Tablette', micros: const {'iron_mg': 1.0});
      await repo.delete(gone.id);
      expect((await repo.watchSupplements().first).map((s) => s.name), ['Eisen', 'Zink']);
      final first = await repo.take(a, at: DateTime.utc(2026, 10, 1));
      await repo.take(b, at: DateTime.utc(2026, 10, 3));
      final undone = await repo.take(a, at: DateTime.utc(2026, 10, 2));
      await repo.deleteIntake(undone.id);
      expect((await repo.watchIntakes().first).map((i) => i.name), ['Zink', 'Eisen']);
      expect(first.id, isNotEmpty);
    });
  });

  group('HouseholdPrefsRepository', () {
    late HouseholdPrefsRepository prefs;
    setUp(() => prefs = HouseholdPrefsRepository(db, householdId: () async => 'h1', onChanged: () => changed++));

    test('set speichert JSON je Schluessel und schickt eine Zeile mit zusammengesetztem Schluessel in die Outbox', () async {
      await prefs.set(microReferenceOnPref, true);
      await prefs.set(microReferenceOverridesPref, {'vit_c_mg': 100});
      expect(await prefs.load(), {microReferenceOnPref: true, microReferenceOverridesPref: {'vit_c_mg': 100}});
      final box = await outbox('household_prefs');
      expect(box.map((e) => e.rowId), ['h1:$microReferenceOnPref', 'h1:$microReferenceOverridesPref']);
      final payload = jsonDecode(box.last.payload) as Map<String, dynamic>;
      expect(payload['value'], {'vit_c_mg': 100}, reason: 'jsonb, nicht Text');
      expect(payload['key'], microReferenceOverridesPref);
    });

    test('derselbe Wert noch einmal: kein neuer Sync', () async {
      await prefs.set(microReferenceOnPref, true);
      final n = changed;
      await prefs.set(microReferenceOnPref, true);
      expect(changed, n);
      expect(await outbox('household_prefs'), hasLength(1));
      await prefs.set(microReferenceOnPref, false);
      expect(await prefs.load(), {microReferenceOnPref: false});
      expect(await outbox('household_prefs'), hasLength(2));
    });

    test('ungueltiger Schluessel wird abgelehnt', () async {
      expect(() => prefs.set('', 1), throwsArgumentError);
      expect(() => prefs.set('x' * 65, 1), throwsArgumentError);
    });

    test('eine unlesbare Zeile faellt weg, der Rest bleibt nutzbar', () async {
      await prefs.set('gut', 1);
      await db.into(db.householdPrefs).insert(HouseholdPrefsCompanion.insert(householdId: 'h1', key: 'kaputt', value: '{nicht json', updatedAt: DateTime.utc(2026)));
      expect(await prefs.load(), {'gut': 1});
    });
  });
}
