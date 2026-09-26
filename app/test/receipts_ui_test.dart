import 'package:drift/drift.dart' show Value;
import 'dart:io';

import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/files/receipt_file_service.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/receipt_repository.dart';
import 'package:einkaufstracker/domain/receipt/month_summary.dart';
import 'package:einkaufstracker/features/receipts/receipt_detail_page.dart';
import 'package:einkaufstracker/features/receipts/receipts_overview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';

Receipt _receipt(String id, DateTime utc, int cents, {String? store = 's1', bool mismatch = false, DateTime? deleted}) => Receipt(
      id: id,
      householdId: 'h',
      storeId: store,
      purchasedAt: utc,
      totalCents: cents,
      status: 'confirmed',
      source: 'pdf_text',
      sumMismatch: mismatch,
      updatedAt: DateTime.utc(2026),
      deletedAt: deleted,
    );

final _store = Store(id: 's1', householdId: 'h', chain: 'Billa', branch: '0643', updatedAt: DateTime.utc(2026));

ReceiptItem _item(String id, int no, String text, int cents, {String kind = 'article', double qty = 1, int? unit}) => ReceiptItem(
      id: id,
      householdId: 'h',
      receiptId: 'r1',
      lineNo: no,
      kind: kind,
      rawText: text,
      quantity: qty,
      quantityUnit: 'piece',
      unitPriceCents: unit,
      lineTotalCents: cents,
      needsReview: false,
      updatedAt: DateTime.utc(2026),
    );

