import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;

import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/core/format.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/shopping_list_repository.dart';
import 'package:einkaufstracker/domain/receipt/billa_text_parser.dart';
import 'package:einkaufstracker/domain/receipt/parsed_receipt.dart';
import 'package:einkaufstracker/domain/receipt/price_history.dart';
import 'package:einkaufstracker/domain/shopping_list/list_price_estimate.dart';
import 'package:einkaufstracker/features/receipts/receipt_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Ist-Soll-Abgleich (Wettbewerbsanalyse, ADR-030): was die per Bon abgehakten Listeneintraege vor dem Einkauf gekostet
/// haetten, gegen das, was auf dem Bon dafuer bezahlt wurde.
void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  Future<void> receipt(String id, DateTime at) => db.into(db.receipts).insert(Receipt(
        id: id, householdId: 'h1', purchasedAt: at, totalCents: 100, status: 'confirmed', source: 'manual', sumMismatch: false, updatedAt: DateTime.utc(2026),
      ));

  Future<void> bought(String id, String receiptId, String productId, int unitPriceNormCents, {int? lineTotal}) =>
      db.into(db.receiptItems).insert(ReceiptItem(
            excluded: false, id: id, householdId: 'h1', receiptId: receiptId, lineNo: 1, kind: 'article', rawText: 'x', productId: productId,
            quantity: 1, quantityUnit: 'kg', lineTotalCents: lineTotal ?? unitPriceNormCents, unitPriceNormCents: unitPriceNormCents, needsReview: false, updatedAt: DateTime.utc(2026),
          ));

  group('ShoppingListRepository.checkOffForProduct mit Bon (Vergleich)', () {
    late ShoppingListRepository list;
    late Product reis;

    setUp(() async {
      list = shoppingListRepo(db);
      reis = await productRepo(db).create(name: 'Reis', baseUnit: 'kg', packSize: 0.5);
    });

    test('geschaetzt gegen bezahlt: Anzahl mal Inhalt mal letzter Grundpreis VOR diesem Bon', () async {
      await receipt('alt', DateTime.utc(2026, 9, 1));
      await bought('a', 'alt', reis.id, 250); // 250 Cent je kg
      await list.addManual(productId: reis.id, quantity: 2, unit: 'kg'); // 2 Packungen a 0,5 kg = 1 kg -> 250 Cent
      await receipt('neu', DateTime.utc(2026, 9, 20));
      await bought('b', 'neu', reis.id, 260, lineTotal: 260);

      await list.checkOffForProduct(reis.id, receiptId: 'neu', paidCents: 260);

      final c = (await list.comparisonFor('neu'))!;
      expect([c.estimatedCents, c.actualCents, c.items], [250, 260, 1]);
      expect(c.result.differenceCents, 10);
      expect((await db.select(db.shoppingListItems).get()).single.checked, isTrue);
    });

    test('der Preis aus dem eigenen Bon zaehlt nicht als Vorwissen (sonst waere Schaetzung gleich Bezahlt)', () async {
      await receipt('neu', DateTime.utc(2026, 9, 20));
      await bought('b', 'neu', reis.id, 260);
      await list.addManual(productId: reis.id, quantity: 2, unit: 'kg');
      await list.checkOffForProduct(reis.id, receiptId: 'neu', paidCents: 260);
      expect(await list.comparisonFor('neu'), isNull, reason: 'es gab vorher keinen Preis');
      expect((await db.select(db.shoppingListItems).get()).single.checked, isTrue, reason: 'abgehakt wird trotzdem');
    });

    test('der juengste fruehere Kauf gibt den Preis, nicht der aelteste', () async {
      await receipt('r1', DateTime.utc(2026, 7, 1));
      await receipt('r2', DateTime.utc(2026, 9, 1));
      await bought('a', 'r1', reis.id, 999);
      await bought('b', 'r2', reis.id, 200);
      await list.addManual(productId: reis.id, quantity: 2, unit: 'kg');
      await receipt('neu', DateTime.utc(2026, 9, 20));
      await list.checkOffForProduct(reis.id, receiptId: 'neu', paidCents: 300);
      expect((await list.comparisonFor('neu'))!.estimatedCents, 200);
    });

    test('mehrere Produkte desselben Bons werden aufsummiert', () async {
      final milch = await productRepo(db).create(name: 'Milch', baseUnit: 'l', packSize: 1);
      await receipt('alt', DateTime.utc(2026, 9, 1));
      await bought('a', 'alt', reis.id, 250);
      await bought('b', 'alt', milch.id, 120);
      await list.addManual(productId: reis.id, quantity: 2, unit: 'kg'); // 250
      await list.addManual(productId: milch.id, quantity: 2, unit: 'l'); // 2 l * 120 = 240
      await receipt('neu', DateTime.utc(2026, 9, 20));
      await list.checkOffForProduct(reis.id, receiptId: 'neu', paidCents: 260);
      await list.checkOffForProduct(milch.id, receiptId: 'neu', paidCents: 230);
      final c = (await list.comparisonFor('neu'))!;
      expect([c.estimatedCents, c.actualCents, c.items], [490, 490, 2]);
      expect(c.result.differenceCents, 0);
    });

    test('ohne Bon-Angaben (Altverhalten) wird nichts festgehalten', () async {
      await receipt('alt', DateTime.utc(2026, 9, 1));
      await bought('a', 'alt', reis.id, 250);
      await list.addManual(productId: reis.id, quantity: 2, unit: 'kg');
      await list.checkOffForProduct(reis.id);
      expect(await db.select(db.keyValues).get().then((k) => k.where((e) => e.key.startsWith('list_vs_actual'))), isEmpty);
    });

    test('unbestaetigte Vorschlaege werden nicht verglichen (sie werden auch nicht abgehakt)', () async {
      await receipt('alt', DateTime.utc(2026, 9, 1));
      await bought('a', 'alt', reis.id, 250);
      await productRepo(db).update(reis.copyWith(restock: true));
      await list.suggestDepleted(reis.id);
      await receipt('neu', DateTime.utc(2026, 9, 20));
      await list.checkOffForProduct(reis.id, receiptId: 'neu', paidCents: 260);
      expect(await list.comparisonFor('neu'), isNull);
    });

    test('bereits abgehakte Eintraege werden nicht noch einmal gezaehlt', () async {
      await receipt('alt', DateTime.utc(2026, 9, 1));
      await bought('a', 'alt', reis.id, 250);
      await list.addManual(productId: reis.id, quantity: 2, unit: 'kg');
      await receipt('neu', DateTime.utc(2026, 9, 20));
      await list.checkOffForProduct(reis.id, receiptId: 'neu', paidCents: 260);
      await list.checkOffForProduct(reis.id, receiptId: 'neu', paidCents: 260); // zweite Zeile desselben Produkts auf dem Bon
      final c = (await list.comparisonFor('neu'))!;
      expect([c.estimatedCents, c.actualCents, c.items], [250, 260, 1]);
    });

    test('unbekannter Bon und beschaedigter Eintrag ergeben null statt eines Fehlers', () async {
      expect(await list.comparisonFor('gibt-es-nicht'), isNull);
      await db.setKv('list_vs_actual:kaputt', '{nicht json');
      expect(await list.comparisonFor('kaputt'), isNull);
    });
  });

  test('Gesamtablauf: Bon speichern hakt den Listeneintrag ab und haelt den Vergleich fest', () async {
    final products = productRepo(db);
    final list = shoppingListRepo(db);
    final repo = receiptRepo(db, productRepo: products, inventoryRepo: inventoryRepo(db), shoppingListRepo: list);
    await seedCategories(db);
    await repo.saveParsed(_parse('billa_digital_04'));
    final champignon = await (db.select(db.products)..where((p) => p.name.equals('Clever Champignon weiß'))).getSingle();
    final priorPrice = (await (db.select(db.receiptItems)..where((i) => i.productId.equals(champignon.id))).getSingle()).unitPriceNormCents!;
    await list.addManual(productId: champignon.id, unit: champignon.baseUnit);

    // Zweiter Bon mit demselben Artikel (wie im bestehenden Alias-Test): loest das Abhaken aus
    final text = File('test/fixtures/receipts/billa_digital_06.txt').readAsStringSync().replaceFirst(_firstArticle('billa_digital_06'), 'IC Clever Champignon weiß');
    final saved = await repo.saveParsed(const BillaTextParser().parse(text));

    final c = await list.comparisonFor(saved.receiptId);
    expect(c, isNotNull, reason: 'der Eintrag wurde durch diesen Bon abgehakt, der Preis davor war bekannt');
    expect(c!.estimatedCents, priorPrice, reason: 'Anzahl 1, kein Inhalt: ein Stueck zum frueheren Preis');
    final paid = (await (db.select(db.receiptItems)..where((i) => i.receiptId.equals(saved.receiptId) & i.productId.equals(champignon.id))).getSingle()).lineTotalCents;
    expect(c.actualCents, paid);
  });

  group('latestUnitPriceByProduct', () {
    PriceHistoryItem item(String receiptId, String? productId, int? price) =>
        (receiptId: receiptId, productId: productId, unitPriceNormCents: price, quantity: 1, quantityUnit: 'kg');
    PriceHistoryReceipt rec(String id, DateTime at) => (id: id, storeId: null, purchasedAtUtc: at);

    test('der neueste Kauf je Produkt gewinnt', () {
      final r = latestUnitPriceByProduct(
        items: [item('alt', 'p1', 100), item('neu', 'p1', 200), item('alt', 'p2', 50)],
        receipts: [rec('alt', DateTime.utc(2026, 1, 1)), rec('neu', DateTime.utc(2026, 6, 1))],
      );
      expect(r, {'p1': 200, 'p2': 50});
    });

    test('Positionen ohne Produkt, ohne Grundpreis oder mit unbekanntem Bon fehlen', () {
      final r = latestUnitPriceByProduct(
        items: [item('a', null, 100), item('a', 'p1', null), item('weg', 'p2', 100)],
        receipts: [rec('a', DateTime.utc(2026, 1, 1))],
      );
      expect(r, isEmpty);
    });

    test('ein Bon kann ausgeschlossen werden', () {
      final r = latestUnitPriceByProduct(
        items: [item('alt', 'p1', 100), item('neu', 'p1', 200)],
        receipts: [rec('alt', DateTime.utc(2026, 1, 1)), rec('neu', DateTime.utc(2026, 6, 1))],
        excludeReceiptId: 'neu',
      );
      expect(r, {'p1': 100});
    });
  });

  group('formatEstimateVsActual', () {
    test('teurer als geschaetzt', () {
      expect(formatEstimateVsActual(const EstimateVsActual(estimatedCents: 2430, actualCents: 2610)), 'geschätzt 24,30 € · bezahlt 26,10 € (1,80 € teurer als geschätzt)');
    });
    test('guenstiger als geschaetzt', () {
      expect(formatEstimateVsActual(const EstimateVsActual(estimatedCents: 2610, actualCents: 2430)), 'geschätzt 26,10 € · bezahlt 24,30 € (1,80 € günstiger als geschätzt)');
    });
    test('genau getroffen', () {
      expect(formatEstimateVsActual(const EstimateVsActual(estimatedCents: 500, actualCents: 500)), 'geschätzt 5,00 € · bezahlt 5,00 € (genau wie geschätzt)');
    });
  });

  group('Bon-Detailseite', () {
    Receipt rcp() => Receipt(
          id: 'r1', householdId: 'h1', purchasedAt: DateTime.utc(2026, 9, 20, 10), totalCents: 500, status: 'confirmed', source: 'manual', sumMismatch: false, updatedAt: DateTime.utc(2026),
        );

    Widget host(ListComparison? comparison) {
      final holder = memoryDb();
      addTearDown(holder.close);
      return ProviderScope(
        overrides: [
          categoriesStreamProvider.overrideWith((ref) => Stream.value(const <Category>[])),
          receiptProvider('r1').overrideWith((ref) => Stream.value(rcp())),
          receiptItemsProvider('r1').overrideWith((ref) => Stream.value(const <ReceiptItem>[])),
          receiptFilesStreamProvider('r1').overrideWith((ref) => Stream.value(const <ReceiptFile>[])),
          storesStreamProvider.overrideWith((ref) => Stream.value(const <Store>[])),
          listComparisonProvider('r1').overrideWith((ref) async => comparison),
        ],
        child: const MaterialApp(home: ReceiptDetailPage(receiptId: 'r1')),
      );
    }

    testWidgets('zeigt den Vergleich zur Einkaufsliste, wenn es einen gibt', (tester) async {
      await tester.pumpWidget(host(const ListComparison(estimatedCents: 2430, actualCents: 2610, items: 3)));
      await tester.pumpAndSettle();
      expect(find.text('3 Artikel von der Einkaufsliste'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('receipt-list-comparison-text'))).data, 'geschätzt 24,30 € · bezahlt 26,10 € (1,80 € teurer als geschätzt)');
    });

    testWidgets('Einzahl bei einem Artikel', (tester) async {
      await tester.pumpWidget(host(const ListComparison(estimatedCents: 100, actualCents: 100, items: 1)));
      await tester.pumpAndSettle();
      expect(find.text('1 Artikel von der Einkaufsliste'), findsOneWidget);
    });

    testWidgets('ohne Vergleich keine Karte', (tester) async {
      await tester.pumpWidget(host(null));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('receipt-list-comparison')), findsNothing);
    });
  });
}

ParsedReceipt _parse(String fixture) => const BillaTextParser().parse(File('test/fixtures/receipts/$fixture.txt').readAsStringSync());

String _firstArticle(String fixture) => _parse(fixture).items.firstWhere((i) => i.kind == ReceiptItemKind.article).rawText;
