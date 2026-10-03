/// Mikronaehrstoffe als Wertetabelle (Phase N3, ADR-032): `Map<Schluessel, Zahl>` mit den Schluesseln des Registers
/// (`nutrient_registry.dart`, Einheit im Schluessel). Je 100 g im Profil (BLS, Produkt) und absolut fuer die verzehrte Menge im
/// Snapshot einer Zutat (`meal_ingredients.micros`).
///
/// **Ein fehlender Schluessel heisst unbekannt, `0` ist eine echte Null.** Deshalb gibt es hier nie einen Standardwert 0 und nie
/// eine Summe ueber unbekannte Werte.
library;

import 'dart:convert';

import 'nutrient_registry.dart';

typedef Micros = Map<String, double>;

/// Liest ein JSON-Objekt (Server `jsonb`, Produktprofil) defensiv: nur Registerschluessel, nur endliche Zahlen, keine negativen.
/// Zahlen als Text ("13,2") werden gelesen. Alles andere faellt weg. `null`, wenn nichts uebrig bleibt.
Micros? parseMicros(Object? json) {
  if (json is String) {
    try {
      json = jsonDecode(json);
    } on FormatException {
      return null;
    }
  }
  if (json is! Map) return null;
  final out = <String, double>{};
  for (final n in nutrientRegistry) {
    final v = json[n.key];
    final d = v is num ? v.toDouble() : (v is String ? double.tryParse(v.replaceAll(',', '.')) : null);
    if (d != null && d.isFinite && d >= 0) out[n.key] = d;
  }
  return out.isEmpty ? null : out;
}

/// Je-100-g-Werte auf [amountG] Gramm (bzw. ml) umgerechnet. `null` ohne Profil oder ohne sinnvolle Menge.
Micros? scaleMicros(Micros? per100, double? amountG) {
  if (per100 == null || per100.isEmpty || amountG == null || !(amountG > 0)) return null;
  return {for (final e in per100.entries) e.key: e.value * amountG / 100};
}

/// Absolute Werte zurueck auf je 100 g (wenn von einer gespeicherten Zeile nur der Snapshot da ist). `null` ohne Menge.
Micros? micros100From(Micros? absolute, double? amountG) {
  if (absolute == null || absolute.isEmpty || amountG == null || !(amountG > 0)) return null;
  return {for (final e in absolute.entries) e.key: e.value * 100 / amountG};
}

/// JSON-Text fuer die lokale Spalte `meal_ingredients.micros`, `null` bei leerer Tabelle. Werte auf vier Nachkommastellen.
String? encodeMicros(Micros? m) {
  if (m == null || m.isEmpty) return null;
  final keys = nutrientKeys.where(m.containsKey).toList();
  return jsonEncode({for (final k in keys) k: (m[k]! * 10000).round() / 10000});
}

/// Ein Mikronaehrstoff als Zahl mit Einheit, wie die Oberflaeche ihn zeigt ("12,4 mg", "0,8 µg"): Nachkommastellen aus dem
/// Register, Dezimalkomma. Sehr kleine, aber echte Werte zeigen nicht "0".
String formatMicro(NutrientDef def, double value) {
  var d = def.decimals;
  if (value > 0 && value < 1 && d == 0) d = 1;
  if (value > 0 && value < 0.1 && d <= 1) d = 2;
  return '${value.toStringAsFixed(d).replaceAll('.', ',')} ${def.unit}';
}
