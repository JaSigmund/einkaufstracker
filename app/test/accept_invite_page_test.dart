import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/household/household_invites.dart';
import 'package:einkaufstracker/features/auth/login_page.dart';
import 'package:einkaufstracker/features/household/accept_invite_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';

/// Einladung annehmen (Phase 6, ADR-017 Option A): ohne Anmeldung erreichbar, legt das Konto an und meldet dann an.
void main() {
  late FakeAcceptInviteApi api;
  late FakeAuth auth;

  setUp(() {
    api = FakeAcceptInviteApi();
    auth = FakeAuth();
  });

  Widget host({FakeAuth? useAuth}) => ProviderScope(
        overrides: [
          acceptInviteApiProvider.overrideWithValue(api),
          authRepositoryProvider.overrideWithValue(useAuth ?? auth),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(initialLocation: '/accept', routes: [
            GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('HOME'))),
            GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
            GoRoute(path: '/accept', builder: (_, _) => const AcceptInvitePage()),
          ]),
        ),
      );

  Future<void> fill(WidgetTester tester, {String code = 'abcd-efgh-jkmn', String email = ' Neu@Test.at ', String password = 'ein-langes-passwort', String? repeat}) async {
    await tester.enterText(find.byKey(const Key('accept-code')), code);
    await tester.enterText(find.byKey(const Key('accept-email')), email);
    await tester.enterText(find.byKey(const Key('accept-password')), password);
    await tester.enterText(find.byKey(const Key('accept-repeat')), repeat ?? password);
    await tester.pump();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('accept-submit')));
    await tester.tap(find.byKey(const Key('accept-submit')));
    await tester.pumpAndSettle();
  }

  String? error(WidgetTester tester) {
    final f = find.byKey(const Key('accept-error'));
    return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
  }

  testWidgets('Erfolg: Code und Adresse werden normalisiert an den Server geschickt, danach wird angemeldet', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await fill(tester);
    await submit(tester);

    expect(api.calls.single, (code: 'ABCDEFGHJKMN', email: 'neu@test.at', password: 'ein-langes-passwort'));
    expect(auth.signIns.single, ('neu@test.at', 'ein-langes-passwort'));
    expect(error(tester), isNull);
  });

  group('Pruefung vor dem Senden: nichts geht ans Netz', () {
    for (final (name, args, expected) in <(String, Map<String, String>, String)>[
      ('Code zu kurz', {'code': 'ABCD'}, 'Der Code hat 12 Zeichen'),
      ('Code mit verwechselbarem Zeichen', {'code': 'ABCD-EFGH-JKM0'}, 'Der Code hat 12 Zeichen'),
      ('Adresse ungueltig', {'email': 'keine-adresse'}, 'E-Mail-Adresse eingeben'),
      ('Passwort zu kurz', {'password': 'kurz'}, 'mindestens 10 Zeichen'),
      ('Passwoerter verschieden', {'repeat': 'ein-anderes-passwort'}, 'nicht gleich'),
    ]) {
      testWidgets(name, (tester) async {
        await tester.pumpWidget(host());
        await tester.pumpAndSettle();
        await fill(tester, code: args['code'] ?? 'ABCD-EFGH-JKMN', email: args['email'] ?? 'neu@test.at', password: args['password'] ?? 'ein-langes-passwort', repeat: args['repeat']);
        await submit(tester);
        expect(error(tester), contains(expected));
        expect(api.calls, isEmpty);
        expect(auth.signIns, isEmpty);
      });
    }
  });

  group('Fehler des Servers', () {
    for (final (message) in [
      'Die Einladung wurde nicht gefunden oder die E-Mail-Adresse passt nicht dazu.',
      'Die Einladung ist abgelaufen. Bitte eine neue anfordern.',
      'Zu dieser E-Mail-Adresse gibt es schon ein Konto. Melde dich damit an.',
    ]) {
      testWidgets(message, (tester) async {
        api.error = InviteFailure(message);
        await tester.pumpWidget(host());
        await tester.pumpAndSettle();
        await fill(tester);
        await submit(tester);
        expect(error(tester), message);
        expect(auth.signIns, isEmpty, reason: 'ohne Konto keine Anmeldung');
      });
    }

    testWidgets('nach einem Fehler kann man es korrigieren und erneut versuchen', (tester) async {
      api.error = const InviteFailure('Die Einladung ist abgelaufen. Bitte eine neue anfordern.');
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await fill(tester);
      await submit(tester);
      expect(error(tester), isNotNull);

      api.error = null;
      await submit(tester);
      expect(error(tester), isNull);
      expect(auth.signIns, hasLength(1));
      expect(api.calls, hasLength(2));
    });
  });

  testWidgets('Konto angelegt, aber Anmeldung scheitert (z.B. Netz weg): Hinweis und weiter zur normalen Anmeldung', (tester) async {
    final failing = FakeAuth(failWith: 'Kein Netz.');
    await tester.pumpWidget(host(useAuth: failing));
    await tester.pumpAndSettle();
    await fill(tester);
    await submit(tester);

    expect(api.calls, hasLength(1), reason: 'das Konto ist angelegt');
    expect(find.text('Du bist dem Haushalt beigetreten. Bitte melde dich jetzt an.'), findsOneWidget);
    expect(find.byKey(const Key('login-accept-invite')), findsOneWidget, reason: 'Login-Seite');
  });

  testWidgets('Passwort ist standardmaessig verborgen und laesst sich einblenden (beide Felder)', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('accept-password'))).obscureText, isTrue);
    expect(tester.widget<TextField>(find.byKey(const Key('accept-repeat'))).obscureText, isTrue);
    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(const Key('accept-password'))).obscureText, isFalse);
    expect(tester.widget<TextField>(find.byKey(const Key('accept-repeat'))).obscureText, isFalse);
  });

  testWidgets('von der Anmeldung aus erreichbar ("Einladung annehmen")', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [acceptInviteApiProvider.overrideWithValue(api), authRepositoryProvider.overrideWithValue(auth)],
      child: MaterialApp.router(
        routerConfig: GoRouter(initialLocation: '/login', routes: [
          GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
          GoRoute(path: '/accept-invite', builder: (_, _) => const AcceptInvitePage()),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('login-accept-invite')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('accept-code')), findsOneWidget);
  });
}