void main() {
  group('Monatssumme (Wiener Zeit)', () {
    PurchaseRecord p(DateTime utc, int cents) => (purchasedAtUtc: utc, totalCents: cents);

    test('summiert nur den gewaehlten Monat', () {
      final m = summarizeMonth([
        p(DateTime.utc(2026, 9, 5, 10), 1000),
        p(DateTime.utc(2026, 9, 20, 10), 2500),
        p(DateTime.utc(2026, 8, 30, 10), 9999), // Vormonat
      ], year: 2026, month: 9);
      expect(m.totalCents, 3500);
      expect(m.receiptCount, 2);
    });

    test('Einkauf 30.09. 23:30 UTC ist in Wien schon Oktober (FR-07)', () {
      final list = [p(DateTime.utc(2026, 9, 30, 23, 30), 1000)];
      expect(summarizeMonth(list, year: 2026, month: 10).totalCents, 1000);
      expect(summarizeMonth(list, year: 2026, month: 9).totalCents, 0);
    });

    test('Einkauf 31.10. 23:30 UTC (Winterzeit) ist in Wien schon November', () {
      final list = [p(DateTime.utc(2026, 10, 31, 23, 30), 500)];
      expect(summarizeMonth(list, year: 2026, month: 11).receiptCount, 1);
    });

    test('Leere Liste ergibt 0', () {
      final m = summarizeMonth(const [], year: 2026, month: 9);
      expect((m.totalCents, m.receiptCount), (0, 0));
    });
  });

  group('Uebersicht', () {
    Widget host(List<Receipt> list, {DateTime? now, List<Store>? stores}) => ProviderScope(
          overrides: [
            receiptsStreamProvider.overrideWith((ref) => Stream.value(list)),
            storesStreamProvider.overrideWith((ref) => Stream.value(stores ?? [_store])),
          ],
          child: MaterialApp.router(
            routerConfig: GoRouter(routes: [
              GoRoute(path: '/', builder: (_, _) => Scaffold(body: ReceiptsOverview(now: now ?? DateTime.utc(2026, 9, 26, 12)))),
              GoRoute(path: '/receipt/:id', builder: (_, s) => Scaffold(body: Text('DETAIL ${s.pathParameters['id']}'))),
            ]),
          ),
        );

    testWidgets('zeigt Monatssumme des aktuellen Monats und die Bons, neueste zuerst', (tester) async {
      await tester.pumpWidget(host([
        _receipt('a', DateTime.utc(2026, 9, 24, 12, 42), 2319),
        _receipt('b', DateTime.utc(2026, 9, 26, 14, 38), 2638, mismatch: true),
        _receipt('c', DateTime.utc(2026, 8, 12, 16, 10), 632),
      ]));
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(find.byKey(const Key('period-label'))).data, 'September 2026');
      expect(tester.widget<Text>(find.byKey(const Key('month-total'))).data, '49,57 €');
      expect(find.text('2 Einkäufe'), findsOneWidget);
      expect(find.text('Billa, Filiale 0643'), findsNWidgets(2)); // nur September, der August ist ausgefiltert
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget); // Bon mit Abweichung markiert
    });

    final hofer = Store(id: 's2', householdId: 'h', chain: 'Hofer', updatedAt: DateTime.utc(2026));
    List<Receipt> mixed() => [
          _receipt('a', DateTime.utc(2026, 9, 24, 12, 42), 2319),
          _receipt('b', DateTime.utc(2026, 9, 26, 14, 38), 1000, store: 's2'),
          _receipt('c', DateTime.utc(2026, 8, 12, 16, 10), 632),
          _receipt('d', DateTime.utc(2026, 8, 20, 9, 0), 500, store: 's2'),
        ];

    testWidgets('Filter Monat: Alle Monate zeigt alles, ein anderer Monat nur seine Bons, Summe folgt dem Filter', (tester) async {
      await tester.pumpWidget(host(mixed(), stores: [_store, hofer]));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('month-total'))).data, '33,19 €'); // September: 23,19 + 10,00

      await tester.tap(find.byKey(const Key('filter-month')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alle Monate').last);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('period-label'))).data, 'Alle Monate');
      expect(tester.widget<Text>(find.byKey(const Key('month-total'))).data, '44,51 €');
      expect(find.text('4 Einkäufe'), findsOneWidget);

      await tester.tap(find.byKey(const Key('filter-month')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('August 2026').last);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('month-total'))).data, '11,32 €');
      expect(find.text('2 Einkäufe'), findsOneWidget);
    });

    testWidgets('Filter Markt: nur Billa oder nur Hofer, kombinierbar mit dem Monat, erneutes Tippen hebt auf', (tester) async {
      await tester.pumpWidget(host(mixed(), stores: [_store, hofer]));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('filter-chain-Billa')), findsOneWidget);
      expect(find.byKey(const Key('filter-chain-Hofer')), findsOneWidget);

      await tester.tap(find.byKey(const Key('filter-chain-Hofer')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('period-label'))).data, 'September 2026 · Hofer');
      expect(tester.widget<Text>(find.byKey(const Key('month-total'))).data, '10,00 €');
      expect(find.text('1 Einkauf'), findsOneWidget);
      expect(find.text('Hofer'), findsWidgets);

      await tester.tap(find.byKey(const Key('filter-chain-Billa')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('month-total'))).data, '23,19 €');

      await tester.tap(find.byKey(const Key('filter-chain-Billa'))); // aufheben
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('month-total'))).data, '33,19 €');
    });

    testWidgets('Auswahl ohne Treffer: Hinweis, Summe 0', (tester) async {
      await tester.pumpWidget(host([_receipt('a', DateTime.utc(2026, 8, 24, 12, 42), 2319)], stores: [_store]));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('no-match')), findsOneWidget); // aktueller Monat (September) hat keinen Bon
      expect(tester.widget<Text>(find.byKey(const Key('month-total'))).data, '0,00 €');
    });

    testWidgets('ohne Bons: Hinweis auf den Import und Monatssumme 0', (tester) async {
      await tester.pumpWidget(host(const []));
      await tester.pumpAndSettle();
      expect(find.text('Noch keine Bons'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('month-total'))).data, '0,00 €');
    });

    testWidgets('Tippen auf einen Bon oeffnet die Detailseite', (tester) async {
      await tester.pumpWidget(host([_receipt('a', DateTime.utc(2026, 9, 24, 12, 42), 2319)]));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Billa, Filiale 0643'));
      await tester.pumpAndSettle();
      expect(find.text('DETAIL a'), findsOneWidget);
    });
  });

  group('Detailseite', () {
    Widget host(AppDatabaseHolder h, {required Receipt receipt, required List<ReceiptItem> items, List<Category> categories = const [], List<ReceiptFile> files = const []}) => ProviderScope(
          overrides: [
            categoriesStreamProvider.overrideWith((ref) => Stream.value(categories)),
            receiptProvider('r1').overrideWith((ref) => Stream.value(receipt)),
            receiptItemsProvider('r1').overrideWith((ref) => Stream.value(items)),
            receiptFilesStreamProvider('r1').overrideWith((ref) => Stream.value(files)),
            receiptFileServiceProvider.overrideWithValue(h.files),
            storesStreamProvider.overrideWith((ref) => Stream.value([_store])),
            receiptRepositoryProvider.overrideWithValue(h.repo),
          ],
          child: MaterialApp.router(
            routerConfig: GoRouter(initialLocation: '/', routes: [
              GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('LISTE')), routes: [
                GoRoute(path: 'receipt', builder: (_, _) => const ReceiptDetailPage(receiptId: 'r1')),
              ]),
            ]),
          ),
        );

    testWidgets('zeigt Positionen mit Menge, Rabatt und Pfand und die Summe', (tester) async {
      final db = memoryDb();
      addTearDown(db.close);
      final holder = AppDatabaseHolder(db);
      final items = [
        _item('i1', 1, 'DKIH Cherrytomaten Sophie', 570, qty: 2, unit: 285),
        _item('i2', 2, 'EXTREM AKTION', -134, kind: 'discount'),
        _item('i3', 3, 'PFANDARTIKEL', 25, kind: 'deposit'),
      ];
      await tester.pumpWidget(host(holder, receipt: _receipt('r1', DateTime.utc(2026, 7, 2, 17, 51), 461), items: items));
      final router = GoRouter.of(tester.element(find.text('LISTE')));
      router.go('/receipt');
      await tester.pumpAndSettle();

      expect(find.text('Billa, Filiale 0643'), findsOneWidget);
      expect(find.text('02.07.2026, 19:51 Uhr'), findsOneWidget);
      expect(find.text('Nicht zugeordnet · 2 × 2,85 €'), findsOneWidget);
      expect(find.text('Rabatt'), findsOneWidget);
      expect(find.text('Pfand'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('items-sum'))).data, '4,61 €');
      expect(tester.widget<Text>(find.byKey(const Key('receipt-total'))).data, '4,61 €');
    });

    testWidgets('Loeschen mit Rueckfrage: Abbrechen loescht nichts, Bestaetigen entfernt den Bon', (tester) async {
      final db = memoryDb();
      addTearDown(db.close);
      // echter Bon in der Datenbank, damit softDelete etwas tut
      final repo = receiptRepo(db);
      await db.into(db.receipts).insert(_receipt('r1', DateTime.utc(2026, 7, 2, 17, 51), 100).toCompanion(false));
      final holder = AppDatabaseHolder(db, repo: repo);

      await tester.pumpWidget(host(holder, receipt: _receipt('r1', DateTime.utc(2026, 7, 2, 17, 51), 100), items: const []));
      GoRouter.of(tester.element(find.text('LISTE'))).go('/receipt');
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Löschen'));
      await tester.pumpAndSettle();
      expect(find.text('Bon löschen?'), findsOneWidget);

      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect((await db.select(db.receipts).getSingle()).deletedAt, isNull);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Löschen'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Löschen'));
      await tester.pumpAndSettle();

      expect((await db.select(db.receipts).getSingle()).deletedAt, isNotNull);
      expect(find.text('LISTE'), findsOneWidget); // zurueck auf der Liste
    });

    testWidgets('Tippen auf einen Artikel oeffnet die Kategorieauswahl, die Wahl wird gelernt', (tester) async {
      final db = memoryDb();
      addTearDown(db.close);
      final cat = await seedCategories(db);
      final repo = receiptRepo(db);
      await db.into(db.receipts).insert(_receipt('r1', DateTime.utc(2026, 7, 2, 17, 51), 285).toCompanion(false));
      await db.into(db.receiptItems).insert(_item('i1', 1, 'scharfer Aufstrich', 285).toCompanion(false));
      final categories = await db.select(db.categories).get();

      await tester.pumpWidget(host(AppDatabaseHolder(db, repo: repo),
          receipt: _receipt('r1', DateTime.utc(2026, 7, 2, 17, 51), 285),
          items: [_item('i1', 1, 'scharfer Aufstrich', 285)],
          categories: categories));
      GoRouter.of(tester.element(find.text('LISTE'))).go('/receipt');
      await tester.pumpAndSettle();
      expect(find.text('Nicht zugeordnet'), findsOneWidget);

      await tester.tap(find.text('scharfer Aufstrich'));
      await tester.pumpAndSettle();
      final pick = find.byKey(const Key('pick-Öle, Gewürze & Saucen'));
      await tester.scrollUntilVisible(pick, 100, scrollable: find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)));
      await tester.tap(pick);
      await tester.pumpAndSettle();

      expect((await db.select(db.receiptItems).getSingle()).categoryId, cat['Öle, Gewürze & Saucen']);
      expect((await db.select(db.categoryAliases).getSingle()).aliasText, 'scharfer aufstrich');
      expect(find.text('Zugeordnet'), findsOneWidget);
    });

    testWidgets('Zugeordneter Artikel zeigt den Kategorienamen', (tester) async {
      final db = memoryDb();
      addTearDown(db.close);
      await seedCategories(db);
      final categories = await db.select(db.categories).get();
      final item = _item('i1', 1, 'Clever Champignon weiß', 199).copyWith(categoryId: const Value('cat:Gemüse'));
      await tester.pumpWidget(host(AppDatabaseHolder(db), receipt: _receipt('r1', DateTime.utc(2026, 7, 2, 17, 51), 199), items: [item], categories: categories));
      GoRouter.of(tester.element(find.text('LISTE'))).go('/receipt');
      await tester.pumpAndSettle();
      expect(find.text('Gemüse'), findsOneWidget);
    });

    testWidgets('Abgelegte Originalbelege erscheinen als Eintraege, Foto und PDF', (tester) async {
      final db = memoryDb();
      addTearDown(db.close);
      final files = [
        ReceiptFile(id: 'f1', householdId: 'h', receiptId: 'r1', kind: 'image', pageNo: 1, storagePath: 'h/r1/f1.jpg', updatedAt: DateTime.utc(2026)),
        ReceiptFile(id: 'f2', householdId: 'h', receiptId: 'r1', kind: 'pdf', pageNo: 1, storagePath: 'h/r1/f2.pdf', updatedAt: DateTime.utc(2026)),
      ];
      await tester.pumpWidget(host(AppDatabaseHolder(db), receipt: _receipt('r1', DateTime.utc(2026, 7, 2, 17, 51), 100), items: const [], files: files));
      GoRouter.of(tester.element(find.text('LISTE'))).go('/receipt');
      await tester.pumpAndSettle();
      expect(find.text('Originalbeleg ansehen (Foto, Seite 1)'), findsOneWidget);
      expect(find.text('Originalbeleg ansehen (PDF)'), findsOneWidget);
    });

    testWidgets('Ohne abgelegte Belege gibt es keinen Eintrag', (tester) async {
      final db = memoryDb();
      addTearDown(db.close);
      await tester.pumpWidget(host(AppDatabaseHolder(db), receipt: _receipt('r1', DateTime.utc(2026, 7, 2, 17, 51), 100), items: const []));
      GoRouter.of(tester.element(find.text('LISTE'))).go('/receipt');
      await tester.pumpAndSettle();
      expect(find.textContaining('Originalbeleg'), findsNothing);
    });

    testWidgets('Bon mit Abweichung zeigt einen Hinweis', (tester) async {
      final db = memoryDb();
      addTearDown(db.close);
      await tester.pumpWidget(host(AppDatabaseHolder(db), receipt: _receipt('r1', DateTime.utc(2026, 7, 2, 17, 51), 100, mismatch: true), items: const []));
      GoRouter.of(tester.element(find.text('LISTE'))).go('/receipt');
      await tester.pumpAndSettle();
      expect(find.textContaining('nicht alle Prüfungen'), findsOneWidget);
    });
  });
}

/// Haelt Datenbank und Repository fuer die Detailseiten-Tests zusammen.
class AppDatabaseHolder {
  AppDatabaseHolder(AppDatabase db, {ReceiptRepository? repo})
      : repo = repo ?? receiptRepo(db),
        files = fileService(db, FakeRemoteFileStore(), Directory.systemTemp.createTempSync('rf'), repo: repo ?? receiptRepo(db));
  final ReceiptRepository repo;
  final ReceiptFileService files;
}
