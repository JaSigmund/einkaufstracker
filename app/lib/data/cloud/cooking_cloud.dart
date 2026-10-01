import '../../domain/recipes/recipe_suggestion.dart';
import '../../features/recipes/cooking_chat_panel.dart';

/// Die Cloud ist nicht erreichbar oder hat nicht geantwortet (offline, Fehler, Zeitueberschreitung).
class CookingCloudUnavailable implements Exception {
  const CookingCloudUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Der Haushalt hat die Cloud-Auswertung nicht erlaubt (household_settings.allow_cloud_ocr,
/// wiederverwendet fuer Rezeptvorschlaege/Chat statt eines eigenen Schalters, ADR-021 Q-23).
class CookingCloudNotAllowed implements Exception {
  const CookingCloudNotAllowed();
  @override
  String toString() => 'Cloud-Auswertung ist in den Einstellungen ausgeschaltet.';
}

/// Ein benoetigtes Zutat fuer einen Rezeptvorschlag-Aufruf.
typedef SuggestionIngredient = ({String name, double? quantity, String? unit});

/// Ruft die Edge Functions `suggest-recipes` und `cooking-chat` auf (ADR-021).
abstract class CookingCloud {
  /// Liefert 3 bis 5 Rezeptideen passend zu [ingredients] (dringlichste zuerst, siehe
  /// `buildRecipeSuggestionContext`). Nur auf Tastendruck aufrufen (Q-21).
  Future<List<RecipeSuggestion>> suggestRecipes(List<SuggestionIngredient> ingredients);

  /// Schickt eine Chat-Nachricht samt Kontext ab. Kompatibel mit [CookingChatSend].
  Future<String> chat(String message, CookingChatContext context);
}
