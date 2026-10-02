import 'package:einkaufstracker/domain/nutrition/ingredient_nutrition.dart';
import 'package:einkaufstracker/domain/nutrition/nutrient_scaling.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mengenaufloesung und Snapshot-Naehrwerte einer Tagebuch-Zutat (Doku 15 §3.4, §5.3).
void main() {
  group('resolveIngredientAmount', () {
    test('Gewichtsware (kg) in Gramm erfasst: 150 g = 0,15 kg Abzug, 150 g Naehrwertbasis', () {
      final a = resolveIngredientAmount(quantity: 150, entryUnit: EntryUnit.g, baseUnit: 'kg', nutrientsBasis: 'g');
      expect(a.inventoryQuantity, closeTo(0.15, 1e-9));
      expect(a.nutrientBasisAmount, closeTo(150, 1e-9));
    });

    test('Fluessigkeit (l) in ml erfasst: 250 ml = 0,25 l Abzug, 250 ml Basis', () {
      final a = resolveIngredientAmount(quantity: 250, entryUnit: EntryUnit.ml, baseUnit: 'l', nutrientsBasis: 'ml');
      expect(a.inventoryQuantity, closeTo(0.25, 1e-9));
      expect(a.nutrientBasisAmount, closeTo(250, 1e-9));
    });

    test('Stueckware: 2 Stueck = 2 Abzug; Naehrwertbasis ueber das Stueckgewicht (2 x 150 g)', () {
      final a = resolveIngredientAmount(quantity: 2, entryUnit: EntryUnit.piece, baseUnit: 'piece', nutrientsBasis: 'g', unitWeightG: 150);
      expect(a.inventoryQuantity, 2);
      expect(a.nutrientBasisAmount, 300);
    });

    test('Stueckware ohne Stueckgewicht: Abzug moeglich, Naehrwertbasis unbekannt (null statt Raten)', () {
      final a = resolveIngredientAmount(quantity: 2, entryUnit: EntryUnit.piece, baseUnit: 'piece', nutrientsBasis: 'g');
      expect(a.inventoryQuantity, 2);
      expect(a.nutrientBasisAmount, isNull);
    });

    test('Gewicht eingegeben, Produkt ist Stueckware: ueber das Stueckgewicht (300 g = 2 Stk bei 150 g)', () {
      final a = resolveIngredientAmount(quantity: 300, entryUnit: EntryUnit.g, baseUnit: 'piece', nutrientsBasis: 'g', unitWeightG: 150);
      expect(a.inventoryQuantity, closeTo(2, 1e-9));
      expect(a.nutrientBasisAmount, closeTo(300, 1e-9));
    });

    test('Gewicht eingegeben, Stueckware ohne Stueckgewicht: Abzug nicht berechenbar', () {
      final a = resolveIngredientAmount(quantity: 300, entryUnit: EntryUnit.g, baseUnit: 'piece', nutrientsBasis: 'g');
      expect(a.inventoryQuantity, isNull);
      expect(a.nutrientBasisAmount, closeTo(300, 1e-9));
    });

    test('Stueck eingegeben, Produkt in kg gefuehrt: ueber das Stueckgewicht (2 x 150 g = 0,3 kg)', () {
      final a = resolveIngredientAmount(quantity: 2, entryUnit: EntryUnit.piece, baseUnit: 'kg', nutrientsBasis: 'g', unitWeightG: 150);
      expect(a.inventoryQuantity, closeTo(0.3, 1e-9));
    });

    test('Volumen eingegeben, Produkt in kg gefuehrt: ueber die Dichte (Oel 0,92: 100 ml = 0,092 kg)', () {
      final a = resolveIngredientAmount(quantity: 100, entryUnit: EntryUnit.ml, baseUnit: 'kg', nutrientsBasis: 'g', densityGPerMl: 0.92);
      expect(a.inventoryQuantity, closeTo(0.092, 1e-9));
      expect(a.nutrientBasisAmount, closeTo(92, 1e-9));
    });

    test('Gewicht eingegeben, Produkt in l gefuehrt: ueber die Dichte (Standard 1,0: 200 g = 0,2 l)', () {
      final a = resolveIngredientAmount(quantity: 200, entryUnit: EntryUnit.g, baseUnit: 'l', nutrientsBasis: 'ml');
      expect(a.inventoryQuantity, closeTo(0.2, 1e-9));
      expect(a.nutrientBasisAmount, closeTo(200, 1e-9));
    });

    test('ohne hinterlegte Naehrwerte (nutrientsBasis null): keine Naehrwertbasis, Abzug trotzdem', () {
      final a = resolveIngredientAmount(quantity: 100, entryUnit: EntryUnit.g, baseUnit: 'kg');
      expect(a.inventoryQuantity, closeTo(0.1, 1e-9));
      expect(a.nutrientBasisAmount, isNull);
    });

    test('normierte Menge fuer die Datenbank: g -> kg, ml -> l, Stueck bleibt (Spalte unit kennt kein g/ml)', () {
      final g = resolveIngredientAmount(quantity: 150, entryUnit: EntryUnit.g, baseUnit: 'kg');
      expect((g.quantity, g.unit), (0.15, 'kg'));
      final ml = resolveIngredientAmount(quantity: 250, entryUnit: EntryUnit.ml, baseUnit: 'l');
      expect((ml.quantity, ml.unit), (0.25, 'l'));
      final piece = resolveIngredientAmount(quantity: 2, entryUnit: EntryUnit.piece, baseUnit: 'piece');
      expect((piece.quantity, piece.unit), (2.0, 'piece'));
    });

    test('kg und l direkt erfasst', () {
      expect(resolveIngredientAmount(quantity: 1.5, entryUnit: EntryUnit.kg, baseUnit: 'kg').inventoryQuantity, 1.5);
      expect(resolveIngredientAmount(quantity: 2, entryUnit: EntryUnit.l, baseUnit: 'l').inventoryQuantity, 2);
    });
  });

  group('EntryUnit', () {
    test('natuerliche Eingabeeinheit je Inventar-Basiseinheit', () {
      expect(EntryUnit.naturalFor('kg'), EntryUnit.g);
      expect(EntryUnit.naturalFor('l'), EntryUnit.ml);
      expect(EntryUnit.naturalFor('piece'), EntryUnit.piece);
    });

    test('fromDb: bekannter Name, unbekannter faellt auf g zurueck', () {
      expect(EntryUnit.fromDb('piece'), EntryUnit.piece);
      expect(EntryUnit.fromDb('unbekannt'), EntryUnit.g);
    });

    test('Anzeige: "Stk" statt "piece"', () {
      expect(EntryUnit.piece.label, 'Stk');
      expect(EntryUnit.piece.dbName, 'piece');
    });
  });

  group('ingredientNutrients', () {
    const per100 = NutrientsPer100(kcal: 350, proteinG: 10);

    test('skaliert ueber die Naehrwertbasis (72 g bei 350 kcal je 100 g = 252 kcal)', () {
      final n = ingredientNutrients(per100, const IngredientAmount(inventoryQuantity: 0.072, nutrientBasisAmount: 72));
      expect(n!.kcal, closeTo(252, 1e-9));
      expect(n.proteinG, closeTo(7.2, 1e-9));
    });

    test('ohne Naehrwertprofil: null', () {
      expect(ingredientNutrients(null, const IngredientAmount(nutrientBasisAmount: 100)), isNull);
    });

    test('ohne bestimmbare Menge: null statt 0 (Zutat zaehlt als "nicht erfasst")', () {
      expect(ingredientNutrients(per100, const IngredientAmount(inventoryQuantity: 2)), isNull);
    });
  });

  group('NutrientsPer100.fromMap', () {
    test('liest alle 8 Schluessel von products.nutrients_per_100', () {
      final p = NutrientsPer100.fromMap({
        'kcal': 52, 'protein_g': 0.3, 'fat_g': 0.2, 'sat_fat_g': 0.05, 'carbs_g': 11.4, 'sugar_g': 10.4, 'fiber_g': 2.4, 'salt_g': 0.01,
      })!;
      expect([p.kcal, p.proteinG, p.fatG, p.satFatG, p.carbsG, p.sugarG, p.fiberG, p.saltG], [52, 0.3, 0.2, 0.05, 11.4, 10.4, 2.4, 0.01]);
    });

    test('fehlende oder nicht numerische Eintraege werden zu null', () {
      final p = NutrientsPer100.fromMap({'kcal': 100, 'protein_g': 'viel', 'fat_g': null})!;
      expect(p.kcal, 100);
      expect(p.proteinG, isNull);
      expect(p.fatG, isNull);
    });

    test('null und leere Map ergeben kein Profil', () {
      expect(NutrientsPer100.fromMap(null), isNull);
      expect(NutrientsPer100.fromMap({}), isNull);
      expect(NutrientsPer100.fromMap({'unbekannt': 1}), isNull);
    });
  });
}
