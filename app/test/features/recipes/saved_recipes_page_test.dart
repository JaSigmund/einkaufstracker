import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/saved_recipe_repository.dart';
import 'package:einkaufstracker/domain/recipes/saved_recipe.dart';
import 'package:einkaufstracker/features/recipes/recipe_viewer_page.dart';
import 'package:einkaufstracker/features/recipes/saved_recipes_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fakes.dart';

InventoryItem _item(String id, String productId, {double quantity = 1}) => InventoryItem(
      id: id,
      householdId: 'h1',
      productId: productId,
      quantity: quantity,
      unit: 'piece',
      location: 'pantry',
      dateKind: 'best_before',
      status: 'sealed',
      isSuggestion: false,
      updatedAt: DateTime.utc(2026),
    );

void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  Widget app({List<InventoryItem> active = const []}) => ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          savedRecipeRepositoryProvider.overrideWithValue(SavedRecipeRepository(db)),
          activeInventoryStreamProvider.overrideWith((ref) => Stream.value(active)),
          shoppingListRepositoryProvider.overrideWithValue(shoppingListRepo(db)),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(initialLocation: '/', routes: [
            GoRoute(path: '/', builder: (_, _) => const SavedRecipesPage()),
            GoRoute(
              path: '/recipe-viewer',
              builder: (_, state) {
                final a = state.extra as RecipeViewerArgs;
                return Scaffold(body: Text('VIEWER: ${a.title}'));
              },
            ),
          ]),
        ),
      );

  testWidgets('ohne gespeicherte Rezepte: Hinweistext', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.textContaining('Noch keine Rezepte gespeichert'), findsOneWidget);
  });

  testWidgets('zeigt gespeicherte Rezepte, Tippen oeffnet den Viewer', (tester) async {
    await SavedRecipeRepository(db).save(SavedRecipe(
      id: 'r1',
      title: 'Kürbissuppe',
      sourceUrl: 'https://example.test',
      ingredients: const [SavedIngredient(productId: 'p1', name: 'Kürbis', quantity: 1, unit: 'piece')],
      savedAt: DateTime.utc(2026, 10, 1),
    ));

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Kürbissuppe'), findsOneWidget);
    await tester.tap(find.text('Kürbissuppe'));
    await tester.pumpAndSettle();

    expect(find.text('VIEWER: Kürbissuppe'), findsOneWidget);
  });

  testWidgets('fehlende Zutaten werden zur Einkaufsliste hinzugefuegt', (tester) async {
    await SavedRecipeRepository(db).save(SavedRecipe(
      id: 'r1',
      title: 'Kürbissuppe',
      sourceUrl: '',
      ingredients: const [
        SavedIngredient(productId: 'p1', name: 'Kürbis', quantity: 1, unit: 'piece'), // im Inventar vorhanden
        SavedIngredient(productId: 'p2', name: 'Sahne', quantity: 1, unit: 'piece'), // fehlt
        SavedIngredient(productId: null, name: 'Muskat', quantity: 1, unit: 'piece'), // keine Produkt-Zuordnung -> immer fehlend
      ],
      savedAt: DateTime.utc(2026, 10, 1),
    ));

    await tester.pumpWidget(app(active: [_item('i1', 'p1')]));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-missing-r1')));
    await tester.pumpAndSettle();

    final items = await (db.select(db.shoppingListItems)).get();
    expect(items, hasLength(2));
    expect(items.map((i) => i.productId ?? i.freeText), containsAll(['p2', 'Muskat']));
    expect(find.textContaining('2 fehlende Zutat'), findsOneWidget);
  });

  testWidgets('loeschen entfernt das Rezept aus der Liste', (tester) async {
    await SavedRecipeRepository(db).save(SavedRecipe(
      id: 'r1',
      title: 'Kürbissuppe',
      sourceUrl: '',
      ingredients: const [],
      savedAt: DateTime.utc(2026, 10, 1),
    ));

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Kürbissuppe'), findsOneWidget);

    await tester.tap(find.byKey(const Key('delete-recipe-r1')));
    await tester.pumpAndSettle();

    expect(find.text('Kürbissuppe'), findsNothing);
    expect(find.textContaining('Noch keine Rezepte gespeichert'), findsOneWidget);
  });
}
