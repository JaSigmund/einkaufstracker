import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/features/recipes/cooking_chat_panel.dart';
import 'package:einkaufstracker/features/recipes/recipe_viewer_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

/// Testet nur den Web/PWA-Pfad (`useEmbeddedWebView: false`, erzwungen). Der native WebView-Pfad
/// braucht eine echte Plattform-Implementierung (Android/iOS) und ist wie bei den anderen
/// Plattform-Integrationen in diesem Projekt (ML Kit, `flutter_local_notifications`) nicht über
/// `flutter test` prüfbar — siehe Doku-Kommentar in `recipe_viewer_page.dart`.
void main() {
  Widget app({required Future<void> Function(String) launchExternal, CookingChatSend sendChatMessage = cookingChatNotImplemented}) =>
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) {
            final db = memoryDb();
            ref.onDispose(db.close);
            return db;
          }),
          notificationSchedulerProvider.overrideWithValue(FakeNotificationScheduler()),
          cookingSessionsStreamProvider.overrideWith((ref) => const Stream.empty()),
        ],
        child: MaterialApp(
          home: RecipeViewerPage(
            recipeTitle: 'Kürbissuppe',
            url: 'https://www.google.com/search?q=site:gutekueche.at+K%C3%BCrbissuppe+rezept',
            useEmbeddedWebView: false,
            ingredients: const ['Kürbis'],
            launchExternal: launchExternal,
            sendChatMessage: sendChatMessage,
          ),
        ),
      );

  testWidgets('oeffnet die URL beim Anzeigen extern (Web/PWA-Pfad)', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(app(launchExternal: (url) async => opened.add(url)));
    await tester.pumpAndSettle();

    expect(opened, ['https://www.google.com/search?q=site:gutekueche.at+K%C3%BCrbissuppe+rezept']);
    expect(find.text('"Kürbissuppe" wurde im Browser geöffnet.'), findsOneWidget);
  });

  testWidgets('"Erneut oeffnen" ruft launchExternal erneut auf', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(app(launchExternal: (url) async => opened.add(url)));
    await tester.pumpAndSettle();
    expect(opened, hasLength(1));

    await tester.tap(find.byKey(const Key('recipe-reopen-external')));
    await tester.pumpAndSettle();

    expect(opened, hasLength(2));
  });

  testWidgets('Chat-Button oeffnet das Koch-Chat-Panel mit dem Rezepttitel', (tester) async {
    await tester.pumpWidget(app(launchExternal: (_) async {}));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('recipe-chat-button')));
    await tester.pumpAndSettle();

    expect(find.text('Koch-Chat zu "Kürbissuppe"'), findsOneWidget);
  });

  testWidgets('Timer-Button oeffnet den Koch-Timer mit dem Rezepttitel', (tester) async {
    await tester.pumpWidget(app(launchExternal: (_) async {}));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('recipe-timer-button')));
    await tester.pumpAndSettle();

    expect(find.text('Kochzeit: Kürbissuppe'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
