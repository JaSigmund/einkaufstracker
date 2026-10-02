/// Journal-Ansicht des Essenstagebuchs (Phase 7e, Doku 15 §3.6/§7): Monats-Mosaik und Wochenrueckblick.
/// Reine Funktionen ohne Datenbankzugriff, bauen auf `buildDailyNutrition` auf (FR-13, FR-15, FR-17).
library;

import '../receipt/vienna_time.dart';
import 'daily_nutrition.dart';
import 'frequent_meals.dart';

/// Eine Mahlzeit fuer das Journal (unabhaengig von der Datenbank-Klasse).
typedef JournalMeal = ({
  String id,
  DateTime eatenAtUtc,
  String title,
  bool hasPhoto,
  double servingsEaten,
  double servingsMade,
  bool isEstimate,
});

NutritionMeal _nutritionMeal(JournalMeal m) =>
    (id: m.id, eatenAtUtc: m.eatenAtUtc, servingsEaten: m.servingsEaten, servingsMade: m.servingsMade, isEstimate: m.isEstimate);

DateTime _vienna(DateTime utc) {
  final l = utcToViennaLocal(utc);
  return DateTime(l.year, l.month, l.day);
}

/// Ein Kalendertag im Monats-Mosaik.
class JournalDay {
  JournalDay(this.day);

  /// Kalendertag in Wiener Ortszeit (Mitternacht, ohne Zeitzone).
  final DateTime day;

  /// Mahlzeiten des Tages, die spaetere zuerst.
  final mealIds = <String>[];

  /// Mahlzeit, deren Foto den Tag im Mosaik vertritt (die juengste mit Foto), `null` ohne Foto.
  String? photoMealId;

  /// Bekannte kcal des Tages. `null`, wenn fuer keine Zutat ein Wert bekannt ist: ein Tag ohne Naehrwerte ist
  /// "unbekannt", nicht "0 kcal" (FR-15).
  double? kcal;

  bool hasEstimates = false;

  /// Es gibt mindestens eine Mahlzeit. Ein Tag ohne Eintrag ist "nicht erfasst" (FR-15).
  bool get logged => mealIds.isNotEmpty;
}

/// Alle Tage eines Monats in Reihenfolge, auch die ohne Eintrag (damit das Mosaik die Luecken zeigt).
List<JournalDay> buildMonthJournal({
  required int year,
  required int month,
  required Iterable<JournalMeal> meals,
  required Iterable<NutritionIngredient> ingredients,
}) {
  final count = DateTime(year, month + 1, 0).day;
  final days = [for (var d = 1; d <= count; d++) JournalDay(DateTime(year, month, d))];

  final inMonth = <JournalMeal>[];
  for (final m in meals) {
    final day = _vienna(m.eatenAtUtc);
    if (day.year == year && day.month == month) inMonth.add(m);
  }
  inMonth.sort((a, b) => b.eatenAtUtc.compareTo(a.eatenAtUtc));
  for (final m in inMonth) {
    final d = days[_vienna(m.eatenAtUtc).day - 1];
    d.mealIds.add(m.id);
    if (d.photoMealId == null && m.hasPhoto) d.photoMealId = m.id;
  }

  // kcal gilt nur als bekannt, wenn mindestens eine Zutat des Tages einen Energiewert hat
  final dayOf = {for (final m in inMonth) m.id: _vienna(m.eatenAtUtc)};
  final known = <DateTime>{
    for (final i in ingredients)
      if (i.kcal != null && dayOf.containsKey(i.mealId)) dayOf[i.mealId]!,
  };
  for (final n in buildDailyNutrition(inMonth.map(_nutritionMeal), ingredients.where((i) => dayOf.containsKey(i.mealId)))) {
    final d = days[n.day.day - 1];
    d.hasEstimates = n.hasEstimates;
    if (known.contains(n.day)) d.kcal = n.totals.kcal;
  }
  return days;
}

/// Rueckblick auf eine Woche (Montag bis Sonntag, Wiener Zeit).
class WeekReview {
  const WeekReview({
    required this.weekStart,
    required this.mealCount,
    required this.daysLogged,
    required this.averagePerDay,
    required this.hasEstimates,
    required this.topMeals,
    required this.photoMealIds,
  });

  final DateTime weekStart;
  final int mealCount;

  /// Tage der Woche mit mindestens einer Mahlzeit (von 7).
  final int daysLogged;

  /// Durchschnitt je erfasstem Tag, nicht je Kalendertag (FR-15).
  final NutrientTotals averagePerDay;
  final bool hasEstimates;

  /// Die am haeufigsten gegessenen Gerichte der Woche.
  final List<FrequentMeal> topMeals;

  /// Mahlzeiten mit Foto, die juengste zuerst (hoechstens [maxPhotos]).
  final List<String> photoMealIds;

  static const maxPhotos = 6;
}

/// Rueckblick auf die Woche, die mit [weekStart] (Montag) beginnt. `null`, wenn in der Woche nichts erfasst wurde.
WeekReview? buildWeekReview({
  required DateTime weekStart,
  required Iterable<JournalMeal> meals,
  required Iterable<NutritionIngredient> ingredients,
}) {
  final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
  final end = DateTime(start.year, start.month, start.day + 7);
  final inWeek = [
    for (final m in meals)
      if (!_vienna(m.eatenAtUtc).isBefore(start) && _vienna(m.eatenAtUtc).isBefore(end)) m,
  ];
  if (inWeek.isEmpty) return null;
  inWeek.sort((a, b) => b.eatenAtUtc.compareTo(a.eatenAtUtc));
  final ids = {for (final m in inWeek) m.id};

  final days = buildDailyNutrition(inWeek.map(_nutritionMeal), ingredients.where((i) => ids.contains(i.mealId)));
  final week = buildWeeklyNutrition(days).single;
  final top = frequentMeals([for (final m in inWeek) (id: m.id, title: m.title, eatenAtUtc: m.eatenAtUtc)], limit: 3);
  return WeekReview(
    weekStart: start,
    mealCount: inWeek.length,
    daysLogged: week.daysLogged,
    averagePerDay: week.averagePerDay,
    hasEstimates: week.hasEstimates,
    topMeals: top,
    photoMealIds: [for (final m in inWeek) if (m.hasPhoto) m.id].take(WeekReview.maxPhotos).toList(),
  );
}
