/// Texte zur Nahrungsergaenzung (Phase N4, ADR-035). Reine Funktionen.
library;

import '../../core/format.dart';
import 'micros.dart';
import 'nutrient_registry.dart';

/// Kurzfassung der Inhaltsstoffe fuer eine Listenzeile: "Vitamin D 25 µg, Vitamin C 80 mg, Eisen 14 mg +2". Die Reihenfolge ist die
/// des Registers (Vitamine, dann Mineralstoffe). Leer ohne Werte.
String summarizeMicros(Micros micros, {int maxItems = 3}) {
  final defs = [for (final d in nutrientRegistry) if (micros.containsKey(d.key)) d];
  if (defs.isEmpty) return '';
  final shown = [for (final d in defs.take(maxItems)) '${d.label.split(' (').first} ${formatMicro(d, micros[d.key]!)}'];
  final rest = defs.length - shown.length;
  return rest > 0 ? '${shown.join(', ')} +$rest' : shown.join(', ');
}

/// "1 × Tablette", "2 × Kapsel", "0,5 × Messlöffel": die Einheit bleibt, wie der Nutzer sie nannte (keine Mehrzahlbildung raten).
String formatServings(double servings, String label) => '${formatQuantity(servings)} × $label';

/// Gueltige Anzahl einer Einnahme: groesser als 0 und hoechstens 100.
bool isValidServings(double? servings) => servings != null && servings.isFinite && servings > 0 && servings <= 100;

/// Liest eine Zahl, wie man sie tippt: "2", "0,5", "12.5". `null` bei allem anderen.
double? parseAmount(String text) {
  final t = text.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  return v != null && v.isFinite ? v : null;
}
