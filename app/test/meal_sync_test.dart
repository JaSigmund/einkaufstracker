import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/meal_repository.dart';
import 'package:einkaufstracker/data/sync/mappers.dart';
import 'package:einkaufstracker/data/sync/sync_engine.dart';
import 'package:einkaufstracker/domain/nutrition/ingredient_nutrition.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Das Essenstagebuch muss ueber den Sync auf einem zweiten Geraet ankommen, samt Verknuepfung der Ledger-Bewegungen
/// zur Mahlzeit (meal_id) -- sonst waere die Gegenbuchung auf Geraet B nicht nachvollziehbar.
void main() {
  late AppDatabase a;
  late AppDatabase b;
  late FakeRemoteStore remote;

  setUp(() {
    a = memoryDb();
    b = memoryDb();
    remote = FakeRemoteStore();
  });
  tearDown(() async {
    await a.close();
    await b.close();
  });

  Future<Meal> cookOnA() async {
    final product = await productRepo(a).create(
      name: 'Reis',
      baseUnit: 'kg',
      nutrientsPer100: {'kcal': 350},
      nutrientsBasis: 'g',
      nutrientsSource: 'manual',
    );
    await inventoryRepo(a).recordFromScan(productId: product.id, ean: '1', quantity: 1, unit: 'kg', now: DateTime.utc(2026, 9, 1));
    return mealRepo(a).create(MealDraft(
      title: 'Reispfanne',
      eatenAt: DateTime.utc(2026, 9, 22, 12),
      ingredients: [IngredientDraft(productId: product.id, quantity: 150, entryUnit: EntryUnit.g)],
    ));
  }

  test('Mahlzeit, Zutat und Ledger-Bewegung mit meal_id kommen auf Geraet B an', () async {
    final meal = await cookOnA();
    await SyncEngine(a, remote).sync();
    await SyncEngine(b, remote).sync();

    final onB = await (b.select(b.meals)..where((m) => m.id.equals(meal.id))).getSingle();
    expect(onB.title, 'Reispfanne');
    final ing = await (b.select(b.mealIngredients)..where((i) => i.mealId.equals(meal.id))).getSingle();
    expect(ing.kcal, closeTo(525, 1e-9));
    expect(ing.unit, 'kg');
    final moves = await (b.select(b.inventoryMovements)..where((m) => m.mealId.equals(meal.id))).get();
    expect(moves, hasLength(1));
    expect(moves.single.type, 'meal');
    expect(moves.single.quantityDelta, closeTo(-0.15, 1e-9));
  });

  test('Loeschen auf Geraet A: Gegenbuchung und Soft-Delete kommen auf Geraet B an', () async {
    final meal = await cookOnA();
    await SyncEngine(a, remote).sync();
    await SyncEngine(b, remote).sync();

    await mealRepo(a).delete(meal.id);
    await SyncEngine(a, remote).sync();
    await SyncEngine(b, remote).sync();

    expect((await (b.select(b.meals)..where((m) => m.id.equals(meal.id))).getSingle()).deletedAt, isNotNull);
    final moves = await (b.select(b.inventoryMovements)..where((m) => m.mealId.equals(meal.id))).get();
    expect(moves.map((m) => m.type).toSet(), {'meal', 'adjustment'});
    expect(moves.fold<double>(0, (s, m) => s + m.quantityDelta), closeTo(0, 1e-9));
  });

  group('Mapper', () {
    test('Mahlzeit: Hin- und Rueckweg ohne Verlust', () async {
      final meal = await cookOnA();
      final restored = mealFromRemote(mealToRemote(meal));
      expect(restored.title.value, meal.title);
      expect(restored.eatenAt.value, meal.eatenAt);
      expect(restored.servingsEaten.value, meal.servingsEaten);
      expect(restored.isEstimate.value, meal.isEstimate);
    });

    test('Zutat: nicht gesetzte Naehrwerte bleiben null, werden nicht zu 0', () async {
      final meal = await cookOnA();
      final ing = (await mealRepo(a).ingredientsOf(meal.id)).single;
      final remoteJson = mealIngredientToRemote(ing);
      expect(remoteJson['fat_g'], isNull);
      expect(mealIngredientFromRemote(remoteJson).fatG.value, isNull);
    });

    test('Bewegung ohne meal_id (alte Zeilen, Server ohne Wert): bleibt null', () {
      final restored = inventoryMovementFromRemote({
        'id': 'm1',
        'household_id': 'h1',
        'product_id': 'p1',
        'occurred_at': '2026-09-01T10:00:00Z',
        'type': 'purchase',
        'quantity_delta': 1,
        'unit': 'kg',
        'updated_at': '2026-09-01T10:00:00Z',
      });
      expect(restored.mealId.value, isNull);
    });
  });
}
