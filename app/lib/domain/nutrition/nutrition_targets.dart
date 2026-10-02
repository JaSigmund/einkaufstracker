/// Vom Nutzer gesetzte Richtwerte fuer die Naehrwerte (LH-MEAL-09, Doku 15 §1/§3.5).
///
/// Die App gibt **keine** Werte vor: ohne eigene Eingabe gibt es keinen Richtwert, und der Vergleich bewertet nicht,
/// er sagt nur "darunter", "im Bereich" oder "darueber" (Doku 15 §2: keine Ernaehrungsberatung).
/// Reine Funktionen ohne Datenbankzugriff.
library;

import 'daily_nutrition.dart';

/// Die sieben ausgewerteten Naehrwerte mit Schluessel im Server-JSON (`nutrition_targets.targets`), Anzeigename und Einheit.
enum NutrientKey {
  kcal('kcal', 'Energie', 'kcal'),
  proteinG('protein_g', 'Eiweiß', 'g'),
  fatG('fat_g', 'Fett', 'g'),
  carbsG('carbs_g', 'Kohlenhydrate', 'g'),
  sugarG('sugar_g', 'Zucker', 'g'),
  fiberG('fiber_g', 'Ballaststoffe', 'g'),
  saltG('salt_g', 'Salz', 'g');

  const NutrientKey(this.jsonKey, this.label, this.unit);

  final String jsonKey;
  final String label;
  final String unit;

  static NutrientKey? fromJsonKey(String key) {
    for (final k in values) {
      if (k.jsonKey == key) return k;
    }
    return null;
  }
}

extension NutrientTotalsByKey on NutrientTotals {
  double valueOf(NutrientKey key) => switch (key) {
        NutrientKey.kcal => kcal,
        NutrientKey.proteinG => proteinG,
        NutrientKey.fatG => fatG,
        NutrientKey.carbsG => carbsG,
        NutrientKey.sugarG => sugarG,
        NutrientKey.fiberG => fiberG,
        NutrientKey.saltG => saltG,
      };
}

/// Untere und/oder obere Grenze je Tag. Beide optional: "mindestens 60 g Eiweiß" und "hoechstens 6 g Salz" sind
/// jeweils einseitige Ziele, "1.800 bis 2.200 kcal" ein Bereich.
class NutrientTarget {
  const NutrientTarget({this.min, this.max});

  final double? min;
  final double? max;

  bool get isSet => min != null || max != null;

  /// Ein Bereich mit `min > max` ergibt keinen Sinn.
  bool get isConsistent => min == null || max == null || min! <= max!;

  /// Vergleichswert fuer den Fortschrittsbalken: die Obergrenze, sonst die Untergrenze.
  double? get reference => max ?? min;

  @override
  bool operator ==(Object other) => other is NutrientTarget && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);
}

enum TargetStatus { noTarget, below, within, above }

/// Ergebnis des Vergleichs eines Tageswerts mit seinem Richtwert.
class TargetCheck {
  const TargetCheck(this.status, this.fraction);

  final TargetStatus status;

  /// Wert im Verhaeltnis zum Vergleichswert (1,0 = genau erreicht), `null` ohne Richtwert.
  final double? fraction;
}

TargetCheck checkTarget(double value, NutrientTarget? target) {
  if (target == null || !target.isSet) return const TargetCheck(TargetStatus.noTarget, null);
  final reference = target.reference!;
  final fraction = reference > 0 ? value / reference : null;
  if (target.min != null && value < target.min!) return TargetCheck(TargetStatus.below, fraction);
  if (target.max != null && value > target.max!) return TargetCheck(TargetStatus.above, fraction);
  return TargetCheck(TargetStatus.within, fraction);
}

/// Alle Richtwerte eines Haushalts. Leer, solange der Nutzer keine gesetzt hat.
class NutritionTargets {
  const NutritionTargets([this.byKey = const {}]);

  final Map<NutrientKey, NutrientTarget> byKey;

  bool get isEmpty => byKey.values.every((t) => !t.isSet);

  NutrientTarget? operator [](NutrientKey key) {
    final t = byKey[key];
    return t != null && t.isSet ? t : null;
  }

  /// Kopie mit geaendertem Richtwert; ein leerer ([NutrientTarget.isSet] false) Richtwert entfernt den Eintrag.
  NutritionTargets withTarget(NutrientKey key, NutrientTarget? target) {
    final next = Map<NutrientKey, NutrientTarget>.of(byKey);
    if (target == null || !target.isSet) {
      next.remove(key);
    } else {
      next[key] = target;
    }
    return NutritionTargets(next);
  }

  /// Serverformat: `{"kcal": {"min": 1800, "max": 2200}, "protein_g": {"min": 60}}`
  Map<String, dynamic> toJson() => {
        for (final e in byKey.entries)
          if (e.value.isSet) e.key.jsonKey: {if (e.value.min != null) 'min': e.value.min, if (e.value.max != null) 'max': e.value.max},
      };

  /// Liest defensiv: unbekannte Schluessel, negative oder nicht numerische Werte und widerspruechliche Bereiche
  /// werden verworfen statt die ganze Zeile unbrauchbar zu machen (der Server speichert beliebiges JSON).
  factory NutritionTargets.fromJson(Object? json) {
    if (json is! Map) return const NutritionTargets();
    final out = <NutrientKey, NutrientTarget>{};
    for (final e in json.entries) {
      final key = e.key is String ? NutrientKey.fromJsonKey(e.key as String) : null;
      final v = e.value;
      if (key == null || v is! Map) continue;
      final min = _positive(v['min']);
      final max = _positive(v['max']);
      final t = NutrientTarget(min: min, max: max);
      if (t.isSet && t.isConsistent) out[key] = t;
    }
    return NutritionTargets(out);
  }

  static double? _positive(Object? v) => v is num && v.isFinite && v >= 0 ? v.toDouble() : null;

  @override
  bool operator ==(Object other) => other is NutritionTargets && NutrientKey.values.every((k) => this[k] == other[k]);

  @override
  int get hashCode => Object.hashAll(NutrientKey.values.map((k) => this[k]));
}
