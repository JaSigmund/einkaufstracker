import 'package:flutter/material.dart';

import '../../domain/app_update/app_update_gate.dart';
import '../../domain/recipes/cooking_chat.dart';

// Die Datentypen (CookingChatContext, ChatMessage, CookingChatSend) stehen in domain/recipes/cooking_chat.dart, damit die
// Datenschicht sie ohne Abhaengigkeit von der Oberflaeche nutzen kann (Codereview 2026-10-16).
export '../../domain/recipes/cooking_chat.dart';

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
    // Verlauf VOR dieser Nachricht, auf das Fenster begrenzt (Q-22) -- die neue Nachricht selbst geht
    // separat als userMessage mit, nicht nochmal im Verlauf.
    final history = _messages.length > cookingChatHistoryWindow
        ? _messages.sublist(_messages.length - cookingChatHistoryWindow)
        : List<ChatMessage>.of(_messages);
    setState(() {
      _messages.add(ChatMessage(text: text, fromUser: true));
      _controller.clear();
      _sending = true;
      _error = null;
    });
    try {
      final contextWithHistory = CookingChatContext(
        recipeTitle: widget.chatContext.recipeTitle,
        ingredients: widget.chatContext.ingredients,
        history: history,
      );
      final reply = await widget.sendMessage(text, contextWithHistory);
      if (!mounted) return;
      setState(() => _messages.add(ChatMessage(text: reply, fromUser: false)));
    } catch (e) {
      if (!mounted) return;
      // Update-Sperre (ADR-022): hier hilft nur ein Update, deshalb ohne "konnte nicht gesendet werden"-Praefix.
      setState(() => _error = e is AppUpdateRequiredException ? e.toString() : 'Nachricht konnte nicht gesendet werden: $e');
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
                tooltip: 'Senden',
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
