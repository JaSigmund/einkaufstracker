import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/changelog/changelog_repository.dart';
import 'package:einkaufstracker/features/changelog/changelog_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('zeigt Version, Titel, Datum und Stichpunkte, neueste zuerst', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        changelogProvider.overrideWith((ref) async => [
              ChangelogEntry(version: '1.1.0', title: 'Fehlerverfolgung', highlights: const ['Status je Bericht', 'Changelog'], releasedAt: DateTime.utc(2026, 9, 28)),
              ChangelogEntry(version: '1.0.0', title: 'Start', highlights: const ['Bon-Import'], releasedAt: DateTime.utc(2026, 9, 1)),
            ]),
      ],
      child: const MaterialApp(home: ChangelogPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('1.1.0'), findsOneWidget);
    expect(find.text('Fehlerverfolgung'), findsOneWidget);
    expect(find.text('Status je Bericht'), findsOneWidget);
    expect(find.text('1.0.0'), findsOneWidget);

    final titles = tester.widgetList<Text>(find.textContaining(RegExp('Fehlerverfolgung|Start'))).map((t) => t.data).toList();
    expect(titles.indexOf('Fehlerverfolgung'), lessThan(titles.indexOf('Start'))); // neueste zuerst
  });

  testWidgets('leer: Hinweistext', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [changelogProvider.overrideWith((ref) async => const [])],
      child: const MaterialApp(home: ChangelogPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('changelog-empty')), findsOneWidget);
  });

  testWidgets('ohne Netz: verstaendliche Meldung statt Absturz', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [changelogProvider.overrideWith((ref) async => Future<List<ChangelogEntry>>.error('kein Netz'))],
      child: const MaterialApp(home: ChangelogPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('changelog-error')), findsOneWidget);
  });
}
