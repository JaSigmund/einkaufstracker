/// Mikronaehrstoffe aus den Naehrwerten von Open Food Facts (Phase N4, ADR-035). OFF liefert je 100 g in **Gramm** (`calcium_100g: 0.12`
/// heisst 120 mg), das Register arbeitet in der Einheit des Naehrstoffs (mg, µg, g). Reine Funktion.
///
/// OFF-Daten stammen von Nutzern und enthalten Tippfehler. Deshalb zaehlt nur, was endlich, nicht negativ und physikalisch moeglich
/// ist (hoechstens 100 g je 100 g); alles andere faellt weg, ohne dass das Produkt abgelehnt wird. Ein fehlender Wert bleibt unbekannt, nie 0.
library;

import 'micros.dart';
import 'nutrient_registry.dart';

/// OFF-Name (ohne `_100g`) -> Schluessel im Register.
const offMicroKeys = <String, String>{
  'vitamin-a': 'vit_a_ug',
  'vitamin-d': 'vit_d_ug',
  'vitamin-e': 'vit_e_mg',
  'vitamin-k': 'vit_k_ug',
  'vitamin-c': 'vit_c_mg',
  'vitamin-b1': 'vit_b1_mg',
  'vitamin-b2': 'vit_b2_mg',
  'vitamin-pp': 'niacin_mg',
  'vitamin-b6': 'vit_b6_mg',
  'vitamin-b9': 'folate_ug',
  'vitamin-b12': 'vit_b12_ug',
  'pantothenic-acid': 'pantothenic_mg',
  'biotin': 'biotin_ug',
  'potassium': 'potassium_mg',
  'calcium': 'calcium_mg',
  'magnesium': 'magnesium_mg',
  'phosphorus': 'phosphorus_mg',
  'iron': 'iron_mg',
  'zinc': 'zinc_mg',
  'iodine': 'iodine_ug',
  'copper': 'copper_mg',
  'manganese': 'manganese_mg',
  'chloride': 'chloride_mg',
  'fluoride': 'fluoride_mg',
  'chromium': 'chromium_ug',
  'molybdenum': 'molybdenum_ug',
  'monounsaturated-fat': 'mufa_g',
  'polyunsaturated-fat': 'pufa_g',
  'omega-3-fat': 'omega3_g',
  'alpha-linolenic-acid': 'ala_g',
  'eicosapentaenoic-acid': 'epa_g',
  'docosahexaenoic-acid': 'dha_g',
  'omega-6-fat': 'linoleic_g',
  'cholesterol': 'cholesterol_mg',
  'starch': 'starch_g',
};

/// Faktor von Gramm auf die Einheit des Registers.
double _fromGrams(String unit) => switch (unit) {
      'mg' => 1000,
      'µg' => 1000000,
      _ => 1,
    };

/// Liest die Mikronaehrstoffe je 100 g aus dem `nutriments`-Objekt von OFF, `null`, wenn keiner dabei ist.
Micros? microsFromOffNutriments(Map<String, dynamic> nutriments) {
  final out = <String, double>{};
  for (final e in offMicroKeys.entries) {
    final raw = nutriments['${e.key}_100g'];
    final grams = raw is num ? raw.toDouble() : (raw is String ? double.tryParse(raw.replaceAll(',', '.')) : null);
    if (grams == null || !grams.isFinite || grams < 0 || grams > 100) continue;
    final def = nutrientDef(e.value);
    if (def == null) continue;
    out[e.value] = grams * _fromGrams(def.unit);
  }
  return out.isEmpty ? null : out;
}
