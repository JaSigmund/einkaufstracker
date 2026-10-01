import 'package:flutter/material.dart';

/// Kontext, der automatisch (ohne Zutun des Nutzers) an jede Chat-Nachricht angehängt wird (ADR-021:
/// "ohne den aktuellen Kontext zu beschreiben"). Aktuell nur das angezeigte Rezept und seine
/// Zutaten — Inventar-Kontext (`buildRecipeSuggestionContext`) kommt dazu, sobald die Edge Function
/// steht.
class CookingChatContext {
  const CookingChatContext({required this.recipeTitle, this.ingredients = const []});

  final String recipeTitle;
  final List<String> ingredients;
}

/// Schickt eine Chat-Nachricht samt [CookingChatContext] ab und liefert die Antwort. Austauschbar für
/// Tests und für den (noch nicht gebauten) echten Edge-Function-Aufruf.
typedef CookingChatSend = Future<String> Function(String userMessage, CookingChatContext context);

/// Noch kein echter Edge-Function-Aufruf: ADR-021s offene Fragen Q-21 (Häufigkeit/Kosten), Q-22
/// (Gesprächsverlauf) und Q-23 (Einwilligung) sind unbeantwortet. Liefert eine ehrliche Fehlermeldung
/// im Chat statt eines stillen Fehlschlags oder einer vorgetäuschten Antwort.
Future<String> cookingChatNotImplemented(String userMessage, CookingChatContext context) async {
  throw UnimplementedError('Der Koch-Chat ist noch nicht angebunden (ADR-021, Fragen Q-21 bis Q-23 offen).');
}

class ChatMessage {
  const ChatMessage({required this.text, required this.fromUser});

  final String text;
  final bool fromUser;
}

/// Chat-Panel mit automatischem Kontext (ADR-021): der Nutzer tippt nur seine Frage, [chatContext]
/// wird bei jeder Nachricht automatisch mitgeschickt.
class CookingChatPanel extends StatefulWidget {
  const CookingChatPanel({super.key, required this.chatContext, this.sendMessage = cookingChatNotImplemented});

  final CookingChatContext chatContext;
  final CookingChatSend sendMessage;

  @override
  State<CookingChatPanel> createState() => _CookingChatPanelState();
}

class _CookingChatPanelState extends State<CookingChatPanel> {
  final _controller = TextEditingController();
  final _messages = <ChatMessage>[];
  bool _sending = false;
  String? _error;

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _messages.add(ChatMessage(text: text, fromUser: true));
      _controller.clear();
      _sending = true;
      _error = null;
    });
    try {
      final reply = await widget.sendMessage(text, widget.chatContext);
      if (!mounted) return;
      setState(() => _messages.add(ChatMessage(text: reply, fromUser: false)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Nachricht konnte nicht gesendet werden: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Koch-Chat zu "${widget.chatContext.recipeTitle}"', style: t.textTheme.titleMedium),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: ListView.builder(
              key: const Key('chat-messages'),
              shrinkWrap: true,
              itemCount: _messages.length,
              itemBuilder: (_, i) {
                final m = _messages[i];
                return Align(
                  alignment: m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: m.fromUser ? t.colorScheme.primaryContainer : t.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(m.text),
                  ),
                );
              },
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!, key: const Key('chat-error'), style: TextStyle(color: t.colorScheme.error)),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(
                child: TextField(
                  key: const Key('chat-input'),
                  controller: _controller,
                  decoration: const InputDecoration(hintText: 'Frage stellen …'),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                key: const Key('chat-send'),
                icon: _sending
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
                onPressed: _sending ? null : _send,
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
