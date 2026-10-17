// Texte fuer Fachwerte (Naehrwerte, Richtwerte, Preisvergleich). Codereview 2026-10-16: stand in core/format.dart, das
// dafuer domain/ importieren musste; core ist die unterste Schicht und kennt keine Fachtypen (test/architecture_test.dart).
import '../../core/format.dart';
import '../../domain/nutrition/nutrition_targets.dart';
import '../../domain/shopping_list/list_price_estimate.dart';

/// Ein Naehrwert mit Einheit: kcal mit Tausenderpunkt, alles andere in Gramm.
String formatNutrient(NutrientKey key, double value) => key == NutrientKey.kcal ? formatKcal(value) : formatNutrientGrams(value);

/// Richtwert als Text: "1.800–2.200 kcal", "mindestens 60 g" oder "höchstens 6 g".
String formatTarget(NutrientKey key, NutrientTarget target) {
  String n(double v) => key == NutrientKey.kcal ? formatKcal(v).replaceAll(' kcal', '') : formatQuantity(v);
  final unit = key.unit;
  if (target.min != null && target.max != null) return '${n(target.min!)}–${n(target.max!)} $unit';
  if (target.min != null) return 'mindestens ${n(target.min!)} $unit';
  return 'höchstens ${n(target.max!)} $unit';
}

/// Schaetzung gegen tatsaechlich bezahlt: "geschätzt 24,30 € · bezahlt 26,10 € (1,80 € teurer als geschätzt)".
String formatEstimateVsActual(EstimateVsActual c) {
  final diff = c.differenceCents;
  final note = diff == 0
      ? 'genau wie geschätzt'
      : diff > 0
          ? '${formatEuro(diff)} teurer als geschätzt'
          : '${formatEuro(-diff)} günstiger als geschätzt';
  return 'geschätzt ${formatEuro(c.estimatedCents)} · bezahlt ${formatEuro(c.actualCents)} ($note)';
}
