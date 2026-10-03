import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/meal_repository.dart';
import 'package:einkaufstracker/domain/nutrition/ingredient_nutrition.dart';
import 'package:einkaufstracker/domain/nutrition/nutrient_scaling.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Stueckmengen mit dem Gewicht einer Einheit beim Speichern (Phase N2, ADR-033): "2 Scheiben a 28 g" wird zu 56 g Naehrwertbasis,
/// der Bestand eines Produkts in kg wird richtig abgezogen, und ohne Gewicht bleibt es "nicht erfasst" statt 0.
void main() {
  late AppDatabase db;
  late MealRepository meals;

  setUp(() {
    db = memoryDb();
    meals = mealRepo(db);
  });
  tearDown(() => db.close());

  MealDraft draft(List<IngredientDraft> ingredients) => MealDraft(title: 'Test', eatenAt: DateTime.utc(2026, 10, 3, 12), ingredients: ingredients);

  const bread = NutrientsPer100(kcal: 260, proteinG: 8, carbsG: 49);

  test('Freitext-Zutat in Stueck mit Gewicht: Gramm, Naehrwerte und die erfasste Anzahl', () async {
    final m = await meals.create(draft(const [
      IngredientDraft(freeText: 'Weizenbrot', quantity: 2, entryUnit: EntryUnit.piece, per100: bread, per100Basis: 'g', blsCode: 'B311000', unitWeightG: 28),
    ]));
    final i = (await meals.ingredientsOf(m.id)).single;
    expect([i.quantity, i.unit, i.amountG], [2, 'piece', 56]);
    expect(i.kcal, closeTo(145.6, 1e-9));
    expect(i.proteinG, closeTo(4.48, 1e-9));
  });

  test('ohne Gewicht bleibt die Stueckzutat ohne Naehrwerte (null statt 0)', () async {
    final m = await meals.create(draft(const [
      IngredientDraft(freeText: 'Weizenbrot', quantity: 2, entryUnit: EntryUnit.piece, per100: bread, per100Basis: 'g', blsCode: 'B311000'),
    ]));
    final i = (await meals.ingredientsOf(m.id)).single;
    expect(i.amountG, isNull);
    expect(i.kcal, isNull);
    expect(i.quantity, 2);
  });

  test('das Gewicht der Zeile gilt nur fuer Stueck, nicht fuer Gramm', () async {
    final m = await meals.create(draft(const [
      IngredientDraft(freeText: 'Weizenbrot', quantity: 50, entryUnit: EntryUnit.g, per100: bread, per100Basis: 'g', unitWeightG: 28),
    ]));
    final i = (await meals.ingredientsOf(m.id)).single;
    expect([i.quantity, i.unit, i.amountG], [0.05, 'kg', 50]);
    expect(i.kcal, closeTo(130, 1e-9));
  });

  group('Produkt', () {
    late Product reis;

    setUp(() async {
      reis = await productRepo(db).create(
        name: 'Aepfel',
        baseUnit: 'kg',
        nutrientsPer100: {'kcal': 52},
        nutrientsBasis: 'g',
        nutrientsSource: 'manual',
      );
      await inventoryRepo(db).recordFromScan(productId: reis.id, ean: '1', quantity: 1, unit: 'kg', bestBefore: DateTime.utc(2026, 12, 1), now: DateTime.utc(2026, 9, 1));
    });

    Future<double> stock() async => (await db.select(db.inventoryItems).get()).fold<double>(0, (s, i) => s + i.quantity);

    test('2 Aepfel mit Gewicht der Zeile (150 g): 300 g Naehrwertbasis, 0,3 kg vom Bestand abgezogen', () async {
      final m = await meals.create(draft([IngredientDraft(productId: reis.id, quantity: 2, entryUnit: EntryUnit.piece, unitWeightG: 150)]));
      final i = (await meals.ingredientsOf(m.id)).single;
      expect([i.quantity, i.unit, i.amountG], [2, 'piece', 300]);
      expect(i.kcal, closeTo(156, 1e-9));
      expect(await stock(), closeTo(0.7, 1e-9));
    });

    test('das Gewicht am Produkt gilt, wenn die Zeile keines mitbringt; das der Zeile geht vor', () async {
      await productRepo(db).setUnitWeight(reis.id, 200);
      final a = await meals.create(draft([IngredientDraft(productId: reis.id, quantity: 1, entryUnit: EntryUnit.piece, deduct: false)]));
      expect((await meals.ingredientsOf(a.id)).single.amountG, 200);
      final b = await meals.create(draft([IngredientDraft(productId: reis.id, quantity: 1, entryUnit: EntryUnit.piece, deduct: false, unitWeightG: 120)]));
      expect((await meals.ingredientsOf(b.id)).single.amountG, 120);
    });

    test('Stueck ohne jedes Gewicht: kein Abzug moeglich, keine Naehrwerte, die Mahlzeit wird trotzdem gespeichert', () async {
      final m = await meals.create(draft([IngredientDraft(productId: reis.id, quantity: 2, entryUnit: EntryUnit.piece)]));
      final i = (await meals.ingredientsOf(m.id)).single;
      expect(i.amountG, isNull);
      expect(i.kcal, isNull);
      expect(await stock(), closeTo(1, 1e-9));
    });
  });

  test('Bearbeiten mit anderer Anzahl rechnet mit dem Gewicht der Zeile neu', () async {
    final m = await meals.create(draft(const [
      IngredientDraft(freeText: 'Banane', quantity: 1, entryUnit: EntryUnit.piece, per100: NutrientsPer100(kcal: 79), per100Basis: 'g', unitWeightG: 118),
    ]));
    await meals.update(
      m.id,
      draft(const [
        IngredientDraft(freeText: 'Banane', quantity: 3, entryUnit: EntryUnit.piece, per100: NutrientsPer100(kcal: 79), per100Basis: 'g', unitWeightG: 118),
      ]),
    );
    final rows = (await meals.ingredientsOf(m.id));
    expect(rows, hasLength(1));
    expect([rows.single.quantity, rows.single.amountG], [3, 354]);
  });
}
