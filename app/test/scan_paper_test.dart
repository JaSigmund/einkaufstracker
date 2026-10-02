import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/cloud/cloud_receipt.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/domain/ocr/row_cluster.dart';
import 'package:einkaufstracker/domain/receipt/parsed_receipt.dart';
import 'package:einkaufstracker/features/receipt_import/import_review_page.dart';
import 'package:einkaufstracker/features/receipt_import/photo_receipt_service.dart';
import 'package:einkaufstracker/features/receipt_import/receipt_import_service.dart';
import 'package:einkaufstracker/features/receipt_import/scan_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';

class _FakeScanner implements ReceiptScanner {
  _FakeScanner(this.result, {this.fail = false});
  final List<ScannedPage>? result;
  final bool fail;

  @override
  Future<List<ScannedPage>?> scan() async {
    if (fail) throw StateError('Scanner nicht verfuegbar');
    return result;
  }
}

class _SlowScanner implements ReceiptScanner {
  final completer = Completer<List<ScannedPage>?>();

  @override
  Future<List<ScannedPage>?> scan() => completer.future;
}

class _NoCloud implements CloudReceiptReader {
  @override
  Future<ParsedReceipt> read(List<Uint8List> jpegs, {String storeHint = 'Billa'}) => throw const CloudUnavailable('kein Netz');
}

List<ScannedPage> _pages(String fixture) {
  final json = jsonDecode(File('test/fixtures/ocr/$fixture.json').readAsStringSync()) as Map<String, dynamic>;
  return [
    for (final page in json['pages'] as List)
      ScannedPage('p.jpg', [
        for (final l in page as List)
          OcrLine(l['text'] as String,
              Rect.fromLTRB((l['l'] as num).toDouble(), (l['t'] as num).toDouble(), (l['r'] as num).toDouble(), (l['b'] as num).toDouble())),
      ]),
  ];
}

void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  Widget app(ReceiptScanner scanner) => ProviderScope(
        overrides: [
          receiptScannerProvider.overrideWithValue(scanner),
          // Die Pruefansicht speichert ueber diesen Dienst
          receiptImportServiceProvider.overrideWithValue(ReceiptImportService(FakePdfReader(text: ''), receiptRepo(db))),
          photoReceiptServiceProvider.overrideWithValue(PhotoReceiptService(
            repo: receiptRepo(db),
            cloud: _NoCloud(),
            cloudAllowed: () async => false,
            prepare: (path, {cutY}) async => Uint8List(0),
          )),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(initialLocation: '/', routes: [
            GoRoute(path: '/', builder: (_, _) => const Scaffold(body: ScanPage())),
            GoRoute(path: '/import-review', builder: (_, state) => ImportReviewPage(preview: state.extra as ImportPreview)),
          ]),
        ),
      );

  testWidgets('Papierbon: Scan, lokale Erkennung, Pruefansicht mit Quelle, Speichern legt den Bon an', (tester) async {
    await tester.pumpWidget(app(_FakeScanner(_pages('billa_paper_02'))));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan-paper')));
    await tester.pumpAndSettle();
    expect(find.text('Bon prüfen'), findsOneWidget);
    expect(find.textContaining('Foto, lokal gelesen'), findsOneWidget);
    expect(find.text('Die Summe der Positionen entspricht der Bon-Summe.'), findsNothing); // Steuerblock ist gelesen
    expect(find.textContaining('Alles stimmig'), findsOneWidget);

    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final saved = await db.select(db.receipts).getSingle();
    expect(saved.source, 'on_device');
    expect(saved.totalCents, 2638);
  });

  testWidgets('Abbruch im Scanner: nichts passiert, keine Ladeanzeige', (tester) async {
    await tester.pumpWidget(app(_FakeScanner(null)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-paper')));
    await tester.pumpAndSettle();
    expect(find.text('Bon prüfen'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('Scanner-Fehler: Meldung, keine Ladeanzeige', (tester) async {
    await tester.pumpWidget(app(_FakeScanner(null, fail: true)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-paper')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Scan nicht möglich'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('Schlechter Scan ohne Cloud: Prüfansicht warnt und nennt den Grund', (tester) async {
    await tester.pumpWidget(app(_FakeScanner(_pages('billa_paper_01_scan3'))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-paper')));
    await tester.pumpAndSettle();
    expect(find.text('Bon prüfen'), findsOneWidget);
    expect(find.byKey(const Key('review-note')), findsOneWidget);
    expect(find.text('Trotzdem speichern'), findsOneWidget);
  });

  testWidgets('Ladekreis nur an "Papierbon fotografieren" (nicht am PDF-Import), dazu ein Statustext', (tester) async {
    final scanner = _SlowScanner();
    await tester.pumpWidget(app(scanner));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scan-status')), findsNothing);

    await tester.tap(find.byKey(const Key('scan-paper')));
    await tester.pump();

    expect(find.byKey(const Key('scan-status')), findsOneWidget);
    expect(find.textContaining('Scanner wird geöffnet'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('scan-paper')), matching: find.byType(CircularProgressIndicator)), findsOneWidget);
    final pdfCard = find.ancestor(of: find.text('Digitalen Bon importieren'), matching: find.byType(ListTile));
    expect(find.descendant(of: pdfCard, matching: find.byType(CircularProgressIndicator)), findsNothing);

    scanner.completer.complete(null); // Abbruch im Scanner
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scan-status')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
