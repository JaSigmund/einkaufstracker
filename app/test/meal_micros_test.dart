import 'dart:convert';

import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/nutrition/bls_food_search.dart';
import 'package:einkaufstracker/data/repositories/meal_repository.dart';
import 'package:einkaufstracker/data/sync/sync_engine.dart';
import 'package:einkaufstracker/domain/nutrition/food_match.dart';
import 'package:einkaufstracker/domain/nutrition/ingredient_nutrition.dart';
import 'package:einkaufstracker/domain/nutrition/meal_analysis.dart';
import 'package:einkaufstracker/domain/nutrition/micros.dart';
import 'package:einkaufstracker/domain/nutrition/nutrient_scaling.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Mikronaehrstoffe beim Speichern, Sync und Lesen (Phase N3, ADR-032): Snapshot der verzehrten Menge je Zutat, Produktprofil vor
/// BLS-Profil, "unbekannt" statt 0, Sync als jsonb-Objekt.
const _banane = {'vit_c_mg': 11.0, 'iron_mg': 0.4, 'vit_d_ug': 0.0};

void main() {
  late AppDatabase db;
  late MealRepository meals;

  setUp(() {
    db = memoryDb();
    meals = mealRepo(db);
  });
  tearDown(() => db.close());

  MealDraft draft(List<IngredientDraft> ingredients) => MealDraft(title: 'Test', eatenAt: DateTime.utc(2026, 10, 3, 12), ingredients: ingredients);

  IngredientDraft banana({double grams = 236, Micros? micros = _banane}) => IngredientDraft(
        freeText: 'Banane',
        quantity: grams,
        entryUnit: EntryUnit.g,
        per100: const NutrientsPer100(kcal: 79),
        per100Basis: 'g',
        blsCode: 'F503100',
        microsPer100: micros,
      );

  test('Freitext-Zutat mit BLS-Mikronaehrstoffen: Snapshot der verzehrten Menge, echte Null bleibt', () async {
    final m = await meals.create(draft([banana()]));
    final i = (await meals.ingredientsOf(m.id)).single;
    final micros = parseMicros(i.micros)!;
    expect(micros['vit_c_mg'], closeTo(25.96, 1e-9));
    expect(micros['iron_mg'], closeTo(0.944, 1e-9));
    expect(micros['vit_d_ug'], 0, reason: 'eine echte Null bleibt im Snapshot');
    expect(micros.containsKey('zinc_mg'), isFalse, reason: 'ein fehlender Schluessel heisst unbekannt');
  });

  test('ohne Mikronaehrstoffdaten oder ohne bekannte Menge: null (unbekannt, nicht 0)', () async {
    final a = await meals.create(draft([banana(micros: null)]));
    expect((await meals.ingredientsOf(a.id)).single.micros, isNull);
    final b = await meals.create(draft(const [
      IngredientDraft(freeText: 'Banane', quantity: 2, entryUnit: EntryUnit.piece, per100: NutrientsPer100(kcal: 79), per100Basis: 'g', microsPer100: _banane),
    ]));
    expect((await meals.ingredientsOf(b.id)).single.micros, isNull, reason: 'Stueck ohne Gewicht: keine Menge in g, keine Rechnung');
  });

  test('von Hand eingetragene Werte haben keine Mikronaehrstoffe', () async {
    final m = await meals.create(draft(const [
      IngredientDraft(freeText: 'Tiramisu', quantity: 1, entryUnit: EntryUnit.piece, manualNutrients: NutrientAmounts(kcal: 450), microsPer100: _banane),
    ]));
    expect((await meals.ingredientsOf(m.id)).single.micros, isNull);
  });

  test('Stueckmenge mit Gewicht rechnet ueber die Gramm', () async {
    final m = await meals.create(draft(const [
      IngredientDraft(
        freeText: 'Banane',
        quantity: 2,
        entryUnit: EntryUnit.piece,
        per100: NutrientsPer100(kcal: 79),
        per100Basis: 'g',
        microsPer100: _banane,
        unitWeightG: 118,
      ),
    ]));
    expect(parseMicros((await meals.ingredientsOf(m.id)).single.micros)!['vit_c_mg'], closeTo(25.96, 1e-9));
  });

  group('Produkt', () {
    test('ein Produkt mit eigenem Profil rechnet mit dessen Mikronaehrstoffen, nicht mit denen der Zeile', () async {
      final p = await productRepo(db).create(
        name: 'Apfelsaft',
        baseUnit: 'l',
        nutrientsPer100: {'kcal': 46, 'vit_c_mg': 2.0},
        nutrientsBasis: 'ml',
        nutrientsSource: 'manual',
      );
      final m = await meals.create(draft([
        IngredientDraft(productId: p.id, quantity: 200, entryUnit: EntryUnit.ml, deduct: false, microsPer100: const {'vit_c_mg': 99.0}),
      ]));
      expect(parseMicros((await meals.ingredientsOf(m.id)).single.micros), {'vit_c_mg': closeTo(4, 1e-9)});
    });

    test('ein Produkt mit Makroprofil, aber ohne Mikronaehrstoffe, hat keine (die der Zeile gelten dann nicht)', () async {
      final p = await productRepo(db).create(
        name: 'Reis',
        baseUnit: 'kg',
        nutrientsPer100: {'kcal': 350},
        nutrientsBasis: 'g',
        nutrientsSource: 'manual',
      );
      final m = await meals.create(draft([IngredientDraft(productId: p.id, quantity: 100, entryUnit: EntryUnit.g, deduct: false, microsPer100: _banane)]));
      expect((await meals.ingredientsOf(m.id)).single.micros, isNull);
    });

    test('ein Produkt ohne Profil nimmt die Mikronaehrstoffe des zugeordneten BLS-Eintrags', () async {
      final p = await productRepo(db).create(name: 'Milch', baseUnit: 'l');
      final m = await meals.create(draft([
        IngredientDraft(
          productId: p.id,
          quantity: 250,
          entryUnit: EntryUnit.ml,
          deduct: false,
          per100: const NutrientsPer100(kcal: 65),
          per100Basis: 'g',
          blsCode: 'M111300',
          microsPer100: const {'calcium_mg': 117.0},
        ),
      ]));
      expect(parseMicros((await meals.ingredientsOf(m.id)).single.micros), {'calcium_mg': closeTo(292.5, 1e-9)});
    });

    test('setBlsProfile uebernimmt die Mikronaehrstoffe in das Profil des Produkts', () async {
      final products = productRepo(db);
      final p = await products.create(name: 'Milch', baseUnit: 'l');
      await products.setBlsProfile(
        p.id,
        const BlsFood(code: 'M111300', nameDe: 'Vollmilch', per100: NutrientsPer100(kcal: 65, proteinG: 3.4), micros: {'calcium_mg': 117.0, 'vit_b12_ug': 0.37, 'vit_d_ug': 0.0}),
      );
      final stored = (await products.byId(p.id))!;
      final json = jsonDecode(stored.nutrientsPer100!) as Map<String, dynamic>;
      expect(json['kcal'], 65);
      expect(json['calcium_mg'], 117);
      expect(json['vit_d_ug'], 0, reason: 'eine echte Null wird mitgenommen');
      expect(productMicros(stored), {'calcium_mg': 117.0, 'vit_b12_ug': 0.37, 'vit_d_ug': 0.0});
      // und das Makroprofil bleibt lesbar
      expect(NutrientsPer100.fromMap(json)!.kcal, 65);
      expect(productMicros((await products.create(name: 'Salz', baseUnit: 'kg'))), isNull);
    });

    test('ein Produkt mit Mikronaehrstoffen im Profil liefert sie ueber die ganze Kette bis in die Zutat', () async {
      final products = productRepo(db);
      final p = await products.create(name: 'Milch', baseUnit: 'l');
      await products.setBlsProfile(p.id, const BlsFood(code: 'M111300', nameDe: 'Vollmilch', per100: NutrientsPer100(kcal: 65), micros: {'calcium_mg': 117.0}));
      final m = await meals.create(draft([IngredientDraft(productId: p.id, quantity: 200, entryUnit: EntryUnit.ml, deduct: false)]));
      expect(parseMicros((await meals.ingredientsOf(m.id)).single.micros), {'calcium_mg': closeTo(234, 1e-9)});
    });
  });

  test('Bearbeiten rechnet die Mikronaehrstoffe mit der neuen Menge neu', () async {
    final m = await meals.create(draft([banana(grams: 100)]));
    await meals.update(m.id, draft([banana(grams: 300)]));
    final rows = await meals.ingredientsOf(m.id);
    expect(rows, hasLength(1));
    expect(parseMicros(rows.single.micros)!['vit_c_mg'], closeTo(33, 1e-9));
  });

  group('Sync', () {
    test('der Snapshot geht als Objekt (jsonb) zum Server und kommt als Text zurueck', () async {
      final remote = FakeRemoteStore();
      final m = await meals.create(draft([banana(), banana(micros: null)]));
      await SyncEngine(db, remote).sync();

      final stored = remote.table('meal_ingredients').values.toList();
      final withMicros = stored.firstWhere((r) => r['micros'] != null);
      expect(withMicros['micros'], isA<Map>());
      expect((withMicros['micros'] as Map)['vit_c_mg'], closeTo(25.96, 1e-9));
      expect(stored.where((r) => r['micros'] == null), hasLength(1), reason: 'Zutat ohne Daten schickt null');

      final other = memoryDb();
      addTearDown(other.close);
      await SyncEngine(other, remote).sync();
      final rows = await mealRepo(other).ingredientsOf(m.id);
      expect(rows.map((r) => parseMicros(r.micros)?['vit_c_mg']).toList(), contains(closeTo(25.96, 1e-9)));
      expect(rows.where((r) => r.micros == null), hasLength(1));
    });
  });

  group('Parsing', () {
    test('BlsFood liest die Naehrstoffe der Suchzeile', () {
      final f = blsFoodFromRow({'bls_code': 'F503100', 'name_de': 'Banane roh', 'kcal': 79, 'nutrients': {'vit_c_mg': 11, 'iron_mg': '0,4', 'unbekannt': 5}});
      expect(f.micros, {'vit_c_mg': 11.0, 'iron_mg': 0.4});
      expect(blsFoodFromRow({'bls_code': 'A', 'name_de': 'B'}).micros, isNull);
      expect(blsFoodFromRow({'bls_code': 'A', 'name_de': 'B', 'nutrients': 'kaputt'}).micros, isNull);
    });

    test('BlsFood.toMatch behaelt die Naehrstoffe', () {
      const f = BlsFood(code: 'F503100', nameDe: 'Banane roh', per100: NutrientsPer100(kcal: 79), micros: {'vit_c_mg': 11.0});
      expect(f.toMatch().micros, {'vit_c_mg': 11.0});
      expect(f.toMatch().confirmed().micros, {'vit_c_mg': 11.0});
    });

    test('der Treffer der Foto-Analyse liest die Naehrstoffe, ein Treffer ohne bleibt gueltig', () {
      final a = parseMealAnalysis({
        'ingredients': [
          {'name': 'Banane', 'match': {'code': 'F503100', 'name': 'Banane roh', 'per100': {'kcal': 79}, 'method': 'synonym', 'trust': 'sure', 'nutrients': {'vit_c_mg': 11}}},
          {'name': 'Reis', 'match': {'code': 'C352000', 'name': 'Reis', 'per100': {'kcal': 351}, 'nutrients': null}},
        ],
      });
      expect(a.ingredients[0].match!.micros, {'vit_c_mg': 11.0});
      expect(a.ingredients[1].match, isNotNull);
      expect(a.ingredients[1].match!.micros, isNull);
    });

    test('FoodMatch.confirmed behaelt die Naehrstoffe auch ohne BlsFood', () {
      const m = FoodMatch(code: 'X', name: 'Y', per100: NutrientsPer100(kcal: 1), micros: {'iron_mg': 1.0});
      expect(m.confirmed().micros, {'iron_mg': 1.0});
    });
  });
}
