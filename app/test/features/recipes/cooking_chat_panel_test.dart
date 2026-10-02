import 'package:einkaufstracker/domain/app_update/app_update_gate.dart';
import 'package:einkaufstracker/features/recipes/cooking_chat_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app({required CookingChatSend sendMessage}) => MaterialApp(
        home: Scaffold(
          body: CookingChatPanel(
            chatContext: const CookingChatContext(recipeTitle: 'Kürbissuppe', ingredients: ['Kürbis', 'Zwiebel']),
            sendMessage: sendMessage,
          ),
        ),
      );

  testWidgets('zeigt den Rezepttitel im Panel-Titel', (tester) async {
    await tester.pumpWidget(app(sendMessage: (_, _) async => 'Antwort'));
    expect(find.text('Koch-Chat zu "Kürbissuppe"'), findsOneWidget);
  });

  testWidgets('Nachricht senden: eigene Nachricht und Antwort erscheinen, Kontext wird automatisch mitgeschickt', (tester) async {
    String? receivedMessage;
    CookingChatContext? receivedContext;
    await tester.pumpWidget(app(sendMessage: (msg, ctx) async {
      receivedMessage = msg;
      receivedContext = ctx;
      return 'Du kannst Sahne durch Milch ersetzen.';
    }));

    await tester.enterText(find.byKey(const Key('chat-input')), 'Kann ich Sahne weglassen?');
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pumpAndSettle();

    expect(receivedMessage, 'Kann ich Sahne weglassen?');
    expect(receivedContext!.recipeTitle, 'Kürbissuppe');
    expect(receivedContext!.ingredients, ['Kürbis', 'Zwiebel']);
    expect(find.text('Kann ich Sahne weglassen?'), findsOneWidget);
    expect(find.text('Du kannst Sahne durch Milch ersetzen.'), findsOneWidget);
  });

  testWidgets('Enter im Textfeld sendet ebenfalls', (tester) async {
    var calls = 0;
    await tester.pumpWidget(app(sendMessage: (_, _) async {
      calls++;
      return 'ok';
    }));

    await tester.enterText(find.byKey(const Key('chat-input')), 'Frage');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(calls, 1);
  });

  testWidgets('leere Nachricht wird nicht gesendet', (tester) async {
    var calls = 0;
    await tester.pumpWidget(app(sendMessage: (_, _) async {
      calls++;
      return 'ok';
    }));

    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(find.byKey(const Key('chat-messages')), findsOneWidget);
  });

  testWidgets('Fehler beim Senden: Fehlermeldung statt Absturz', (tester) async {
    await tester.pumpWidget(app(sendMessage: (_, _) async => throw UnimplementedError('noch nicht angebunden')));

    await tester.enterText(find.byKey(const Key('chat-input')), 'Hallo?');
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat-error')), findsOneWidget);
  });

  testWidgets('Update-Sperre (ADR-022): Hinweis auf das Update, ohne "konnte nicht gesendet werden"', (tester) async {
    await tester.pumpWidget(app(sendMessage: (_, _) async => throw const AppUpdateRequiredException()));

    await tester.enterText(find.byKey(const Key('chat-input')), 'Hallo?');
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.byKey(const Key('chat-error'))).data, const AppUpdateRequiredException().toString());
  });

  testWidgets('zweite Nachricht schickt die erste Runde als Verlauf mit (Q-22)', (tester) async {
    final contexts = <CookingChatContext>[];
    await tester.pumpWidget(app(sendMessage: (_, ctx) async {
      contexts.add(ctx);
      return 'Antwort ${contexts.length}';
    }));

    await tester.enterText(find.byKey(const Key('chat-input')), 'Erste Frage');
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('chat-input')), 'Zweite Frage');
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pumpAndSettle();

    expect(contexts, hasLength(2));
    expect(contexts[0].history, isEmpty); // erste Nachricht: noch kein Verlauf
    expect(contexts[1].history.map((m) => (m.text, m.fromUser)), [
      ('Erste Frage', true),
      ('Antwort 1', false),
    ]);
  });
}
