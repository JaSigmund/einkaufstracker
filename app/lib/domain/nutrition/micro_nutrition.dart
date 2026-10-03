/// Tages- und Wochenwerte der Mikronaehrstoffe mit Datenabdeckung und Beitraegen (Phase N3, ADR-032, Doku 22 §4.3).
///
/// Reine Funktionen ohne Datenbankzugriff, gleiches Muster wie `buildDailyNutrition`. Regeln:
/// - **Unbekannt bleibt unbekannt.** Ein fehlender Wert ist keine 0. Jede Summe nennt die **Abdeckung**: "aus 9 von 11 Zutaten mit
///   Daten"; unter 100 % ist die Summe ein "mindestens".
/// - Die Abdeckung gilt **je Naehrstoff**, denn eine Zutat kann Vitamin C haben und Jod nicht.
/// - Portionsanteil wie bei den Makros (FR-13): Summe der Zutaten x `servingsEaten / servingsMade`.
/// - Wochenwerte sind der Durchschnitt ueber die **erfassten** Tage (FR-15), mit der Zahl der erfassten Tage.
library;

import '../receipt/vienna_time.dart';
import 'micros.dart';
import 'nutrient_registry.dart';

/// Eine Mahlzeit fuer die Mikronaehrstoff-Auswertung.
typedef MicroMeal = ({String id, String title, DateTime eatenAtUtc, double servingsEaten, double servingsMade});

/// Eine Zutat mit ihrem Mikronaehrstoff-Snapshot. `micros == null`: die Zutat hat keine Daten.
typedef MicroIngredient = ({String mealId, String name, Micros? micros});

/// Woher ein Teil des Tageswertes kommt ("Woher kommt das?").
class MicroContribution {
  const MicroContribution({required this.mealId, required this.mealTitle, required this.ingredient, required this.amount});

  final String mealId;
  final String mealTitle;
  final String ingredient;

  /// Beitrag zum Tageswert in der Einheit des Naehrstoffs (nach Portionsanteil).
  final double amount;
}

/// Ein Naehrstoff an einem Tag oder in einer Woche (Durchschnitt je erfasstem Tag).
class MicroValue {
  const MicroValue({this.total = 0, this.withData = 0, this.ingredients = 0, this.contributions = const []});

  /// Summe der bekannten Beitraege.
  final double total;

  /// Zutaten mit einem Wert fuer diesen Naehrstoff (auch einer echten 0) und alle Zutaten.
  final int withData;
  final int ingredients;

  /// Beitraege, groesster zuerst.
  final List<MicroContribution> contributions;

  /// Anteil der Zutaten mit Daten, 1,0 ohne Zutaten.
  double get coverage => ingredients == 0 ? 1 : withData / ingredients;

  /// Die Summe ist vollstaendig (jede Zutat hat einen Wert) und damit kein "mindestens".
  bool get complete => withData == ingredients;

  /// Gar keine Daten, obwohl es Zutaten gibt: die Anzeige sagt "unbekannt" statt "0".
  bool get unknown => ingredients > 0 && withData == 0;
}

/// Die Mikronaehrstoffe eines Kalendertags (Wiener Zeit).
class DayMicros {
  DayMicros(this.day);

  final DateTime day;
  final Map<String, MicroValue> byKey = {};
  int meals = 0;
  int ingredients = 0;
  bool hasEstimates = false;

  MicroValue valueOf(String key) => byKey[key] ?? MicroValue(ingredients: ingredients);
}

/// Mikronaehrstoffe einer Woche als Durchschnitt je erfasstem Tag.
class WeekMicros {
  WeekMicros(this.weekStart, this.daysLogged, this.byKey, this.ingredients);

  final DateTime weekStart;
  final int daysLogged;
  final Map<String, MicroValue> byKey;
  final int ingredients;

  MicroValue valueOf(String key) => byKey[key] ?? MicroValue(ingredients: ingredients);
}

