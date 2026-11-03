/// Tages- und Wochenwerte der Mikronaehrstoffe mit Datenabdeckung und Beitraegen (Phase N3, ADR-032, Doku 22 §4.3).
///
/// Reine Funktionen ohne Datenbankzugriff, gleiches Muster wie `buildDailyNutrition`. Regeln:
/// - **Unbekannt bleibt unbekannt.** Ein fehlender Wert ist keine 0. Jede Summe nennt die **Abdeckung**: "aus 9 von 11 Zutaten mit
///   Daten"; unter 100 % ist die Summe ein "mindestens".
/// - Die Abdeckung gilt **je Naehrstoff**, denn eine Zutat kann Vitamin C haben und Jod nicht.
/// - Portionsanteil wie bei den Makros (FR-13): Summe der Zutaten x `servingsEaten / servingsMade`.
/// - Wochenwerte sind der Durchschnitt ueber die **erfassten** Tage (FR-15), mit der Zahl der erfassten Tage.
library;

import '../../core/vienna_time.dart';
import 'micros.dart';
import 'nutrient_registry.dart';

/// Eine Mahlzeit fuer die Mikronaehrstoff-Auswertung.
typedef MicroMeal = ({String id, String title, DateTime eatenAtUtc, double servingsEaten, double servingsMade});

/// Eine Zutat mit ihrem Mikronaehrstoff-Snapshot. `micros == null`: die Zutat hat keine Daten.
typedef MicroIngredient = ({String mealId, String name, Micros? micros});

/// Eine Einnahme von Nahrungsergaenzung (Phase N4, ADR-035) mit den absoluten Mengen fuer die genommenen Einheiten. Sie zaehlt **nicht**
/// als Zutat: die Packung nennt, was drin ist, ein fehlender Wert heisst dort "nicht enthalten" und senkt die Abdeckung der
/// Lebensmittel nicht. Eine Einnahme macht einen Tag auch nicht zum erfassten Essenstag (Wochen-Ø, Journal).
typedef MicroIntake = ({String id, String name, DateTime takenAtUtc, Micros micros});

/// Woher ein Teil des Tageswertes kommt ("Woher kommt das?").
class MicroContribution {
  const MicroContribution({
    required this.mealId,
    required this.mealTitle,
    required this.ingredient,
    required this.amount,
    this.supplement = false,
    this.occurrences = 1,
  });

  final String mealId;
  final String mealTitle;
  final String ingredient;

  /// Der Beitrag stammt aus Nahrungsergaenzung, nicht aus einer Mahlzeit.
  final bool supplement;

  /// Beitrag zum Tageswert in der Einheit des Naehrstoffs (nach Portionsanteil). In der Woche: Durchschnitt je erfasstem Tag, damit die
  /// Beitraege zusammen den Wochenwert ergeben.
  final double amount;

  /// In wie vielen Mahlzeiten (oder Einnahmen) die Zutat vorkam: am Tag dieselbe Zutat einer Mahlzeit zusammengezaehlt, in der Woche
  /// dieselbe Zutat ueber alle Mahlzeiten.
  final int occurrences;
}

/// Eine Zutat ohne Wert fuer einen Naehrstoff: sie macht die Summe zum "mindestens" und wird in der Aufschluesselung genannt.
class MicroMissing {
  const MicroMissing({required this.mealTitle, required this.ingredient, this.occurrences = 1});

  final String mealTitle;
  final String ingredient;
  final int occurrences;
}

/// Ein Naehrstoff an einem Tag oder in einer Woche (Durchschnitt je erfasstem Tag).
class MicroValue {
  const MicroValue({
    this.total = 0,
    this.withData = 0,
    this.ingredients = 0,
    this.contributions = const [],
    this.supplementTotal = 0,
    this.missing = const [],
  });

  /// Zutaten ohne Wert fuer diesen Naehrstoff, nach Name sortiert (Mahlzeiten-Zutaten, nie Nahrungsergaenzung).
  final List<MicroMissing> missing;

  /// Summe der bekannten Beitraege (Mahlzeiten und Nahrungsergaenzung).
  final double total;

  /// Davon aus Nahrungsergaenzung.
  final double supplementTotal;

  /// Zutaten mit einem Wert fuer diesen Naehrstoff (auch einer echten 0) und alle Zutaten.
  final int withData;
  final int ingredients;

