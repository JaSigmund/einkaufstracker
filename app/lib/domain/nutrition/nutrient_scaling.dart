/// Skaliert Naehrwerte je 100 g/ml auf eine tatsaechlich verzehrte Menge (Doku 15 Essenstagebuch
/// und Naehrwerte, §5.1/§5.4). Vorbereitung fuer Phase 7 (noch nicht verdrahtet).
library;

/// Naehrwertprofil je 100 g bzw. 100 ml -- dieselben 8 Schluessel wie `products.nutrients_per_100`
/// und die geplante Tabelle `bls_foods`, damit ein Wert beide Quellen gleich behandeln kann.
class NutrientsPer100 {
  const NutrientsPer100({
    this.kcal,
    this.proteinG,
    this.fatG,
    this.satFatG,
    this.carbsG,
    this.sugarG,
    this.fiberG,
    this.saltG,
  });

  final double? kcal;
  final double? proteinG;
  final double? fatG;
  final double? satFatG;
  final double? carbsG;
  final double? sugarG;
  final double? fiberG;
  final double? saltG;
}

/// Absolute Naehrwerte einer Zutatenmenge -- passend zu den Snapshot-Spalten in `meal_ingredients`
/// (die bewusst kein `sat_fat_g` hat, siehe `supabase/planned/meal_diary_draft.sql`).
class NutrientAmounts {
  const NutrientAmounts({this.kcal, this.proteinG, this.fatG, this.carbsG, this.sugarG, this.fiberG, this.saltG});

  final double? kcal;
  final double? proteinG;
  final double? fatG;
  final double? carbsG;
  final double? sugarG;
  final double? fiberG;
  final double? saltG;
}

/// Reine Dreisatzrechnung: `amountG / 100 * Wert je 100`. Fehlende Einzelwerte bleiben `null`
/// statt `0`, damit eine Zutat ohne bekannten Naehrwert nicht faelschlich als "0 kcal" in
/// Tagessummen einfliesst (vgl. `v_daily_nutrition`, die ueber `sum()` aggregiert).
NutrientAmounts scaleNutrients({required NutrientsPer100 per100, required double amountG}) {
  double? scale(double? valuePer100) => valuePer100 == null ? null : valuePer100 * amountG / 100;
  return NutrientAmounts(
    kcal: scale(per100.kcal),
    proteinG: scale(per100.proteinG),
    fatG: scale(per100.fatG),
    carbsG: scale(per100.carbsG),
    sugarG: scale(per100.sugarG),
    fiberG: scale(per100.fiberG),
    saltG: scale(per100.saltG),
  );
}
