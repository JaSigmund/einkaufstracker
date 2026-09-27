/// Versucht, aus einer OFF-Packungsangabe (Feld `quantity`, z.B. "500 g", "1 kg", "1,5kg") ein
/// Stueckgewicht in Gramm zu lesen (`products.unit_weight_g`, Vorbereitung fuer Phase 7 Essenstagebuch).
/// Volumenangaben (l, ml, cl — dort waere Gramm ohne Dichte nicht verlaesslich), Mehrfachpackungen
/// ("6 x 33 cl") und andere nicht eindeutige Formate ergeben `null`, statt zu raten.
double? parseUnitWeightGrams(String quantityText) {
  final match = RegExp(r'^\s*([\d.,]+)\s*(kg|g)\s*$', caseSensitive: false).firstMatch(quantityText.trim());
  if (match == null) return null;
  final value = double.tryParse(match.group(1)!.replaceAll(',', '.'));
  if (value == null) return null;
  return match.group(2)!.toLowerCase() == 'kg' ? value * 1000 : value;
}
