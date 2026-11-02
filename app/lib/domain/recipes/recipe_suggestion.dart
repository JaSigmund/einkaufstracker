/// Eine von der KI vorgeschlagene Rezeptidee (ADR-021). Bewusst **ohne Kochanleitung**: die liefert
/// nicht die KI, sondern die verlinkte, echte Rezeptseite (`recipe_search_url.dart`) -- so entsteht
/// weder eine erfundene, ungeprüfte Anleitung noch eine Kopie fremder Inhalte.
class RecipeSuggestion {
  const RecipeSuggestion({required this.title, required this.reason, required this.matchingIngredients, this.missingIngredients = const []});

  final String title;

  /// Kurze Begruendung, z.B. "nutzt den Joghurt, der morgen ablaeuft".
  final String reason;

  /// Zutaten aus dem Inventar-Kontext (`buildRecipeSuggestionContext`), auf die sich der Vorschlag
  /// stuetzt -- fuer die Anzeige ("passt zu: Joghurt, Gurke") und fuer `findMissingIngredients`.
  final List<String> matchingIngredients;

  /// Zutaten, die nicht im Inventar-Kontext standen und erst eingekauft werden muessen (ADR-042). Leer, solange der Nutzer nur Vorschlaege
  /// aus dem Vorhandenen will.
  final List<String> missingIngredients;
}

/// Parst die rohe JSON-Antwort der (noch nicht gebauten) Edge Function `suggest-recipes`. Ungueltige
/// oder unvollstaendige Eintraege werden uebersprungen statt die ganze Antwort zu verwerfen (gleiches
/// Prinzip wie beim defensiven Parsen der Bon-Cloud-Antwort, `parsed_receipt.dart`/ADR-008) -- ein
/// einzelner kaputter Vorschlag soll nicht alle anderen mitreissen.
List<RecipeSuggestion> parseRecipeSuggestions(Object? rawJson) {
  if (rawJson is! List) return const [];

  final result = <RecipeSuggestion>[];
  for (final entry in rawJson) {
    if (entry is! Map) continue;
    final title = entry['title'];
    if (title is! String || title.trim().isEmpty) continue;

    final reason = entry['reason'];
    final ingredientsRaw = entry['matchingIngredients'];
    final ingredients = ingredientsRaw is List ? ingredientsRaw.whereType<String>().toList() : const <String>[];
    final missingRaw = entry['missingIngredients'];
    final missing = missingRaw is List ? [for (final m in missingRaw.whereType<String>()) if (m.trim().isNotEmpty) m.trim()] : const <String>[];

    result.add(RecipeSuggestion(
      title: title.trim(),
      reason: reason is String ? reason.trim() : '',
      matchingIngredients: ingredients,
      missingIngredients: missing,
    ));
  }
  return result;
}
