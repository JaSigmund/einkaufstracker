import 'dart:io';
import 'dart:typed_data';

import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/features/receipt_import/import_review_page.dart';
import 'package:einkaufstracker/features/receipt_import/receipt_import_service.dart';
import 'package:einkaufstracker/features/receipt_import/scan_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  Widget app({required Future<Uint8List?> Function() pick, required String text}) => ProviderScope(
        overrides: [
          receiptImportServiceProvider.overrideWithValue(ReceiptImportService(FakePdfReader(text: text), receiptRepo(db))),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(initialLocation: '/', routes: [
            GoRoute(path: '/', builder: (_, _) => Scaffold(body: ScanPage(pickPdf: pick))),
            GoRoute(
              path: '/import-review',
              builder: (_, state) => ImportReviewPage(preview: state.extra as ImportPreview),
            ),
          ]),
        ),
      );

  final text = File('test/fixtures/receipts/billa_digital_04.txt').readAsStringSync();

  testWidgets('Nach dem Speichern eines Bons laeuft KEINE Ladeanzeige mehr (Regression: Anzeige blieb haengen)', (tester) async {
    await tester.pumpWidget(app(pick: () async => Uint8List.fromList([1]), text: text));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Digitalen Bon importieren'));
    await tester.pumpAndSettle();
    expect(find.text('Bon prüfen'), findsOneWidget);

    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    // zurueck auf der Scan-Seite: keine Ladeanzeige, Import sofort wieder moeglich
    expect(find.text('Digitalen Bon importieren'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect((await db.select(db.receipts).get()).length, 1);
  });

  testWidgets('Nach Verwerfen (Zurueck) ist ebenfalls keine Ladeanzeige mehr da', (tester) async {
    await tester.pumpWidget(app(pick: () async => Uint8List.fromList([1]), text: text));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Digitalen Bon importieren'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verwerfen'));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect((await db.select(db.receipts).get()), isEmpty);
  });

  testWidgets('Abbruch der Dateiauswahl: nichts passiert, keine Ladeanzeige', (tester) async {
    await tester.pumpWidget(app(pick: () async => null, text: text));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Digitalen Bon importieren'));
    await tester.pumpAndSettle();
    expect(find.text('Bon prüfen'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('Fehler beim Auswaehlen: Meldung, keine Ladeanzeige', (tester) async {
    await tester.pumpWidget(app(pick: () async => throw Exception('kein Zugriff'), text: text));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Digitalen Bon importieren'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Import nicht möglich'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
