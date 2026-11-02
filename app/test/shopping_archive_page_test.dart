import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/features/shopping_list/shopping_archive_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  Widget app(List<ShoppingListItem> archived, {List<Product> products = const [], List<ShoppingList> lists = const []}) => ProviderScope(
        overrides: [
          shoppingListRepositoryProvider.overrideWithValue(shoppingListRepo(db)),
          archivedShoppingItemsStreamProvider.overrideWith((ref) => Stream.value(archived)),
          productsStreamProvider.overrideWith((ref) => Stream.value(products)),
          shoppingListsStreamProvider.overrideWith((ref) => Stream.value(lists)),
        ],
        child: const MaterialApp(home: ShoppingArchivePage()),
      );

  testWidgets('ohne Archiv: Hinweis', (tester) async {
    await tester.pumpWidget(app(const []));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shopping-archive-empty')), findsOneWidget);
  });

  testWidgets('zeigt den Einkauf mit Liste und Anzahl, aufgeklappt die Eintraege, und holt ihn zurueck', (tester) async {
    final repo = shoppingListRepo(db);
    final a = await repo.addManual(freeText: 'Milch');
    final b = await repo.addManual(freeText: 'Eier');
    await repo.setChecked(a.id, true);
    await repo.setChecked(b.id, true);
    await repo.archiveItems([a.id, b.id]);
    final rows = await db.select(db.shoppingListItems).get();
    final lists = await db.select(db.shoppingLists).get();

    await tester.pumpWidget(app(rows, lists: lists));
    await tester.pumpAndSettle();
    expect(find.text('Einkaufsliste · 2 Einträge'), findsOneWidget);
    expect(find.text('Milch'), findsNothing);

    await tester.tap(find.text('Einkaufsliste · 2 Einträge'));
    await tester.pumpAndSettle();
    expect(find.text('Milch'), findsOneWidget);
    expect(find.text('Eier'), findsOneWidget);

    await tester.tap(find.text('Zurück auf die Liste'));
    await tester.pumpAndSettle();
    expect((await db.select(db.shoppingListItems).get()).where((i) => i.archivedAt != null), isEmpty);
  });
}
