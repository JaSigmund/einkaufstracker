import 'package:einkaufstracker/domain/nutrition/meal_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

/// Antwort der Edge Function analyze-meal (Phase 7c): defensiv gelesen, ein kaputter Eintrag verwirft nicht alles.
void main() {
  test('normale Antwort', () {
    final a = parseMealAnalysis({
      'dish_title': 'Reispfanne',
      'meal_type_guess': 'dinner',
      'servings_visible': 2,
      'ingredients': [
        {'name': 'Reis', 'inventory_product_id': 'p1', 'est_amount_g': 150, 'confidence': 0.8},
        {'name': 'Paprika', 'inventory_product_id': null, 'est_amount_g': 80.5, 'confidence': 0.4},
      ],
      'notes': 'Öl nicht sichtbar',
    });
    expect(a.dishTitle, 'Reispfanne');
    expect(a.mealType, 'dinner');
    expect(a.servingsVisible, 2);
    expect(a.notes, 'Öl nicht sichtbar');
    expect(a.ingredients, hasLength(2));
    expect(a.ingredients[0].inventoryProductId, 'p1');
    expect(a.ingredients[0].estimatedGrams, 150);
    expect(a.ingredients[0].confidence, 0.8);
    expect(a.ingredients[1].inventoryProductId, isNull);
    expect(a.ingredients[1].estimatedGrams, 80.5);
    expect(a.isEmpty, isFalse);
  });

  test('Nicht-Objekt ergibt eine leere Analyse', () {
    for (final v in [null, 'text', 5, <Object?>[]]) {
      final a = parseMealAnalysis(v);
      expect(a.isEmpty, isTrue, reason: '$v');
      expect(a.dishTitle, isEmpty);
      expect(a.mealType, isNull);
    }
  });

  test('kaputte Zutaten werden einzeln verworfen', () {
    final a = parseMealAnalysis({
      'ingredients': [
        null,
        'Reis',
        {'name': ''},
        {'name': 7},
        {'name': '  Karotte ', 'est_amount_g': 80, 'confidence': 0.6},
      ],
    });
    expect(a.ingredients.map((i) => i.name), ['Karotte']);
  });

  test('0, negative und nicht numerische Mengen bedeuten "nicht schaetzbar"', () {
    final a = parseMealAnalysis({
      'ingredients': [
        {'name': 'A', 'est_amount_g': 0},
        {'name': 'B', 'est_amount_g': -4},
        {'name': 'C', 'est_amount_g': 'viel'},
        {'name': 'D'},
      ],
    });
    expect(a.ingredients.map((i) => i.estimatedGrams), [null, null, null, null]);
  });

  test('Konfidenz wird auf 0 bis 1 begrenzt, fehlende ist 0', () {
    final a = parseMealAnalysis({
      'ingredients': [
        {'name': 'A', 'confidence': 5},
        {'name': 'B', 'confidence': -1},
        {'name': 'C', 'confidence': 'hoch'},
        {'name': 'D'},
      ],
    });
    expect(a.ingredients.map((i) => i.confidence), [1.0, 0.0, 0.0, 0.0]);
  });

  test('leerer Text als Produkt-ID bedeutet kein Produkt', () {
    final a = parseMealAnalysis({
      'ingredients': [
        {'name': 'Ei', 'inventory_product_id': ''},
      ],
    });
    expect(a.ingredients.single.inventoryProductId, isNull);
  });

  test('Mahlzeitentyp nur aus der bekannten Liste, "unknown" und Unbekanntes sind null', () {
    expect(parseMealAnalysis({'meal_type_guess': 'breakfast'}).mealType, 'breakfast');
    expect(parseMealAnalysis({'meal_type_guess': 'unknown'}).mealType, isNull);
    expect(parseMealAnalysis({'meal_type_guess': 'brunch'}).mealType, isNull);
    expect(parseMealAnalysis({'meal_type_guess': 3}).mealType, isNull);
  });

  test('Portionen: nur positive Zahlen', () {
    expect(parseMealAnalysis({'servings_visible': 3}).servingsVisible, 3);
    expect(parseMealAnalysis({'servings_visible': 0}).servingsVisible, isNull);
    expect(parseMealAnalysis({'servings_visible': -1}).servingsVisible, isNull);
    expect(parseMealAnalysis({'servings_visible': 'zwei'}).servingsVisible, isNull);
  });

  test('keine Zutaten: leer, auch wenn Titel und Hinweis da sind', () {
    final a = parseMealAnalysis({'dish_title': 'Teller', 'ingredients': [], 'notes': 'kein Essen erkennbar'});
    expect(a.isEmpty, isTrue);
    expect(a.notes, 'kein Essen erkennbar');
  });
}
