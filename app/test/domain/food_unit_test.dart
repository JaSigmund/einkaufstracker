import 'package:einkaufstracker/domain/nutrition/food_unit.dart';
import 'package:einkaufstracker/domain/nutrition/meal_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

/// Haushaltsmasse und ihre Gewichte (Phase N2, ADR-033).
FoodUnit _u(FoodUnitKey key, double g, {UnitSize size = UnitSize.none, String source = 'usda'}) =>
    FoodUnit(blsCode: 'F503100', key: key, size: size, gramsEdible: g, source: source);

void main() {
  group('FoodUnitKey', () {
    test('Namen der Datenbank und Anzeige', () {
      expect(FoodUnitKey.fromDb('slice'), FoodUnitKey.slice);
      expect(FoodUnitKey.fromDb('tbsp')?.singular, 'EL');
      expect(FoodUnitKey.fromDb('handvoll'), isNull);
      expect(FoodUnitKey.fromDb(null), isNull);
      for (final k in FoodUnitKey.values) {
        expect(FoodUnitKey.fromDb(k.db), k, reason: k.name);
      }
    });

    test('Einzahl bei genau 1, sonst Mehrzahl', () {
      expect(FoodUnitKey.slice.labelFor(1), 'Scheibe');
      expect(FoodUnitKey.slice.labelFor(2), 'Scheiben');
      expect(FoodUnitKey.slice.labelFor(0.5), 'Scheiben');
      expect(FoodUnitKey.piece.labelFor(3), 'Stk');
      expect(FoodUnitKey.head.labelFor(2), 'Köpfe');
      expect(FoodUnitKey.tbsp.labelFor(2), 'EL');
    });
  });

  test('UnitSize.fromDb: unbekannt oder leer heisst ohne Groesse', () {
    expect(UnitSize.fromDb('small'), UnitSize.small);
    expect(UnitSize.fromDb('medium').label, 'mittel');
    expect(UnitSize.fromDb(''), UnitSize.none);
    expect(UnitSize.fromDb('riesig'), UnitSize.none);
    expect(UnitSize.fromDb(null), UnitSize.none);
  });

  group('foodUnitFromRow', () {
    test('liest Zahlen und Text-Zahlen', () {
      final a = foodUnitFromRow({'bls_code': 'F503100', 'unit_key': 'piece', 'size': 'medium', 'grams_edible': 118, 'source': 'usda'})!;
      expect([a.blsCode, a.key, a.size, a.gramsEdible, a.source], ['F503100', FoodUnitKey.piece, UnitSize.medium, 118, 'usda']);
      final b = foodUnitFromRow({'bls_code': 'Q120000', 'unit_key': 'tbsp', 'size': '', 'grams_edible': '13,5', 'source': 'curated'})!;
      expect(b.gramsEdible, 13.5);
      expect(b.size, UnitSize.none);
    });

    test('unlesbare Zeilen werden verworfen', () {
      expect(foodUnitFromRow({'bls_code': 'X', 'unit_key': 'handvoll', 'grams_edible': 5}), isNull);
      expect(foodUnitFromRow({'bls_code': 'X', 'unit_key': 'piece', 'grams_edible': 0}), isNull);
      expect(foodUnitFromRow({'bls_code': 'X', 'unit_key': 'piece', 'grams_edible': 'viel'}), isNull);
      expect(foodUnitFromRow({'bls_code': 'X', 'unit_key': 'piece'}), isNull);
      expect(foodUnitFromRow({'unit_key': 'piece', 'grams_edible': 5}), isNull);
    });

    test('ohne Quelle gilt usda', () {
      expect(foodUnitFromRow({'bls_code': 'X', 'unit_key': 'piece', 'grams_edible': 5})!.source, 'usda');
    });
  });

  group('Auswahl', () {
    final banane = [
      _u(FoodUnitKey.piece, 136, size: UnitSize.large),
      _u(FoodUnitKey.piece, 101, size: UnitSize.small),
      _u(FoodUnitKey.piece, 118, size: UnitSize.medium),
    ];

    test('unitKeysOf: bekannte Einheiten in fester Reihenfolge, Stueck zuerst', () {
      expect(unitKeysOf([_u(FoodUnitKey.tsp, 5), _u(FoodUnitKey.slice, 28), _u(FoodUnitKey.tbsp, 15), _u(FoodUnitKey.piece, 50)]),
          [FoodUnitKey.piece, FoodUnitKey.slice, FoodUnitKey.tbsp, FoodUnitKey.tsp]);
      expect(unitKeysOf(const []), isEmpty);
    });

    test('sizesOf: klein bis gross', () {
      expect(sizesOf(banane, FoodUnitKey.piece).map((u) => u.gramsEdible), [101, 118, 136]);
      expect(sizesOf(banane, FoodUnitKey.slice), isEmpty);
    });

    test('defaultUnit: mittel, sonst ohne Angabe, sonst klein, sonst gross', () {
      expect(defaultUnit(banane, FoodUnitKey.piece)?.gramsEdible, 118);
      expect(defaultUnit([_u(FoodUnitKey.piece, 50), _u(FoodUnitKey.piece, 60, size: UnitSize.large)], FoodUnitKey.piece)?.gramsEdible, 50);
      expect(defaultUnit([_u(FoodUnitKey.piece, 30, size: UnitSize.small), _u(FoodUnitKey.piece, 60, size: UnitSize.large)], FoodUnitKey.piece)?.gramsEdible, 30);
      expect(defaultUnit([_u(FoodUnitKey.piece, 60, size: UnitSize.large)], FoodUnitKey.piece)?.gramsEdible, 60);
      expect(defaultUnit(banane, FoodUnitKey.tbsp), isNull);
    });
  });

  group('parseAnalyzedUnit', () {
    test('liest Anzahl, Einheit, Gewicht, Quelle und Groesse', () {
      final u = parseAnalyzedUnit({'count': 2, 'unit_key': 'piece', 'unit_weight_g': 59, 'unit_source': 'household', 'size': ''})!;
      expect([u.count, u.key, u.weightG, u.source, u.size], [2, FoodUnitKey.piece, 59, 'household', UnitSize.none]);
      expect(u.totalG, 118);
      final v = parseAnalyzedUnit({'count': 1.5, 'unit_key': 'slice', 'unit_weight_g': 28, 'size': 'medium'})!;
      expect(v.source, 'usda');
      expect(v.size, UnitSize.medium);
      expect(v.totalG, 42);
    });

    test('unbrauchbar: null', () {
      for (final bad in <Object?>[
        null,
        'x',
        {'count': 0, 'unit_key': 'piece', 'unit_weight_g': 5},
        {'count': -1, 'unit_key': 'piece', 'unit_weight_g': 5},
        {'count': 2, 'unit_key': 'handvoll', 'unit_weight_g': 5},
        {'count': 2, 'unit_key': 'piece', 'unit_weight_g': 0},
        {'count': 2, 'unit_key': 'piece'},
        {'count': 'zwei', 'unit_key': 'piece', 'unit_weight_g': 5},
      ]) {
        expect(parseAnalyzedUnit(bad), isNull, reason: '$bad');
      }
    });

    test('in der Analyse: die Zutat behaelt Gramm und bekommt die Einheit, eine kaputte Einheit macht die Zutat nicht kaputt', () {
      final a = parseMealAnalysis({
        'ingredients': [
          {'name': 'Ei', 'est_amount_g': 100, 'unit': {'count': 2, 'unit_key': 'piece', 'unit_weight_g': 50, 'unit_source': 'usda', 'size': 'medium'}},
          {'name': 'Brot', 'est_amount_g': 60, 'unit': {'count': 2, 'unit_key': 'nonsens', 'unit_weight_g': 30}},
          {'name': 'Reis', 'est_amount_g': 150, 'unit': null},
        ],
      });
      expect(a.ingredients.map((i) => i.unit?.totalG), [100, null, null]);
      expect(a.ingredients.map((i) => i.estimatedGrams), [100, 60, 150]);
      expect(a.ingredients.first.unit?.key, FoodUnitKey.piece);
    });
  });
}
