import 'dart:convert';

import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/sync/mappers.dart';
import 'package:einkaufstracker/features/receipts/receipt_detail_page.dart';
import 'package:einkaufstracker/features/report/report_items.dart';
import 'package:einkaufstracker/features/report/report_page.dart';
import 'package:einkaufstracker/features/report/trend_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';

/// Ausgeschlossene Bon-Positionen (ADR-020 "Rechnungen teilen", Feature-Request vom 2026-10-01): von jemand
/// anderem bezahlte Positionen zaehlen nicht zu Auswertung, Budget und Trend, bleiben aber auf dem Bon sichtbar.
Receipt _receipt(String id, DateTime utc, int cents) => Receipt(
      id: id, householdId: 'h1', purchasedAt: utc, totalCents: cents, status: 'confirmed', source: 'pdf_text',
      sumMismatch: false, updatedAt: DateTime.utc(2026),
    );

ReceiptItem _item(String rid, String id, int no, String text, int cents,
        {String kind = 'article', String? cat, bool excluded = false, String? productId}) =>
    ReceiptItem(
      id: id, householdId: 'h1', receiptId: rid, lineNo: no, kind: kind, rawText: text, quantity: 1, quantityUnit: 'piece',
      lineTotalCents: cents, categoryId: cat, productId: productId, needsReview: false, excluded: excluded,
      updatedAt: DateTime.utc(2026),
    );

