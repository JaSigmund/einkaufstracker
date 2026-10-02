import 'package:einkaufstracker/domain/recipes/recipe_suggestion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseRecipeSuggestions', () {
    test('parst eine gueltige Liste', () {
      final result = parseRecipeSuggestions([
        {
          'title': 'Joghurt-Gurken-Salat',
          'reason': 'nutzt den Joghurt, der morgen ablaeuft',
          'matchingIngredients': ['Joghurt', 'Gurke'],
        },
      ]);
      expect(result, hasLength(1));
      expect(result.single.title, 'Joghurt-Gurken-Salat');
      expect(result.single.reason, 'nutzt den Joghurt, der morgen ablaeuft');
      expect(result.single.matchingIngredients, ['Joghurt', 'Gurke']);
    });

    test('Eintrag ohne Titel wird uebersprungen, Rest bleibt erhalten', () {
      final result = parseRecipeSuggestions([
        {'reason': 'kein Titel'},
        {'title': 'Reispfanne', 'matchingIngredients': ['Reis']},
      ]);
      expect(result, hasLength(1));
      expect(result.single.title, 'Reispfanne');
    });

    test('Titel nur aus Leerzeichen wird uebersprungen', () {
      final result = parseRecipeSuggestions([
        {'title': '   '},
      ]);
      expect(result, isEmpty);
    });

    test('fehlende reason/matchingIngredients: leere Werte statt Absturz', () {
      final result = parseRecipeSuggestions([
        {'title': 'Mysteriöses Gericht'},
      ]);
      expect(result.single.reason, '');
      expect(result.single.matchingIngredients, isEmpty);
    });

    test('kein JSON-Array: leere Liste statt Absturz', () {
      expect(parseRecipeSuggestions({'title': 'kein Array'}), isEmpty);
      expect(parseRecipeSuggestions(null), isEmpty);
      expect(parseRecipeSuggestions('Text'), isEmpty);
    });

    test('Eintrag, der keine Map ist, wird uebersprungen', () {
      final result = parseRecipeSuggestions([
        'kaputter Eintrag',
        {'title': 'Gutes Rezept'},
      ]);
      expect(result, hasLength(1));
      expect(result.single.title, 'Gutes Rezept');
    });
  });
}
