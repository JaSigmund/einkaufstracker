import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/features/common/sync_status_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sync-Banner: was der Nutzer ueber den Stand der Uebertragung erfaehrt.
void main() {
  Widget host(SyncStatus status, {int pending = 0}) => ProviderScope(
        overrides: [
          syncControllerProvider.overrideWith(() => _FixedSync(status)),
          pendingChangesProvider.overrideWith((ref) => Stream.value(pending)),
        ],
        child: const MaterialApp(home: Scaffold(body: SyncStatusBanner())),
      );

  testWidgets('Codereview-Fund 2026-10-16: dauerhaft abgelehnte Aenderungen werden genannt, nicht nur "wartend"', (tester) async {
    await tester.pumpWidget(host(const SyncStatus(rejected: 2), pending: 5));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 Änderung(en) lehnt der Server ab'), findsOneWidget);
    expect(find.byIcon(Icons.report_problem_outlined), findsOneWidget);
  });

  testWidgets('ohne Ablehnungen bleibt es bei der Zahl wartender Aenderungen', (tester) async {
    await tester.pumpWidget(host(const SyncStatus(), pending: 3));
    await tester.pumpAndSettle();
    expect(find.textContaining('3 Änderung(en) warten'), findsOneWidget);
  });

  testWidgets('Codereview-Fund 2026-10-16: der Banner zeigt den verstaendlichen Text, nie das technische Detail', (tester) async {
    await tester.pumpWidget(host(const SyncStatus(error: 'Synchronisierung fehlgeschlagen.', errorDetail: 'Bad state: Spalte fehlt')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Synchronisierung fehlgeschlagen'), findsOneWidget);
    expect(find.textContaining('Bad state'), findsNothing);
  });
}

class _FixedSync extends SyncController {
  _FixedSync(this._status);
  final SyncStatus _status;

  @override
  SyncStatus build() => _status;

  @override
  Future<void> sync() async {}
}
