import 'package:einkaufstracker/domain/nutrition/daily_nutrition.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tages- und Wochenwerte (Doku 15 §3.5, FR-13, FR-15, FR-17).
NutritionMeal meal(String id, DateTime utc, {double eaten = 1, double made = 1, bool estimate = false}) =>
    (id: id, eatenAtUtc: utc, servingsEaten: eaten, servingsMade: made, isEstimate: estimate);

NutritionIngredient ing(String mealId, {double? kcal, double? protein, double? fat, double? salt}) => (
      mealId: mealId,
      kcal: kcal,
      proteinG: protein,
      fatG: fat,
      carbsG: null,
      sugarG: null,
      fiberG: null,
      saltG: salt,
    );

void main() {
  group('buildDailyNutrition', () {
    test('FR-13: 800 kcal bei 1 von 4 Portionen ergeben 200 kcal (wie der Schema-Test v_daily_nutrition)', () {
      final days = buildDailyNutrition(
        [meal('m1', DateTime.utc(2026, 9, 22, 10), eaten: 1, made: 4)],
        [ing('m1', kcal: 800, protein: 20, salt: 2)],
      );
      expect(days, hasLength(1));
      expect(days.single.totals.kcal, 200);
      expect(days.single.totals.proteinG, 5);
      expect(days.single.totals.saltG, 0.5);
    });

    test('mehrere Zutaten und Mahlzeiten desselben Tages werden summiert', () {
      final days = buildDailyNutrition(
        [meal('m1', DateTime.utc(2026, 9, 22, 7)), meal('m2', DateTime.utc(2026, 9, 22, 17))],
        [ing('m1', kcal: 300), ing('m1', kcal: 100), ing('m2', kcal: 600)],
      );
      expect(days.single.totals.kcal, 1000);
      expect(days.single.meals, 2);
    });

    test('Tagesgrenze in Wiener Zeit: 23:30 UTC im Sommer (01:30 MESZ) gehoert schon zum naechsten Tag', () {
      final days = buildDailyNutrition(
        [meal('m1', DateTime.utc(2026, 7, 1, 23, 30)), meal('m2', DateTime.utc(2026, 7, 1, 21, 59))],
        [ing('m1', kcal: 100), ing('m2', kcal: 200)],
      );
      expect(days.map((d) => d.day), [DateTime(2026, 7, 1), DateTime(2026, 7, 2)]);
      expect(days.map((d) => d.totals.kcal), [200, 100]);
    });

    test('Tage ohne Mahlzeit kommen nicht vor (FR-15: "nicht erfasst", nicht 0 kcal)', () {
      final days = buildDailyNutrition(
        [meal('m1', DateTime.utc(2026, 9, 20, 10)), meal('m2', DateTime.utc(2026, 9, 23, 10))],
        [ing('m1', kcal: 100), ing('m2', kcal: 100)],
      );
      expect(days.map((d) => d.day.day), [20, 23]);
    });

    test('Tage sind aufsteigend sortiert, auch bei durcheinander gelieferten Mahlzeiten', () {
      final days = buildDailyNutrition(
        [meal('m2', DateTime.utc(2026, 9, 23, 10)), meal('m1', DateTime.utc(2026, 9, 20, 10))],
        [ing('m1', kcal: 1), ing('m2', kcal: 1)],
      );
      expect(days.map((d) => d.day.day), [20, 23]);
    });

    test('unbekannte Werte zaehlen als nicht bekannt, nicht als 0: Summe der bekannten Beitraege', () {
      final days = buildDailyNutrition(
        [meal('m1', DateTime.utc(2026, 9, 22, 10))],
        [ing('m1', kcal: 100), ing('m1', kcal: null, protein: 5)],
      );
      expect(days.single.totals.kcal, 100);
      expect(days.single.totals.proteinG, 5);
    });

    test('Datenqualitaet: Anteil der Zutaten mit Naehrwerten (§3.5)', () {
      final days = buildDailyNutrition(
        [meal('m1', DateTime.utc(2026, 9, 22, 10))],
        [ing('m1', kcal: 100), ing('m1', kcal: 50), ing('m1'), ing('m1')],
      );
      expect(days.single.ingredients, 4);
      expect(days.single.ingredientsWithNutrients, 2);
      expect(days.single.dataQuality, 0.5);
    });

    test('Tag ohne Zutaten: Datenqualitaet 1,0 statt Division durch null', () {
      final days = buildDailyNutrition([meal('m1', DateTime.utc(2026, 9, 22, 10))], const []);
      expect(days.single.dataQuality, 1);
      expect(days.single.totals.kcal, 0);
    });

    test('Schaetzwerte sind erkennbar (FR-17): ein geschaetzter Eintrag markiert den ganzen Tag', () {
      final days = buildDailyNutrition(
        [meal('m1', DateTime.utc(2026, 9, 22, 10)), meal('m2', DateTime.utc(2026, 9, 22, 19), estimate: true)],
        [ing('m1', kcal: 100), ing('m2', kcal: 800)],
      );
      expect(days.single.hasEstimates, isTrue);
      expect(buildDailyNutrition([meal('m1', DateTime.utc(2026, 9, 22, 10))], [ing('m1', kcal: 1)]).single.hasEstimates, isFalse);
    });

    test('Mahlzeit mit servingsMade 0 wird uebersprungen statt durch null zu teilen', () {
      expect(buildDailyNutrition([meal('m1', DateTime.utc(2026, 9, 22, 10), made: 0)], [ing('m1', kcal: 100)]), isEmpty);
    });

    test('Zutaten ohne passende Mahlzeit werden ignoriert', () {
      final days = buildDailyNutrition([meal('m1', DateTime.utc(2026, 9, 22, 10))], [ing('m1', kcal: 100), ing('fremd', kcal: 999)]);
      expect(days.single.totals.kcal, 100);
    });
  });

  group('buildWeeklyNutrition', () {
    List<DayNutrition> days(Map<int, double> kcalByDay) => buildDailyNutrition(
          [for (final d in kcalByDay.keys) meal('m$d', DateTime.utc(2026, 9, d, 10))],
          [for (final e in kcalByDay.entries) ing('m${e.key}', kcal: e.value)],
        );

    test('Tagesdurchschnitt ueber die erfassten Tage, nicht ueber sieben (FR-15)', () {
      // 21.09.2026 ist ein Montag: zwei erfasste Tage mit 2000 und 1000 kcal
      final weeks = buildWeeklyNutrition(days({21: 2000, 22: 1000}));
      expect(weeks, hasLength(1));
      expect(weeks.single.weekStart, DateTime(2026, 9, 21));
      expect(weeks.single.daysLogged, 2);
      expect(weeks.single.averagePerDay.kcal, 1500);
    });

    test('Tage verschiedener Wochen werden getrennt, aelteste Woche zuerst; Sonntag gehoert zur Vorwoche', () {
      final weeks = buildWeeklyNutrition(days({20: 100, 21: 200})); // 20.09. ist Sonntag, 21.09. Montag
      expect(weeks.map((w) => w.weekStart), [DateTime(2026, 9, 14), DateTime(2026, 9, 21)]);
      expect(weeks.map((w) => w.averagePerDay.kcal), [100, 200]);
    });

    test('Schaetzung eines Tages markiert die Woche', () {
      final d = buildDailyNutrition(
        [meal('m1', DateTime.utc(2026, 9, 21, 10), estimate: true), meal('m2', DateTime.utc(2026, 9, 22, 10))],
        [ing('m1', kcal: 100), ing('m2', kcal: 100)],
      );
      expect(buildWeeklyNutrition(d).single.hasEstimates, isTrue);
    });

    test('keine Tage: keine Wochen', () {
      expect(buildWeeklyNutrition(const []), isEmpty);
    });
  });
}