  /// Alle Beitraege, groesster zuerst.
  final List<MicroContribution> contributions;

  /// Anteil der Zutaten mit Daten, 1,0 ohne Zutaten.
  double get coverage => ingredients == 0 ? 1 : withData / ingredients;

  /// Die Summe ist vollstaendig (jede Zutat hat einen Wert) und damit kein "mindestens".
  bool get complete => withData == ingredients;

  /// Gar keine Daten, obwohl es Zutaten gibt: die Anzeige sagt "unbekannt" statt "0".
  bool get unknown => ingredients > 0 && withData == 0 && supplementTotal == 0;
}

/// Die Mikronaehrstoffe eines Kalendertags (Wiener Zeit).
class DayMicros {
  DayMicros(this.day);

  final DateTime day;
  final Map<String, MicroValue> byKey = {};
  int meals = 0;
  int ingredients = 0;

  /// Einnahmen von Nahrungsergaenzung an diesem Tag.
  int intakes = 0;
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
List<DayMicros> buildDailyMicros(
  Iterable<MicroMeal> meals,
  Iterable<MicroIngredient> ingredients, {
  bool Function(String mealId)? isEstimate,
  Iterable<MicroIntake> intakes = const [],
}) {
  final byMeal = <String, List<MicroIngredient>>{};
  for (final i in ingredients) {
    byMeal.putIfAbsent(i.mealId, () => []).add(i);
  }
  final days = <DateTime, DayMicros>{};
  final totals = <DateTime, Map<String, double>>{};
  final withData = <DateTime, Map<String, int>>{};
  final contribs = <DateTime, Map<String, List<MicroContribution>>>{};
  final supplementTotals = <DateTime, Map<String, double>>{};
  // alle Zutaten des Tages mit Mahlzeit: daraus je Naehrstoff die ohne Wert
  final dayIngredients = <DateTime, List<(String mealTitle, MicroIngredient ingredient)>>{};

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
      dayIngredients.putIfAbsent(day, () => []).add((m.title, i));
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
  for (final intake in intakes) {
    final local = utcToViennaLocal(intake.takenAtUtc);
    final day = DateTime(local.year, local.month, local.day);
    final d = days.putIfAbsent(day, () => DayMicros(day));
    d.intakes++;
    for (final e in intake.micros.entries) {
      totals.putIfAbsent(day, () => {}).update(e.key, (v) => v + e.value, ifAbsent: () => e.value);
      supplementTotals.putIfAbsent(day, () => {}).update(e.key, (v) => v + e.value, ifAbsent: () => e.value);
      contribs.putIfAbsent(day, () => {}).putIfAbsent(e.key, () => []).add(
            MicroContribution(mealId: 'supplement:${intake.id}', mealTitle: 'Nahrungsergänzung', ingredient: intake.name, amount: e.value, supplement: true),
          );
    }
  }
  for (final e in days.entries) {
    final day = e.key;
    final d = e.value;
    for (final key in nutrientKeys) {
      d.byKey[key] = MicroValue(
        total: totals[day]?[key] ?? 0,
        withData: withData[day]?[key] ?? 0,
        ingredients: d.ingredients,
        // dieselbe Zutat zweimal in einer Mahlzeit (zwei Mal Zwiebel) ist eine Zeile, dasselbe Praeparat zweimal am Tag auch
        contributions: _mergeContributions(contribs[day]?[key] ?? const [], (c) => c.supplement ? 'S|${c.ingredient}' : 'M|${c.mealId}|${c.ingredient}', 1),
        supplementTotal: supplementTotals[day]?[key] ?? 0,
        missing: _mergeMissing([
          for (final (title, i) in dayIngredients[day] ?? const <(String, MicroIngredient)>[])
            if (i.micros?[key] == null) MicroMissing(mealTitle: title, ingredient: i.name),
        ], (x) => '${x.mealTitle}|${x.ingredient}'),
      );
    }
  }
  return days.values.toList()..sort((a, b) => a.day.compareTo(b.day));
}

/// Fasst Beitraege mit gleichem Schluessel zusammen, teilt die Mengen durch [divisor] und sortiert groesster zuerst. Verschiedene
/// Mahlzeiten-Titel werden zu "3 Mahlzeiten".
List<MicroContribution> _mergeContributions(Iterable<MicroContribution> list, String Function(MicroContribution) keyOf, int divisor) {
  final merged = <String, MicroContribution>{};
  for (final c in list) {
    final prev = merged[keyOf(c)];
    merged[keyOf(c)] = prev == null
        ? c
        : MicroContribution(
            mealId: prev.mealId == c.mealId ? c.mealId : '',
            mealTitle: prev.mealTitle == c.mealTitle ? c.mealTitle : '',
            ingredient: c.ingredient,
            amount: prev.amount + c.amount,
            supplement: c.supplement,
            occurrences: prev.occurrences + c.occurrences,
          );
  }
  return [
    for (final c in merged.values)
      MicroContribution(
        mealId: c.mealId,
        mealTitle: c.mealTitle.isNotEmpty ? c.mealTitle : '${c.occurrences} ${c.supplement ? 'Einnahmen' : 'Mahlzeiten'}',
        ingredient: c.ingredient,
        amount: c.amount / divisor,
        supplement: c.supplement,
        occurrences: c.occurrences,
      ),
  ]..sort((a, b) => b.amount.compareTo(a.amount));
}

List<MicroMissing> _mergeMissing(Iterable<MicroMissing> list, String Function(MicroMissing) keyOf) {
  final merged = <String, MicroMissing>{};
  for (final x in list) {
    final prev = merged[keyOf(x)];
    merged[keyOf(x)] = prev == null
        ? x
        : MicroMissing(
            mealTitle: prev.mealTitle == x.mealTitle ? x.mealTitle : '',
            ingredient: x.ingredient,
            occurrences: prev.occurrences + x.occurrences,
          );
  }
  return [
    for (final x in merged.values)
      MicroMissing(mealTitle: x.mealTitle.isNotEmpty ? x.mealTitle : '${x.occurrences} Mahlzeiten', ingredient: x.ingredient, occurrences: x.occurrences),
  ]..sort((a, b) => a.ingredient.toLowerCase().compareTo(b.ingredient.toLowerCase()));
}

/// Wochenwerte aus den Tageswerten, aelteste Woche zuerst (Woche ab Montag). Je Naehrstoff der Durchschnitt der Tagessummen ueber die
/// erfassten Tage; die Abdeckung zaehlt alle Zutaten der Woche.
List<WeekMicros> buildWeeklyMicros(List<DayMicros> days) {
  final weeks = <DateTime, List<DayMicros>>{};
  // Ein Tag nur mit Nahrungsergaenzung ist kein erfasster Essenstag und geht nicht in den Durchschnitt ein (FR-15)
  for (final d in days.where((d) => d.meals > 0)) {
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
      final supplementTotal = list.fold<double>(0, (s, d) => s + d.valueOf(key).supplementTotal) / list.length;
      final withData = list.fold<int>(0, (s, d) => s + d.valueOf(key).withData);
      // dieselbe Zutat ueber die ganze Woche ist eine Zeile, als Durchschnitt je erfasstem Tag wie der Wochenwert selbst
      final contributions = _mergeContributions(
        [for (final d in list) ...d.valueOf(key).contributions],
        (c) => '${c.supplement}|${c.ingredient}',
        list.length,
      );
      final missing = _mergeMissing([for (final d in list) ...d.valueOf(key).missing], (x) => x.ingredient);
      byKey[key] = MicroValue(
        total: total,
        withData: withData,
        ingredients: ingredients,
        contributions: contributions,
        supplementTotal: supplementTotal,
        missing: missing,
      );
    }
    out.add(WeekMicros(e.key, list.length, byKey, ingredients));
  }
  return out..sort((a, b) => a.weekStart.compareTo(b.weekStart));
}

/// Anteil an der Referenzmenge (1,0 = erreicht), `null` ohne Referenz oder bei 0 als Referenz.
double? referenceFraction(double value, double? reference) => reference == null || !(reference > 0) ? null : value / reference;

/// Anteil eines Beitrags an der Summe als "42 %", unter einem halben Prozent "< 1 %", ohne Summe `null`.
String? shareText(double amount, double total) {
  if (!(total > 0)) return null;
  final pct = amount / total * 100;
  return pct < 0.5 ? '< 1 %' : '${pct.round()} %';
}

/// "62 % der Referenzmenge": nie "Mangel" oder "zu viel" (Neutralitaet, Doku 15 §2).
String referenceText(double fraction) => '${(fraction * 100).round()} % der Referenzmenge';
