import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/saved_recipe_repository.dart';
import 'package:einkaufstracker/domain/recipes/saved_recipe.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

SavedRecipe _recipe(String id, String title, {List<SavedIngredient> ingredients = const [], DateTime? savedAt}) => SavedRecipe(
      id: id,
      title: title,
      sourceUrl: 'https://example.test/$id',
      ingredients: ingredients,
      savedAt: savedAt ?? DateTime.utc(2026, 10, 1),
    );

void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  group('SavedRecipeRepository', () {
    test('ohne gespeicherte Rezepte: leere Liste', () async {
      expect(await SavedRecipeRepository(db).loadAll(), isEmpty);
    });

    test('speichern und laden', () async {
      final repo = SavedRecipeRepository(db);
      await repo.save(_recipe('r1', 'Kürbissuppe', ingredients: const [
        SavedIngredient(productId: 'p1', name: 'Kürbis', quantity: 1, unit: 'piece'),
      ]));

      final all = await repo.loadAll();
      expect(all, hasLength(1));
      expect(all.single.title, 'Kürbissuppe');
      expect(all.single.ingredients.single.name, 'Kürbis');
    });

    test('erneutes Speichern mit gleicher id ersetzt den Eintrag statt ihn zu duplizieren', () async {
      final repo = SavedRecipeRepository(db);
      await repo.save(_recipe('r1', 'Alter Titel'));
      await repo.save(_recipe('r1', 'Neuer Titel'));

      final all = await repo.loadAll();
      expect(all, hasLength(1));
      expect(all.single.title, 'Neuer Titel');
    });

    test('loeschen entfernt nur das gewaehlte Rezept', () async {
      final repo = SavedRecipeRepository(db);
      await repo.save(_recipe('r1', 'Kürbissuppe'));
      await repo.save(_recipe('r2', 'Linsensuppe'));

      await repo.delete('r1');

      final all = await repo.loadAll();
      expect(all, hasLength(1));
      expect(all.single.id, 'r2');
    });

    test('neueste Rezepte zuerst', () async {
      final repo = SavedRecipeRepository(db);
      await repo.save(_recipe('r1', 'Älter', savedAt: DateTime.utc(2026, 9, 1)));
      await repo.save(_recipe('r2', 'Neuer', savedAt: DateTime.utc(2026, 10, 1)));

      final all = await repo.loadAll();
      expect(all.map((r) => r.id), ['r2', 'r1']);
    });

    test('bleibt ueber eine neue Repository-Instanz hinweg erhalten (echte Persistenz)', () async {
      await SavedRecipeRepository(db).save(_recipe('r1', 'Kürbissuppe'));
      final all = await SavedRecipeRepository(db).loadAll();
      expect(all, hasLength(1));
    });
  });
}
