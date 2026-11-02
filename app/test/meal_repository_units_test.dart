import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/meal_repository.dart';
import 'package:einkaufstracker/domain/nutrition/food_unit.dart';
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

  group('Haushaltseinheit auf Stueckware', () {
    Future<double> stock() async => (await db.select(db.inventoryItems).get()).fold<double>(0, (s, i) => s + i.quantity);

    Future<Product> brot({double? unitWeightG}) async {
      final p = await productRepo(db).create(
        name: 'Brot',
        baseUnit: 'piece',
        unitWeightG: unitWeightG,
        nutrientsPer100: {'kcal': 260},
        nutrientsBasis: 'g',
        nutrientsSource: 'manual',
      );
      await inventoryRepo(db).recordFromScan(productId: p.id, ean: '1', quantity: 2, unit: 'piece', bestBefore: DateTime.utc(2026, 12, 1), now: DateTime.utc(2026, 9, 1));
      return p;
    }

    test('mit Stueckgewicht wird anteilig abgezogen: 2 Scheiben a 28 g von 1 Brot zu 560 g sind 0,1 Stueck', () async {
      final p = await brot(unitWeightG: 560);
      final m = await meals.create(draft([IngredientDraft(productId: p.id, quantity: 2, entryUnit: EntryUnit.piece, unitKey: FoodUnitKey.slice, unitWeightG: 28)]));
      final i = (await meals.ingredientsOf(m.id)).single;
      expect([i.quantity, i.unit, i.amountG, i.source], [2, 'piece', 56, 'inventory']);
      expect(i.kcal, closeTo(145.6, 1e-9));
      expect(await stock(), closeTo(1.9, 1e-9));
      final movement = await db.select(db.inventoryMovements).get();
      expect(movement.last.quantityDelta, closeTo(-0.1, 1e-9));
    });

    test('ohne Stueckgewicht kein Abzug, aber Naehrwerte, und die Zeile bleibt ohne Bestandsbezug', () async {
      final p = await brot();
      final m = await meals.create(draft([IngredientDraft(productId: p.id, quantity: 2, entryUnit: EntryUnit.piece, unitKey: FoodUnitKey.slice, unitWeightG: 28)]));
      final i = (await meals.ingredientsOf(m.id)).single;
      expect(i.amountG, 56);
      expect(i.kcal, closeTo(145.6, 1e-9));
      expect(i.inventoryItemId, isNull);
      expect(i.source, 'manual');
      expect(await stock(), 2);
    });

    test('ganze Stueck bleiben ganze Stueck, auch wenn das Gewicht der Zeile vom Produkt abweicht oder fehlt', () async {
      final mitGewicht = await brot(unitWeightG: 560);
      await meals.create(draft([IngredientDraft(productId: mitGewicht.id, quantity: 1, entryUnit: EntryUnit.piece, unitKey: FoodUnitKey.piece, unitWeightG: 600)]));
      expect(await stock(), 1);
      await meals.create(draft([IngredientDraft(productId: mitGewicht.id, quantity: 1, entryUnit: EntryUnit.piece)]));
      expect(await stock(), 0);
    });

    test('Scheibe ohne eigenes Gewicht nimmt nicht das Gewicht des ganzen Stuecks', () async {
      final p = await brot(unitWeightG: 560);
      final m = await meals.create(draft([IngredientDraft(productId: p.id, quantity: 2, entryUnit: EntryUnit.piece, unitKey: FoodUnitKey.slice)]));
      expect((await meals.ingredientsOf(m.id)).single.amountG, isNull);
      expect(await stock(), 2);
    });

    test('Bearbeiten bucht den anteiligen Abzug zurueck und neu', () async {
      final p = await brot(unitWeightG: 560);
      IngredientDraft scheiben(double n) => IngredientDraft(productId: p.id, quantity: n, entryUnit: EntryUnit.piece, unitKey: FoodUnitKey.slice, unitWeightG: 28);
      final m = await meals.create(draft([scheiben(2)]));
      await meals.update(m.id, draft([scheiben(4)]));
      expect(await stock(), closeTo(1.8, 1e-9));
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
