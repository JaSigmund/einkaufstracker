// GENERIERT von tools/build_bls_nutrients.py aus tools/nutrient_registry.json -- nicht von Hand aendern.
// Register der Mikronaehrstoffe (Phase N3, ADR-032): Schluessel, Name, Gruppe, Einheit, Nachkommastellen und die
// Kennzeichnungs-Referenzmenge (Verordnung (EU) Nr. 1169/2011 Anhang XIII Teil A, Erwachsene; keine Empfehlung).
library;

enum NutrientGroup {
  vitamin('Vitamine'),
  mineral('Mineralstoffe'),
  fat('Fettsäuren'),
  other('Weiteres');

  const NutrientGroup(this.label);
  final String label;
}

class NutrientDef {
  const NutrientDef({required this.key, required this.label, required this.group, required this.unit, required this.decimals, this.euReference, this.featured = false});

  /// Schluessel in `bls_foods.nutrients`, `meal_ingredients.micros` und `products.nutrients_per_100` (Einheit steht im Schluessel).
  final String key;
  final String label;
  final NutrientGroup group;
  final String unit;
  final int decimals;

  /// Kennzeichnungs-Referenzmenge fuer Erwachsene in [unit] oder `null`.
  final double? euReference;

  /// In der Vorauswahl der Seite "Nährstoffe" sichtbar (die zwoelf haeufig gefragten).
  final bool featured;
}

