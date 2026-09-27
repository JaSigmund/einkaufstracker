import '../categorization/normalize_name.dart';

/// Vorbelegung fuer ein neu angelegtes Produkt: wie lange es nach dem Oeffnen haelt, wo es typischerweise
/// gelagert wird, und ob ein MHD oder ein Verbrauchsdatum massgeblich ist. Startwerte aus Doku 06 §3.2
/// (Richtwerte, keine Garantie), vom Nutzer je Produkt jederzeit ueberschreibbar.
class ShelfLifeSuggestion {
  const ShelfLifeSuggestion({this.openedShelfLifeDays, required this.location, this.dateKind = 'best_before'});
  final int? openedShelfLifeDays;
  final String location;
  final String dateKind;
}

/// Schreibweise eines Stichworts wie in domain/categorization/keyword_rules.dart: `abc` enthaelt, `=abc`
/// ist genau dieses Token (fuer kurze, mehrdeutige Woerter wie "ei"), `a b` mit Leerzeichen prueft den
/// ganzen normalisierten Namen auf diese Wortfolge (fuer "h milch", da der Bindestrich zu einem Leerzeichen wird).
class _Rule {
  const _Rule(this.keywords, this.suggestion);
  final List<String> keywords;
  final ShelfLifeSuggestion suggestion;

  bool matches(String normalized, List<String> tokens) => keywords.any((k) {
        if (k.contains(' ')) return normalized.contains(k);
        if (k.startsWith('=')) return tokens.contains(k.substring(1));
        return tokens.any((t) => t.contains(k));
      });
}

/// Regeln in Prioritaetsreihenfolge: die erste passende gewinnt. Spezifischere Begriffe (z.B. "h-milch")
/// stehen vor allgemeineren ("milch"), damit z.B. H-Milch nicht als Frischmilch erkannt wird.
final _rules = <_Rule>[
  _Rule(['hmilch', 'haltbarmilch', 'h milch'], const ShelfLifeSuggestion(openedShelfLifeDays: 3, location: 'fridge')),
  _Rule(['joghurt', 'jogurt', 'sauerrahm', 'schlagobers', 'schlagsahne'], const ShelfLifeSuggestion(openedShelfLifeDays: 4, location: 'fridge')),
  _Rule(['frischmilch', 'vollmilch', 'milch'], const ShelfLifeSuggestion(openedShelfLifeDays: 3, location: 'fridge')),
  _Rule(['frischkaese', 'topfen'], const ShelfLifeSuggestion(openedShelfLifeDays: 6, location: 'fridge')),
  _Rule(['hartkaese', 'schnittkaese', 'kaese'], const ShelfLifeSuggestion(openedShelfLifeDays: 12, location: 'fridge')),
  _Rule(['aufschnitt', 'wurst', 'schinken', 'salami'], const ShelfLifeSuggestion(openedShelfLifeDays: 2, location: 'fridge')),
  _Rule(['hackfleisch', 'faschiert', 'fleisch', 'fisch'], const ShelfLifeSuggestion(openedShelfLifeDays: 1, location: 'fridge', dateKind: 'use_by')),
  _Rule(['fruchtsaft', 'saft'], const ShelfLifeSuggestion(openedShelfLifeDays: 4, location: 'fridge')),
  _Rule(['honig'], const ShelfLifeSuggestion(location: 'pantry')),
  _Rule(['marmelade', 'konfituere'], const ShelfLifeSuggestion(openedShelfLifeDays: 28, location: 'pantry')),
  _Rule(['ketchup', 'senf', 'sauce', 'sosse'], const ShelfLifeSuggestion(openedShelfLifeDays: 42, location: 'fridge')),
  _Rule(['konserve', 'dose'], const ShelfLifeSuggestion(openedShelfLifeDays: 2, location: 'fridge')),
  _Rule(['tofu', 'pesto'], const ShelfLifeSuggestion(openedShelfLifeDays: 5, location: 'fridge')),
  _Rule(['=ei', 'eier'], const ShelfLifeSuggestion(location: 'fridge')),
  _Rule(['brot', 'semmel', 'gebaeck'], const ShelfLifeSuggestion(openedShelfLifeDays: 4, location: 'pantry')),
];

/// Sucht eine passende Vorbelegung fuer einen Produkt- oder Bon-Namen. `null`, wenn nichts passt (der
/// generische Standard des Produktformulars gilt dann weiter).
ShelfLifeSuggestion? suggestShelfLife(String rawText) {
  final normalized = normalizeItemName(rawText);
  final tokens = normalized.split(' ').where((t) => t.isNotEmpty).toList();
  if (tokens.isEmpty) return null;
  for (final rule in _rules) {
    if (rule.matches(normalized, tokens)) return rule.suggestion;
  }
  return null;
}
