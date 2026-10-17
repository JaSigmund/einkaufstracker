/// Tages- und Wochenwerte aus dem Essenstagebuch (Doku 15 Essenstagebuch und Naehrwerte, §3.5, FR-13, FR-15, FR-17).
/// Reine Funktionen ohne Datenbankzugriff, gleiches Muster wie `buildMonthReport`.
library;

import '../../core/vienna_time.dart';

/// Eine Mahlzeit fuer die Auswertung (unabhaengig von der Datenbank-Klasse).
typedef NutritionMeal = ({String id, DateTime eatenAtUtc, double servingsEaten, double servingsMade, bool isEstimate});

/// Eine Zutat mit ihrem Naehrwert-Snapshot. `null` heisst "nicht bekannt" und ist nicht dasselbe wie 0.
typedef NutritionIngredient = ({
  String mealId,
  double? kcal,
  double? proteinG,
  double? fatG,
  double? carbsG,
  double? sugarG,
  double? fiberG,
  double? saltG,
});

/// Die sieben ausgewerteten Naehrwerte (LH-MEAL-09), Summe der bekannten Beitraege.
class NutrientTotals {
  const NutrientTotals({this.kcal = 0, this.proteinG = 0, this.fatG = 0, this.carbsG = 0, this.sugarG = 0, this.fiberG = 0, this.saltG = 0});

  final double kcal;
  final double proteinG;
  final double fatG;
  final double carbsG;
  final double sugarG;
  final double fiberG;
  final double saltG;

  NutrientTotals operator +(NutrientTotals o) => NutrientTotals(
        kcal: kcal + o.kcal,
        proteinG: proteinG + o.proteinG,
        fatG: fatG + o.fatG,
        carbsG: carbsG + o.carbsG,
        sugarG: sugarG + o.sugarG,
        fiberG: fiberG + o.fiberG,
        saltG: saltG + o.saltG,
      );

  NutrientTotals scaled(double factor) => NutrientTotals(
        kcal: kcal * factor,
        proteinG: proteinG * factor,
        fatG: fatG * factor,
        carbsG: carbsG * factor,
        sugarG: sugarG * factor,
        fiberG: fiberG * factor,
        saltG: saltG * factor,
      );
}

/// Werte eines Kalendertags (Wiener Zeit).
class DayNutrition {
  DayNutrition(this.day);

  /// Kalendertag in Wiener Ortszeit (Mitternacht, ohne Zeitzone).
  final DateTime day;
  NutrientTotals totals = const NutrientTotals();
  int meals = 0;

  /// Zutaten insgesamt und davon mit mindestens einem bekannten Naehrwert: Grundlage der Datenqualitaet (§3.5).
  int ingredients = 0;
  int ingredientsWithNutrients = 0;

  /// Mindestens eine Mahlzeit des Tages ist nur geschaetzt (z.B. Restaurant), FR-17.
  bool hasEstimates = false;

  /// Anteil der Zutaten mit hinterlegten Naehrwerten, 1,0 wenn der Tag keine Zutaten hat.
  double get dataQuality => ingredients == 0 ? 1 : ingredientsWithNutrients / ingredients;
}

/// Werte einer Woche als Tagesdurchschnitt ueber die **erfassten** Tage (FR-15: ein Tag ohne Eintrag ist
/// "nicht erfasst" und geht nicht als 0 kcal in den Mittelwert ein).
class WeekNutrition {
  WeekNutrition(this.weekStart, this.averagePerDay, this.daysLogged, this.hasEstimates);

  /// Montag der Woche (Wiener Ortszeit, Mitternacht).
  final DateTime weekStart;
  final NutrientTotals averagePerDay;
  final int daysLogged;
  final bool hasEstimates;
}

bool _hasAny(NutritionIngredient i) =>
    i.kcal != null || i.proteinG != null || i.fatG != null || i.carbsG != null || i.sugarG != null || i.fiberG != null || i.saltG != null;

NutrientTotals _of(NutritionIngredient i) => NutrientTotals(
      kcal: i.kcal ?? 0,
      proteinG: i.proteinG ?? 0,
      fatG: i.fatG ?? 0,
      carbsG: i.carbsG ?? 0,
      sugarG: i.sugarG ?? 0,
      fiberG: i.fiberG ?? 0,
      saltG: i.saltG ?? 0,
    );

/// Tageswerte, aeltester Tag zuerst. Pro Mahlzeit gilt FR-13: Summe der Zutaten x `servingsEaten / servingsMade`.
/// Tage ohne Mahlzeit kommen nicht vor (FR-15). Zutaten ohne passende Mahlzeit werden ignoriert.
List<DayNutrition> buildDailyNutrition(Iterable<NutritionMeal> meals, Iterable<NutritionIngredient> ingredients) {
  final byMeal = <String, List<NutritionIngredient>>{};
  for (final i in ingredients) {
    byMeal.putIfAbsent(i.mealId, () => []).add(i);
  }
  final days = <DateTime, DayNutrition>{};
  for (final m in meals) {
    if (m.servingsMade <= 0) continue;
    final local = utcToViennaLocal(m.eatenAtUtc);
    final day = DateTime(local.year, local.month, local.day);
    final d = days.putIfAbsent(day, () => DayNutrition(day));
    final share = m.servingsEaten / m.servingsMade;
    final own = byMeal[m.id] ?? const <NutritionIngredient>[];
    var sum = const NutrientTotals();
    for (final i in own) {
      sum = sum + _of(i);
      d.ingredients++;
      if (_hasAny(i)) d.ingredientsWithNutrients++;
    }
    d.totals = d.totals + sum.scaled(share);
    d.meals++;
    if (m.isEstimate) d.hasEstimates = true;
  }
  return days.values.toList()..sort((a, b) => a.day.compareTo(b.day));
}

/// Wochenwerte aus den Tageswerten, aelteste Woche zuerst. Die Woche beginnt am Montag.
List<WeekNutrition> buildWeeklyNutrition(List<DayNutrition> days) {
  final weeks = <DateTime, List<DayNutrition>>{};
  for (final d in days) {
    final monday = DateTime(d.day.year, d.day.month, d.day.day - (d.day.weekday - 1));
    weeks.putIfAbsent(monday, () => []).add(d);
  }
  final result = [
    for (final e in weeks.entries)
      WeekNutrition(
        e.key,
        e.value.fold(const NutrientTotals(), (s, d) => s + d.totals).scaled(1 / e.value.length),
        e.value.length,
        e.value.any((d) => d.hasEstimates),
      ),
  ]..sort((a, b) => a.weekStart.compareTo(b.weekStart));
  return result;
}
