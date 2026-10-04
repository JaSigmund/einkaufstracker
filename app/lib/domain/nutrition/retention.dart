/// Garfaktoren (Phase N4, ADR-037): Beim Garen gehen Vitamine und Mineralstoffe verloren, vor allem Vitamin C, Folat und B-Vitamine, die in
/// Kochwasser und Hitze verschwinden. Die BLS-Werte eines **rohen** Eintrags gelten fuer das rohe Lebensmittel. Wer das Rohgewicht
/// erfasst und angibt, wie es zubereitet wurde, bekommt die Werte um die typischen Verluste gemindert.
///
/// Die Faktoren stammen aus der USDA Table of Nutrient Retention Factors (Release 6, 2007, CC0) und gelten fuer 15 Naehrstoffe (siehe
/// `retention_data.dart`); fuer alle anderen gibt es keinen Wert, sie bleiben wie roh. Energie und Makronaehrstoffe aendern sich nicht.
/// Die Faktoren sind **Durchschnittswerte** fuer eine Kategorie ("Gemuese, gekocht und abgegossen"), keine Messung an deinem Essen.
///
/// Reine Funktionen ohne Datenbankzugriff.
library;

import 'micros.dart';
import 'nutrient_registry.dart';
import 'retention_data.dart';

/// Art der Zubereitung, soweit die USDA-Daten sie unterscheiden.
enum CookMethod {
  boiled('boiled', 'Gekocht'),
  steamed('steamed', 'Gedämpft'),
  fried('fried', 'Gebraten'),
  baked('baked', 'Gebacken'),
  grilled('grilled', 'Gegrillt');

  const CookMethod(this.key, this.label);

  final String key;
  final String label;

  static CookMethod? fromKey(String? key) {
    for (final m in values) {
      if (m.key == key) return m;
    }
    return null;
  }
}

/// Die Faktoren einer Kategorie und Zubereitung: Prozent je Naehrstoffschluessel und die USDA-Quelle.
class RetentionFactors {
  const RetentionFactors({required this.category, required this.method, required this.usdaCode, required this.usdaDescription, required this.percent});

  final String category;
  final CookMethod method;
  final int usdaCode;
  final String usdaDescription;
  final Map<String, int> percent;

  /// Der Wert, der in der Zeile gespeichert wird (`meal_ingredients.preparation`): `kategorie:zubereitung`.
  String get storageKey => '$category:${method.key}';
}

/// Kategorie eines **rohen** BLS-Eintrags, `null`, wenn es fuer ihn keine Garfaktoren gibt (bereits gegarte Eintraege, Getraenke,
/// Zutaten, die man nicht gart). [blsCode] ist der Code, [name] der Name des Eintrags ("Gemüsepaprika rot, roh"), [fatPer100] der
/// Fettgehalt je 100 g (entscheidet bei Fisch zwischen mager und fett; ohne Angabe gibt es fuer Fisch keine Kategorie).
String? retentionCategory({required String blsCode, required String name, double? fatPer100}) {
  if (blsCode.isEmpty) return null;
  final group = blsCode[0];
  final lower = name.toLowerCase();
  for (final rule in retentionRules) {
    if (!rule.groups.contains(group)) continue;
    if (rule.raw && !lower.endsWith('roh')) continue;
    if (!RegExp(rule.include).hasMatch(lower)) continue;
    final exclude = rule.exclude;
    if (exclude != null && RegExp(exclude).hasMatch(lower)) continue;
    if (rule.category == 'fish') {
      if (fatPer100 == null) return null;
      return fatPer100 <= 5 ? 'fish_lean' : 'fish_fat';
    }
    return rule.category;
  }
  return null;
}

/// Zubereitungen, fuer die es bei dieser Kategorie Faktoren gibt, in der Reihenfolge der Oberflaeche.
List<CookMethod> cookMethodsFor(String category) {
  final codes = retentionMethodCodes[category];
  if (codes == null) return const [];
  return [for (final m in CookMethod.values) if (codes.containsKey(m.key)) m];
}

/// Die Faktoren fuer Kategorie und Zubereitung, `null`, wenn es sie nicht gibt.
RetentionFactors? retentionFor(String category, CookMethod method) {
  final code = retentionMethodCodes[category]?[method.key];
  final percent = code == null ? null : retentionFactorPercent[code];
  if (code == null || percent == null) return null;
  return RetentionFactors(category: category, method: method, usdaCode: code, usdaDescription: retentionDescriptions[code] ?? '', percent: percent);
}

/// Liest den gespeicherten Wert `kategorie:zubereitung` zurueck, `null` bei Unbekanntem (alte oder fremde Werte).
RetentionFactors? retentionFromStorage(String? stored) {
  if (stored == null) return null;
  final parts = stored.split(':');
  if (parts.length != 2) return null;
  final method = CookMethod.fromKey(parts[1]);
  return method == null ? null : retentionFor(parts[0], method);
}

/// Wendet die Faktoren auf Mikronaehrstoffe an (absolute Mengen oder je 100 g, es ist nur eine Multiplikation). Schluessel ohne Faktor
/// bleiben unveraendert. `null` bleibt `null`.
Micros? applyRetention(Micros? micros, RetentionFactors? factors) {
  if (micros == null || factors == null) return micros;
  return {for (final e in micros.entries) e.key: e.value * (factors.percent[e.key] ?? 100) / 100};
}

/// Macht [applyRetention] rueckgaengig (aus gespeicherten, bereits geminderten Werten das rohe Profil zurueckgewinnen). Alle Faktoren
/// liegen ueber 0, die Umkehr ist also immer moeglich.
Micros? undoRetention(Micros? micros, RetentionFactors? factors) {
  if (micros == null || factors == null) return micros;
  return {for (final e in micros.entries) e.key: e.value * 100 / (factors.percent[e.key] ?? 100)};
}

/// Die staerksten Verluste fuer die Anzeige: "Folat −35 %, Vitamin C −35 %, Vitamin B1 −20 %". Nur Naehrstoffe, die im Profil [present]
/// vorkommen (sonst wuerde ein Verlust genannt, der nichts veraendert). Gleiche Verluste alphabetisch.
String lossSummary(RetentionFactors factors, {Iterable<String>? present, int max = 3}) {
  final entries = [
    for (final e in factors.percent.entries)
      if (e.value < 100 && (present == null || present.contains(e.key))) e,
  ]..sort((a, b) {
      final byLoss = a.value.compareTo(b.value);
      if (byLoss != 0) return byLoss;
      return (nutrientDef(a.key)?.label ?? a.key).compareTo(nutrientDef(b.key)?.label ?? b.key);
    });
  return [for (final e in entries.take(max)) '${(nutrientDef(e.key)?.label ?? e.key).split(' (').first} −${100 - e.value} %'].join(', ');
}
