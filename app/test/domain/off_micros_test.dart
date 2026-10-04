import 'package:einkaufstracker/domain/nutrition/nutrient_registry.dart';
import 'package:einkaufstracker/domain/nutrition/off_micros.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mikronaehrstoffe aus Open Food Facts (Phase N4): Gramm je 100 g werden zur Einheit des Registers.
void main() {
  test('Gramm werden zu mg, µg und g umgerechnet', () {
    final m = microsFromOffNutriments({
      'calcium_100g': 0.12, // 120 mg
      'vitamin-d_100g': 0.0000025, // 2,5 µg
      'omega-3-fat_100g': 1.5, // bleibt in g
      'iron_100g': 0.0021, // 2,1 mg
    })!;
    expect(m['calcium_mg'], closeTo(120, 1e-9));
    expect(m['vit_d_ug'], closeTo(2.5, 1e-9));
    expect(m['omega3_g'], closeTo(1.5, 1e-9));
    expect(m['iron_mg'], closeTo(2.1, 1e-9));
  });

  test('ohne einen einzigen Mikronaehrstoff null, Makros zaehlen nicht', () {
    expect(microsFromOffNutriments({'energy-kcal_100g': 64, 'proteins_100g': 3.3}), isNull);
    expect(microsFromOffNutriments(const {}), isNull);
  });

  test('Tippfehler fallen weg, der Rest bleibt: negativ, nicht endlich, ueber 100 g, kein Zahlenwert', () {
    final m = microsFromOffNutriments({
      'calcium_100g': -0.1,
      'iron_100g': double.nan,
      'zinc_100g': 250,
      'copper_100g': 'viel',
      'magnesium_100g': 0.03,
      'vitamin-c_100g': 0.0, // eine echte Null bleibt eine Null
    })!;
    expect(m.keys.toSet(), {'magnesium_mg', 'vit_c_mg'});
    expect(m['vit_c_mg'], 0);
  });

  test('Zahlen als Text mit Komma werden gelesen', () {
    expect(microsFromOffNutriments({'potassium_100g': '0,35'})!['potassium_mg'], closeTo(350, 1e-9));
  });

  test('jeder zugeordnete Schluessel gibt es im Register, jeder nur einmal', () {
    for (final key in offMicroKeys.values) {
      expect(nutrientDef(key), isNotNull, reason: key);
    }
    expect(offMicroKeys.values.toSet().length, offMicroKeys.length);
  });
}
