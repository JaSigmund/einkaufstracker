// Koch-Chat (ADR-021): was mit jeder Nachricht mitgeht und wie sie abgeschickt wird. Rein fachlich, ohne Oberflaeche
// (vorher in features/recipes/cooking_chat_panel.dart, Codereview 2026-10-16).

/// Kontext, der automatisch (ohne Zutun des Nutzers) an jede Chat-Nachricht angehängt wird (ADR-021:
/// "ohne den aktuellen Kontext zu beschreiben"): das angezeigte Rezept, seine Zutaten, und — gemäß
/// Q-22 — ein begrenztes Fenster des bisherigen Gesprächs (die Edge Function selbst ist zustandslos,
/// der Client hält den Verlauf und schickt ihn mit).
class CookingChatContext {
  const CookingChatContext({required this.recipeTitle, this.ingredients = const [], this.history = const []});

  final String recipeTitle;
  final List<String> ingredients;
  final List<ChatMessage> history;
}

/// Schickt eine Chat-Nachricht samt [CookingChatContext] ab und liefert die Antwort. Austauschbar für
/// Tests und für den echten Edge-Function-Aufruf (`SupabaseCookingCloud.chat`).
typedef CookingChatSend = Future<String> Function(String userMessage, CookingChatContext context);

/// Standard, solange keine echte Implementierung angebunden ist (z.B. Vorschau ohne Haushalt).
/// Liefert eine ehrliche Fehlermeldung im Chat statt eines stillen Fehlschlags.
Future<String> cookingChatNotImplemented(String userMessage, CookingChatContext context) async {
  throw UnimplementedError('Der Koch-Chat ist nicht verfügbar.');
}

class ChatMessage {
  const ChatMessage({required this.text, required this.fromUser});

  final String text;
  final bool fromUser;
}

/// Wie viele vergangene Nachrichten maximal mitgeschickt werden (Q-22: begrenztes Fenster statt
/// vollem Verlauf, haelt die Kosten pro Nachricht beschraenkt).
const cookingChatHistoryWindow = 6;