void main() {
  group('setItemExcluded', () {
    late AppDatabase db;
    setUp(() => db = memoryDb());
    tearDown(() => db.close());

    Future<void> seed() async {
      await db.into(db.receipts).insert(_receipt('r1', DateTime.utc(2026, 9, 10, 10), 800).toCompanion(false));
      await db.batch((b) => b.insertAll(db.receiptItems, [
            _item('r1', 'a1', 1, 'Bier', 300).toCompanion(false),
            _item('r1', 'd1', 2, 'Bier Aktion', -50, kind: 'discount').toCompanion(false),
            _item('r1', 'p1', 3, 'Pfand', 25, kind: 'deposit').toCompanion(false),
            _item('r1', 'a2', 4, 'Brot', 400).toCompanion(false),
            _item('r1', 'd2', 5, 'Brot Aktion', -20, kind: 'discount').toCompanion(false),
            _item('r1', 'bd', 6, 'Rabattsammler', -30, kind: 'bill_discount').toCompanion(false),
          ]));
    }

    Future<Map<String, bool>> excludedById() async =>
        {for (final i in await db.select(db.receiptItems).get()) i.id: i.excluded};

    test('Artikel ausschliessen nimmt den Rabatt direkt darunter mit, nicht aber andere Artikel', () async {
      await seed();
      final changed = await receiptRepo(db).setItemExcluded('a1', true);

      expect(changed, 2);
      final flags = await excludedById();
      expect(flags['a1'], isTrue);
      expect(flags['d1'], isTrue, reason: 'der Rabatt gehoert zum Artikel darueber');
      expect(flags['a2'], isFalse);
      expect(flags['d2'], isFalse, reason: 'Rabatt des naechsten Artikels bleibt eigen');
    });

    test('Die Mitnahme der Rabatte stoppt an der ersten Nicht-Rabatt-Zeile (Pfand bleibt unberuehrt)', () async {
      await seed();
      await receiptRepo(db).setItemExcluded('a1', true);
      expect((await excludedById())['p1'], isFalse);
    });

    test('Wieder einschliessen macht Artikel und Rabatt rueckgaengig', () async {
      await seed();
      final repo = receiptRepo(db);
      await repo.setItemExcluded('a1', true);
      final changed = await repo.setItemExcluded('a1', false);

      expect(changed, 2);
      expect((await excludedById()).values.every((v) => !v), isTrue);
    });

    test('Rabatt auf den ganzen Bon laesst sich nicht ausschliessen', () async {
      await seed();
      final changed = await receiptRepo(db).setItemExcluded('bd', true);
      expect(changed, 0);
      expect((await excludedById())['bd'], isFalse);
    });

    test('Wirkt nur auf diese Position, nicht auf gleich benannte Artikel anderer Bons (anders als die Kategorie)', () async {
      await seed();
      await db.into(db.receipts).insert(_receipt('r2', DateTime.utc(2026, 9, 12, 10), 300).toCompanion(false));
      await db.into(db.receiptItems).insert(_item('r2', 'b1', 1, 'Bier', 300).toCompanion(false));

      await receiptRepo(db).setItemExcluded('a1', true);
      expect((await excludedById())['b1'], isFalse);
    });

    test('Keine Aenderung, kein Sync-Eintrag, kein onChanged', () async {
      await seed();
      var changed = 0;
      final repo = receiptRepo(db, onChanged: () => changed++);
      final before = (await db.select(db.outbox).get()).length;

      expect(await repo.setItemExcluded('a2', false), 0, reason: 'war schon nicht ausgeschlossen');
      expect((await db.select(db.outbox).get()).length, before);
      expect(changed, 0);
    });

    test('Landet in der Outbox mit excluded=true und kommt per Mapper unveraendert zurueck', () async {
      await seed();
      await receiptRepo(db).setItemExcluded('a2', true);

      final entries = (await db.select(db.outbox).get()).where((o) => o.remoteTable == 'receipt_items' && o.rowId == 'a2');
      final payload = jsonDecode(entries.last.payload) as Map<String, dynamic>;
      expect(payload['excluded'], isTrue);

      final row = await (db.select(db.receiptItems)..where((i) => i.id.equals('a2'))).getSingle();
      expect(receiptItemToRemote(row)['excluded'], isTrue);
      expect(receiptItemFromRemote({...receiptItemToRemote(row)}).excluded.value, isTrue);
    });

    test('Aelterer Serverstand ohne excluded-Spalte: gilt als nicht ausgeschlossen', () {
      final remote = receiptItemToRemote(_item('r1', 'x', 1, 'Alt', 100))..remove('excluded');
      expect(receiptItemFromRemote(remote).excluded.value, isFalse);
    });
  });

  group('reportItemsOf', () {
    test('teilt in eigene und ausgeschlossene Positionen, Summen bleiben getrennt', () {
      final split = reportItemsOf([
        _item('r1', 'a1', 1, 'Bier', 300, excluded: true),
        _item('r1', 'a2', 2, 'Brot', 400),
      ]);
      expect(split.own.map((i) => i.rawText), ['Brot']);
      expect(split.excluded.map((i) => i.rawText), ['Bier']);
    });

    test('Produktname kommt aus der Produktliste', () {
      final product = Product(
        id: 'p1', householdId: 'h1', name: 'Vollmilch', baseUnit: 'l', defaultDateKind: 'best_before',
        defaultLocation: 'fridge', restock: false, updatedAt: DateTime.utc(2026),
      );
      final split = reportItemsOf([_item('r1', 'a1', 1, 'H-MILCH', 150, productId: 'p1')], products: {'p1': product});
      expect(split.own.single.productName, 'Vollmilch');
    });

    test('ohne Ausschluss landet alles in own', () {
      final split = reportItemsOf([_item('r1', 'a1', 1, 'Brot', 400)]);
      expect(split.excluded, isEmpty);
      expect(split.own, hasLength(1));
    });
  });

  group('Detailseite', () {
    Widget host(AppDatabase db, List<ReceiptItem> items) {
      final repo = receiptRepo(db);
      return ProviderScope(
        overrides: [
          categoriesStreamProvider.overrideWith((ref) => Stream.value(const <Category>[])),
          receiptProvider('r1').overrideWith((ref) => Stream.value(_receipt('r1', DateTime.utc(2026, 9, 10, 10), 700))),
          receiptItemsProvider('r1').overrideWith((ref) => Stream.value(items)),
          receiptFilesStreamProvider('r1').overrideWith((ref) => Stream.value(const <ReceiptFile>[])),
          storesStreamProvider.overrideWith((ref) => Stream.value(const <Store>[])),
          receiptRepositoryProvider.overrideWithValue(repo),
          inventoryRepositoryProvider.overrideWithValue(inventoryRepo(db)),
          productsStreamProvider.overrideWith((ref) => Stream.value(const <Product>[])),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(initialLocation: '/', routes: [
            GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('LISTE')), routes: [
              GoRoute(path: 'receipt', builder: (_, _) => const ReceiptDetailPage(receiptId: 'r1')),
            ]),
          ]),
        ),
      );
    }

    testWidgets('ausgeschlossene Position: durchgestrichen, Hinweis im Untertitel, Summenzeile "davon von anderen bezahlt"', (tester) async {
      final db = memoryDb();
      addTearDown(db.close);
      await tester.pumpWidget(host(db, [
        _item('r1', 'a1', 1, 'Bier', 300, excluded: true),
        _item('r1', 'a2', 2, 'Brot', 400),
      ]));
      GoRouter.of(tester.element(find.text('LISTE'))).go('/receipt');
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(find.text('Bier')).style?.decoration, TextDecoration.lineThrough);
      expect(tester.widget<Text>(find.text('Brot')).style?.decoration, isNot(TextDecoration.lineThrough));
      expect(find.textContaining('von anderem bezahlt'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('items-sum'))).data, '7,00 €', reason: 'Bon-Summe bleibt die volle Summe');
      expect(tester.widget<Text>(find.byKey(const Key('items-excluded-sum'))).data, '3,00 €');
    });

    testWidgets('ohne ausgeschlossene Position gibt es die Summenzeile nicht', (tester) async {
      final db = memoryDb();
      addTearDown(db.close);
      await tester.pumpWidget(host(db, [_item('r1', 'a2', 1, 'Brot', 400)]));
      GoRouter.of(tester.element(find.text('LISTE'))).go('/receipt');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('items-excluded-sum')), findsNothing);
    });

    testWidgets('Schalter im Sheet schliesst die Position aus (inkl. Rabatt darunter) und zeigt eine Rueckmeldung', (tester) async {
      final db = memoryDb();
      addTearDown(db.close);
      final items = [
        _item('r1', 'a1', 1, 'Bier', 300),
        _item('r1', 'd1', 2, 'Bier Aktion', -50, kind: 'discount', cat: 'c'),
      ];
      await db.into(db.receipts).insert(_receipt('r1', DateTime.utc(2026, 9, 10, 10), 250).toCompanion(false));
      await db.batch((b) => b.insertAll(db.receiptItems, [for (final i in items) i.toCompanion(false)]));
      await tester.pumpWidget(host(db, items));
      GoRouter.of(tester.element(find.text('LISTE'))).go('/receipt');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bier'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('item-excluded-switch')), findsOneWidget);
      await tester.tap(find.byKey(const Key('item-excluded-switch')));
      await tester.pumpAndSettle();

      final rows = {for (final i in await db.select(db.receiptItems).get()) i.id: i.excluded};
      expect(rows, {'a1': true, 'd1': true});
      expect(find.textContaining('zählt nicht zu deinen Ausgaben'), findsOneWidget);
    });
  });

  group('Auswertung', () {
    testWidgets('Monatsauswertung zaehlt ausgeschlossene Positionen nicht und nennt den Betrag separat', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          receiptsStreamProvider.overrideWith((ref) => Stream.value([_receipt('a', DateTime.utc(2026, 9, 10, 10), 700)])),
          allItemsStreamProvider.overrideWith((ref) => Stream.value([
                _item('a', 'i1', 1, 'Bier', 300, cat: 'g', excluded: true),
                _item('a', 'i2', 2, 'Brot', 400, cat: 'g'),
              ])),
          categoriesStreamProvider.overrideWith((ref) => Stream.value([
                Category(id: 'g', householdId: 'h1', name: 'Getränke', sortOrder: 0, isStorable: false, updatedAt: DateTime.utc(2026)),
              ])),
          productsStreamProvider.overrideWith((ref) => Stream.value(const <Product>[])),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(routes: [
            GoRoute(path: '/', builder: (_, _) => Scaffold(body: ReportPage(now: DateTime.utc(2026, 9, 26, 12)))),
          ]),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(find.byKey(const Key('report-total'))).data, '4,00 €');
      expect(tester.widget<Text>(find.byKey(const Key('report-excluded'))).data, 'Ohne 3,00 €, die jemand anderes bezahlt hat');
    });

    testWidgets('ohne ausgeschlossene Positionen erscheint der Hinweis nicht', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          receiptsStreamProvider.overrideWith((ref) => Stream.value([_receipt('a', DateTime.utc(2026, 9, 10, 10), 400)])),
          allItemsStreamProvider.overrideWith((ref) => Stream.value([_item('a', 'i2', 1, 'Brot', 400)])),
          categoriesStreamProvider.overrideWith((ref) => Stream.value(const <Category>[])),
          productsStreamProvider.overrideWith((ref) => Stream.value(const <Product>[])),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(routes: [
            GoRoute(path: '/', builder: (_, _) => Scaffold(body: ReportPage(now: DateTime.utc(2026, 9, 26, 12)))),
          ]),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('report-excluded')), findsNothing);
    });

    testWidgets('Trend zaehlt ausgeschlossene Positionen ebenfalls nicht', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          receiptsStreamProvider.overrideWith((ref) => Stream.value([_receipt('a', DateTime.utc(2026, 9, 10, 10), 700)])),
          allItemsStreamProvider.overrideWith((ref) => Stream.value([
                _item('a', 'i1', 1, 'Bier', 300, cat: 'g', excluded: true),
                _item('a', 'i2', 2, 'Brot', 400, cat: 'g'),
              ])),
          categoriesStreamProvider.overrideWith((ref) => Stream.value(const <Category>[])),
        ],
        child: MaterialApp(home: TrendPage(now: DateTime.utc(2026, 9, 26, 12))),
      ));
      await tester.pumpAndSettle();

      expect(find.text('4,00 €'), findsWidgets);
      expect(find.text('7,00 €'), findsNothing);
    });
  });
}
