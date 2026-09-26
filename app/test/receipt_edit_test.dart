import 'dart:io';

import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/core/format.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/domain/receipt/billa_text_parser.dart';
import 'package:einkaufstracker/domain/receipt/parsed_receipt.dart';
import 'package:einkaufstracker/features/receipt_import/import_review_page.dart';
import 'package:einkaufstracker/features/receipt_import/receipt_edit_page.dart';
import 'package:einkaufstracker/features/receipt_import/receipt_import_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';

ParsedReceipt _parse(String name) => const BillaTextParser().parse(File('test/fixtures/receipts/$name.txt').readAsStringSync());

void main() {
  group('parseEuroCents', () {
    final cases = <String, int?>{
      '2,49': 249,
      '2.49': 249,
      '2,5': 250,
      '3': 300,
      '-0,86': -86,
      '-0.86': -86,
      '1.234,56': 123456,
      '1.234,56 €': 123456,
      ' 12 ': 1200,
      '': null,
      'abc': null,
      '2,499': null,
      '2,4,9': null,
    };
    cases.forEach((input, expected) => test('"$input" -> $expected', () => expect(parseEuroCents(input), expected)));
  });

  group('ParsedReceipt.edited', () {
    test('Pruefungen werden neu gerechnet: Positionen plus Bon-Rabatte gegen die Summe', () {
      final base = _parse('billa_digital_03');
      final edited = ParsedReceipt.edited(
        base: base,
        items: base.items.take(2).toList(),
        bonDiscounts: const [],
        totalCents: base.items.take(2).fold<int>(0, (s, i) => s + i.lineTotalCents),
        purchasedAtUtc: base.purchasedAtUtc!,
      );
      expect(edited.isTrustworthy, isTrue);
      expect(edited.externalId, base.externalId); // Re-Nr bleibt
      expect(edited.branchCode, base.branchCode);

      final wrong = ParsedReceipt.edited(base: base, items: base.items.take(2).toList(), bonDiscounts: const [], totalCents: 1, purchasedAtUtc: base.purchasedAtUtc!);
      expect(wrong.isTrustworthy, isFalse);
    });

    test('manual: leerer Bon ist gueltig, aber nicht stimmig, solange nichts erfasst ist', () {
      final m = ParsedReceipt.manual(purchasedAtUtc: DateTime.utc(2026, 9, 27));
      expect(m.isParsed, isTrue);
      expect(m.items, isEmpty);
    });
  });

  group('Editor', () {
    late AppDatabase db;
    setUp(() => db = memoryDb());
    tearDown(() => db.close());

    Widget app(ImportPreview preview) => ProviderScope(
          overrides: [
            receiptImportServiceProvider.overrideWithValue(ReceiptImportService(FakePdfReader(text: ''), receiptRepo(db))),
          ],
          child: MaterialApp.router(
            routerConfig: GoRouter(initialLocation: '/', routes: [
              GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('START'))),
              GoRoute(path: '/import-review', builder: (_, s) => ImportReviewPage(preview: s.extra as ImportPreview)),
              GoRoute(path: '/import-edit', builder: (_, s) => ReceiptEditPage(preview: s.extra as ImportPreview)),
            ]),
          ),
        );

    Future<void> openReview(WidgetTester tester, ImportPreview preview) async {
      await tester.pumpWidget(app(preview));
      await tester.pumpAndSettle();
      GoRouter.of(tester.element(find.text('START'))).push('/import-review', extra: preview);
      await tester.pumpAndSettle();
    }

    testWidgets('Betrag einer Position korrigieren: Summe wird neu geprueft, gespeichert wird die Korrektur', (tester) async {
      // Bon, bei dem der Preis einer Position falsch gelesen wurde (Cloud liest 3,89 als 3,39)
      final base = _parse('billa_digital_04');
      final wrongItems = [
        for (final i in base.items)
          if (i.rawText == 'Farmer Soft Sandwich')
            ParsedItem(rawText: i.rawText, kind: i.kind, lineTotalCents: i.lineTotalCents - 50, taxCode: i.taxCode)
          else
            i,
      ];
      final wrong = ParsedReceipt.edited(base: base, items: wrongItems, bonDiscounts: base.bonDiscounts, totalCents: base.totalCents!, purchasedAtUtc: base.purchasedAtUtc!);
      expect(wrong.isTrustworthy, isFalse);

      await openReview(tester, ImportPreview(receipt: wrong, source: ReceiptSources.photoCloud));
      expect(find.text('Trotzdem speichern'), findsOneWidget);

      await tester.tap(find.byKey(const Key('review-edit')));
      await tester.pumpAndSettle();
      expect(find.text('Bon bearbeiten'), findsOneWidget);
      expect(find.textContaining('Differenz 0,50 €'), findsOneWidget);

      await tester.tap(find.text('Farmer Soft Sandwich'));
      await tester.pumpAndSettle();
      final original = base.items.firstWhere((i) => i.rawText == 'Farmer Soft Sandwich').lineTotalCents;
      await tester.enterText(find.byKey(const Key('line-amount')), formatEuro(original).replaceAll(' €', ''));
      await tester.tap(find.byKey(const Key('line-ok')));
      await tester.pumpAndSettle();
      expect(find.textContaining('das entspricht der Summe'), findsOneWidget);

      await tester.tap(find.byKey(const Key('edit-apply')));
      await tester.pumpAndSettle();
      expect(find.textContaining('von dir bearbeitet'), findsOneWidget);
      expect(find.text('Speichern'), findsOneWidget); // jetzt stimmig, keine Rueckfrage mehr

      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      final saved = await db.select(db.receipts).getSingle();
      expect(saved.sumMismatch, isFalse);
      expect(saved.source, 'llm');
      final items = await db.select(db.receiptItems).get();
      expect(items.fold<int>(0, (s, i) => s + i.lineTotalCents), base.totalCents);
    });

    testWidgets('Position loeschen (Wischen) und hinzufuegen, Rabatt wird immer negativ', (tester) async {
      final base = _parse('billa_digital_04');
      await openReview(tester, ImportPreview(receipt: base));
      await tester.tap(find.byKey(const Key('review-edit')));
      await tester.pumpAndSettle();

      final before = base.items.length;
      await tester.drag(find.byKey(const Key('line-0')), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.textContaining('Differenz'), findsOneWidget); // Summe passt nicht mehr

      await tester.tap(find.byKey(const Key('add-line')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('line-name')), 'Aktion Test');
      await tester.enterText(find.byKey(const Key('line-amount')), '1,00'); // positiv eingegeben
      await tester.tap(find.byKey(const Key('line-kind')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rabatt auf einen Artikel').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('line-ok')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Aktion Test'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Aktion Test'), findsOneWidget);
      expect(find.text('-1,00 €'), findsWidgets);
      expect(before, greaterThan(1));
    });

    testWidgets('Ungueltige Eingaben werden im Dialog abgelehnt', (tester) async {
      await openReview(tester, ImportPreview(receipt: _parse('billa_digital_04')));
      await tester.tap(find.byKey(const Key('review-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-line')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('line-ok')));
      await tester.pumpAndSettle();
      expect(find.text('Bitte einen Namen eingeben.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('line-name')), 'X');
      await tester.enterText(find.byKey(const Key('line-amount')), 'abc');
      await tester.tap(find.byKey(const Key('line-ok')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Betrag wie 2,49'), findsOneWidget);
    });

    testWidgets('Nicht lesbarer Bon (z.B. offline): manuell eingeben und speichern', (tester) async {
      const failed = ParsedReceipt.failed(['Datum und Uhrzeit nicht gefunden']);
      await openReview(tester, const ImportPreview(receipt: failed, source: ReceiptSources.photoLocal, error: 'Der Bon konnte nicht gelesen werden.'));
      expect(find.byKey(const Key('review-manual')), findsOneWidget);

      await tester.tap(find.byKey(const Key('review-manual')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('edit-total')), '3,50');
      await tester.tap(find.byKey(const Key('add-line')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('line-name')), 'Milch');
      await tester.enterText(find.byKey(const Key('line-amount')), '3,50');
      await tester.tap(find.byKey(const Key('line-ok')));
      await tester.pumpAndSettle();
      expect(find.textContaining('das entspricht der Summe'), findsOneWidget);
      await tester.tap(find.byKey(const Key('edit-apply')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      final r = await db.select(db.receipts).getSingle();
      expect(r.totalCents, 350);
      expect((await db.select(db.receiptItems).getSingle()).rawText, 'Milch');
    });

    testWidgets('Nach der Bearbeitung wird erneut auf Duplikate geprueft', (tester) async {
      final base = _parse('billa_digital_04');
      await receiptRepo(db).saveParsed(base);
      // zweite Fassung ohne Re-Nr (wie Cloud-Lesung), Uhrzeit aber gleich
      final noId = ParsedReceipt.edited(
        base: null,
        chain: 'Billa',
        items: base.items,
        bonDiscounts: base.bonDiscounts,
        totalCents: base.totalCents! + 100, // falsch gelesene Summe: kein Duplikat
        purchasedAtUtc: base.purchasedAtUtc!,
      );
      await openReview(tester, ImportPreview(receipt: noId, source: ReceiptSources.photoCloud));
      expect(find.text('Dieser Bon ist schon gespeichert'), findsNothing);

      await tester.tap(find.byKey(const Key('review-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('edit-total')), formatEuro(base.totalCents!).replaceAll(' €', ''));
      await tester.tap(find.byKey(const Key('edit-apply')));
      await tester.pumpAndSettle();
      expect(find.text('Dieser Bon ist schon gespeichert'), findsOneWidget);
    });
  });
}
