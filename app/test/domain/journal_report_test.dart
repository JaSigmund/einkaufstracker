import 'package:einkaufstracker/domain/nutrition/daily_nutrition.dart';
import 'package:einkaufstracker/domain/nutrition/journal_report.dart';
import 'package:flutter_test/flutter_test.dart';

/// Monatsbericht fuer den PDF-Export (Ausbau 1.12).
ReportMealInput meal(String id, DateTime utc, {String title = 'Essen', String type = 'lunch', double eaten = 1, double made = 1, bool estimate = false, bool photo = false}) =>
    (id: id, eatenAtUtc: utc, title: title, mealType: type, servingsEaten: eaten, servingsMade: made, isEstimate: estimate, hasPhoto: photo);

NutritionIngredient ing(String mealId, {double? kcal, double? protein}) =>
    (mealId: mealId, kcal: kcal, proteinG: protein, fatG: null, carbsG: null, sugarG: null, fiberG: null, saltG: null);

void main() {
  JournalReport build(List<ReportMealInput> meals, List<NutritionIngredient> ingredients) =>
      buildJournalReport(year: 2026, month: 9, meals: meals, ingredients: ingredients)!;

  test('ein Monat ohne Eintrag hat keinen Bericht', () {
    expect(buildJournalReport(year: 2026, month: 9, meals: [meal('a', DateTime.utc(2026, 10, 1, 10))], ingredients: const []), isNull);
    expect(buildJournalReport(year: 2026, month: 9, meals: const [], ingredients: const []), isNull);
  });

  test('nur erfasste Tage, Mahlzeiten von frueh nach spaet, kcal je Mahlzeit und Tag', () {
    final r = build(
      [
        meal('abend', DateTime.utc(2026, 9, 3, 17), title: 'Pasta', type: 'dinner'),
        meal('mittag', DateTime.utc(2026, 9, 3, 10), title: 'Suppe'),
        meal('sonst', DateTime.utc(2026, 9, 10, 8), title: 'Müsli', type: 'breakfast'),
      ],
      [ing('abend', kcal: 700), ing('abend', kcal: 100), ing('mittag', kcal: 300), ing('sonst', kcal: 400)],
    );
    expect(r.daysInMonth, 30);
    expect(r.daysLogged, 2);
    expect(r.mealCount, 3);
    expect(r.days.map((d) => d.day.day), [3, 10]);
    final d3 = r.days.first;
    expect(d3.meals.map((m) => m.title), ['Suppe', 'Pasta'], reason: 'frueh zuerst');
    expect(d3.meals.map((m) => m.kcal), [300, 800]);
    expect(d3.kcal, 1100);
    expect(r.kcalByDay, {3: 1100, 10: 400});
  });

  test('kcal je Mahlzeit beruecksichtigt die gegessene Portion', () {
    final r = build([meal('a', DateTime.utc(2026, 9, 3, 10), eaten: 1, made: 4)], [ing('a', kcal: 1000)]);
    expect(r.days.single.meals.single.kcal, 250);
    expect(r.days.single.kcal, 250);
  });

  test('ohne bekannten Wert ist kcal null, nicht 0, und der Tag taucht nicht im Raster auf', () {
    final r = build([meal('a', DateTime.utc(2026, 9, 3, 10)), meal('b', DateTime.utc(2026, 9, 4, 10))], [ing('a'), ing('b', kcal: 500)]);
    expect(r.days.first.meals.single.kcal, isNull);
    expect(r.days.first.kcal, isNull);
    expect(r.kcalByDay.containsKey(3), isFalse);
    expect(r.kcalByDay[4], 500);
  });

  test('Durchschnitt nur ueber Tage mit bekannten kcal', () {
    final r = build(
      [meal('a', DateTime.utc(2026, 9, 3, 10)), meal('b', DateTime.utc(2026, 9, 4, 10)), meal('c', DateTime.utc(2026, 9, 5, 10))],
      [ing('a', kcal: 1000, protein: 40), ing('b', kcal: 2000, protein: 80), ing('c')],
    );
    expect(r.daysLogged, 3);
    expect(r.daysWithKnownKcal, 2);
    expect(r.averagePerDay!.kcal, 1500);
    expect(r.averagePerDay!.proteinG, 60);
  });

  test('ohne jeden bekannten Wert gibt es keinen Durchschnitt', () {
    final r = build([meal('a', DateTime.utc(2026, 9, 3, 10))], [ing('a')]);
    expect(r.averagePerDay, isNull);
    expect(r.daysWithKnownKcal, 0);
  });

  test('Schaetzwerte werden markiert, am Tag und im Bericht', () {
    final r = build([meal('a', DateTime.utc(2026, 9, 3, 10), estimate: true), meal('b', DateTime.utc(2026, 9, 4, 10))], [ing('a', kcal: 600), ing('b', kcal: 500)]);
    expect(r.hasEstimates, isTrue);
    expect(r.days.first.hasEstimates, isTrue);
    expect(r.days.last.hasEstimates, isFalse);
    expect(r.days.first.meals.single.isEstimate, isTrue);
  });

  test('haeufigste Gerichte des Monats und das Foto des Tages (die juengste Mahlzeit mit Foto)', () {
    final r = build(
      [
        meal('a', DateTime.utc(2026, 9, 3, 10), title: 'Müsli', photo: true),
        meal('b', DateTime.utc(2026, 9, 4, 10), title: 'müsli'),
        meal('c', DateTime.utc(2026, 9, 4, 16), title: 'Kuchen', photo: true),
        meal('d', DateTime.utc(2026, 9, 4, 12), title: 'Suppe', photo: true),
      ],
      const [],
    );
    expect(r.topMeals.first.title, 'müsli', reason: 'Titel der juengsten Mahlzeit der Gruppe');
    expect(r.topMeals.first.count, 2);
    expect(r.days.last.photoMealId, 'c');
    expect(r.days.first.photoMealId, 'a');
  });

  test('Zeiten um Mitternacht zaehlen nach Wiener Ortszeit zum richtigen Tag', () {
    // 30.9. 22:30 UTC ist in Wien (Sommerzeit, UTC+2) bereits der 1.10., also nicht mehr im September
    final r = build([meal('a', DateTime.utc(2026, 9, 30, 22, 30)), meal('b', DateTime.utc(2026, 9, 30, 20))], const []);
    expect(r.days.map((d) => d.day.day), [30]);
    expect(r.mealCount, 1);
  });
}
