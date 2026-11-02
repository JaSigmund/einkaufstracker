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

Product _product(String id, String name) => Product(
      id: id,
      householdId: 'h1',
      name: name,
      baseUnit: 'piece',
      defaultDateKind: 'best_before',
      defaultLocation: 'pantry',
      restock: false,
      updatedAt: DateTime.utc(2026),
    );

void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  Widget app({List<InventoryItem> active = const [], List<Product> products = const []}) => ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          savedRecipeRepositoryProvider.overrideWithValue(SavedRecipeRepository(db)),
          activeInventoryStreamProvider.overrideWith((ref) => Stream.value(active)),
          productsStreamProvider.overrideWith((ref) => Stream.value(products)),
          shoppingListRepositoryProvider.overrideWithValue(shoppingListRepo(db)),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(initialLocation: '/', routes: [
            GoRoute(path: '/', builder: (_, _) => const SavedRecipesPage()),
            GoRoute(
              path: '/recipe-form',
              builder: (_, state) => Scaffold(body: Text('FORM: ${(state.extra as SavedRecipe?)?.title ?? 'neu'}')),
            ),
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
      ingredients: const [SavedIngredient(productId: 'p1', name: 'Kürbis', unit: 'piece')],
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
        SavedIngredient(productId: 'p1', name: 'Kürbis', unit: 'piece'), // im Inventar vorhanden
        SavedIngredient(productId: 'p2', name: 'Sahne', unit: 'piece'), // fehlt
        SavedIngredient(productId: null, name: 'Muskat', unit: 'piece'), // kein Produkt dieses Namens -> fehlt als freier Text
        SavedIngredient(productId: null, name: 'zwiebel', unit: 'piece'), // frei getippt, aber ueber den Namen im Inventar gefunden
      ],
      savedAt: DateTime.utc(2026, 10, 1),
    ));

    await tester.pumpWidget(app(
      active: [_item('i1', 'p1'), _item('i2', 'p3')],
      products: [_product('p1', 'Kürbis'), _product('p2', 'Sahne'), _product('p3', 'Zwiebel')],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-missing-r1')));
    await tester.pumpAndSettle();

    final items = await (db.select(db.shoppingListItems)).get();
    expect(items, hasLength(2));
    expect(items.map((i) => i.productId ?? i.freeText), containsAll(['p2', 'Muskat']));
    expect(find.text('2 Zutaten auf die Einkaufsliste gesetzt.'), findsOneWidget);
  });

  testWidgets('Codereview-Fund 2026-10-01: schon ein kleiner Bestand gilt als vorhanden, es wird keine Menge geraten', (tester) async {
    await SavedRecipeRepository(db).save(SavedRecipe(
      id: 'r1',
      title: 'Kürbissuppe',
      sourceUrl: '',
      ingredients: const [SavedIngredient(productId: 'p1', name: 'Kürbis', unit: 'piece')],
      savedAt: DateTime.utc(2026, 10, 1),
    ));

    // Nur ein winziger Rest im Inventar -- koennte fuer das Rezept zu wenig sein, das weiss die App nicht
    // und darf deshalb nicht trotzdem "fehlend" melden (frueherer Fehler: der beim Speichern vorhandene
    // Bestand wurde faelschlich als Rezeptbedarf behandelt).
    await tester.pumpWidget(app(active: [_item('i1', 'p1', quantity: 0.1)], products: [_product('p1', 'Kürbis')]));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-missing-r1')));
    await tester.pumpAndSettle();

    expect(await db.select(db.shoppingListItems).get(), isEmpty);
    expect(find.textContaining('Schon alles im Haus'), findsOneWidget);
  });

  testWidgets('eigenes Rezept ohne Link oeffnet das Formular statt des Viewers, der Knopf legt ein neues an', (tester) async {
    await SavedRecipeRepository(db).save(SavedRecipe(
      id: 'r1',
      title: 'Omas Lasagne',
      sourceUrl: '',
      ingredients: const [],
      notes: 'Mit viel Käse',
      savedAt: DateTime.utc(2026, 10, 1),
    ));

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.textContaining('eigenes Rezept'), findsOneWidget);

    await tester.tap(find.text('Omas Lasagne'));
    await tester.pumpAndSettle();
    expect(find.text('FORM: Omas Lasagne'), findsOneWidget);

    final router = GoRouter.of(tester.element(find.text('FORM: Omas Lasagne')));
    router.pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-own-recipe')));
    await tester.pumpAndSettle();
    expect(find.text('FORM: neu'), findsOneWidget);
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
