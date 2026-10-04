/// Schaetzung des Nicht-Erfassten eines Tages (Phase 7d, offener Rest, Doku 15 §3.5): Zutaten ohne Naehrwerte, deren Menge bekannt ist
/// ("200 g Gewuerzgurke", Menge da, Profil fehlt), fehlen in der Tagessumme. Wer wissen will, wie gross die Luecke etwa ist, schaltet
/// eine Schaetzung dazu. Sie ersetzt nie die bekannte Summe und steht immer getrennt und als Schaetzung da.
///
/// Reine Funktionen ohne Datenbankzugriff. Regeln:
/// - Geschaetzt wird nur, was eine bekannte Menge hat. Zutaten ohne Menge werden gezaehlt, aber nicht geschaetzt.
/// - Die Dichte (kcal je g) kommt, in dieser Reihenfolge, aus den bekannten Zutaten desselben Tages, aus dem bisherigen Verlauf, sonst
///   als Faustwert (150 kcal je 100 g, ein durchschnittliches Essen). Die Quelle wird mitgeliefert und in der Oberflaeche genannt.
/// - Portionsanteil wie bei den Tageswerten (FR-13): gegessen durch gekocht.
library;

import 'daily_nutrition.dart';

/// Eine Zutat eines Tages: Menge in g (oder ml) und bekannte kcal. `null` heisst jeweils unbekannt.
typedef UnrecordedIngredient = ({String mealId, double? grams, double? kcal});

/// Woher die Energiedichte der Schaetzung stammt.
enum DensityBasis {
  /// aus den bekannten Zutaten desselben Tages
  day,

  /// aus dem bisherigen Verlauf aller erfassten Tage
  history,

  /// Faustwert, weil es weder am Tag noch im Verlauf eine Grundlage gibt
  fallback,
}

/// Faustwert fuer die Energiedichte eines durchschnittlichen Essens in kcal je g.
const fallbackKcalPerGram = 1.5;

class UnrecordedEstimate {
  const UnrecordedEstimate({required this.ingredients, required this.withoutAmount, required this.grams, required this.kcal, required this.basis});

  /// Zutaten ohne Naehrwerte mit bekannter Menge (sie gehen in die Schaetzung ein).
  final int ingredients;

  /// Zutaten ohne Naehrwerte und ohne Menge (gezaehlt, nicht geschaetzt).
  final int withoutAmount;

  /// Geschaetzte Menge in g nach Portionsanteil.
  final double grams;

  /// Geschaetzte zusaetzliche kcal.
  final double kcal;
  final DensityBasis basis;
}

/// Energiedichte (kcal je g) der Zutaten mit bekanntem Wert und bekannter Menge, `null` ohne Grundlage. Mengengewichtet: viel Reis
/// zaehlt mehr als ein Loeffel Oel.
double? kcalPerGram(Iterable<UnrecordedIngredient> ingredients) {
  var grams = 0.0;
  var kcal = 0.0;
  for (final i in ingredients) {
    if (i.kcal == null || i.grams == null || !(i.grams! > 0)) continue;
    grams += i.grams!;
    kcal += i.kcal!;
  }
  return grams > 0 ? kcal / grams : null;
}

/// Schaetzt die Luecke eines Tages. `null`, wenn es dort keine Zutat ohne Naehrwerte gibt.
///
/// [meals] sind die Mahlzeiten des Tages, [ingredients] ihre Zutaten. [historyKcalPerGram] ist die Dichte aus allen erfassten Tagen
/// (siehe [kcalPerGram]).
UnrecordedEstimate? estimateUnrecorded(
  Iterable<NutritionMeal> meals,
  Iterable<UnrecordedIngredient> ingredients, {
  double? historyKcalPerGram,
}) {
  final share = <String, double>{
    for (final m in meals)
      if (m.servingsMade > 0) m.id: m.servingsEaten / m.servingsMade,
  };
  final ofDay = [for (final i in ingredients) if (share.containsKey(i.mealId)) i];
  final unknown = [for (final i in ofDay) if (i.kcal == null) i];
  if (unknown.isEmpty) return null;

  final withAmount = [for (final i in unknown) if (i.grams != null && i.grams! > 0) i];
  final dayDensity = kcalPerGram(ofDay);
  final (density, basis) = dayDensity != null
      ? (dayDensity, DensityBasis.day)
      : (historyKcalPerGram != null && historyKcalPerGram > 0)
          ? (historyKcalPerGram, DensityBasis.history)
          : (fallbackKcalPerGram, DensityBasis.fallback);

  final grams = withAmount.fold<double>(0, (s, i) => s + i.grams! * share[i.mealId]!);
  return UnrecordedEstimate(
    ingredients: withAmount.length,
    withoutAmount: unknown.length - withAmount.length,
    grams: grams,
    kcal: grams * density,
    basis: basis,
  );
}

/// Anteil an einem Richtwert fuer die Ringdarstellung eines Tages: 0 bis 1 begrenzt (ein Ring ist nie ueber voll), `null` ohne
/// bekannten Wert oder ohne Richtwert. Der Ring bewertet nicht: eine Farbe, keine Ampel.
double? ringFraction(double? value, double? reference) {
  if (value == null || reference == null || !(reference > 0)) return null;
  final f = value / reference;
  return f < 0 ? 0 : (f > 1 ? 1 : f);
}
