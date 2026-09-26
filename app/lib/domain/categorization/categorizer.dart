import 'keyword_rules.dart';
import 'normalize_name.dart';

/// Woher eine Zuordnung stammt (absteigende Verlaesslichkeit).
enum CategorySource {
  /// Der Nutzer hat diesen Artikel schon einmal zugeordnet.
  alias,

  /// Ein Stichwort hat gegriffen.
  rule,

  /// Aus der Art der Position (Pfand).
  kind,

  /// Bei Rabatten: uebernimmt die Kategorie des Artikels darueber.
  inherited,

  /// Nichts gepasst, der Nutzer muss zuordnen.
  none,
}

class CategorySuggestion {
  const CategorySuggestion(this.categoryId, this.source);
  final String? categoryId;
  final CategorySource source;

  bool get isAssigned => categoryId != null;
}

/// Ordnet Bon-Artikel Kategorien zu: 1. gelernte Zuordnung des Nutzers, 2. Stichwortregeln.
/// Nach Doku 05 §3.7 (Stufen 1 und 2); Fuzzy-Match und KI-Vorschlag folgen bei Bedarf.
class Categorizer {
  Categorizer({required this.categoryIdByName, this.aliasCategoryIdByKey = const {}});

  /// Kategoriename -> ID im Haushalt des Nutzers.
  final Map<String, String> categoryIdByName;

  /// Normalisierter Artikelname -> ID der vom Nutzer gelernten Kategorie.
  final Map<String, String> aliasCategoryIdByKey;

  /// [rawText] ist der Name wie auf dem Bon. [isDeposit] markiert Pfandpositionen.
  CategorySuggestion categorize(String rawText, {bool isDeposit = false}) {
    if (isDeposit) {
      final id = categoryIdByName[CategoryNames.pfand];
      return CategorySuggestion(id, id == null ? CategorySource.none : CategorySource.kind);
    }
    final key = normalizeItemName(rawText);
    final learned = aliasCategoryIdByKey[key];
    if (learned != null) return CategorySuggestion(learned, CategorySource.alias);

    final tokens = key.split(' ').where((t) => t.isNotEmpty).toList();
    for (final rule in keywordRules) {
      if (rule.matches(key, tokens)) {
        final id = categoryIdByName[rule.category];
        if (id != null) return CategorySuggestion(id, CategorySource.rule);
        // Kategorie beim Nutzer umbenannt oder geloescht: naechste Regel pruefen
      }
    }
    return const CategorySuggestion(null, CategorySource.none);
  }
}
