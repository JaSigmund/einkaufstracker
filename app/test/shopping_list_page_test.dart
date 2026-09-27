import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
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

  Widget app({List<ShoppingListItem> items = const [], List<Product> products = const [], List<Category> categories = const []}) =>
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          shoppingListRepositoryProvider.overrideWithValue(shoppingListRepo(db)),
          productRepositoryProvider.overrideWithValue(productRepo(db)),
          shoppingListItemsStreamProvider.overrideWith((ref) => Stream.value(items)),
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

    expect(find.text('2 kg'), findsOneWidget); // Anzahl (2 Packungen)
    expect(find.textContaining('insgesamt'), findsOneWidget);
    expect(find.textContaining('0,3 kg'), findsOneWidget); // 2 x 0,15 kg
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
}
