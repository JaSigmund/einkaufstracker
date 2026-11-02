import 'package:einkaufstracker/domain/recipes/meal_plan.dart';
import 'package:einkaufstracker/domain/recipes/recipe_suggestion.dart';
import 'package:einkaufstracker/domain/recipes/saved_recipe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const milk = (id: 'p1', name: 'Milch', baseUnit: 'l');
  const rice = (id: 'p2', name: 'Reis', baseUnit: 'kg');
  SavedIngredient free(String name) => SavedIngredient(productId: null, name: name, unit: 'piece');

  test('Die Woche beginnt am Montag', () {
    expect(weekStartOf(DateTime(2026, 11, 2)), DateTime.utc(2026, 11, 2)); // Montag
    expect(weekStartOf(DateTime(2026, 11, 8)), DateTime.utc(2026, 11, 2)); // Sonntag
    expect(weekStartOf(DateTime(2026, 11, 9)), DateTime.utc(2026, 11, 9));
  });

  test('Zutaten aus Text: getrennt, getrimmt, doppelte einmal', () {
    expect(parseIngredientText(' Reis, Linsen ,reis,\nKokosmilch,, ').map((i) => i.name), ['Reis', 'Linsen', 'Kokosmilch']);
  });

  test('Zutaten-JSON hin und zurueck, Kaputtes reisst nichts mit', () {
    final raw = encodePlanIngredients([const SavedIngredient(productId: 'p1', name: 'Milch', unit: 'l')]);
    expect(decodePlanIngredients(raw).single.productId, 'p1');
    expect(decodePlanIngredients('kein json'), isEmpty);
    expect(decodePlanIngredients('{"a":1}'), isEmpty);
    expect(decodePlanIngredients('[{"x":1},{"name":"Reis"}]').single.name, 'Reis');
  });

  group('Was fehlt', () {
    test('Vorhandenes fehlt nicht, ein Produkt ohne Bestand schon, mit seiner Grundeinheit', () {
      final missing = findMissingForPlan(
        const [SavedIngredient(productId: 'p1', name: 'Milch', unit: 'l'), SavedIngredient(productId: 'p2', name: 'Reis', unit: 'kg')],
        inStock: {'p1'},
        products: const [milk, rice],
      );
      expect(missing, [(productId: 'p2', freeText: null, unit: 'kg')]);
    });

    test('Freier Name wird einem Produkt zugeordnet, sonst bleibt er freier Text', () {
      final missing = findMissingForPlan([free('milch'), free('reis'), free('Sahne')], inStock: {'p1'}, products: const [milk, rice]);
      expect(missing, [(productId: 'p2', freeText: null, unit: 'kg'), (productId: null, freeText: 'Sahne', unit: 'piece')]);
    });

    test('Dasselbe aus zwei Gerichten steht nur einmal da', () {
      final missing = findMissingForPlan(
        [free('Sahne'), free('sahne'), free('Reis'), const SavedIngredient(productId: 'p2', name: 'Reis', unit: 'kg')],
        inStock: const {},
        products: const [rice],
      );
      expect(missing, hasLength(2));
    });
  });

  test('Vorschlag mit fehlenden Zutaten; alte Antworten ohne das Feld gehen weiter', () {
    final parsed = parseRecipeSuggestions([
      {'title': 'Curry', 'reason': 'x', 'matchingIngredients': ['Reis'], 'missingIngredients': ['Sahne', ' ', 5]},
      {'title': 'Reis', 'reason': 'y', 'matchingIngredients': ['Reis']},
    ]);
    expect(parsed.first.missingIngredients, ['Sahne']);
    expect(parsed.last.missingIngredients, isEmpty);
  });
}
