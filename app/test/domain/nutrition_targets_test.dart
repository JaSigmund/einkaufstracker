import 'package:einkaufstracker/domain/nutrition/daily_nutrition.dart';
import 'package:einkaufstracker/domain/nutrition/nutrition_targets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('checkTarget', () {
    test('ohne Richtwert: kein Vergleich, kein Anteil', () {
      final c = checkTarget(500, null);
      expect(c.status, TargetStatus.noTarget);
      expect(c.fraction, isNull);
    });

    test('leerer Richtwert (weder min noch max) zaehlt als kein Richtwert', () {
      expect(checkTarget(500, const NutrientTarget()).status, TargetStatus.noTarget);
    });

    test('Bereich: darunter, im Bereich (Grenzen eingeschlossen), darueber', () {
      const t = NutrientTarget(min: 1800, max: 2200);
      expect(checkTarget(1799.9, t).status, TargetStatus.below);
      expect(checkTarget(1800, t).status, TargetStatus.within);
      expect(checkTarget(2000, t).status, TargetStatus.within);
      expect(checkTarget(2200, t).status, TargetStatus.within);
      expect(checkTarget(2200.1, t).status, TargetStatus.above);
    });

    test('nur Untergrenze (mindestens 60 g Eiweiss): nie "darueber"', () {
      const t = NutrientTarget(min: 60);
      expect(checkTarget(30, t).status, TargetStatus.below);
      expect(checkTarget(60, t).status, TargetStatus.within);
      expect(checkTarget(400, t).status, TargetStatus.within);
    });

    test('nur Obergrenze (hoechstens 6 g Salz): nie "darunter"', () {
      const t = NutrientTarget(max: 6);
      expect(checkTarget(0, t).status, TargetStatus.within);
      expect(checkTarget(6, t).status, TargetStatus.within);
      expect(checkTarget(6.5, t).status, TargetStatus.above);
    });

    test('Anteil bezieht sich auf die Obergrenze, ohne sie auf die Untergrenze', () {
      expect(checkTarget(1100, const NutrientTarget(min: 1000, max: 2000)).fraction, closeTo(0.55, 1e-9));
      expect(checkTarget(30, const NutrientTarget(min: 60)).fraction, closeTo(0.5, 1e-9));
    });

    test('Richtwert 0 ergibt keinen Anteil statt einer Division durch null', () {
      final c = checkTarget(5, const NutrientTarget(max: 0));
      expect(c.status, TargetStatus.above);
      expect(c.fraction, isNull);
    });
  });

  group('NutritionTargets JSON', () {
    test('Round-Trip im Serverformat', () {
      final t = const NutritionTargets()
          .withTarget(NutrientKey.kcal, const NutrientTarget(min: 1800, max: 2200))
          .withTarget(NutrientKey.proteinG, const NutrientTarget(min: 60));
      expect(t.toJson(), {
        'kcal': {'min': 1800.0, 'max': 2200.0},
        'protein_g': {'min': 60.0},
      });
      expect(NutritionTargets.fromJson(t.toJson()), t);
    });

    test('leere Richtwerte stehen nicht im JSON', () {
      final t = const NutritionTargets().withTarget(NutrientKey.fatG, const NutrientTarget());
      expect(t.toJson(), isEmpty);
      expect(t.isEmpty, isTrue);
    });

    test('withTarget(null) entfernt einen vorhandenen Richtwert', () {
      final t = const NutritionTargets().withTarget(NutrientKey.saltG, const NutrientTarget(max: 6));
      expect(t.isEmpty, isFalse);
      expect(t.withTarget(NutrientKey.saltG, null).isEmpty, isTrue);
    });

    test('fromJson akzeptiert ganze Zahlen vom Server (jsonb liefert int)', () {
      final t = NutritionTargets.fromJson({
        'kcal': {'min': 1800, 'max': 2200},
      });
      expect(t[NutrientKey.kcal], const NutrientTarget(min: 1800, max: 2200));
    });

    test('fromJson verwirft Unbrauchbares, behaelt den Rest', () {
      final t = NutritionTargets.fromJson({
        'unknown_key': {'min': 1},
        'kcal': 'viel',
        'protein_g': {'min': -5},
        'fat_g': {'min': 80, 'max': 40},
        'salt_g': {'max': 6},
        'fiber_g': {'min': '30'},
      });
      expect(t.byKey.keys, [NutrientKey.saltG], reason: 'nur salt_g ist gueltig');
      expect(t[NutrientKey.saltG], const NutrientTarget(max: 6));
    });

    test('fromJson mit Nicht-Map (null, Liste, Text) ergibt leere Richtwerte', () {
      expect(NutritionTargets.fromJson(null).isEmpty, isTrue);
      expect(NutritionTargets.fromJson([1, 2]).isEmpty, isTrue);
      expect(NutritionTargets.fromJson('x').isEmpty, isTrue);
    });

    test('Gleichheit hangt nicht von der Einfuegereihenfolge ab', () {
      final a = const NutritionTargets()
          .withTarget(NutrientKey.kcal, const NutrientTarget(max: 2000))
          .withTarget(NutrientKey.saltG, const NutrientTarget(max: 6));
      final b = const NutritionTargets()
          .withTarget(NutrientKey.saltG, const NutrientTarget(max: 6))
          .withTarget(NutrientKey.kcal, const NutrientTarget(max: 2000));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == a.withTarget(NutrientKey.kcal, const NutrientTarget(max: 2100)), isFalse);
    });
  });

  test('valueOf liefert zu jedem Schluessel den passenden Tageswert', () {
    const totals = NutrientTotals(kcal: 1, proteinG: 2, fatG: 3, carbsG: 4, sugarG: 5, fiberG: 6, saltG: 7);
    expect([for (final k in NutrientKey.values) totals.valueOf(k)], [1, 2, 3, 4, 5, 6, 7]);
  });

  test('jsonKey ist je Naehrwert eindeutig und per fromJsonKey umkehrbar', () {
    final keys = NutrientKey.values.map((k) => k.jsonKey).toSet();
    expect(keys.length, NutrientKey.values.length);
    for (final k in NutrientKey.values) {
      expect(NutrientKey.fromJsonKey(k.jsonKey), k);
    }
    expect(NutrientKey.fromJsonKey('sat_fat_g'), isNull, reason: 'gesaettigtes Fett wird nicht ausgewertet (LH-MEAL-09)');
  });
}
