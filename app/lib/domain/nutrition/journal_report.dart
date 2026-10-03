/// Monatsbericht des Essenstagebuchs fuer den PDF-Export (Ausbau 1.12): was an welchem Tag gegessen wurde, kcal je Mahlzeit und
/// Tag, Durchschnitt und die haeufigsten Gerichte. Reine Funktionen ohne Datenbankzugriff, bauen auf [buildMonthJournal] und
/// [buildDailyNutrition] auf, damit die Zahlen im PDF genau die der App sind.
///
/// Wie im Journal gilt: ein Tag ohne Eintrag ist "nicht erfasst" und kommt im Bericht nicht als 0 kcal vor, ein Tag ohne bekannte
/// Naehrwerte hat keine kcal-Angabe (nicht 0), und der Durchschnitt geht nur ueber Tage mit bekannten kcal.
library;

import 'daily_nutrition.dart';
import 'frequent_meals.dart';
import 'journal.dart';

/// Eine Mahlzeit fuer den Bericht (unabhaengig von der Datenbank-Klasse).
typedef ReportMealInput = ({
  String id,
  DateTime eatenAtUtc,
  String title,
  String mealType,
  double servingsEaten,
  double servingsMade,
  bool isEstimate,
  bool hasPhoto,
});

class ReportMeal {
  const ReportMeal({required this.id, required this.eatenAtUtc, required this.title, required this.mealType, required this.kcal, required this.isEstimate, required this.hasPhoto});

  final String id;
  final DateTime eatenAtUtc;
  final String title;
  final String mealType;

  /// Bekannte kcal der gegessenen Portion, `null`, wenn fuer keine Zutat ein Wert bekannt ist.
  final double? kcal;
  final bool isEstimate;
  final bool hasPhoto;
}

/// Ein erfasster Tag des Berichts.
class ReportDay {
  const ReportDay({required this.day, required this.meals, required this.kcal, required this.hasEstimates, required this.photoMealId});

  /// Kalendertag in Wiener Ortszeit.
  final DateTime day;

  /// Mahlzeiten des Tages, die fruehere zuerst (Lesereihenfolge eines Tagebuchs).
  final List<ReportMeal> meals;

  /// Bekannte kcal des Tages, `null` ohne jeden bekannten Wert.
  final double? kcal;
  final bool hasEstimates;

  /// Mahlzeit, deren Foto den Tag im Bericht vertritt (die juengste mit Foto).
  final String? photoMealId;
}

class JournalReport {
  const JournalReport({
    required this.year,
    required this.month,
    required this.daysInMonth,
    required this.days,
    required this.mealCount,
    required this.daysWithKnownKcal,
    required this.averagePerDay,
    required this.hasEstimates,
    required this.topMeals,
    required this.kcalByDay,
  });

  final int year;
  final int month;
  final int daysInMonth;

  /// Nur die erfassten Tage, in Reihenfolge.
  final List<ReportDay> days;
  final int mealCount;

  /// Tage, an denen mindestens eine Zutat einen Energiewert hat: nur diese gehen in [averagePerDay] ein.
  final int daysWithKnownKcal;

  /// Durchschnitt je Tag mit bekannten kcal, `null`, wenn es keinen solchen Tag gibt.
  final NutrientTotals? averagePerDay;
  final bool hasEstimates;
  final List<FrequentMeal> topMeals;

  /// kcal je Kalendertag (1 bis [daysInMonth]) fuer das Kalenderraster, `null` fuer nicht erfasste Tage und Tage ohne bekannte Werte.
  final Map<int, double> kcalByDay;

  int get daysLogged => days.length;
}

ReportMeal? _mealOrNull(ReportMealInput? m, ReportMeal Function(ReportMealInput) build) => m == null ? null : build(m);

/// Bericht fuer den Monat. `null`, wenn in dem Monat nichts erfasst wurde (dann gibt es nichts zu exportieren).
JournalReport? buildJournalReport({
  required int year,
  required int month,
  required Iterable<ReportMealInput> meals,
  required Iterable<NutritionIngredient> ingredients,
}) {
  final list = meals.toList();
  final ingredientList = ingredients.toList();
  final journalMeals = [
    for (final m in list)
      (
        id: m.id,
        eatenAtUtc: m.eatenAtUtc,
        title: m.title,
        hasPhoto: m.hasPhoto,
        servingsEaten: m.servingsEaten,
        servingsMade: m.servingsMade,
        isEstimate: m.isEstimate,
      ),
  ];
  final month0 = buildMonthJournal(year: year, month: month, meals: journalMeals, ingredients: ingredientList);
  if (!month0.any((d) => d.logged)) return null;

  final byId = {for (final m in list) m.id: m};
  final ingredientsByMeal = <String, List<NutritionIngredient>>{};
  for (final i in ingredientList) {
    ingredientsByMeal.putIfAbsent(i.mealId, () => []).add(i);
  }

  ReportMeal reportMeal(ReportMealInput m) {
    final own = ingredientsByMeal[m.id] ?? const <NutritionIngredient>[];
    final known = own.any((i) => i.kcal != null);
    final kcal = known
        ? buildDailyNutrition(
            [(id: m.id, eatenAtUtc: m.eatenAtUtc, servingsEaten: m.servingsEaten, servingsMade: m.servingsMade, isEstimate: m.isEstimate)],
            own,
          ).single.totals.kcal
        : null;
    return ReportMeal(id: m.id, eatenAtUtc: m.eatenAtUtc, title: m.title, mealType: m.mealType, kcal: kcal, isEstimate: m.isEstimate, hasPhoto: m.hasPhoto);
  }

  final days = <ReportDay>[];
  final inMonth = <ReportMealInput>[];
  for (final d in month0) {
    if (!d.logged) continue;
    // JournalDay.mealIds ist spaetere zuerst, ein Tagebuch liest sich von frueh nach spaet
    final dayMeals = [for (final id in d.mealIds.reversed) ?_mealOrNull(byId[id], reportMeal)];
    inMonth.addAll([for (final id in d.mealIds) ?byId[id]]);
    days.add(ReportDay(day: d.day, meals: dayMeals, kcal: d.kcal, hasEstimates: d.hasEstimates, photoMealId: d.photoMealId));
  }

  // Durchschnitt ueber die Tage mit bekannten kcal (FR-15: unbekannt ist nicht 0)
  final monthIds = {for (final m in inMonth) m.id};
  final nutrition = {
    for (final n in buildDailyNutrition(
      [for (final m in inMonth) (id: m.id, eatenAtUtc: m.eatenAtUtc, servingsEaten: m.servingsEaten, servingsMade: m.servingsMade, isEstimate: m.isEstimate)],
      ingredientList.where((i) => monthIds.contains(i.mealId)),
    ))
      n.day: n,
  };
  var sum = const NutrientTotals();
  var counted = 0;
  for (final d in days) {
    if (d.kcal == null) continue;
    final n = nutrition[d.day];
    if (n == null) continue;
    sum += n.totals;
    counted++;
  }

  return JournalReport(
    year: year,
    month: month,
    daysInMonth: month0.length,
    days: days,
    mealCount: inMonth.length,
    daysWithKnownKcal: counted,
    averagePerDay: counted == 0 ? null : sum.scaled(1 / counted),
    hasEstimates: days.any((d) => d.hasEstimates),
    topMeals: frequentMeals([for (final m in inMonth) (id: m.id, title: m.title, eatenAtUtc: m.eatenAtUtc)], limit: 5),
    kcalByDay: {for (final d in days) if (d.kcal != null) d.day.day: d.kcal!},
  );
}
