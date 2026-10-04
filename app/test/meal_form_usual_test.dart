import 'dart:typed_data';

import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/meal_repository.dart';
import 'package:einkaufstracker/domain/nutrition/ingredient_nutrition.dart';
import 'package:einkaufstracker/domain/nutrition/meal_analysis.dart';
import 'package:einkaufstracker/domain/nutrition/micros.dart';
import 'package:einkaufstracker/domain/nutrition/nutrient_scaling.dart';
import 'package:einkaufstracker/features/diary/meal_form_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;

import 'support/fakes.dart';

/// "Fehlt etwas?" im Formular nach der Foto-Analyse (Ausbau 1.12): uebliche Zutaten aus aehnlichen frueheren Mahlzeiten.
Uint8List _png() => Uint8List.fromList(img.encodePng(img.Image(width: 8, height: 8)));

void formTest(String name, Future<void> Function(WidgetTester tester) body) => testWidgets(name, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

void main() {
  late AppDatabase db;
  late MealRepository meals;
  late FakeMealPhotoService photos;
  late FakeMealAnalysisCloud cloud;
  var products = <Product>[];

  setUp(() {
    db = memoryDb();
    meals = mealRepo(db);
    photos = FakeMealPhotoService(db, meals);
    cloud = FakeMealAnalysisCloud();
    products = [];
  });
  tearDown(() => db.close());

  IngredientDraft food(String name, double grams, double kcal, {String? blsCode, Micros? micros}) => IngredientDraft(
        freeText: name,
        quantity: grams,
        entryUnit: EntryUnit.g,
        per100: NutrientsPer100(kcal: kcal),
        per100Basis: 'g',
        blsCode: blsCode,
        microsPer100: micros,
      );

  Future<Meal> past(String title, int day, List<IngredientDraft> ingredients) =>
      meals.create(MealDraft(title: title, eatenAt: DateTime.utc(2026, 9, day, 12), ingredients: ingredients));

  Future<void> threeRiceMeals({bool withOil = true}) async {
    for (var d = 1; d <= 3; d++) {
      await past('Reispfanne $d', d, [
        food('Reis', 150, 130),
        food('Paprika', 80, 31),
        if (withOil) food('Olivenöl', 8.0 + 2 * d, 884, blsCode: 'Q120000', micros: const {'vit_e_mg': 12.0}),
      ]);
    }
  }

  MealAnalysis photoOfRiceAndPepper() => const MealAnalysis(dishTitle: 'Reispfanne', ingredients: [
        AnalyzedIngredient(name: 'Reis', estimatedGrams: 160, confidence: 0.8),
        AnalyzedIngredient(name: 'Paprika', estimatedGrams: 90, confidence: 0.7),
      ]);

  Widget host({Meal? existing}) => ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          mealRepositoryProvider.overrideWithValue(meals),
          productRepositoryProvider.overrideWithValue(productRepo(db)),
          inventoryRepositoryProvider.overrideWithValue(inventoryRepo(db)),
          foodLinkRepositoryProvider.overrideWithValue(foodLinkRepo(db)),
          foodUnitsSourceProvider.overrideWithValue(FakeFoodUnitsSource()),
          productsStreamProvider.overrideWith((ref) => Stream.value(products)),
          activeInventoryStreamProvider.overrideWith((ref) => Stream.value(const <InventoryItem>[])),
          mealPhotoServiceProvider.overrideWithValue(photos),
          mealPhotoPickerProvider.overrideWithValue(({required bool camera}) async => _png()),
          mealAnalysisCloudProvider.overrideWithValue(cloud),
          blsFoodSearchProvider.overrideWithValue(FakeBlsFoodSearch()),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(routes: [
            GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('START'))),
            GoRoute(path: '/form', builder: (_, _) => MealFormPage(existing: existing)),
          ]),
        ),
      );

  Future<void> openAndAnalyze(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('START'))).push('/form');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('meal-photo-camera')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('meal-analyze')));
    await tester.pumpAndSettle();
    if (find.byKey(const Key('meal-analyze-confirm')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('meal-analyze-confirm')));
      await tester.pumpAndSettle();
    }
  }

  String chipText(WidgetTester tester, int i) => ((tester.widget<ActionChip>(find.byKey(Key('usual-chip-$i'))).label) as Text).data!;

  formTest('nach der Analyse schlaegt die App das Oel vor, das in aehnlichen Mahlzeiten immer dabei war', (tester) async {
    await threeRiceMeals();
    cloud.analysis = photoOfRiceAndPepper();
    await openAndAnalyze(tester);

    expect(find.byKey(const Key('meal-usual')), findsOneWidget);
    expect(find.text('Fehlt etwas?'), findsOneWidget);
    expect(chipText(tester, 0), 'Olivenöl (ca. 12 g)', reason: 'Median von 10, 12 und 14 g');
    expect(find.byKey(const Key('usual-chip-1')), findsNothing);
  });

  formTest('Antippen legt die Zeile mit Menge, Naehrwerten und Mikronaehrstoffen an, der Vorschlag verschwindet', (tester) async {
    await threeRiceMeals();
    cloud.analysis = photoOfRiceAndPepper();
    await openAndAnalyze(tester);

    await tester.tap(find.byKey(const Key('usual-chip-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('meal-usual')), findsNothing, reason: 'der einzige Vorschlag ist uebernommen');
    expect(find.byKey(const Key('ingredient-row-2')), findsOneWidget);
    final tile = tester.widget<ListTile>(find.byKey(const Key('ingredient-row-2')));
    expect(((tile.title) as Text).data, 'Olivenöl');
    expect(find.textContaining('12 g · 106 kcal'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('meal-title')), 'Reispfanne');
    await tester.tap(find.byKey(const Key('meal-save')));
    await tester.pumpAndSettle();
    final saved = (await db.select(db.meals).get()).firstWhere((m) => m.title == 'Reispfanne');
    final rows = (await db.select(db.mealIngredients).get()).where((r) => r.mealId == saved.id).toList();
    final oil = rows.firstWhere((r) => r.freeText == 'Olivenöl');
    expect(oil.source, 'estimate');
    expect(oil.blsCode, 'Q120000');
    expect(oil.amountG, 12);
    expect(oil.kcal, closeTo(106.08, 1e-9));
    expect(parseMicros(oil.micros)!['vit_e_mg'], closeTo(1.44, 1e-9));
  });

  formTest('"Nein danke" blendet den Hinweis aus und legt nichts an', (tester) async {
    await threeRiceMeals();
    cloud.analysis = photoOfRiceAndPepper();
    await openAndAnalyze(tester);
    await tester.tap(find.byKey(const Key('usual-dismiss')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('meal-usual')), findsNothing);
    expect(find.byKey(const Key('ingredient-row-2')), findsNothing);
  });

  formTest('ohne aehnliche fruehere Mahlzeiten gibt es keinen Hinweis', (tester) async {
    await past('Etwas anderes', 1, [food('Lachs', 150, 200), food('Brokkoli', 100, 34), food('Olivenöl', 10, 884, blsCode: 'Q120000')]);
    await past('Noch etwas', 2, [food('Lachs', 150, 200), food('Brokkoli', 100, 34), food('Olivenöl', 10, 884, blsCode: 'Q120000')]);
    cloud.analysis = photoOfRiceAndPepper();
    await openAndAnalyze(tester);
    expect(find.byKey(const Key('meal-usual')), findsNothing);
  });

  formTest('ist das Oel schon erkannt, wird es nicht noch einmal vorgeschlagen', (tester) async {
    await threeRiceMeals();
    cloud.analysis = const MealAnalysis(dishTitle: 'Reispfanne', ingredients: [
      AnalyzedIngredient(name: 'Reis', estimatedGrams: 160, confidence: 0.8),
      AnalyzedIngredient(name: 'Paprika', estimatedGrams: 90, confidence: 0.7),
      AnalyzedIngredient(name: 'Olivenöl', estimatedGrams: 10, confidence: 0.4),
    ]);
    await openAndAnalyze(tester);
    expect(find.byKey(const Key('meal-usual')), findsNothing);
  });

  formTest('ein Produkt mit Naehrwerten uebernimmt sein eigenes Profil, kein Freitext', (tester) async {
    final oel = await productRepo(db).create(name: 'Olivenöl', baseUnit: 'l', nutrientsPer100: {'kcal': 884}, nutrientsBasis: 'g', nutrientsSource: 'manual');
    products = [oel];
    for (var d = 1; d <= 3; d++) {
      await past('Reispfanne $d', d, [
        food('Reis', 150, 130),
        food('Paprika', 80, 31),
        IngredientDraft(productId: oel.id, quantity: 10.0 + d, entryUnit: EntryUnit.ml, deduct: false),
      ]);
    }
    cloud.analysis = photoOfRiceAndPepper();
    await openAndAnalyze(tester);
    expect(chipText(tester, 0), startsWith('Olivenöl (ca. '));
    await tester.tap(find.byKey(const Key('usual-chip-0')));
    await tester.pumpAndSettle();
    final tile = tester.widget<ListTile>(find.byKey(const Key('ingredient-row-2')));
    expect(((tile.leading) as Icon).icon, Icons.kitchen_outlined, reason: 'Produkt-Zeile');
    expect(find.textContaining('kcal'), findsWidgets);
  });

  test('recentHistory: juengste zuerst, mit Zutaten, ohne die ausgeschlossene und ohne geloeschte Mahlzeit', () async {
    final a = await past('A', 1, [food('x', 100, 10)]);
    final b = await past('B', 2, [food('y', 100, 10), food('z', 100, 10)]);
    final c = await past('C', 3, [food('w', 100, 10)]);
    await meals.delete(b.id);
    final all = await meals.recentHistory();
    expect(all.map((e) => e.$1.title), ['C', 'A']);
    expect(all.first.$2.map((i) => i.freeText), ['w']);
    final without = await meals.recentHistory(excludeMealId: c.id);
    expect(without.map((e) => e.$1.title), ['A']);
    expect((await meals.recentHistory(limit: 1)).map((e) => e.$1.title), ['C']);
    expect(a.id, isNotEmpty);
  });
}