/// Alle Mikronaehrstoffe in Anzeigereihenfolge (Gruppe, dann wie in der Tabelle der Doku).
const nutrientRegistry = <NutrientDef>[
  NutrientDef(key: 'vit_a_ug', label: 'Vitamin A (Retinol-Äquivalent)', group: NutrientGroup.vitamin, unit: 'µg', decimals: 0, euReference: 800.0, featured: true),
  NutrientDef(key: 'vit_d_ug', label: 'Vitamin D', group: NutrientGroup.vitamin, unit: 'µg', decimals: 1, euReference: 5.0, featured: true),
  NutrientDef(key: 'vit_e_mg', label: 'Vitamin E', group: NutrientGroup.vitamin, unit: 'mg', decimals: 1, euReference: 12.0),
  NutrientDef(key: 'vit_k_ug', label: 'Vitamin K', group: NutrientGroup.vitamin, unit: 'µg', decimals: 0, euReference: 75.0),
  NutrientDef(key: 'vit_c_mg', label: 'Vitamin C', group: NutrientGroup.vitamin, unit: 'mg', decimals: 0, euReference: 80.0, featured: true),
  NutrientDef(key: 'vit_b1_mg', label: 'Vitamin B1 (Thiamin)', group: NutrientGroup.vitamin, unit: 'mg', decimals: 2, euReference: 1.1),
  NutrientDef(key: 'vit_b2_mg', label: 'Vitamin B2 (Riboflavin)', group: NutrientGroup.vitamin, unit: 'mg', decimals: 2, euReference: 1.4),
  NutrientDef(key: 'niacin_mg', label: 'Niacin (Niacin-Äquivalent)', group: NutrientGroup.vitamin, unit: 'mg', decimals: 1, euReference: 16.0),
  NutrientDef(key: 'vit_b6_mg', label: 'Vitamin B6', group: NutrientGroup.vitamin, unit: 'mg', decimals: 2, euReference: 1.4),
  NutrientDef(key: 'folate_ug', label: 'Folat (Folat-Äquivalent)', group: NutrientGroup.vitamin, unit: 'µg', decimals: 0, euReference: 200.0, featured: true),
  NutrientDef(key: 'vit_b12_ug', label: 'Vitamin B12', group: NutrientGroup.vitamin, unit: 'µg', decimals: 1, euReference: 2.5, featured: true),
  NutrientDef(key: 'pantothenic_mg', label: 'Pantothensäure', group: NutrientGroup.vitamin, unit: 'mg', decimals: 1, euReference: 6.0),
  NutrientDef(key: 'biotin_ug', label: 'Biotin', group: NutrientGroup.vitamin, unit: 'µg', decimals: 0, euReference: 50.0),
  NutrientDef(key: 'potassium_mg', label: 'Kalium', group: NutrientGroup.mineral, unit: 'mg', decimals: 0, euReference: 2000.0, featured: true),
  NutrientDef(key: 'calcium_mg', label: 'Calcium', group: NutrientGroup.mineral, unit: 'mg', decimals: 0, euReference: 800.0, featured: true),
  NutrientDef(key: 'magnesium_mg', label: 'Magnesium', group: NutrientGroup.mineral, unit: 'mg', decimals: 0, euReference: 375.0, featured: true),
  NutrientDef(key: 'phosphorus_mg', label: 'Phosphor', group: NutrientGroup.mineral, unit: 'mg', decimals: 0, euReference: 700.0),
  NutrientDef(key: 'iron_mg', label: 'Eisen', group: NutrientGroup.mineral, unit: 'mg', decimals: 1, euReference: 14.0, featured: true),
  NutrientDef(key: 'zinc_mg', label: 'Zink', group: NutrientGroup.mineral, unit: 'mg', decimals: 1, euReference: 10.0, featured: true),
  NutrientDef(key: 'iodine_ug', label: 'Jod', group: NutrientGroup.mineral, unit: 'µg', decimals: 0, euReference: 150.0, featured: true),
  NutrientDef(key: 'copper_mg', label: 'Kupfer', group: NutrientGroup.mineral, unit: 'mg', decimals: 2, euReference: 1.0),
  NutrientDef(key: 'manganese_mg', label: 'Mangan', group: NutrientGroup.mineral, unit: 'mg', decimals: 2, euReference: 2.0),
  NutrientDef(key: 'chloride_mg', label: 'Chlorid', group: NutrientGroup.mineral, unit: 'mg', decimals: 0, euReference: 800.0),
  NutrientDef(key: 'fluoride_mg', label: 'Fluorid', group: NutrientGroup.mineral, unit: 'mg', decimals: 2, euReference: 3.5),
  NutrientDef(key: 'chromium_ug', label: 'Chrom', group: NutrientGroup.mineral, unit: 'µg', decimals: 0, euReference: 40.0),
  NutrientDef(key: 'molybdenum_ug', label: 'Molybdän', group: NutrientGroup.mineral, unit: 'µg', decimals: 0, euReference: 50.0),
  NutrientDef(key: 'mufa_g', label: 'Einfach ungesättigte Fettsäuren', group: NutrientGroup.fat, unit: 'g', decimals: 1),
  NutrientDef(key: 'pufa_g', label: 'Mehrfach ungesättigte Fettsäuren', group: NutrientGroup.fat, unit: 'g', decimals: 1),
  NutrientDef(key: 'omega3_g', label: 'Omega-3-Fettsäuren', group: NutrientGroup.fat, unit: 'g', decimals: 2, featured: true),
  NutrientDef(key: 'ala_g', label: 'Alpha-Linolensäure (ALA)', group: NutrientGroup.fat, unit: 'g', decimals: 2),
  NutrientDef(key: 'epa_g', label: 'EPA', group: NutrientGroup.fat, unit: 'g', decimals: 2),
  NutrientDef(key: 'dha_g', label: 'DHA', group: NutrientGroup.fat, unit: 'g', decimals: 2),
  NutrientDef(key: 'linoleic_g', label: 'Linolsäure (Omega-6)', group: NutrientGroup.fat, unit: 'g', decimals: 1),
  NutrientDef(key: 'cholesterol_mg', label: 'Cholesterin', group: NutrientGroup.fat, unit: 'mg', decimals: 0),
  NutrientDef(key: 'water_g', label: 'Wasser', group: NutrientGroup.other, unit: 'g', decimals: 0),
  NutrientDef(key: 'alcohol_g', label: 'Alkohol', group: NutrientGroup.other, unit: 'g', decimals: 1, featured: true),
  NutrientDef(key: 'caffeine_mg', label: 'Koffein', group: NutrientGroup.other, unit: 'mg', decimals: 0, featured: true),
  NutrientDef(key: 'starch_g', label: 'Stärke', group: NutrientGroup.other, unit: 'g', decimals: 1),
  NutrientDef(key: 'eaa_g', label: 'Unentbehrliche Aminosäuren (gesamt)', group: NutrientGroup.other, unit: 'g', decimals: 1),
];

final _byKey = {for (final n in nutrientRegistry) n.key: n};

/// Die Definition zu einem Schluessel, `null` bei unbekanntem.
NutrientDef? nutrientDef(String key) => _byKey[key];

/// Schluessel aller Mikronaehrstoffe.
final nutrientKeys = [for (final n in nutrientRegistry) n.key];
