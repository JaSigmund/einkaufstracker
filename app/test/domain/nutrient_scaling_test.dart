import 'package:einkaufstracker/domain/nutrition/nutrient_scaling.dart';
import 'package:flutter_test/flutter_test.dart';

/// Testet die Naehrwert-Skalierung fuers Essenstagebuch (Doku 15 §5.1/§5.4, Phase 7 Vorbereitung).
void main() {
  test('skaliert 350 kcal je 100 g auf 72 g verzehrte Menge', () {
    const per100 = NutrientsPer100(kcal: 350, proteinG: 10, fatG: 20);
    final result = scaleNutrients(per100: per100, amountG: 72);
    expect(result.kcal, closeTo(252, 0.001));
    expect(result.proteinG, closeTo(7.2, 0.001));
    expect(result.fatG, closeTo(14.4, 0.001));
  });

  test('fehlende Einzelwerte bleiben null statt 0 (keine falsche "0 kcal" in Tagessummen)', () {
    const per100 = NutrientsPer100(kcal: 200);
    final result = scaleNutrients(per100: per100, amountG: 100);
    expect(result.kcal, 200);
    expect(result.proteinG, isNull);
    expect(result.fatG, isNull);
    expect(result.carbsG, isNull);
    expect(result.sugarG, isNull);
    expect(result.fiberG, isNull);
    expect(result.saltG, isNull);
  });

  test('0 g verzehrte Menge ergibt 0, nicht null, fuer bekannte Werte', () {
    const per100 = NutrientsPer100(kcal: 500);
    final result = scaleNutrients(per100: per100, amountG: 0);
    expect(result.kcal, 0);
  });

  test('sat_fat_g aus NutrientsPer100 fliesst nicht in NutrientAmounts ein (meal_ingredients hat keine Spalte dafuer)', () {
    const per100 = NutrientsPer100(kcal: 100, satFatG: 5);
    final result = scaleNutrients(per100: per100, amountG: 100);
    expect(result.kcal, 100);
  });
}
