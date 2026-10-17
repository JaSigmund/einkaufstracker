import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/features/auth/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Widget _app(FakeAuth auth) => ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(auth)],
      child: const MaterialApp(home: LoginPage()),
    );

void main() {
  testWidgets('Leere Eingabe zeigt einen Hinweis und ruft die Anmeldung nicht auf', (tester) async {
    final auth = FakeAuth();
    await tester.pumpWidget(_app(auth));
    await tester.tap(find.text('Anmelden'));
    await tester.pump();
    expect(find.byKey(const Key('login-error')), findsOneWidget);
    expect(find.text('Bitte E-Mail und Passwort eingeben.'), findsOneWidget);
    expect(auth.signIns, isEmpty);
  });

  testWidgets('Falsche Zugangsdaten zeigen die Fehlermeldung der Anmeldung', (tester) async {
    final auth = FakeAuth(failWith: 'E-Mail oder Passwort stimmt nicht.');
    await tester.pumpWidget(_app(auth));
    await tester.enterText(find.byType(TextField).first, 'a@b.at');
    await tester.enterText(find.byType(TextField).last, 'falsch');
    await tester.tap(find.text('Anmelden'));
    await tester.pumpAndSettle();
    expect(find.text('E-Mail oder Passwort stimmt nicht.'), findsOneWidget);
    expect(auth.signIns.single.$1, 'a@b.at');
  });

  testWidgets('Passwort ist standardmaessig verborgen und laesst sich einblenden', (tester) async {
    await tester.pumpWidget(_app(FakeAuth()));
    expect(tester.widget<TextField>(find.byType(TextField).last).obscureText, isTrue);
    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField).last).obscureText, isFalse);
  });

  testWidgets('E-Mail und Passwort bilden eine Autofill-Gruppe, gespeichert wird erst nach gelungener Anmeldung', (tester) async {
    final auth = FakeAuth(failWith: 'E-Mail oder Passwort stimmt nicht.');
    await tester.pumpWidget(_app(auth));
    final fields = find.byType(TextField);
    for (final f in [fields.first, fields.last]) {
      expect(find.ancestor(of: f, matching: find.byType(AutofillGroup)), findsOneWidget);
    }
    expect(tester.widget<TextField>(fields.first).autofillHints, contains(AutofillHints.username));
    expect(tester.widget<TextField>(fields.last).autofillHints, [AutofillHints.password]);

    await tester.enterText(fields.first, 'a@b.at');
    await tester.enterText(fields.last, 'falsch');
    tester.testTextInput.log.clear();
    await tester.tap(find.text('Anmelden'));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.log.map((c) => c.method), isNot(contains('TextInput.finishAutofillContext')));

    auth.failWith = null;
    await tester.tap(find.text('Anmelden'));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.log.map((c) => c.method), contains('TextInput.finishAutofillContext'));
  });
}
