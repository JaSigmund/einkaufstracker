import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import 'package:webview_flutter/webview_flutter.dart';

import 'cooking_chat_panel.dart';

/// Argumente fuer die Route `/recipe-viewer` (per `extra`, siehe `router.dart`).
class RecipeViewerArgs {
  const RecipeViewerArgs({required this.title, this.ingredients = const []});
  final String title;
  final List<String> ingredients;
}

/// Zeigt die externe Kochanleitung zu einem Rezeptvorschlag (ADR-021, Frage Q-24): auf Android/iOS
/// eingebettet per WebView mit einem schwebenden Chat-Button darüber, im Web/PWA-Build stattdessen
/// per externem Browser.
///
/// **Warum die Plattform-Weiche:** `webview_flutter_web` rendert intern über ein `<iframe>`, und
/// Rezeptseiten wie `gutekueche.at` setzen `X-Frame-Options: SAMEORIGIN` (geprüft 2026-10-01) — das
/// würde die Einbettung dort blockieren. Die native WebView (Android `webview_flutter_android` /
/// iOS `webview_flutter_wkwebview`) ist davon nicht betroffen, da sie keine Browser-Iframe-Einbettung
/// ist, sondern eine eigene systemeigene Ansicht — dort bleibt der Chat-Button direkt über dem
/// Rezept sichtbar, ohne dass der Nutzer die App verlässt.
///
/// **Testbarkeit:** [useEmbeddedWebView] ist bewusst ein Konstruktorparameter (Standard `!kIsWeb`)
/// statt einer festverdrahteten `kIsWeb`-Abfrage im `build()`, damit der Web-Pfad (externer Browser,
/// Fallback-Ansicht) unabhängig von der echten Plattform testbar ist. Der native WebView-Pfad selbst
/// bleibt wie bei den bestehenden Plattform-Integrationen (ML Kit, `flutter_local_notifications`)
/// ohne echtes Gerät nicht über `flutter test` prüfbar — dieselbe, bereits akzeptierte Grenze.
class RecipeViewerPage extends StatefulWidget {
  const RecipeViewerPage({
    super.key,
    required this.recipeTitle,
    required this.url,
    this.useEmbeddedWebView = !kIsWeb,
    this.ingredients = const [],
    this.launchExternal = _launchExternalUrl,
    this.sendChatMessage = cookingChatNotImplemented,
  });

  final String recipeTitle;
  final String url;
  final List<String> ingredients;
  final bool useEmbeddedWebView;

  /// Öffnet eine URL extern (Web/PWA-Pfad). Austauschbar für Tests.
  final Future<void> Function(String url) launchExternal;

  /// Schickt eine Chat-Nachricht ab (siehe `cooking_chat_panel.dart`). Austauschbar für Tests.
  final CookingChatSend sendChatMessage;

  @override
  State<RecipeViewerPage> createState() => _RecipeViewerPageState();
}

class _RecipeViewerPageState extends State<RecipeViewerPage> {
  WebViewController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.useEmbeddedWebView) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadRequest(Uri.parse(widget.url));
    } else {
      widget.launchExternal(widget.url);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.recipeTitle)),
      body: widget.useEmbeddedWebView ? WebViewWidget(controller: _controller!) : _ExternalFallback(widget: widget),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('recipe-chat-button'),
        icon: const Icon(Icons.chat_bubble_outline),
        label: const Text('Koch-Chat'),
        onPressed: () => _openChat(context),
      ),
    );
  }

  void _openChat(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => CookingChatPanel(
        chatContext: CookingChatContext(recipeTitle: widget.recipeTitle, ingredients: widget.ingredients),
        sendMessage: widget.sendChatMessage,
      ),
    );
  }
}

/// Anzeige für den Web/PWA-Pfad: die Anleitung wurde bereits extern geöffnet (siehe [initState]),
/// hier bleibt nur ein Hinweis plus die Möglichkeit, den Link erneut zu öffnen — der Chat-Button
/// bleibt ueber dem Scaffold trotzdem erreichbar.
class _ExternalFallback extends StatelessWidget {
  const _ExternalFallback({required this.widget});

  final RecipeViewerPage widget;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.open_in_new, size: 48),
          const SizedBox(height: 16),
          Text('"${widget.recipeTitle}" wurde im Browser geöffnet.', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton(
            key: const Key('recipe-reopen-external'),
            onPressed: () => widget.launchExternal(widget.url),
            child: const Text('Erneut öffnen'),
          ),
        ]),
      ),
    );
  }
}

Future<void> _launchExternalUrl(String url) async {
  await url_launcher.launchUrl(Uri.parse(url), mode: url_launcher.LaunchMode.externalApplication);
}
