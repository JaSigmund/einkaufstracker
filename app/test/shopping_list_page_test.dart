import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/domain/inventory/usage_forecast.dart';
import 'package:einkaufstracker/features/shopping_list/shopping_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Wie an anderer Stelle im Projekt ueblich: die live aus der Datenbank lesenden Stream-Provider werden mit
/// einer Momentaufnahme ueberschrieben, sonst haelt der echte Drift-Stream `pumpAndSettle()` endlos
/// beschaeftigt. Aktionen werden deshalb nicht ueber die UI-Reaktion geprueft, sondern ueber die Datenbank.
void main() {
  late AppDatabase db;

  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  Widget app({
    List<ShoppingListItem> items = const [],
    List<Product> products = const [],
    List<Category> categories = const [],
    List<ReceiptItem> receiptItems = const [],
    List<Receipt> receipts = const [],
    List<ShoppingList> lists = const [],
    Map<String, UsageForecast> forecasts = const {},
    List<Store> stores = const [],
  }) =>
      ProviderScope(
        overrides: [
          allItemsStreamProvider.overrideWith((ref) => Stream.value(receiptItems)),
          receiptsStreamProvider.overrideWith((ref) => Stream.value(receipts)),
          databaseProvider.overrideWithValue(db),
          shoppingListRepositoryProvider.overrideWithValue(shoppingListRepo(db)),
          productRepositoryProvider.overrideWithValue(productRepo(db)),
          shoppingListItemsStreamProvider.overrideWith((ref) => Stream.value(items)),
          shoppingListsStreamProvider.overrideWith((ref) => Stream.value(lists)),
          usageForecastProvider.overrideWithValue(forecasts),
          storesStreamProvider.overrideWith((ref) => Stream.value(stores)),
          productsStreamProvider.overrideWith((ref) => Stream.value(products)),
          categoriesStreamProvider.overrideWith((ref) => Stream.value(categories)),
        ],
        child: const MaterialApp(home: ShoppingListPage()),
      );

  testWidgets('leere Liste: Hinweistext', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shopping-list-empty')), findsOneWidget);
  });

  testWidgets('Einkauf abschliessen archiviert nur das Abgehakte, Rueckgaengig holt es zurueck', (tester) async {
    final repo = shoppingListRepo(db);
    final bought = await repo.addManual(freeText: 'Milch');
    final open = await repo.addManual(freeText: 'Brot');
    await repo.setChecked(bought.id, true);
    final items = await db.select(db.shoppingListItems).get();

    await tester.pumpWidget(app(items: items));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('finish-purchase')));
    await tester.pumpAndSettle();

    Future<ShoppingListItem> row(String id) => (db.select(db.shoppingListItems)..where((i) => i.id.equals(id))).getSingle();
    expect((await row(bought.id)).archivedAt, isNotNull);
    expect((await row(open.id)).archivedAt, isNull);
    expect(find.text('Ein Eintrag archiviert'), findsOneWidget);

    await tester.tap(find.text('Rückgängig'));
    await tester.pumpAndSettle();
    expect((await row(bought.id)).archivedAt, isNull);
    expect((await row(bought.id)).checked, isTrue);
  });

  testWidgets('ohne Abgehaktes gibt es nichts abzuschliessen', (tester) async {
    await shoppingListRepo(db).addManual(freeText: 'Brot');
    await tester.pumpWidget(app(items: await db.select(db.shoppingListItems).get()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('finish-purchase')), findsNothing);
    expect(find.byKey(const Key('open-shopping-archive')), findsOneWidget);
  });

  testWidgets('manuell per Freitext hinzufuegen', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('shopping-list-input')), 'Klopapier');
    await tester.tap(find.byKey(const Key('shopping-list-add')));
    await tester.pumpAndSettle();

    final rows = await db.select(db.shoppingListItems).get();
    expect(rows, hasLength(1));
    expect(rows.single.freeText, 'Klopapier');
    expect(rows.single.source, 'manual');
  });

  testWidgets('Anzahl vor dem Hinzufuegen anpassen (Wunsch "Menge angeben", 2026-09-28)', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-quantity-plus')));
    await tester.tap(find.byKey(const Key('add-quantity-plus')));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget); // Startwert 1 + zweimal +1

    await tester.enterText(find.byKey(const Key('shopping-list-input')), 'Toilettenpapier');
    await tester.tap(find.byKey(const Key('shopping-list-add')));
    await tester.pumpAndSettle();

    final row = await (db.select(db.shoppingListItems)..where((i) => i.freeText.equals('Toilettenpapier'))).getSingle();
    expect(row.quantity, 3);
    // Anzahl setzt sich nach dem Hinzufuegen wieder auf 1 zurueck, statt fuer den naechsten Artikel zu bleiben
    expect(tester.widget<Text>(find.byKey(const Key('add-quantity-value'))).data, '1');
  });

  testWidgets('Gesamtmenge wird angezeigt, wenn das Produkt einen Inhalt (packSize) hat', (tester) async {
    final product = Product(
      id: 'p1',
      householdId: 'h1',
      name: 'Champignons',
      baseUnit: 'kg',
      packSize: 0.15,
      defaultDateKind: 'best_before',
      defaultLocation: 'fridge',
      restock: false,
      updatedAt: DateTime.utc(2026),
    );
    final items = [
      ShoppingListItem(id: 'i1', householdId: 'h1', listId: 'l1', productId: 'p1', quantity: 2, unit: 'kg', checked: false, source: 'manual', isSuggestion: false, updatedAt: DateTime.utc(2026)),
    ];
    await tester.pumpWidget(app(items: items, products: [product]));
    await tester.pumpAndSettle();

    expect(find.text('2 × 150 g'), findsOneWidget); // 2 Packungen zu je 150 g
    expect(find.text('insgesamt 300 g'), findsOneWidget);
  });

  testWidgets('Fehlerbericht Yakult: eine Packung mit 0,29 l zeigt weder "1 l" noch einen Widerspruch', (tester) async {
    final product = Product(id: 'p1', householdId: 'h1', name: 'Yakult', baseUnit: 'l', packSize: 0.29, restock: false, defaultDateKind: 'best_before', defaultLocation: 'pantry', updatedAt: DateTime.utc(2026));
    final items = [
      ShoppingListItem(id: 'i1', householdId: 'h1', listId: 'l1', productId: 'p1', quantity: 1, unit: 'l', checked: false, source: 'manual', isSuggestion: false, updatedAt: DateTime.utc(2026)),
    ];
    await tester.pumpWidget(app(items: items, products: [product]));
    await tester.pumpAndSettle();
    expect(find.text('1 × 290 ml'), findsOneWidget);
    expect(find.text('1 l'), findsNothing);
    expect(find.textContaining('insgesamt'), findsNothing);
  });

  testWidgets('Menge statt Packungen eingeben: wird in Packungen gespeichert und so angezeigt', (tester) async {
    final product = Product(id: 'p1', householdId: 'h1', name: 'Mehl', baseUnit: 'kg', packSize: 0.5, restock: false, defaultDateKind: 'best_before', defaultLocation: 'pantry', updatedAt: DateTime.utc(2026));
    final item = ShoppingListItem(id: 'i1', householdId: 'h1', listId: 'l1', productId: 'p1', quantity: 1, unit: 'kg', checked: false, source: 'manual', isSuggestion: false, updatedAt: DateTime.utc(2026));
    await db.into(db.shoppingLists).insert(ShoppingList(id: 'l1', householdId: 'h1', name: 'Einkaufsliste', isDefault: true, updatedAt: DateTime.utc(2026)));
    await db.into(db.shoppingListItems).insert(item);
    await tester.pumpWidget(app(items: [item], products: [product]));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('shopping-item-quantity-i1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Menge').last);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('shopping-item-quantity-input'))).controller!.text, '500');
    await tester.enterText(find.byKey(const Key('shopping-item-quantity-input')), '150');
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();

    final row = await (db.select(db.shoppingListItems)..where((i) => i.id.equals('i1'))).getSingle();
    expect(row.quantity, 0.3);
    expect(row.unit, 'kg');
  });

  testWidgets('Frei getippter Eintrag: Einheit waehlbar, 0 wird abgelehnt', (tester) async {
    final item = ShoppingListItem(id: 'i1', householdId: 'h1', listId: 'l1', freeText: 'Hackfleisch', quantity: 1, unit: 'piece', checked: false, source: 'manual', isSuggestion: false, updatedAt: DateTime.utc(2026));
    await db.into(db.shoppingLists).insert(ShoppingList(id: 'l1', householdId: 'h1', name: 'Einkaufsliste', isDefault: true, updatedAt: DateTime.utc(2026)));
    await db.into(db.shoppingListItems).insert(item);
    await tester.pumpWidget(app(items: [item]));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('shopping-item-quantity-i1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('shopping-item-quantity-input')), '0');
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(find.text('Bitte eine Menge größer als 0 eingeben'), findsOneWidget);

    await tester.tap(find.byKey(const Key('shopping-item-quantity-unit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('g').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('shopping-item-quantity-input')), '250');
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();

    final row = await (db.select(db.shoppingListItems)..where((i) => i.id.equals('i1'))).getSingle();
    expect(row.quantity, 0.25);
    expect(row.unit, 'kg');
  });

  testWidgets('ohne Inhalt (packSize): keine Gesamtmenge-Zeile', (tester) async {
    final items = [
      ShoppingListItem(id: 'i1', householdId: 'h1', listId: 'l1', freeText: 'Brot', quantity: 1, unit: 'piece', checked: false, source: 'manual', isSuggestion: false, updatedAt: DateTime.utc(2026)),
    ];
    await tester.pumpWidget(app(items: items));
    await tester.pumpAndSettle();
    expect(find.textContaining('insgesamt'), findsNothing);
  });

  testWidgets('Anzahl eines bestehenden Eintrags bearbeiten', (tester) async {
    final items = [
      ShoppingListItem(id: 'i1', householdId: 'h1', listId: 'l1', freeText: 'Milch', quantity: 1, unit: 'piece', checked: false, source: 'manual', isSuggestion: false, updatedAt: DateTime.utc(2026)),
    ];
    await db.into(db.shoppingLists).insert(ShoppingList(id: 'l1', householdId: 'h1', name: 'Einkaufsliste', isDefault: true, updatedAt: DateTime.utc(2026)));
    await db.into(db.shoppingListItems).insert(items.single);
    await tester.pumpWidget(app(items: items));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('shopping-item-quantity-i1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('shopping-item-quantity-input')), '4');
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();

    final row = await (db.select(db.shoppingListItems)..where((i) => i.id.equals('i1'))).getSingle();
    expect(row.quantity, 4);
  });

  testWidgets('gruppiert nach Kategorie, Ohne-Kategorie-Artikel zuletzt', (tester) async {
    final cat = Category(id: 'c1', householdId: 'h1', name: 'Milchprodukte', sortOrder: 0, isStorable: true, updatedAt: DateTime.utc(2026));
    final product = Product(
      id: 'p1',
      householdId: 'h1',
      name: 'Vollmilch',
      categoryId: 'c1',
      baseUnit: 'l',
      defaultDateKind: 'best_before',
      defaultLocation: 'fridge',
      restock: true,
      updatedAt: DateTime.utc(2026),
    );
    final items = [
      ShoppingListItem(id: 'i1', householdId: 'h1', listId: 'l1', productId: 'p1', quantity: 1, unit: 'l', checked: false, source: 'manual', isSuggestion: false, updatedAt: DateTime.utc(2026)),
      ShoppingListItem(id: 'i2', householdId: 'h1', listId: 'l1', freeText: 'Klopapier', quantity: 1, unit: 'piece', checked: false, source: 'manual', isSuggestion: false, updatedAt: DateTime.utc(2026)),
    ];
    await tester.pumpWidget(app(items: items, products: [product], categories: [cat]));
    await tester.pumpAndSettle();

    expect(find.text('Milchprodukte'), findsOneWidget);
    expect(find.text('Ohne Kategorie'), findsOneWidget);
    expect(find.text('Vollmilch'), findsOneWidget);
    expect(find.text('Klopapier'), findsOneWidget);
  });

  testWidgets('abgehakte Artikel erscheinen unter "Erledigt"', (tester) async {
    final items = [
      ShoppingListItem(id: 'i1', householdId: 'h1', listId: 'l1', freeText: 'Milch', quantity: 1, unit: 'piece', checked: true, source: 'manual', isSuggestion: false, updatedAt: DateTime.utc(2026)),
    ];
    await tester.pumpWidget(app(items: items));
    await tester.pumpAndSettle();
    expect(find.textContaining('Erledigt'), findsOneWidget);
  });

  testWidgets('Checkbox hakt ab (in der Datenbank)', (tester) async {
    final items = [
      ShoppingListItem(id: 'i1', householdId: 'h1', listId: 'l1', freeText: 'Milch', quantity: 1, unit: 'piece', checked: false, source: 'manual', isSuggestion: false, updatedAt: DateTime.utc(2026)),
    ];
    await db.into(db.shoppingLists).insert(ShoppingList(id: 'l1', householdId: 'h1', name: 'Einkaufsliste', isDefault: true, updatedAt: DateTime.utc(2026)));
    await db.into(db.shoppingListItems).insert(items.single);
    await tester.pumpWidget(app(items: items));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('shopping-item-i1')));
    await tester.pumpAndSettle();

    final row = await (db.select(db.shoppingListItems)..where((i) => i.id.equals('i1'))).getSingle();
    expect(row.checked, isTrue);
  });

  testWidgets('Vorschlag bestaetigen setzt isSuggestion auf false', (tester) async {
    final items = [
      ShoppingListItem(id: 'i1', householdId: 'h1', listId: 'l1', freeText: 'Milch', quantity: 1, unit: 'piece', checked: false, source: 'depleted', isSuggestion: true, updatedAt: DateTime.utc(2026)),
    ];
    await db.into(db.shoppingLists).insert(ShoppingList(id: 'l1', householdId: 'h1', name: 'Einkaufsliste', isDefault: true, updatedAt: DateTime.utc(2026)));
    await db.into(db.shoppingListItems).insert(items.single);
    await tester.pumpWidget(app(items: items));
    await tester.pumpAndSettle();

    expect(find.text('Vorschläge'), findsOneWidget);
    await tester.tap(find.byKey(const Key('suggestion-add-i1')));
    await tester.pumpAndSettle();

    final row = await (db.select(db.shoppingListItems)..where((i) => i.id.equals('i1'))).getSingle();
    expect(row.isSuggestion, isFalse);
  });

  testWidgets('Vorschlag verwerfen loescht ihn', (tester) async {
    final items = [
      ShoppingListItem(id: 'i1', householdId: 'h1', listId: 'l1', freeText: 'Milch', quantity: 1, unit: 'piece', checked: false, source: 'depleted', isSuggestion: true, updatedAt: DateTime.utc(2026)),
    ];
    await db.into(db.shoppingLists).insert(ShoppingList(id: 'l1', householdId: 'h1', name: 'Einkaufsliste', isDefault: true, updatedAt: DateTime.utc(2026)));
    await db.into(db.shoppingListItems).insert(items.single);
    await tester.pumpWidget(app(items: items));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('suggestion-dismiss-i1')));
    await tester.pumpAndSettle();

    final row = await (db.select(db.shoppingListItems)..where((i) => i.id.equals('i1'))).getSingle();
    expect(row.deletedAt, isNotNull);
  });

  group('Summenschaetzung (ADR-030)', () {
    Product product(String id, {double? packSize, String baseUnit = 'kg'}) => Product(
          id: id, householdId: 'h1', name: 'Produkt $id', baseUnit: baseUnit, packSize: packSize,
          defaultDateKind: 'best_before', defaultLocation: 'pantry', restock: false, updatedAt: DateTime.utc(2026),
        );

    ShoppingListItem item(String id, {String? productId, String? freeText, double quantity = 1, bool checked = false, bool suggestion = false}) => ShoppingListItem(
          id: id, householdId: 'h1', listId: 'l1', productId: productId, freeText: freeText, quantity: quantity, unit: 'kg',
          checked: checked, source: 'manual', isSuggestion: suggestion, updatedAt: DateTime.utc(2026),
        );

    Receipt receipt(String id, DateTime at) => Receipt(
          id: id, householdId: 'h1', purchasedAt: at, totalCents: 100, status: 'confirmed', source: 'manual', sumMismatch: false, updatedAt: DateTime.utc(2026),
        );

    ReceiptItem bought(String id, String receiptId, String productId, int unitPriceNormCents) => ReceiptItem(
          excluded: false, id: id, householdId: 'h1', receiptId: receiptId, lineNo: 1, kind: 'article', rawText: 'x', productId: productId,
          quantity: 1, quantityUnit: 'kg', lineTotalCents: unitPriceNormCents, unitPriceNormCents: unitPriceNormCents, needsReview: false, updatedAt: DateTime.utc(2026),
        );

    String total(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('shopping-estimate-total'))).data!;

    testWidgets('ohne bekannten Preis keine Karte', (tester) async {
      await tester.pumpWidget(app(items: [item('i1', productId: 'p1')], products: [product('p1')]));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shopping-estimate')), findsNothing);
    });

    testWidgets('Packung mit Inhalt: Anzahl mal Inhalt mal Grundpreis, in Euro', (tester) async {
      // 2 Packungen a 0,5 kg, Grundpreis 600 Cent/kg -> 1 kg * 600 = 6,00 EUR
      await tester.pumpWidget(app(
        items: [item('i1', productId: 'p1', quantity: 2)],
        products: [product('p1', packSize: 0.5)],
        receipts: [receipt('r1', DateTime.utc(2026, 9, 1))],
        receiptItems: [bought('ri1', 'r1', 'p1', 600)],
      ));
      await tester.pumpAndSettle();
      expect(total(tester), 'Noch zu kaufen: ca. 6,00 €');
      expect(find.byKey(const Key('shopping-estimate-missing')), findsNothing);
    });

    testWidgets('der neueste Kauf gibt den Preis, egal in welcher Reihenfolge die Positionen kommen', (tester) async {
      await tester.pumpWidget(app(
        items: [item('i1', productId: 'p1')],
        products: [product('p1')],
        receipts: [receipt('neu', DateTime.utc(2026, 9, 20)), receipt('alt', DateTime.utc(2026, 8, 1))],
        receiptItems: [bought('a', 'neu', 'p1', 250), bought('b', 'alt', 'p1', 999)],
      ));
      await tester.pumpAndSettle();
      expect(total(tester), 'Noch zu kaufen: ca. 2,50 €');
    });

    testWidgets('Eintraege ohne Preis (neues Produkt, Freitext) werden genannt, nicht eingerechnet', (tester) async {
      await tester.pumpWidget(app(
        items: [item('i1', productId: 'p1'), item('i2', productId: 'p2'), item('i3', freeText: 'Klopapier')],
        products: [product('p1'), product('p2')],
        receipts: [receipt('r1', DateTime.utc(2026, 9, 1))],
        receiptItems: [bought('a', 'r1', 'p1', 300)],
      ));
      await tester.pumpAndSettle();
      expect(total(tester), 'Noch zu kaufen: ca. 3,00 €');
      expect(tester.widget<Text>(find.byKey(const Key('shopping-estimate-missing'))).data, '2 Artikel ohne bekannten Preis sind nicht eingerechnet.');
    });

    testWidgets('ein Eintrag ohne Preis: Einzahl', (tester) async {
      await tester.pumpWidget(app(
        items: [item('i1', productId: 'p1'), item('i3', freeText: 'Klopapier')],
        products: [product('p1')],
        receipts: [receipt('r1', DateTime.utc(2026, 9, 1))],
        receiptItems: [bought('a', 'r1', 'p1', 300)],
      ));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('shopping-estimate-missing'))).data, '1 Artikel ohne bekannten Preis ist nicht eingerechnet.');
    });

    testWidgets('abgehakte Eintraege und Vorschlaege zaehlen nicht ("noch zu kaufen")', (tester) async {
      await tester.pumpWidget(app(
        items: [item('i1', productId: 'p1'), item('i2', productId: 'p2', checked: true), item('i3', productId: 'p3', suggestion: true)],
        products: [product('p1'), product('p2'), product('p3')],
        receipts: [receipt('r1', DateTime.utc(2026, 9, 1))],
        receiptItems: [bought('a', 'r1', 'p1', 100), bought('b', 'r1', 'p2', 5000), bought('c', 'r1', 'p3', 7000)],
      ));
      await tester.pumpAndSettle();
      expect(total(tester), 'Noch zu kaufen: ca. 1,00 €');
    });

    testWidgets('sind alle Eintraege abgehakt, verschwindet die Karte', (tester) async {
      await tester.pumpWidget(app(
        items: [item('i1', productId: 'p1', checked: true)],
        products: [product('p1')],
        receipts: [receipt('r1', DateTime.utc(2026, 9, 1))],
        receiptItems: [bought('a', 'r1', 'p1', 100)],
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shopping-estimate')), findsNothing);
    });
  });
}
