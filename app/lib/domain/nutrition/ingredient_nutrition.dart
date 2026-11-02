/// Rechnet eine im Essenstagebuch erfasste Zutatenmenge in die zwei Groessen um, die gebraucht werden
/// (Doku 15 Essenstagebuch und Naehrwerte, §3.4 und §5.3): die Menge in der Einheit des Inventars (fuer den
/// FEFO-Abzug) und die Menge in g bzw. ml (Basis der Naehrwertrechnung).
library;

import 'food_unit.dart';
import 'nutrient_scaling.dart';
import 'unit_conversion.dart';

/// Einheiten, in denen eine Zutat im Tagebuch erfasst werden kann.
enum EntryUnit {
  g,
  kg,
  ml,
  l,
  piece;

  /// Kurzform fuer die Anzeige ("g", "Stk").
  String get label => switch (this) {
        EntryUnit.g => 'g',
        EntryUnit.kg => 'kg',
        EntryUnit.ml => 'ml',
        EntryUnit.l => 'l',
        EntryUnit.piece => 'Stk',
      };

  /// Inventar-Basiseinheit derselben Dimension: Gewicht in `kg`, Volumen in `l`, sonst `piece`. Eine Zutat ohne
  /// Produkt (z.B. ein BLS-Treffer) hat keine eigene Basiseinheit und wird in dieser gefuehrt.
  String get dimensionBaseUnit => switch (this) {
        EntryUnit.g || EntryUnit.kg => 'kg',
        EntryUnit.ml || EntryUnit.l => 'l',
        EntryUnit.piece => 'piece',
      };

  /// Name, wie er in der Datenbank steht (`base_unit`-Enum, `piece` statt `Stk`).
  String get dbName => name;

  static EntryUnit fromDb(String value) => EntryUnit.values.firstWhere((u) => u.name == value, orElse: () => EntryUnit.g);

  /// Die natuerliche Eingabeeinheit zu einer Inventar-Basiseinheit: g fuer Gewichtsware, ml fuer Fluessiges,
  /// Stueck fuer Stueckware (Menschen geben 150 g Reis an, nicht 0,15 kg).
  static EntryUnit naturalFor(String baseUnit) => switch (baseUnit) {
        'kg' => EntryUnit.g,
        'l' => EntryUnit.ml,
        _ => EntryUnit.piece,
      };
}

/// Ergebnis von [resolveIngredientAmount]. Jede Groesse ist `null`, wenn sie sich nicht berechnen laesst
/// (z.B. Stueckgewicht unbekannt) -- die Oberflaeche soll dann nachfragen statt zu raten (Doku 15 §5.3).
class IngredientAmount {
  const IngredientAmount({this.quantity = 0, this.unit = 'kg', this.inventoryQuantity, this.nutrientBasisAmount});

  /// Die erfasste Menge in einer der drei Datenbank-Einheiten (`meal_ingredients.quantity`/`unit` kennen nur
  /// `kg`, `l` und `piece`, nicht `g`/`ml`): 150 g werden als 0,15 kg gespeichert.
  final double quantity;
  final String unit;

  /// Menge in der Basiseinheit des Produkts (`kg`, `l` oder `piece`), wie sie im Inventar gefuehrt wird.
  final double? inventoryQuantity;

  /// Menge in g bzw. ml, je nach `nutrients_basis` des Produkts. `null` ohne hinterlegte Naehrwerte.
  final double? nutrientBasisAmount;
}

/// Bringt [quantity] in [entryUnit] auf die Einheit des Inventars ([baseUnit]: `kg`, `l` oder `piece`) und auf
/// die Naehrwert-Basis ([nutrientsBasis]: `g`, `ml` oder `null`, wenn das Produkt keine Naehrwerte hat).
///
/// [unitWeightG] ist das Gewicht einer erfassten Einheit, [productPieceWeightG] das eines ganzen Stuecks des Produkts; es springt ein,
/// wenn die Zeile kein eigenes Gewicht hat. Gebraucht werden sie, sobald zwischen Stueck und Gewicht/Volumen gewechselt werden muss,
/// [densityGPerMl] (Standard 1,0) beim Wechsel zwischen Gewicht und Volumen.
///
/// [unitKey] nennt die Haushaltseinheit einer Stueckmenge. Scheibe, EL und Co. zaehlen Teile, keine ganzen Stuecke: Bei Stueckware ergibt
/// sich der Abzug aus dem Verhaeltnis der Gewichte, ohne [productPieceWeightG] ist [IngredientAmount.inventoryQuantity] `null`.
IngredientAmount resolveIngredientAmount({
  required double quantity,
  required EntryUnit entryUnit,
  required String baseUnit,
  String? nutrientsBasis,
  double? unitWeightG,
  double? productPieceWeightG,
  FoodUnitKey? unitKey,
  double densityGPerMl = 1.0,
}) {
  // Eingabe auf die drei Inventar-Einheiten normieren (g -> kg, ml -> l).
  final (double q, String u) = switch (entryUnit) {
    EntryUnit.g => (quantity / 1000, 'kg'),
    EntryUnit.kg => (quantity, 'kg'),
    EntryUnit.ml => (quantity / 1000, 'l'),
    EntryUnit.l => (quantity, 'l'),
    EntryUnit.piece => (quantity, 'piece'),
  };
  final countsParts = entryUnit == EntryUnit.piece && unitKey != null && unitKey != FoodUnitKey.piece;
  // Das Gewicht eines ganzen Stuecks gilt nicht fuer eine Scheibe
  final weight = unitWeightG ?? (countsParts ? null : productPieceWeightG);

  return IngredientAmount(
    quantity: q,
    unit: u,
    inventoryQuantity: countsParts && baseUnit == 'piece'
        ? (weight == null || productPieceWeightG == null || productPieceWeightG <= 0 ? null : q * weight / productPieceWeightG)
        : _toBaseUnit(q, u, baseUnit, weight, densityGPerMl),
    nutrientBasisAmount: nutrientsBasis == null
        ? null
        : convertToNutrientBasis(quantity: q, quantityUnit: u, basis: nutrientsBasis, unitWeightG: weight, densityGPerMl: densityGPerMl),
  );
}

/// Menge in Gramm, `null` wenn ein Stueckgewicht fehlt.
double? _toGrams(double q, String unit, double? unitWeightG, double density) => switch (unit) {
      'kg' => q * 1000,
      'l' => q * 1000 * density,
      'piece' => unitWeightG == null ? null : q * unitWeightG,
      _ => null,
    };

double? _toBaseUnit(double q, String from, String to, double? unitWeightG, double density) {
  if (from == to) return q;
  final grams = _toGrams(q, from, unitWeightG, density);
  if (grams == null) return null;
  return switch (to) {
    'kg' => grams / 1000,
    'l' => grams / density / 1000,
    'piece' => unitWeightG == null ? null : grams / unitWeightG,
    _ => null,
  };
}

/// Snapshot-Naehrwerte einer Zutat, oder `null` wenn das Produkt keine Naehrwerte hat oder die Menge in g/ml
/// nicht bestimmbar ist. `null` statt 0, damit die Zutat in Tagessummen als "nicht erfasst" gilt und nicht als
/// "0 kcal" (FR-15, FR-17).
NutrientAmounts? ingredientNutrients(NutrientsPer100? per100, IngredientAmount amount) {
  final basisAmount = amount.nutrientBasisAmount;
  if (per100 == null || basisAmount == null) return null;
  return scaleNutrients(per100: per100, amountG: basisAmount);
}
