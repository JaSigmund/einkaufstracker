import 'dart:convert';

import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/household_prefs_repository.dart';
import 'package:einkaufstracker/data/repositories/shopping_list_repository.dart';
import 'package:einkaufstracker/domain/shopping_list/aisle_order.dart';
import 'package:einkaufstracker/domain/inventory/usage_forecast.dart';
import 'package:einkaufstracker/features/shopping_list/shopping_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Mehrere Einkaufslisten je Haushalt und die Vorhersage "Bald aufgebraucht" (Ausbau 1.14).
void pageTest(String name, Future<void> Function(WidgetTester tester) body) => testWidgets(name, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

void main() {
  late AppDatabase db;
  late ShoppingListRepository repo;

  setUp(() {
    db = memoryDb();
    repo = shoppingListRepo(db);
  });
  tearDown(() => db.close());

  Future<List<ShoppingListItem>> items() => db.select(db.shoppingListItems).get();
  Future<List<ShoppingList>> lists() => (db.select(db.shoppingLists)..where((l) => l.deletedAt.isNull())).get();

  group('ShoppingListRepository', () {
    test('createList legt die Standardliste zuerst an und danach die neue, der Name wird gekuerzt', () async {
      final l = await repo.createList('  Drogerie ');
      expect(l.name, 'Drogerie');
      expect(l.isDefault, isFalse);
      final all = await lists();
      expect(all, hasLength(2));
      expect(all.where((x) => x.isDefault), hasLength(1));
      final box = (await db.select(db.outbox).get()).where((e) => e.remoteTable == 'shopping_lists').toList();
      expect(box, hasLength(2), reason: 'Standardliste und neue Liste gehen in die Outbox');
      expect((jsonDecode(box.last.payload) as Map)['name'], 'Drogerie');
    });

    test('ungueltige Namen: leer, zu lang, schon vergeben (ohne Gross- und Kleinschreibung)', () async {
      await repo.createList('Drogerie');
      expect(() => repo.createList('  '), throwsArgumentError);
      expect(() => repo.createList('x' * 41), throwsArgumentError);
      expect(() => repo.createList('DROGERIE'), throwsArgumentError);
      expect(() => repo.createList('einkaufsliste'), throwsArgumentError, reason: 'auch der Name der Standardliste ist vergeben');
      expect(await lists(), hasLength(2));
    });

    test('renameList benennt um, auch die Standardliste, gleicher Name ist nichts, ein vergebener wird abgelehnt', () async {
      final a = await repo.createList('Drogerie');
      final defaultId = await repo.defaultListId();
      await repo.renameList(a.id, 'Baumarkt');
      await repo.renameList(defaultId, 'Supermarkt');
      expect({for (final l in await lists()) l.name}, {'Baumarkt', 'Supermarkt'});
      final before = (await db.select(db.outbox).get()).length;
      await repo.renameList(a.id, 'Baumarkt');
      expect((await db.select(db.outbox).get()).length, before, reason: 'gleicher Name: kein Sync');
      expect(() => repo.renameList(a.id, 'supermarkt'), throwsArgumentError);
      await repo.renameList('gibt-es-nicht', 'X'); // nichts
    });

    test('deleteList: die Eintraege wandern auf die Standardliste, nichts geht verloren', () async {
      final l = await repo.createList('Drogerie');
      final defaultId = await repo.defaultListId();
      final item = await repo.addManual(freeText: 'Zahnpasta', listId: l.id);
      expect(item.listId, l.id);
      await repo.deleteList(l.id);
      expect((await lists()).map((x) => x.id), [defaultId]);
      final stored = (await items()).single;
      expect(stored.listId, defaultId);
      expect(stored.deletedAt, isNull);
    });

    test('die Standardliste laesst sich nicht loeschen, eine unbekannte Liste ist nichts', () async {
      final defaultId = await repo.defaultListId();
      await repo.deleteList(defaultId);
      await repo.deleteList('gibt-es-nicht');
      expect(await lists(), hasLength(1));
    });

    test('moveItem verschiebt, dieselbe Liste ist nichts, eine unbekannte Liste wird abgelehnt', () async {
      final l = await repo.createList('Drogerie');
      final item = await repo.addManual(freeText: 'Zahnpasta');
      await repo.moveItem(item.id, l.id);
      expect((await items()).single.listId, l.id);
      final before = (await db.select(db.outbox).get()).length;
      await repo.moveItem(item.id, l.id);
      expect((await db.select(db.outbox).get()).length, before);
      expect(() => repo.moveItem(item.id, 'gibt-es-nicht'), throwsArgumentError);
    });

    test('addManual: unbekannte oder geloeschte Liste faellt auf die Standardliste zurueck', () async {
      final l = await repo.createList('Drogerie');
      await repo.deleteList(l.id);
      final item = await repo.addManual(freeText: 'Seife', listId: l.id);
      expect(item.listId, await repo.defaultListId());
      expect((await repo.addManual(freeText: 'Brot', listId: 'x')).listId, await repo.defaultListId());
    });

    test('watchLists: Standardliste zuerst, dann alphabetisch, ohne geloeschte', () async {
      final z = await repo.createList('Zoo');
      await repo.createList('Apotheke');
      final gone = await repo.createList('Alt');
      await repo.deleteList(gone.id);
      final names = (await repo.watchLists().first).map((l) => l.name).toList();
      expect(names, ['Einkaufsliste', 'Apotheke', 'Zoo']);
      expect(z.isDefault, isFalse);
    });
  });

  test('restore nimmt das Loeschen zurueck und schickt die Aenderung in die Outbox', () async {
    final item = await repo.addManual(freeText: 'Zahnpasta');
    await repo.delete(item.id);
    await repo.restore(item.id);
    final row = (await items()).single;
    expect(row.deletedAt, isNull);
    final last = (await db.select(db.outbox).get()).last;
    expect(last.rowId, item.id);
    expect(jsonDecode(last.payload)['deleted_at'], isNull);
  });

  group('Seite', () {
    var forecasts = <String, UsageForecast>{};

    var stores = <Store>[];
    var categories = <Category>[];

    Future<void> open(WidgetTester tester, {List<Product> products = const []}) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          shoppingListRepositoryProvider.overrideWithValue(repo),
          productRepositoryProvider.overrideWithValue(productRepo(db)),
          allItemsStreamProvider.overrideWith((ref) => Stream.value(const <ReceiptItem>[])),
          receiptsStreamProvider.overrideWith((ref) => Stream.value(const <Receipt>[])),
          productsStreamProvider.overrideWith((ref) => Stream.value(products)),
          categoriesStreamProvider.overrideWith((ref) => Stream.value(categories)),
          storesStreamProvider.overrideWith((ref) => Stream.value(stores)),
          usageForecastProvider.overrideWithValue(forecasts),
        ],
        child: const MaterialApp(home: ShoppingListPage()),
      ));
      await tester.pumpAndSettle();
    }

    setUp(() {
      forecasts = {};
      stores = [];
      categories = [];
    });

    Future<void> createViaUi(WidgetTester tester, String name) async {
      await tester.tap(find.byKey(const Key('list-add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('list-name-field')), name);
      await tester.tap(find.byKey(const Key('list-name-ok')));
      await tester.pumpAndSettle();
    }

    pageTest('ohne Listen gibt es "Neue Liste", die erste neue Liste wird gleich gewaehlt, neue Eintraege landen dort', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('list-add')), findsOneWidget);
      await createViaUi(tester, 'Drogerie');
      final all = await lists();
      final drogerie = all.firstWhere((l) => l.name == 'Drogerie');
      expect(tester.widget<ChoiceChip>(find.byKey(Key('list-chip-${drogerie.id}'))).selected, isTrue);

      await tester.enterText(find.byKey(const Key('shopping-list-input')), 'Zahnpasta');
      await tester.tap(find.byKey(const Key('shopping-list-add')));
      await tester.pumpAndSettle();
      expect((await items()).single.listId, drogerie.id);
      expect(find.text('Zahnpasta'), findsOneWidget);
    });

    pageTest('die Auswahl filtert die Eintraege, die Chips zeigen die Zahl der offenen', (tester) async {
      final l = await repo.createList('Drogerie');
      await repo.addManual(freeText: 'Brot');
      await repo.addManual(freeText: 'Milch');
      await repo.addManual(freeText: 'Zahnpasta', listId: l.id);
      await open(tester);
      final defaultId = await repo.defaultListId();
      expect(find.text('Einkaufsliste (2)'), findsOneWidget);
      expect(find.text('Drogerie (1)'), findsOneWidget);
      expect(find.text('Brot'), findsOneWidget);
      expect(find.text('Zahnpasta'), findsNothing);

      await tester.tap(find.byKey(Key('list-chip-${l.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Zahnpasta'), findsOneWidget);
      expect(find.text('Brot'), findsNothing);

      await tester.tap(find.byKey(Key('list-chip-$defaultId')));
      await tester.pumpAndSettle();
      expect(find.text('Brot'), findsOneWidget);
    });

    pageTest('ein vergebener Name zeigt eine Meldung und legt nichts an', (tester) async {
      await repo.createList('Drogerie');
      await open(tester);
      await createViaUi(tester, 'drogerie');
      expect(find.text('Eine Liste mit diesem Namen gibt es schon'), findsOneWidget);
      expect(await lists(), hasLength(2));
    });

    pageTest('langer Druck auf eine Liste: umbenennen', (tester) async {
      final l = await repo.createList('Drogerie');
      await open(tester);
      await tester.longPress(find.byKey(Key('list-chip-${l.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('list-rename')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('list-name-field'))).controller!.text, 'Drogerie');
      await tester.enterText(find.byKey(const Key('list-name-field')), 'Baumarkt');
      await tester.tap(find.byKey(const Key('list-name-ok')));
      await tester.pumpAndSettle();
      expect((await lists()).any((x) => x.name == 'Baumarkt'), isTrue);
      expect(find.text('Baumarkt'), findsOneWidget);
    });

    pageTest('langer Druck auf eine Liste: loeschen, die Eintraege wandern auf die Standardliste, die Ansicht springt dorthin', (tester) async {
      final l = await repo.createList('Drogerie');
      await repo.addManual(freeText: 'Zahnpasta', listId: l.id);
      await open(tester);
      await tester.tap(find.byKey(Key('list-chip-${l.id}')));
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(Key('list-chip-${l.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('list-delete')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('list-chip-${l.id}')), findsNothing);
      expect(find.text('Zahnpasta'), findsOneWidget, reason: 'jetzt auf der Standardliste, die gewaehlt ist');
    });

    pageTest('die Standardliste hat im Menue kein "Liste loeschen"', (tester) async {
      await repo.createList('Drogerie');
      await open(tester);
      final defaultId = await repo.defaultListId();
      await tester.longPress(find.byKey(Key('list-chip-$defaultId')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('list-rename')), findsOneWidget);
      expect(find.byKey(const Key('list-delete')), findsNothing);
    });

    pageTest('langer Druck auf einen Eintrag: auf eine andere Liste verschieben', (tester) async {
      final l = await repo.createList('Drogerie');
      final item = await repo.addManual(freeText: 'Zahnpasta');
      await open(tester);
      await tester.longPress(find.byKey(Key('shopping-item-${item.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('move-to-${l.id}')));
      await tester.pumpAndSettle();
      expect((await items()).single.listId, l.id);
      expect(find.text('Zahnpasta'), findsNothing, reason: 'die Ansicht zeigt die Standardliste');
    });

    pageTest('Knopf "Liste bearbeiten" oeffnet das Menue der gewaehlten Liste ohne langes Druecken', (tester) async {
      final l = await repo.createList('Drogerie');
      await open(tester);
      await tester.tap(find.byKey(Key('list-chip-${l.id}')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Liste „Drogerie“ bearbeiten'), findsOneWidget);
      await tester.tap(find.byKey(const Key('list-edit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('list-rename')), findsOneWidget);
      expect(find.byKey(const Key('list-delete')), findsOneWidget, reason: 'Menue der gewaehlten, nicht der Standardliste');
    });

    pageTest('Wischen loescht, "Rückgängig" holt den Eintrag zurueck', (tester) async {
      final item = await repo.addManual(freeText: 'Zahnpasta');
      await open(tester);
      await tester.drag(find.byKey(Key('shopping-item-${item.id}')), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.text('Zahnpasta'), findsNothing);
      expect((await items()).single.deletedAt, isNotNull);
      expect(find.text('„Zahnpasta“ gelöscht'), findsOneWidget);

      await tester.tap(find.text('Rückgängig'));
      await tester.pumpAndSettle();
      expect((await items()).single.deletedAt, isNull);
      expect(find.text('Zahnpasta'), findsOneWidget);
    });

    pageTest('die Meldung nach dem Loeschen verschwindet von selbst', (tester) async {
      final item = await repo.addManual(freeText: 'Zahnpasta');
      await open(tester);
      await tester.drag(find.byKey(Key('shopping-item-${item.id}')), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shopping-item-deleted')), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shopping-item-deleted')), findsNothing);
    });

    pageTest('Hinweis auf die Gesten, bis er weggeklickt wird; danach auch beim naechsten Oeffnen nicht mehr', (tester) async {
      await repo.createList('Drogerie');
      await repo.addManual(freeText: 'Brot');
      await open(tester);
      expect(find.textContaining('Nach links wischen löscht einen Eintrag, langes Drücken verschiebt'), findsOneWidget);
      await tester.tap(find.byKey(const Key('shopping-gesture-hint-ok')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shopping-gesture-hint')), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await open(tester);
      expect(find.byKey(const Key('shopping-gesture-hint')), findsNothing);
    });

    pageTest('mit nur einer Liste nennt der Hinweis nur das Wischen, ohne Eintraege gibt es keinen', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('shopping-gesture-hint')), findsNothing);
      await repo.addManual(freeText: 'Brot');
      await tester.pumpAndSettle();
      expect(find.text('Nach links wischen löscht einen Eintrag.'), findsOneWidget);
    });

    pageTest('mit nur einer Liste gibt es nichts zu verschieben', (tester) async {
      final item = await repo.addManual(freeText: 'Brot');
      await open(tester);
      await tester.longPress(find.byKey(Key('shopping-item-${item.id}')));
      await tester.pumpAndSettle();
      expect(find.textContaining('verschieben nach'), findsNothing);
    });

    group('Regal-Reihenfolge', () {
      Category cat(String id, String name) => Category(id: id, householdId: 'h1', name: name, sortOrder: 0, isStorable: true, updatedAt: DateTime.utc(2026));
      Store store(String id, String chain, {String? branch}) => Store(id: id, householdId: 'h1', chain: chain, branch: branch, updatedAt: DateTime.utc(2026));
      Product prod(String id, String name, String? categoryId) => Product(
            id: id, householdId: 'h1', name: name, baseUnit: 'piece', categoryId: categoryId, defaultDateKind: 'best_before', defaultLocation: 'pantry', restock: false, updatedAt: DateTime.utc(2026),
          );

      /// Reihenfolge der Kategorie-Ueberschriften auf der Seite (von oben nach unten)
      List<String> headings(WidgetTester tester) {
        final all = ['Backwaren', 'Gemüse', 'Milch', 'Ohne Kategorie'];
        final found = <MapEntry<double, String>>[
          for (final h in all)
            if (find.text(h).evaluate().isNotEmpty) MapEntry(tester.getTopLeft(find.text(h).first).dy, h),
        ]..sort((a, b) => a.key.compareTo(b.key));
        return [for (final e in found) e.value];
      }

      Future<void> fill() async {
        categories = [cat('c-brot', 'Backwaren'), cat('c-gemuese', 'Gemüse'), cat('c-milch', 'Milch')];
        stores = [store('s1', 'Billa', branch: '0643'), store('s2', 'Spar')];
        await repo.addManual(productId: 'p-brot', unit: 'piece');
        await repo.addManual(productId: 'p-gemuese', unit: 'piece');
        await repo.addManual(productId: 'p-milch', unit: 'piece');
        await repo.addManual(freeText: 'Batterien');
      }

      final products = [prod('p-brot', 'Brot', 'c-brot'), prod('p-gemuese', 'Karotten', 'c-gemuese'), prod('p-milch', 'Joghurt', 'c-milch')];

      pageTest('ohne gespeicherte Reihenfolge bleibt es alphabetisch, es gibt nur den Weg zur Pflege', (tester) async {
        await fill();
        await open(tester, products: products);
        expect(headings(tester), ['Backwaren', 'Gemüse', 'Milch', 'Ohne Kategorie']);
        expect(find.byKey(const Key('aisle-settings')), findsOneWidget);
        expect(find.byKey(const Key('sort-alpha')), findsNothing);
      });

      pageTest('mit Reihenfolge fuer einen Markt: Chips erscheinen, die Auswahl sortiert nach Regal und wird gemerkt', (tester) async {
        await fill();
        await HouseholdPrefsRepository(db, householdId: () async => 'h1').set(aislePrefFor('s1'), ['c-gemuese', 'c-milch', 'c-brot']);
        await open(tester, products: products);
        expect(find.byKey(const Key('sort-store-s1')), findsOneWidget, reason: 'Billa 0643 hat eine Reihenfolge');
        expect(find.byKey(const Key('sort-store-s2')), findsNothing, reason: 'Spar hat keine');
        expect(find.text('Billa 0643'), findsOneWidget);
        expect(headings(tester), ['Backwaren', 'Gemüse', 'Milch', 'Ohne Kategorie'], reason: 'anfangs alphabetisch');

        await tester.tap(find.byKey(const Key('sort-store-s1')));
        await tester.pumpAndSettle();
        expect(headings(tester), ['Gemüse', 'Milch', 'Backwaren', 'Ohne Kategorie']);
        expect(await db.getKv('shopping_sort_store'), 's1');

        await tester.tap(find.byKey(const Key('sort-alpha')));
        await tester.pumpAndSettle();
        expect(headings(tester), ['Backwaren', 'Gemüse', 'Milch', 'Ohne Kategorie']);
      });

      pageTest('die gemerkte Auswahl gilt beim naechsten Oeffnen', (tester) async {
        await fill();
        await HouseholdPrefsRepository(db, householdId: () async => 'h1').set(aislePrefFor('s1'), ['c-milch', 'c-brot']);
        await db.setKv('shopping_sort_store', 's1');
        await open(tester, products: products);
        expect(headings(tester), ['Milch', 'Backwaren', 'Gemüse', 'Ohne Kategorie'], reason: 'Milch und Brot nach Regal, Gemüse (nicht in der Reihenfolge) danach');
      });

      pageTest('eine gemerkte Auswahl ohne Reihenfolge (zurueckgesetzt) faellt auf alphabetisch zurueck', (tester) async {
        await fill();
        await db.setKv('shopping_sort_store', 's2');
        await open(tester, products: products);
        expect(headings(tester), ['Backwaren', 'Gemüse', 'Milch', 'Ohne Kategorie']);
      });
    });

    group('Bald aufgebraucht', () {
      Product product(String id, String name) => Product(
            id: id, householdId: 'h1', name: name, baseUnit: 'piece', defaultDateKind: 'best_before', defaultLocation: 'pantry', restock: false, updatedAt: DateTime.utc(2026),
          );

      UsageForecast due(String id, double daysLeft) =>
          UsageForecast(productId: id, dailyRate: 1, stock: daysLeft, unit: 'piece', observedDays: 30, consumptions: 6);

      pageTest('zeigt Produkte, die in hoechstens drei Tagen leer sind und auf keiner Liste stehen, ein Tipp setzt sie auf die gewaehlte Liste', (tester) async {
        forecasts = {'p1': due('p1', 2), 'p2': due('p2', 10), 'p3': due('p3', 1)};
        final l = await repo.createList('Drogerie');
        final listed = await repo.addManual(productId: 'p3', unit: 'piece');
        await open(tester, products: [product('p1', 'Milch'), product('p2', 'Reis'), product('p3', 'Butter')]);
        expect(find.byKey(const Key('forecast-p1')), findsOneWidget);
        expect(find.byKey(const Key('forecast-p2')), findsNothing, reason: 'reicht noch zehn Tage');
        expect(find.byKey(const Key('forecast-p3')), findsNothing, reason: 'steht schon auf der Liste');
        expect(find.text('reicht voraussichtlich noch etwa 2 Tage'), findsOneWidget);

        await tester.tap(find.byKey(Key('list-chip-${l.id}')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('forecast-add-p1')));
        await tester.pumpAndSettle();
        final added = (await items()).firstWhere((i) => i.productId == 'p1');
        expect(added.listId, l.id);
        expect(added.source, 'manual');
        expect(listed.listId, isNot(l.id));
      });

      pageTest('ohne faellige Produkte keine Karte', (tester) async {
        forecasts = {'p2': due('p2', 10)};
        await open(tester, products: [product('p2', 'Reis')]);
        expect(find.byKey(const Key('shopping-forecast')), findsNothing);
      });
    });
  });
}
