import 'package:einkaufstracker/domain/nutrition/usual_ingredients.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Fehlt etwas?": uebliche Zutaten aus aehnlichen frueheren Mahlzeiten (Ausbau 1.12).
PastIngredient ing(String label, {String? productId, String? blsCode, double? grams, double? kcal, Map<String, double>? micros}) => (
      label: label,
      productId: productId,
      blsCode: blsCode,
      grams: grams,
      kcal: kcal,
      proteinG: null,
      fatG: null,
      carbsG: null,
      sugarG: null,
      fiberG: null,
      saltG: null,
      micros: micros,
    );

PastMeal meal(String id, List<PastIngredient> ingredients) => (id: id, ingredients: ingredients);

Set<String> keysOf(List<String> names) => {for (final n in names) ingredientKey(name: n)};

void main() {
  group('ingredientKey', () {
    test('Produkt vor BLS-Eintrag vor normalisiertem Namen', () {
      expect(ingredientKey(productId: 'p1', blsCode: 'F1', name: 'x'), 'p:p1');
      expect(ingredientKey(blsCode: 'F1', name: 'x'), 'b:F1');
      expect(ingredientKey(name: 'Reis'), ingredientKey(name: ' reis '));
      expect(ingredientKey(name: 'Gemüse'), ingredientKey(name: 'gemuese'));
    });
  });

  final reisgericht = [ing('Reis', grams: 150, kcal: 200), ing('Paprika', grams: 80, kcal: 25)];

  group('suggestMissingIngredients', () {
    test('Oel war in drei von drei aehnlichen Mahlzeiten dabei und fehlt jetzt: Vorschlag mit Median und Profil', () {
      final history = [
        meal('a', [...reisgericht, ing('Olivenöl', grams: 10, kcal: 88)]),
        meal('b', [...reisgericht, ing('Olivenöl', grams: 14, kcal: 123)]),
        meal('c', [...reisgericht, ing('Olivenöl', grams: 12, kcal: 106, micros: {'vit_e_mg': 1.2})]),
      ];
      final s = suggestMissingIngredients(current: keysOf(['Reis', 'Paprika']), history: history);
      expect(s, hasLength(1));
      expect(s.single.label, 'Olivenöl');
      expect([s.single.meals, s.single.similarMeals], [3, 3]);
      expect(s.single.medianGrams, 12);
      expect(s.single.per100!['kcal'], closeTo(880, 1e-9), reason: 'je 100 g aus dem juengsten Vorkommen mit Menge und Werten (a: 88 kcal auf 10 g)');
      expect(s.single.micros100!['vit_e_mg'], closeTo(10, 1e-9), reason: '1,2 mg auf 12 g sind 10 mg je 100 g');
    });

    test('ein Einzelfall ist kein Muster: nur eine aehnliche Mahlzeit gibt keinen Vorschlag', () {
      expect(
        suggestMissingIngredients(current: keysOf(['Reis', 'Paprika']), history: [
          meal('a', [...reisgericht, ing('Öl', grams: 10)]),
        ]),
        isEmpty,
      );
    });

    test('eine Zutat nur in einer von drei aehnlichen Mahlzeiten wird nicht vorgeschlagen', () {
      final history = [
        meal('a', [...reisgericht, ing('Öl', grams: 10)]),
        meal('b', reisgericht),
        meal('c', reisgericht),
      ];
      expect(suggestMissingIngredients(current: keysOf(['Reis', 'Paprika']), history: history), isEmpty);
    });

    test('zwei von vier reicht (die Haelfte), eine von drei nicht', () {
      final history = [
        meal('a', [...reisgericht, ing('Öl', grams: 10)]),
        meal('b', [...reisgericht, ing('Öl', grams: 10)]),
        meal('c', reisgericht),
        meal('d', reisgericht),
      ];
      expect(suggestMissingIngredients(current: keysOf(['Reis', 'Paprika']), history: history).single.label, 'Öl');
    });

    test('was schon in der aktuellen Mahlzeit steht, wird nicht noch einmal vorgeschlagen', () {
      final history = [
        meal('a', [...reisgericht, ing('Öl', grams: 10)]),
        meal('b', [...reisgericht, ing('Öl', grams: 10)]),
      ];
      expect(suggestMissingIngredients(current: keysOf(['Reis', 'Paprika', 'Öl']), history: history), isEmpty);
    });

    test('unaehnliche Mahlzeiten zaehlen nicht: eine gemeinsame Zutat reicht bei zwei aktuellen nicht', () {
      final history = [
        meal('a', [ing('Reis', grams: 100), ing('Huhn', grams: 150), ing('Öl', grams: 10)]),
        meal('b', [ing('Reis', grams: 100), ing('Lachs', grams: 150), ing('Öl', grams: 10)]),
      ];
      expect(suggestMissingIngredients(current: keysOf(['Reis', 'Paprika']), history: history), isEmpty);
    });

    test('die Haelfte der aktuellen Zutaten muss vorkommen: zwei von fuenf reichen nicht', () {
      final history = [
        meal('a', [ing('Reis'), ing('Paprika'), ing('Öl', grams: 10)]),
        meal('b', [ing('Reis'), ing('Paprika'), ing('Öl', grams: 10)]),
      ];
      expect(suggestMissingIngredients(current: keysOf(['Reis', 'Paprika', 'Huhn', 'Erbsen', 'Mais']), history: history), isEmpty);
      expect(suggestMissingIngredients(current: keysOf(['Reis', 'Paprika', 'Huhn']), history: history), hasLength(1));
    });

    test('bei nur einer aktuellen Zutat genuegt diese eine', () {
      final history = [
        meal('a', [ing('Nudeln'), ing('Parmesan', grams: 15)]),
        meal('b', [ing('Nudeln'), ing('Parmesan', grams: 20)]),
      ];
      final s = suggestMissingIngredients(current: keysOf(['Nudeln']), history: history);
      expect(s.single.label, 'Parmesan');
      expect(s.single.medianGrams, 17.5);
    });

    test('ohne aktuelle Zutat oder ohne Verlauf nichts', () {
      expect(suggestMissingIngredients(current: const {}, history: [meal('a', reisgericht), meal('b', reisgericht)]), isEmpty);
      expect(suggestMissingIngredients(current: keysOf(['Reis', 'Paprika']), history: const []), isEmpty);
    });

    test('hoechstens vier, die haeufigsten zuerst, bei Gleichstand alphabetisch', () {
      final extras = ['Öl', 'Salz', 'Butter', 'Pfeffer', 'Knoblauch'];
      final history = [
        for (var m = 0; m < 4; m++) meal('m$m', [...reisgericht, for (final e in extras) if (e != 'Knoblauch' || m < 2) ing(e, grams: 5)]),
      ];
      final s = suggestMissingIngredients(current: keysOf(['Reis', 'Paprika']), history: history);
      expect(s.map((x) => x.label), ['Butter', 'Pfeffer', 'Salz', 'Öl']);
    });

    test('Zutaten ohne Menge werden vorgeschlagen, ohne Median und ohne Profil', () {
      final history = [
        meal('a', [...reisgericht, ing('Gewürz')]),
        meal('b', [...reisgericht, ing('Gewürz')]),
      ];
      final s = suggestMissingIngredients(current: keysOf(['Reis', 'Paprika']), history: history).single;
      expect(s.medianGrams, isNull);
      expect(s.per100, isNull);
      expect(s.micros100, isNull);
    });

    test('Produkte und BLS-Eintraege werden ueber ihren Schluessel verglichen, nicht ueber den Namen', () {
      final history = [
        meal('a', [ing('Reis (alt)', productId: 'reis'), ing('Paprika', blsCode: 'G1'), ing('Öl', productId: 'oel', grams: 10)]),
        meal('b', [ing('Reis neu', productId: 'reis'), ing('Gemüsepaprika rot', blsCode: 'G1'), ing('Öl', productId: 'oel', grams: 10)]),
      ];
      final current = {ingredientKey(productId: 'reis', name: 'Reis'), ingredientKey(blsCode: 'G1', name: 'Paprika')};
      final s = suggestMissingIngredients(current: current, history: history);
      expect(s.single.productId, 'oel');
    });

    test('ein gleicher Name zaehlt als vorhanden, auch wenn nur die fruehere Zutat einen BLS-Eintrag hat', () {
      final history = [
        meal('a', [...reisgericht, ing('Olivenöl', blsCode: 'Q120000', grams: 10)]),
        meal('b', [...reisgericht, ing('Olivenöl', blsCode: 'Q120000', grams: 10)]),
      ];
      final current = keysOf(['Reis', 'Paprika', 'Olivenöl']);
      expect(suggestMissingIngredients(current: current, history: history), isEmpty);
      // aktuelle Zutat mit BLS-Eintrag (Schluessel b:..), fruehere nur mit Namen: ueber currentNames erkannt
      final withBls = {ingredientKey(blsCode: 'Q120000', name: 'Olivenöl'), ...keysOf(['Reis', 'Paprika'])};
      final plain = [
        meal('a', [...reisgericht, ing('Olivenöl', grams: 10)]),
        meal('b', [...reisgericht, ing('Olivenöl', grams: 10)]),
      ];
      expect(suggestMissingIngredients(current: withBls, history: plain), hasLength(1));
      expect(suggestMissingIngredients(current: withBls, currentNames: keysOf(['Reis', 'Paprika', 'Olivenöl']), history: plain), isEmpty);
    });

    test('der juengste Name und das juengste Vorkommen mit Profil gelten', () {
      final history = [
        meal('neu', [...reisgericht, ing('Olivenöl nativ', blsCode: 'Q120000', grams: 10)]),
        meal('alt', [...reisgericht, ing('Olivenöl', blsCode: 'Q120000', grams: 10, kcal: 88)]),
      ];
      final s = suggestMissingIngredients(current: keysOf(['Reis', 'Paprika']), history: history).single;
      expect(s.label, 'Olivenöl nativ');
      expect(s.per100!['kcal'], closeTo(880, 1e-9), reason: 'das juengere Vorkommen hat kein Profil, das aeltere schon');
    });
  });
}
