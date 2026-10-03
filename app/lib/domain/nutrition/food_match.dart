/// Treffer der Zuordnung einer Zutat zu einem Eintrag der Lebensmitteldatenbank (BLS), Phase N1, ADR-031.
///
/// Die Zuordnung selbst passiert auf dem Server (SQL-Funktion `search_bls_foods`, Edge Function `analyze-meal`). Hier steht,
/// was die App damit macht: lesen, anzeigen, als Naehrwertprofil verwenden.
library;

import 'nutrient_scaling.dart';

/// Wie sicher die Zuordnung ist. Die Oberflaeche zeigt drei Marken: sicher (✓), automatisch zugeordnet (~, antippen zum
/// Bestaetigen oder Aendern) und unbekannt (?).
enum MatchTrust {
  /// Gedaechtnis des Haushalts, Synonym, vom Nutzer gewaehlt oder bestaetigt, oder das Produkt hat eigene Naehrwerte.
  sure,

  /// Automatisch zugeordnet (Suche oder KI-Auswahl), noch nicht bestaetigt.
  auto,

  /// Keine Zuordnung.
  unknown;

  /// Wert fuer `meal_ingredients.nutrient_basis` dieser Stufe bei einem BLS-Treffer.
  String get basis => this == MatchTrust.sure ? 'bls_exact' : (this == MatchTrust.auto ? 'bls_matched' : 'unknown');
}

/// Ein zugeordneter BLS-Eintrag mit Naehrwerten je 100 g.
class FoodMatch {
  const FoodMatch({required this.code, required this.name, required this.per100, this.method = 'search', this.trust = MatchTrust.auto});

  final String code;

  /// Offizieller Name des BLS-Eintrags ("Gemüsepaprika rot, roh").
  final String name;
  final NutrientsPer100 per100;

  /// `memory` | `synonym` | `search` | `llm`: woher die Zuordnung stammt. Gedaechtnis und Synonym sind schon bekannt und
  /// muessen nicht noch einmal gelernt werden.
  final String method;
  final MatchTrust trust;

  /// Diese Zuordnung ist dem Haushalt oder den Synonymen schon bekannt (Lernen waere ueberfluessig).
  bool get alreadyKnown => method == 'memory' || method == 'synonym';

  FoodMatch confirmed() => FoodMatch(code: code, name: name, per100: per100, method: method, trust: MatchTrust.sure);
}

/// Liest den Treffer aus der Antwort von `analyze-meal` (`match`-Objekt). `null` bei fehlendem oder unlesbarem Treffer.
FoodMatch? parseFoodMatch(Object? json) {
  if (json is! Map) return null;
  final code = json['code'];
  final name = json['name'];
  if (code is! String || code.isEmpty || name is! String || name.isEmpty) return null;
  final raw = json['per100'];
  final per100 = raw is Map ? NutrientsPer100.fromMap(Map<String, dynamic>.from(raw)) : null;
  if (per100 == null) return null;
  final method = json['method'];
  return FoodMatch(
    code: code,
    name: name,
    per100: per100,
    method: method is String && const {'memory', 'synonym', 'search', 'llm'}.contains(method) ? method : 'search',
    trust: json['trust'] == 'sure' ? MatchTrust.sure : MatchTrust.auto,
  );
}
