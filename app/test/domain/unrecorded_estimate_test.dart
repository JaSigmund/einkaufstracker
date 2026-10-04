import 'package:einkaufstracker/domain/nutrition/daily_nutrition.dart';
import 'package:einkaufstracker/domain/nutrition/unrecorded_estimate.dart';
import 'package:flutter_test/flutter_test.dart';

/// Schaetzung des Nicht-Erfassten und Ringanteil (Journal, Phase 7d/7e).
NutritionMeal meal(String id, {double eaten = 1, double made = 1}) =>
    (id: id, eatenAtUtc: DateTime.utc(2026, 10, 3, 10), servingsEaten: eaten, servingsMade: made, isEstimate: false);
UnrecordedIngredient ing(String mealId, double? grams, double? kcal) => (mealId: mealId, grams: grams, kcal: kcal);

void main() {
  group('kcalPerGram', () {
    test('mengengewichtet: viel Reis zaehlt mehr als ein Loeffel Oel', () {
      // 300 g Reis zu 390 kcal und 10 g Oel zu 90 kcal: 480 kcal auf 310 g
      expect(kcalPerGram([ing('m', 300, 390), ing('m', 10, 90)]), closeTo(480 / 310, 1e-9));
    });

    test('ohne Grundlage null: unbekannte kcal, unbekannte oder leere Menge zaehlen nicht', () {
      expect(kcalPerGram(const []), isNull);
      expect(kcalPerGram([ing('m', 100, null), ing('m', null, 50), ing('m', 0, 10)]), isNull);
    });

    test('eine echte 0 kcal (Wasser) zaehlt als Wert', () {
      expect(kcalPerGram([ing('m', 250, 0), ing('m', 50, 100)]), closeTo(100 / 300, 1e-9));
    });
  });

  group('estimateUnrecorded', () {
    test('ohne Zutat ohne Naehrwerte gibt es nichts zu schaetzen', () {
      expect(estimateUnrecorded([meal('m')], [ing('m', 100, 150)]), isNull);
      expect(estimateUnrecorded([meal('m')], const []), isNull);
    });

    test('Dichte des Tages: 200 g unbekannt bei 1,5 kcal je g des Tages ergibt 300 kcal', () {
      final e = estimateUnrecorded([meal('m')], [ing('m', 200, 300), ing('m', 100, 150), ing('m', 200, null)])!;
      expect(e.basis, DensityBasis.day);
      expect(e.ingredients, 1);
      expect(e.withoutAmount, 0);
      expect(e.grams, 200);
      expect(e.kcal, closeTo(300, 1e-9));
    });

    test('ohne bekannte Zutat am Tag gilt der Verlauf', () {
      final e = estimateUnrecorded([meal('m')], [ing('m', 100, null)], historyKcalPerGram: 2)!;
      expect(e.basis, DensityBasis.history);
      expect(e.kcal, closeTo(200, 1e-9));
    });

    test('ohne Tag und Verlauf gilt der Faustwert, und das steht dran', () {
      final e = estimateUnrecorded([meal('m')], [ing('m', 100, null)])!;
      expect(e.basis, DensityBasis.fallback);
      expect(e.kcal, closeTo(100 * fallbackKcalPerGram, 1e-9));
      expect(estimateUnrecorded([meal('m')], [ing('m', 100, null)], historyKcalPerGram: 0)!.basis, DensityBasis.fallback);
    });

    test('Zutaten ohne Menge werden gezaehlt, aber nicht geschaetzt', () {
      final e = estimateUnrecorded([meal('m')], [ing('m', 100, 150), ing('m', null, null), ing('m', 0, null), ing('m', 50, null)])!;
      expect(e.ingredients, 1);
      expect(e.withoutAmount, 2);
      expect(e.grams, 50);
    });

    test('nur Zutaten ohne Menge: Schaetzung 0, aber die Luecke ist benannt', () {
      final e = estimateUnrecorded([meal('m')], [ing('m', null, null)])!;
      expect([e.ingredients, e.withoutAmount, e.grams, e.kcal], [0, 1, 0, 0]);
    });

    test('Portionsanteil: eine von vier Portionen', () {
      final e = estimateUnrecorded([meal('m', eaten: 1, made: 4)], [ing('m', 400, null)], historyKcalPerGram: 1)!;
      expect(e.grams, 100);
      expect(e.kcal, 100);
    });

    test('Zutaten fremder Mahlzeiten und Mahlzeiten ohne gekochte Portionen zaehlen nicht', () {
      expect(estimateUnrecorded([meal('m')], [ing('anderer', 100, null)]), isNull);
      expect(estimateUnrecorded([meal('m', made: 0)], [ing('m', 100, null)]), isNull);
    });

    test('mehrere Mahlzeiten desselben Tages teilen sich die Dichte', () {
      final e = estimateUnrecorded([meal('a'), meal('b')], [ing('a', 100, 200), ing('b', 100, null)])!;
      expect(e.basis, DensityBasis.day);
      expect(e.kcal, closeTo(200, 1e-9));
    });
  });

  group('ringFraction', () {
    test('Anteil von 0 bis 1, darueber bleibt der Ring voll', () {
      expect(ringFraction(900, 1800), 0.5);
      expect(ringFraction(1800, 1800), 1);
      expect(ringFraction(2500, 1800), 1);
      expect(ringFraction(0, 1800), 0);
    });

    test('ohne Wert oder ohne Richtwert null', () {
      expect(ringFraction(null, 1800), isNull);
      expect(ringFraction(500, null), isNull);
      expect(ringFraction(500, 0), isNull);
      expect(ringFraction(500, -3), isNull);
    });
  });
}
