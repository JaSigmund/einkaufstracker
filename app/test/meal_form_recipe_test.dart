import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/core/clock.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/meal_repository.dart';
import 'package:einkaufstracker/data/repositories/saved_recipe_repository.dart';
import 'package:einkaufstracker/domain/nutrition/ingredient_nutrition.dart';
import 'package:einkaufstracker/domain/nutrition/nutrient_scaling.dart';
import 'package:einkaufstracker/domain/recipes/saved_recipe.dart';
import 'package:einkaufstracker/features/diary/meal_form_page.dart';
import 'package:einkaufstracker/features/diary/recipe_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';

/// Rezepte und geplante Gerichte im Tagebuch (ADR-047).
void formTest(String name, Future<void> Function(WidgetTester tester) body) => testWidgets(name, (tester) async {
      tester.view.physicalSize = const Size(1000, 3000);
      addTearDown(tester.view.resetPhysicalSize);
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

SavedRecipe _recipe({List<SavedIngredient> ingredients = const [SavedIngredient(productId: null, name: 'Linsen', unit: 'kg'), SavedIngredient(productId: null, name: 'Zwiebel', unit: 'piece')]}) =>
    SavedRecipe(id: 'r1', title: 'Linsencurry', sourceUrl: '', ingredients: ingredients, savedAt: DateTime.utc(2026, 10, 1));

void main() {
  late AppDatabase db;
  late MealRepository meals;
  var products = <Product>[];
  var inventory = <InventoryItem>[];
  var plan = <MealPlanEntry>[];

  setUp(() {
    db = memoryDb();
    meals = mealRepo(db);
    products = [];
    inventory = [];
    plan = [];
  });
  tearDown(() => db.close());

  Widget host({RecipeForMeal? recipe}) => ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          mealRepositoryProvider.overrideWithValue(meals),
          productRepositoryProvider.overrideWithValue(productRepo(db)),
          inventoryRepositoryProvider.overrideWithValue(inventoryRepo(db)),
          foodLinkRepositoryProvider.overrideWithValue(foodLinkRepo(db)),
          foodUnitsSourceProvider.overrideWithValue(FakeFoodUnitsSource()),
          productsStreamProvider.overrideWith((ref) => Stream.value(products)),
          activeInventoryStreamProvider.overrideWith((ref) => Stream.value(inventory)),
          mealPhotoServiceProvider.overrideWithValue(FakeMealPhotoService(db, meals)),
          blsFoodSearchProvider.overrideWithValue(FakeBlsFoodSearch()),
          savedRecipeRepositoryProvider.overrideWithValue(SavedRecipeRepository(db)),
          mealPlanStreamProvider.overrideWith((ref) => Stream.value(plan)),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(routes: [
            GoRoute(path: '/', builder: (context, _) => Scaffold(body: TextButton(onPressed: () => context.push('/form'), child: const Text('START')))),
            GoRoute(path: '/form', builder: (_, _) => MealFormPage(recipe: recipe, photosAvailable: false)),
          ]),
        ),
      );

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> open(WidgetTester tester, {RecipeForMeal? recipe}) async {
    await tester.pumpWidget(host(recipe: recipe));
    await tester.pump();
    await tester.tap(find.text('START'));
    await settle(tester);
  }

  Future<List<MealIngredient>> savedIngredients() async {
    final meal = (await db.select(db.meals).get()).firstWhere((m) => m.source == 'recipe');
    return meals.ingredientsOf(meal.id);
  }

  formTest('aus dem Formular: Rezept waehlen fuellt Titel und Zutaten, ohne Mengen sperrt das Speichern', (tester) async {
    await SavedRecipeRepository(db).save(_recipe());
    await open(tester);

    await tester.tap(find.byKey(const Key('meal-from-recipe')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('pick-recipe-r1')));
    await settle(tester);

    expect(find.widgetWithText(TextField, 'Linsencurry'), findsOneWidget);
    expect(find.text('Linsen'), findsOneWidget);
    expect(find.text('Zwiebel'), findsOneWidget);
    expect(find.textContaining('Bei 2 Zutaten fehlt sie noch'), findsOneWidget);

    await tester.tap(find.byKey(const Key('meal-save')));
    await settle(tester);
    expect(find.textContaining('fehlt die Menge'), findsOneWidget);
    expect(await db.select(db.meals).get(), isEmpty);
  });

  formTest('Zutaten ohne Menge weglassen: speichert mit Herkunft Rezept', (tester) async {
    await open(tester, recipe: RecipeForMeal.fromSaved(_recipe()));

    await tester.tap(find.byKey(const Key('meal-recipe-drop-empty')));
    await settle(tester);
    expect(find.text('Linsen'), findsNothing);

    await tester.tap(find.byKey(const Key('meal-save')));
    await settle(tester);
    final meal = (await db.select(db.meals).get()).single;
    expect(meal.title, 'Linsencurry');
    expect(meal.source, 'recipe');
    expect(await meals.ingredientsOf(meal.id), isEmpty);
  });

  formTest('gab es das Gericht schon: Mengen und Portionen vom letzten Mal, Neues aus dem Rezept kommt dazu', (tester) async {
    await meals.create(MealDraft(title: 'linsencurry ', eatenAt: DateTime.utc(2026, 10, 1, 18), servingsEaten: 1, servingsMade: 4, ingredients: const [
      IngredientDraft(freeText: 'Linsen', quantity: 300, entryUnit: EntryUnit.g, per100: NutrientsPer100(kcal: 340), per100Basis: 'g'),
      IngredientDraft(freeText: 'Kokosmilch', quantity: 400, entryUnit: EntryUnit.ml, per100: NutrientsPer100(kcal: 180), per100Basis: 'g'),
    ]));
    await meals.create(MealDraft(title: 'Linsencurry', eatenAt: DateTime.utc(2026, 9, 1, 18), ingredients: const [
      IngredientDraft(freeText: 'Linsen', quantity: 999, entryUnit: EntryUnit.g),
    ]));
    await open(tester, recipe: RecipeForMeal.fromSaved(_recipe()));

    expect(find.byKey(const Key('meal-recipe-amounts-from')), findsOneWidget);
    expect(find.textContaining('300 g'), findsOneWidget, reason: 'die juengste Mahlzeit zaehlt');
    expect(find.text('Kokosmilch'), findsOneWidget, reason: 'was man damals dazugegeben hat, bleibt');
    expect(find.text('Zwiebel'), findsOneWidget);
    expect(find.textContaining('Bei einer Zutat fehlt sie noch'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('meal-servings-made'))).controller!.text, '4');
  });

  formTest('Produkt wird ueber Kennung oder Namen gefunden, Abzug nur bei Bestand', (tester) async {
    final repo = productRepo(db);
    final linsen = await repo.create(name: 'Linsen', baseUnit: 'kg');
    final zwiebel = await repo.create(name: 'Zwiebel', baseUnit: 'piece');
    products = [linsen, zwiebel];
    inventory = [
      InventoryItem(id: 'i1', householdId: 'h1', productId: zwiebel.id, quantity: 3, unit: 'piece', location: 'pantry', dateKind: 'best_before', status: 'sealed', isSuggestion: false, updatedAt: DateTime.utc(2026)),
    ];
    await open(tester, recipe: RecipeForMeal.fromSaved(_recipe(ingredients: [
      SavedIngredient(productId: zwiebel.id, name: 'Zwiebeln, rot', unit: 'piece'),
      const SavedIngredient(productId: null, name: 'linsen', unit: 'kg'),
    ])));

    expect(find.text('Zwiebel'), findsOneWidget, reason: 'ueber die Kennung');
    expect(find.text('Linsen'), findsOneWidget, reason: 'ueber den Namen');
    expect(find.descendant(of: find.byKey(const Key('ingredient-row-0')), matching: find.textContaining('vom Bestand')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('ingredient-row-1')), matching: find.textContaining('vom Bestand')), findsNothing);
  });

  formTest('dieselbe Zutat kommt nicht doppelt, wenn das Formular sie schon hat', (tester) async {
    await open(tester, recipe: RecipeForMeal.fromSaved(_recipe(ingredients: const [
      SavedIngredient(productId: null, name: 'Reis', unit: 'kg'),
      SavedIngredient(productId: null, name: ' reis ', unit: 'kg'),
    ])));
    expect(find.text('Reis'), findsOneWidget);
    expect(find.byKey(const Key('ingredient-row-1')), findsNothing);
  });

  formTest('aus dem Wochenplan: Tageszeit wird uebernommen, was weit weg geplant ist, steht nicht zur Wahl', (tester) async {
    final now = appClock.now().toUtc();
    MealPlanEntry entry(String id, String title, DateTime day, String slot) => MealPlanEntry(
        id: id, householdId: 'h1', plannedOn: DateTime.utc(day.year, day.month, day.day), slot: slot, title: title,
        ingredients: '[{"productId":null,"name":"Nudeln","unit":"kg"}]', updatedAt: now);
    plan = [entry('near', 'Pasta', now, 'lunch'), entry('far', 'Später', now.add(const Duration(days: 10)), 'dinner')];
    await open(tester);

    await tester.tap(find.byKey(const Key('meal-from-recipe')));
    await settle(tester);
    expect(find.byKey(const Key('pick-plan-far')), findsNothing);
    await tester.tap(find.byKey(const Key('pick-plan-near')));
    await settle(tester);

    expect(find.text('Nudeln'), findsOneWidget);
    expect(tester.widget<ChoiceChip>(find.byKey(const Key('meal-type-lunch'))).selected, isTrue);
  });

  formTest('Suche im Auswahlfenster, leerer Treffer sagt es', (tester) async {
    await SavedRecipeRepository(db).save(_recipe());
    await open(tester);
    await tester.tap(find.byKey(const Key('meal-from-recipe')));
    await settle(tester);

    await tester.enterText(find.byKey(const Key('recipe-picker-search')), 'pizza');
    await tester.pump();
    expect(find.byKey(const Key('pick-recipe-r1')), findsNothing);
    expect(find.byKey(const Key('recipe-picker-empty')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('recipe-picker-search')), 'LINSEN');
    await tester.pump();
    expect(find.byKey(const Key('pick-recipe-r1')), findsOneWidget);
  });

  formTest('mit Mengen gespeichert: Zutat traegt die Menge', (tester) async {
    await meals.create(MealDraft(title: 'Linsencurry', eatenAt: DateTime.utc(2026, 10, 1, 18), ingredients: const [
      IngredientDraft(freeText: 'Linsen', quantity: 300, entryUnit: EntryUnit.g, per100: NutrientsPer100(kcal: 340), per100Basis: 'g'),
    ]));
    await open(tester, recipe: RecipeForMeal.fromSaved(_recipe(ingredients: const [SavedIngredient(productId: null, name: 'Linsen', unit: 'kg')])));
    await tester.tap(find.byKey(const Key('meal-save')));
    await settle(tester);
    final saved = await savedIngredients();
    expect(saved.single.freeText, 'Linsen');
    expect(saved.single.kcal, closeTo(1020, 0.01));
  });
}