/// Tageswerte, aeltester Tag zuerst. Tage ohne Mahlzeit kommen nicht vor. Zutaten ohne passende Mahlzeit werden ignoriert.
List<DayMicros> buildDailyMicros(Iterable<MicroMeal> meals, Iterable<MicroIngredient> ingredients, {bool Function(String mealId)? isEstimate}) {
  final byMeal = <String, List<MicroIngredient>>{};
  for (final i in ingredients) {
    byMeal.putIfAbsent(i.mealId, () => []).add(i);
  }
  final days = <DateTime, DayMicros>{};
  final totals = <DateTime, Map<String, double>>{};
  final withData = <DateTime, Map<String, int>>{};
  final contribs = <DateTime, Map<String, List<MicroContribution>>>{};

  for (final m in meals) {
    if (m.servingsMade <= 0) continue;
    final local = utcToViennaLocal(m.eatenAtUtc);
    final day = DateTime(local.year, local.month, local.day);
    final d = days.putIfAbsent(day, () => DayMicros(day));
    final share = m.servingsEaten / m.servingsMade;
    d.meals++;
    if (isEstimate?.call(m.id) ?? false) d.hasEstimates = true;
    for (final i in byMeal[m.id] ?? const <MicroIngredient>[]) {
      d.ingredients++;
      final micros = i.micros;
      if (micros == null) continue;
      for (final e in micros.entries) {
        final amount = e.value * share;
        totals.putIfAbsent(day, () => {}).update(e.key, (v) => v + amount, ifAbsent: () => amount);
        withData.putIfAbsent(day, () => {}).update(e.key, (v) => v + 1, ifAbsent: () => 1);
        contribs.putIfAbsent(day, () => {}).putIfAbsent(e.key, () => []).add(
              MicroContribution(mealId: m.id, mealTitle: m.title, ingredient: i.name, amount: amount),
            );
      }
    }
  }
  for (final e in days.entries) {
    final day = e.key;
    final d = e.value;
    for (final key in nutrientKeys) {
      final list = (contribs[day]?[key] ?? const <MicroContribution>[]).toList()..sort((a, b) => b.amount.compareTo(a.amount));
      d.byKey[key] = MicroValue(
        total: totals[day]?[key] ?? 0,
        withData: withData[day]?[key] ?? 0,
        ingredients: d.ingredients,
        contributions: list,
      );
    }
  }
  return days.values.toList()..sort((a, b) => a.day.compareTo(b.day));
}

/// Wochenwerte aus den Tageswerten, aelteste Woche zuerst (Woche ab Montag). Je Naehrstoff der Durchschnitt der Tagessummen ueber die
/// erfassten Tage; die Abdeckung zaehlt alle Zutaten der Woche.
List<WeekMicros> buildWeeklyMicros(List<DayMicros> days) {
  final weeks = <DateTime, List<DayMicros>>{};
  for (final d in days) {
    final monday = DateTime(d.day.year, d.day.month, d.day.day - (d.day.weekday - 1));
    weeks.putIfAbsent(monday, () => []).add(d);
  }
  final out = <WeekMicros>[];
  for (final e in weeks.entries) {
    final list = e.value;
    final byKey = <String, MicroValue>{};
    final ingredients = list.fold<int>(0, (s, d) => s + d.ingredients);
    for (final key in nutrientKeys) {
      final total = list.fold<double>(0, (s, d) => s + d.valueOf(key).total) / list.length;
      final withData = list.fold<int>(0, (s, d) => s + d.valueOf(key).withData);
      final all = [for (final d in list) ...d.valueOf(key).contributions]..sort((a, b) => b.amount.compareTo(a.amount));
      byKey[key] = MicroValue(total: total, withData: withData, ingredients: ingredients, contributions: all.take(5).toList());
    }
    out.add(WeekMicros(e.key, list.length, byKey, ingredients));
  }
  return out..sort((a, b) => a.weekStart.compareTo(b.weekStart));
}

/// Anteil an der Referenzmenge (1,0 = erreicht), `null` ohne Referenz oder bei 0 als Referenz.
double? referenceFraction(double value, double? reference) => reference == null || !(reference > 0) ? null : value / reference;

/// "62 % der Referenzmenge": nie "Mangel" oder "zu viel" (Neutralitaet, Doku 15 §2).
String referenceText(double fraction) => '${(fraction * 100).round()} % der Referenzmenge';
