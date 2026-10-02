import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/household/household_invites.dart';
import 'package:einkaufstracker/features/household/household_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Haushalt-Seite (Phase 6, ADR-017 Option A): Mitglieder, Person einladen, offene Einladungen verwalten.
HouseholdInvite _invite(String id, String email, {String token = 'ABCDEFGHJKMN', int days = 5}) => HouseholdInvite(
      id: id,
      email: email,
      token: token,
      expiresAt: DateTime.utc(2026, 10, 2, 12).add(Duration(days: days)),
      createdAt: DateTime.utc(2026, 10, 1),
    );

void main() {
  final now = DateTime.utc(2026, 10, 2, 12);
  late FakeHouseholdInviteRepository repo;
  late List<String> shared;

  setUp(() {
    repo = FakeHouseholdInviteRepository();
    shared = [];
  });

  Widget host() => ProviderScope(
        overrides: [
          householdInviteRepositoryProvider.overrideWithValue(repo),
          shareTextProvider.overrideWithValue((text) async => shared.add(text)),
        ],
        child: MaterialApp(home: HouseholdPage(now: now)),
      );

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
  }

  Future<void> invite(WidgetTester tester, String email) async {
    await tester.tap(find.byKey(const Key('household-invite')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('invite-email')), email);
    await tester.tap(find.byKey(const Key('invite-create')));
    await tester.pumpAndSettle();
  }

  testWidgets('allein im Haushalt: "Nur du", keine offenen Einladungen', (tester) async {
    await open(tester);
    expect(tester.widget<Text>(find.byKey(const Key('household-members'))).data, 'Nur du');
    expect(find.byKey(const Key('household-no-invites')), findsOneWidget);
  });

  testWidgets('mehrere Mitglieder werden gezaehlt', (tester) async {
    repo.members = 3;
    await open(tester);
    expect(tester.widget<Text>(find.byKey(const Key('household-members'))).data, '3 Personen');
  });

  testWidgets('offene Einladungen mit Code und Ablauf, abgelaufene als solche gekennzeichnet', (tester) async {
    repo.invites.addAll([_invite('a', 'anna@test.at'), _invite('b', 'bert@test.at', token: 'KMNPQRSTUVWX', days: -2)]);
    await open(tester);
    expect(find.text('anna@test.at'), findsOneWidget);
    expect(find.text('Code ABCD-EFGH-JKMN · gültig bis 7.10.2026'), findsOneWidget);
    expect(find.text('Abgelaufen am 30.9.2026'), findsOneWidget);
    expect(find.textContaining('KMNP-QRST-UVWX'), findsNothing, reason: 'der Code einer abgelaufenen Einladung wird nicht mehr gezeigt');
  });

  testWidgets('Einladen: ungueltige Adresse wird im Dialog gemeldet, nichts wird angelegt', (tester) async {
    await open(tester);
    await invite(tester, 'keine-adresse');
    expect(find.text('Bitte eine gültige E-Mail-Adresse eingeben.'), findsOneWidget);
    expect(repo.created, isEmpty);
  });

  testWidgets('Einladen: Adresse wird normalisiert, Code erscheint im Dreiergruppen-Format', (tester) async {
    await open(tester);
    await invite(tester, '  Neu@Test.AT ');
    expect(repo.created, ['neu@test.at']);
    expect(find.text('Einladung bereit'), findsOneWidget);
    expect(tester.widget<SelectableText>(find.byKey(const Key('invite-code'))).data, matches(RegExp(r'^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$')));
    expect(find.textContaining('neu@test.at'), findsWidgets);
  });

  testWidgets('nach dem Einladen steht die Einladung in der Liste', (tester) async {
    await open(tester);
    await invite(tester, 'neu@test.at');
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('household-no-invites')), findsNothing);
    expect(find.text('neu@test.at'), findsOneWidget);
  });

  testWidgets('Teilen gibt den Einladungstext mit Code weiter', (tester) async {
    await open(tester);
    await invite(tester, 'neu@test.at');
    await tester.tap(find.byKey(const Key('invite-share')));
    await tester.pumpAndSettle();
    expect(shared, hasLength(1));
    expect(shared.single, contains('Einladung annehmen'));
    expect(shared.single, matches(RegExp(r'[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}')));
  });

  testWidgets('Kopieren legt den Einladungstext in die Zwischenablage', (tester) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await open(tester);
    await invite(tester, 'neu@test.at');
    await tester.tap(find.byKey(const Key('invite-copy')));
    await tester.pumpAndSettle();
    expect(clipboard, contains('Einladung annehmen'));
    expect(find.text('Einladungstext kopiert.'), findsOneWidget);
  });

  testWidgets('Fehler beim Einladen (z.B. schon offen) erscheint als Meldung', (tester) async {
    await open(tester);
    repo.failWith = const InviteFailure('Für diese Adresse gibt es schon eine offene Einladung.');
    await invite(tester, 'neu@test.at');
    expect(find.text('Für diese Adresse gibt es schon eine offene Einladung.'), findsOneWidget);
  });

  testWidgets('Zurueckziehen mit Rueckfrage entfernt die Einladung', (tester) async {
    repo.invites.add(_invite('a', 'anna@test.at'));
    await open(tester);
    await tester.tap(find.byKey(const Key('invite-menu-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zurückziehen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('funktioniert danach nicht mehr'), findsOneWidget);
    await tester.tap(find.byKey(const Key('invite-revoke-confirm')));
    await tester.pumpAndSettle();
    expect(repo.revoked, ['a']);
    expect(find.text('anna@test.at'), findsNothing);
    expect(find.byKey(const Key('household-no-invites')), findsOneWidget);
  });

  testWidgets('Zurueckziehen abbrechen laesst die Einladung stehen', (tester) async {
    repo.invites.add(_invite('a', 'anna@test.at'));
    await open(tester);
    await tester.tap(find.byKey(const Key('invite-menu-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zurückziehen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(repo.revoked, isEmpty);
    expect(find.text('anna@test.at'), findsOneWidget);
  });

  testWidgets('abgelaufene Einladung: kein "Code anzeigen", aber Zurueckziehen moeglich', (tester) async {
    repo.invites.add(_invite('b', 'bert@test.at', days: -2));
    await open(tester);
    await tester.tap(find.byKey(const Key('invite-menu-b')));
    await tester.pumpAndSettle();
    expect(find.text('Code anzeigen und teilen'), findsNothing);
    expect(find.text('Zurückziehen'), findsOneWidget);
  });

  testWidgets('"Code anzeigen" zeigt den Code einer offenen Einladung erneut', (tester) async {
    repo.invites.add(_invite('a', 'anna@test.at'));
    await open(tester);
    await tester.tap(find.byKey(const Key('invite-menu-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Code anzeigen und teilen'));
    await tester.pumpAndSettle();
    expect(tester.widget<SelectableText>(find.byKey(const Key('invite-code'))).data, 'ABCD-EFGH-JKMN');
  });

  testWidgets('ohne Netz: Fehlermeldung statt endloser Ladeanzeige', (tester) async {
    repo.failWith = const InviteFailure('Kein Netz. Einladungen brauchen eine Verbindung.');
    await open(tester);
    expect(tester.widget<Text>(find.byKey(const Key('household-invites-error'))).data, contains('Kein Netz'));
    expect(tester.widget<Text>(find.byKey(const Key('household-members'))).data, 'nicht verfügbar');
  });
}
