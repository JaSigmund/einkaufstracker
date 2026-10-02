import 'dart:io';
import 'dart:typed_data';

import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/core/format.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/pdf/pdf_text_reader.dart';
import 'package:einkaufstracker/domain/receipt/parsed_receipt.dart';
import 'package:einkaufstracker/domain/receipt/vienna_time.dart';
import 'package:einkaufstracker/features/receipt_import/import_review_page.dart';
import 'package:einkaufstracker/features/receipt_import/receipt_import_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';

String _fixture(String name) => File('test/fixtures/receipts/$name.txt').readAsStringSync();
final _bytes = Uint8List.fromList([1, 2, 3]);

void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  ReceiptImportService service({String? text, PdfReadException? error}) =>
      ReceiptImportService(FakePdfReader(text: text, error: error), receiptRepo(db));

  group('Import-Dienst', () {
    test('Gueltiger Bon: Vorschau ist importierbar und vertrauenswuerdig', () async {
      final p = await service(text: _fixture('billa_digital_04')).preview(_bytes);
      expect(p.error, isNull);
      expect(p.canImport, isTrue);
      expect(p.isDuplicate, isFalse);
      expect(p.receipt.isTrustworthy, isTrue);
      expect(p.receipt.items.length, 10);
    });

    test('Speichern legt den Bon an; derselbe Bon danach ist ein Duplikat', () async {
      final s = service(text: _fixture('billa_digital_04'));
      final first = await s.preview(_bytes);
      await s.save(first);
      expect((await db.select(db.receipts).get()).length, 1);

      final again = await s.preview(_bytes);
      expect(again.isDuplicate, isTrue);
      expect(again.canImport, isFalse);
      expect(() => s.save(again), throwsStateError);
      expect((await db.select(db.receipts).get()).length, 1);
    });

    test('Codereview-Fund 2026-10-01: Duplikat-Fehlalarm (zwei echte, zufaellig gleich teure Foto-Einkaeufe ohne Re-Nr) laesst sich per Bearbeiten (Uhrzeit korrigieren) aufloesen', () async {
      final s = service();
      final purchasedAt = DateTime.utc(2026, 10, 1, 18, 0);
      // Fotobons haben keine Re-Nr (externalId): findDuplicate erkennt sie nur ueber Summe + Uhrzeit auf
      // 2 Minuten genau -- genau das Szenario aus dem Codereview-Fund, anders als bei einem digitalen
      // PDF-Bon mit Re-Nr (dort greift die externalId-Pruefung zuerst und bleibt davon unberuehrt).
      ParsedReceipt coffeeAt(DateTime t) =>
          ParsedReceipt.edited(base: null, items: const [], bonDiscounts: const [], totalCents: 299, purchasedAtUtc: t);

      final first = ImportPreview(receipt: coffeeAt(purchasedAt), source: ReceiptSources.photoLocal);
      await s.save(first);

      // Zweiter, echter Einkauf eine Minute spaeter: gleiche Summe, faellt ins 2-Minuten-Fenster -> Fehlalarm.
      final secondReceipt = coffeeAt(purchasedAt.add(const Duration(minutes: 1)));
      final second = ImportPreview(receipt: secondReceipt, duplicateOfReceiptId: (await s.recheckDuplicate(ImportPreview(receipt: secondReceipt))).duplicateOfReceiptId, source: ReceiptSources.photoLocal);
      expect(second.isDuplicate, isTrue);

      // Genau das macht der "Bearbeiten"-Weg in ImportReviewPage._edit(): Uhrzeit um mehr als 2 Minuten
      // verschieben, dann erneut pruefen.
      final nudged = coffeeAt(purchasedAt.add(const Duration(minutes: 11)));
      final rechecked = await s.recheckDuplicate(ImportPreview(receipt: nudged, source: second.source));
      expect(rechecked.isDuplicate, isFalse);
      expect(rechecked.canImport, isTrue);

      await s.save(rechecked);
      expect((await db.select(db.receipts).get()).length, 2);
    });

    test('Kein lesbares PDF: Fehlermeldung statt Absturz', () async {
      final p = await service(error: PdfReadException('Die Datei konnte nicht als PDF gelesen werden.')).preview(_bytes);
      expect(p.error, contains('PDF'));
      expect(p.canImport, isFalse);
    });

    test('Text ohne Bon-Format: Fehlermeldung', () async {
      final p = await service(text: 'Das ist irgendein anderes Dokument.').preview(_bytes);
      expect(p.error, isNotNull);
      expect(p.error, contains('kein Billa-Bon'));
      expect(p.canImport, isFalse);
    });

    test('Bon mit fehlender Zeile ist importierbar, aber nicht vertrauenswuerdig', () async {
      final lines = _fixture('billa_digital_04').split('\n')..removeWhere((l) => l.contains('Clever Champignon'));
      final p = await service(text: lines.join('\n')).preview(_bytes);
      expect(p.canImport, isTrue);
      expect(p.receipt.isTrustworthy, isFalse);
    });
  });

  group('Formatierung', () {
    test('Euro mit Komma und Tausenderpunkt, negative Betraege', () {
      expect(formatEuro(0), '0,00 €');
      expect(formatEuro(5), '0,05 €');
      expect(formatEuro(2900), '29,00 €');
      expect(formatEuro(-86), '-0,86 €');
      expect(formatEuro(123456), '1.234,56 €');
      expect(formatEuro(100000000), '1.000.000,00 €');
    });

    test('Menge ohne unnoetige Nachkommastellen, mit Komma', () {
      expect(formatQuantity(2), '2');
      expect(formatQuantity(0.986), '0,986');
    });

    test('Anzeige in Wiener Ortszeit', () {
      expect(formatViennaDateTime(DateTime.utc(2026, 7, 2, 17, 51)), '02.07.2026, 19:51 Uhr'); // Sommerzeit
      expect(formatViennaDateTime(DateTime.utc(2026, 1, 15, 11, 0)), '15.01.2026, 12:00 Uhr'); // Winterzeit
    });

    test('utcToViennaLocal ist die Umkehrung von viennaLocalToUtc', () {
      for (final d in [DateTime(2026, 1, 15, 12, 0), DateTime(2026, 7, 2, 19, 51), DateTime(2026, 3, 29, 3, 30), DateTime(2026, 10, 25, 12, 0)]) {
        expect(utcToViennaLocal(viennaLocalToUtc(d.year, d.month, d.day, d.hour, d.minute)), d);
      }
    });
  });

  group('Pruefansicht', () {
    Future<ImportPreview> previewOf(String text) => service(text: text).preview(_bytes);

    Widget host(ImportPreview preview) => ProviderScope(
          overrides: [receiptImportServiceProvider.overrideWithValue(service(text: ''))],
          child: MaterialApp.router(
            routerConfig: GoRouter(initialLocation: '/import-review', routes: [
              GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('STARTSEITE'))),
              GoRoute(path: '/import-review', builder: (_, _) => ImportReviewPage(preview: preview)),
            ]),
          ),
        );

    testWidgets('Guter Bon: gruenes Ergebnis, Positionen sichtbar, Speichern legt ihn an und geht zur Startseite', (tester) async {
      final preview = await previewOf(_fixture('billa_digital_04'));
      // Dienst mit demselben Repo, damit die Speicherung in der Test-Datenbank landet
      await tester.pumpWidget(ProviderScope(
        overrides: [receiptImportServiceProvider.overrideWithValue(service(text: _fixture('billa_digital_04')))],
        child: MaterialApp.router(
          routerConfig: GoRouter(initialLocation: '/import-review', routes: [
            GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('STARTSEITE'))),
            GoRoute(path: '/import-review', builder: (_, _) => ImportReviewPage(preview: preview)),
          ]),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Alles stimmig: Die Summe der Positionen entspricht der Bon-Summe, und der Steuerblock geht auf.'), findsOneWidget);
      expect(find.text('Billa, Filiale 0643'), findsOneWidget);
      expect(find.text('02.07.2026, 19:51 Uhr · Digitaler Bon (PDF)'), findsOneWidget);
      expect(find.text('Clever Champignon weiß'), findsOneWidget);
      expect(find.text('Speichern'), findsOneWidget);

      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(find.text('STARTSEITE'), findsOneWidget);
      expect((await db.select(db.receipts).get()).length, 1);
    });

    testWidgets('Bon mit Abweichung: rote Meldung mit Differenz, Speichern nur nach Rueckfrage', (tester) async {
      final lines = _fixture('billa_digital_04').split('\n')..removeWhere((l) => l.contains('Clever Champignon'));
      final preview = await previewOf(lines.join('\n'));
      await tester.pumpWidget(host(preview));
      await tester.pumpAndSettle();

      final text = tester.widget<Text>(find.byKey(const Key('check-text'))).data!;
      expect(text, contains('1,89 €')); // Differenz
      expect(text, contains('Steuerklasse H'));
      expect(find.text('Trotzdem speichern'), findsOneWidget);

      await tester.tap(find.text('Trotzdem speichern'));
      await tester.pumpAndSettle();
      expect(find.text('Trotzdem speichern?'), findsOneWidget); // Rueckfrage
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect((await db.select(db.receipts).get()), isEmpty); // nichts gespeichert
    });

    testWidgets('Duplikat: Hinweis, keine Speichern-Schaltflaeche, aber Bearbeiten moeglich (Codereview-Fund 2026-10-01)', (tester) async {
      final s = service(text: _fixture('billa_digital_04'));
      await s.save(await s.preview(_bytes));
      final again = await s.preview(_bytes);
      await tester.pumpWidget(host(again));
      await tester.pumpAndSettle();
      expect(find.text('Dieser Bon ist schon gespeichert'), findsOneWidget);
      expect(find.text('Speichern'), findsNothing);
      // Ohne diesen Weg war ein zweiter, echter (nur zufaellig gleich teurer) Einkauf gar nicht speicherbar.
      expect(find.byKey(const Key('review-edit')), findsOneWidget);
      expect(find.byKey(const Key('review-duplicate-edit')), findsOneWidget);
    });

    testWidgets('Lesefehler: verstaendliche Meldung, keine Speichern-Schaltflaeche', (tester) async {
      final preview = await service(error: PdfReadException('Im PDF wurde kein Text gefunden.')).preview(_bytes);
      await tester.pumpWidget(host(preview));
      await tester.pumpAndSettle();
      expect(find.text('Der Bon konnte nicht gelesen werden'), findsOneWidget);
      expect(find.text('Im PDF wurde kein Text gefunden.'), findsOneWidget);
      expect(find.text('Speichern'), findsNothing);
    });
  });
}
