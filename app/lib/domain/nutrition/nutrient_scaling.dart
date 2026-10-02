/// Skaliert Naehrwerte je 100 g/ml auf eine tatsaechlich verzehrte Menge (Doku 15 Essenstagebuch
/// und Naehrwerte, §5.1/§5.4).
library;

/// Naehrwertprofil je 100 g bzw. 100 ml -- dieselben 8 Schluessel wie `products.nutrients_per_100`
/// und die Tabelle `bls_foods`, damit ein Wert beide Quellen gleich behandeln kann.
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

  /// Liest die Schluessel von `products.nutrients_per_100` (`kcal`, `protein_g`, `fat_g`, `sat_fat_g`,
  /// `carbs_g`, `sugar_g`, `fiber_g`, `salt_g`). Unbekannte oder nicht numerische Eintraege werden zu `null`,
  /// eine leere Map ergibt `null` (kein Naehrwertprofil) statt eines Profils aus lauter `null`.
  static NutrientsPer100? fromMap(Map<String, dynamic>? map) {
    if (map == null || map.isEmpty) return null;
    double? v(String key) => (map[key] is num) ? (map[key] as num).toDouble() : null;
    final p = NutrientsPer100(
      kcal: v('kcal'),
      proteinG: v('protein_g'),
      fatG: v('fat_g'),
      satFatG: v('sat_fat_g'),
      carbsG: v('carbs_g'),
      sugarG: v('sugar_g'),
      fiberG: v('fiber_g'),
      saltG: v('salt_g'),
    );
    final hasAny = [p.kcal, p.proteinG, p.fatG, p.satFatG, p.carbsG, p.sugarG, p.fiberG, p.saltG].any((x) => x != null);
    return hasAny ? p : null;
  }

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
/// (die bewusst kein `sat_fat_g` hat, siehe Migration `0014_meal_diary.sql`).
class NutrientAmounts {
  const NutrientAmounts({this.kcal, this.proteinG, this.fatG, this.carbsG, this.sugarG, this.fiberG, this.saltG});

  final double? kcal;
  final double? proteinG;
  final double? fatG;
  final double? carbsG;
  final double? sugarG;
  final double? fiberG;
  final double? saltG;

  /// Alle bekannten Werte mit [factor] multipliziert; Unbekanntes bleibt unbekannt (`null`).
  NutrientAmounts scaled(double factor) {
    double? f(double? v) => v == null ? null : v * factor;
    return NutrientAmounts(
      kcal: f(kcal), proteinG: f(proteinG), fatG: f(fatG), carbsG: f(carbsG), sugarG: f(sugarG), fiberG: f(fiberG), saltG: f(saltG),
    );
  }
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
