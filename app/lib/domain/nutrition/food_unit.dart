/// Haushaltsmasse eines Lebensmittels (Stueck, Scheibe, EL ...) und ihre Gewichte (Phase N2, ADR-033).
///
/// Die BLS kennt nur Werte je 100 g. Damit "1 Banane" oder "2 EL Oel" Naehrwerte hat, braucht die App das Gewicht einer Einheit.
/// Reihenfolge: eigenes Gewicht des Haushalts, Gewicht am Produkt, Tabelle `food_units` (USDA, essbarer Anteil), sonst fragt die
/// App einmal nach.
library;

/// Die Einheiten der Tabelle `food_units`. In der Datenbank der Mahlzeiten stehen sie alle als `piece` (mit dem Gewicht einer
/// Einheit im Snapshot); der Name bleibt nur in der Oberflaeche.
enum FoodUnitKey {
  piece('piece', 'Stk', 'Stk'),
  slice('slice', 'Scheibe', 'Scheiben'),
  clove('clove', 'Zehe', 'Zehen'),
  head('head', 'Kopf', 'Köpfe'),
  stalk('stalk', 'Stange', 'Stangen'),
  tbsp('tbsp', 'EL', 'EL'),
  tsp('tsp', 'TL', 'TL');

  const FoodUnitKey(this.db, this.singular, this.plural);

  /// Wert in `food_units.unit_key`.
  final String db;
  final String singular;
  final String plural;

  /// "1 Scheibe", "2 Scheiben".
  String labelFor(double quantity) => quantity == 1 ? singular : plural;

  static FoodUnitKey? fromDb(String? value) {
    for (final k in values) {
      if (k.db == value) return k;
    }
    return null;
  }
}

/// Groesse einer Einheit (nur Stueck, Kopf und Stange kennen sie).
enum UnitSize {
  none('', ''),
  small('small', 'klein'),
  medium('medium', 'mittel'),
  large('large', 'groß');

  const UnitSize(this.db, this.label);
  final String db;
  final String label;

  static UnitSize fromDb(String? value) => values.firstWhere((s) => s.db == value, orElse: () => UnitSize.none);
}

/// Eine Zeile aus `food_units`: Gewicht von 1 [key] (in [size]) des BLS-Lebensmittels [blsCode] in g, essbarer Anteil.
class FoodUnit {
  const FoodUnit({required this.blsCode, required this.key, this.size = UnitSize.none, required this.gramsEdible, this.source = 'usda'});

  final String blsCode;
  final FoodUnitKey key;
  final UnitSize size;
  final double gramsEdible;

  /// `usda` | `off` | `curated` | `llm_estimate`
  final String source;
}

/// Liest eine Zeile von `food_units`; `null` bei unbekannter Einheit oder unbrauchbarem Gewicht.
FoodUnit? foodUnitFromRow(Map<String, dynamic> row) {
  final key = FoodUnitKey.fromDb(row['unit_key'] as String?);
  final code = row['bls_code'];
  final raw = row['grams_edible'];
  final grams = raw is num ? raw.toDouble() : (raw is String ? double.tryParse(raw.replaceAll(',', '.')) : null);
  if (key == null || code is! String || grams == null || !(grams > 0)) return null;
  final source = row['source'];
  return FoodUnit(
    blsCode: code,
    key: key,
    size: UnitSize.fromDb(row['size'] as String?),
    gramsEdible: grams,
    source: source is String ? source : 'usda',
  );
}

/// Die Einheiten, die fuer dieses Lebensmittel bekannt sind, in fester Reihenfolge (Stueck zuerst).
List<FoodUnitKey> unitKeysOf(List<FoodUnit> units) {
  final present = {for (final u in units) u.key};
  return [for (final k in FoodUnitKey.values) if (present.contains(k)) k];
}

/// Die Groessen einer Einheit, klein bis gross (ohne Groessenangabe: eine Zeile mit [UnitSize.none]).
List<FoodUnit> sizesOf(List<FoodUnit> units, FoodUnitKey key) {
  const order = {UnitSize.none: 0, UnitSize.small: 1, UnitSize.medium: 2, UnitSize.large: 3};
  return [for (final u in units) if (u.key == key) u]..sort((a, b) => order[a.size]!.compareTo(order[b.size]!));
}

/// Die Standardgroesse einer Einheit: mittel, sonst ohne Angabe, sonst klein, sonst gross (wie `pickSize` in der Function).
FoodUnit? defaultUnit(List<FoodUnit> units, FoodUnitKey key) {
  final of = sizesOf(units, key);
  for (final s in const [UnitSize.medium, UnitSize.none, UnitSize.small, UnitSize.large]) {
    for (final u in of) {
      if (u.size == s) return u;
    }
  }
  return null;
}

/// Wie die Foto-Analyse eine gezaehlte Zutat meldet: "2 Stk a 59 g". [source]: `household` oder die Quelle der Tabelle.
class AnalyzedUnit {
  const AnalyzedUnit({required this.count, required this.key, required this.weightG, required this.source, this.size = UnitSize.none});

  final double count;
  final FoodUnitKey key;
  final double weightG;
  final String source;
  final UnitSize size;

  double get totalG => count * weightG;
}

/// Liest das `unit`-Objekt von `analyze-meal`; `null` bei fehlendem oder unbrauchbarem Objekt.
AnalyzedUnit? parseAnalyzedUnit(Object? json) {
  if (json is! Map) return null;
  final count = json['count'];
  final weight = json['unit_weight_g'];
  final key = FoodUnitKey.fromDb(json['unit_key'] as String?);
  if (count is! num || !(count > 0) || weight is! num || !(weight > 0) || key == null) return null;
  final source = json['unit_source'];
  return AnalyzedUnit(
    count: count.toDouble(),
    key: key,
    weightG: weight.toDouble(),
    source: source is String ? source : 'usda',
    size: UnitSize.fromDb(json['size'] as String?),
  );
}
