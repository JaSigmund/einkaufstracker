import 'package:einkaufstracker/domain/nutrition/unit_conversion.dart';
import 'package:flutter_test/flutter_test.dart';

/// Testet die Einheiten-Umrechnung fuers Essenstagebuch (Doku 15 §5.3, Phase 7 Vorbereitung).
void main() {
  group('convertToNutrientBasis', () {
    test('kg auf Basis g: trivial (Faktor 1000)', () {
      expect(convertToNutrientBasis(quantity: 0.5, quantityUnit: 'kg', basis: 'g'), 500);
    });

    test('l auf Basis ml: trivial (Faktor 1000)', () {
      expect(convertToNutrientBasis(quantity: 0.25, quantityUnit: 'l', basis: 'ml'), 250);
    });

    test('piece auf Basis g: ueber unitWeightG (z.B. Paprika 150 g)', () {
      expect(convertToNutrientBasis(quantity: 2, quantityUnit: 'piece', basis: 'g', unitWeightG: 150), 300);
    });

    test('piece ohne unitWeightG: null statt Raten (Oberflaeche muss nachfragen)', () {
      expect(convertToNutrientBasis(quantity: 1, quantityUnit: 'piece', basis: 'g'), isNull);
    });

    test('l auf Basis g: ueber Dichte (Standard 1,0 wie Wasser)', () {
      expect(convertToNutrientBasis(quantity: 0.2, quantityUnit: 'l', basis: 'g'), 200);
    });

    test('l auf Basis g mit abweichender Dichte (z.B. Oel 0,92)', () {
      expect(convertToNutrientBasis(quantity: 1, quantityUnit: 'l', basis: 'g', densityGPerMl: 0.92), 920);
    });

    test('kg auf Basis ml: ueber Dichte', () {
      final ml = convertToNutrientBasis(quantity: 1, quantityUnit: 'kg', basis: 'ml', densityGPerMl: 0.92)!;
      expect(ml, closeTo(1000 / 0.92, 0.01));
    });

    test('piece auf Basis ml: ueber unitWeightG und Dichte', () {
      // 1 Ei = 60 g, Dichte 1,03 (typisch fuer Eimasse)
      final ml = convertToNutrientBasis(quantity: 1, quantityUnit: 'piece', basis: 'ml', unitWeightG: 60, densityGPerMl: 1.03)!;
      expect(ml, closeTo(60 / 1.03, 0.01));
    });

    test('unbekannte Einheit: null statt Absturz', () {
      expect(convertToNutrientBasis(quantity: 1, quantityUnit: 'unbekannt', basis: 'g'), isNull);
    });
  });

  test('Loeffel-Richtwerte: EL 10 g, TL 5 g', () {
    expect(tablespoonGrams, 10);
    expect(teaspoonGrams, 5);
  });
}
