import 'dart:typed_data';

import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/nutrition/bls_food_search.dart';
import 'package:einkaufstracker/data/repositories/meal_repository.dart';
import 'package:einkaufstracker/domain/nutrition/food_match.dart';
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

/// Mikronaehrstoffe im Tagebuch-Formular (Phase N3, ADR-032): vom Treffer der Datenbank oder der Foto-Analyse bis in den Snapshot der
/// gespeicherten Zutat.
Uint8List _png() => Uint8List.fromList(img.encodePng(img.Image(width: 8, height: 8)));

const _micros = {'vit_c_mg': 11.0, 'iron_mg': 0.4, 'vit_d_ug': 0.0};
const _banane = BlsFood(code: 'F503100', nameDe: 'Banane roh', per100: NutrientsPer100(kcal: 79), micros: _micros);

/// Wie testWidgets, haengt die Seite am Ende aus (echte Drift-Streams halten sonst einen Timer).
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
  late FakeBlsFoodSearch bls;

  setUp(() {
    db = memoryDb();
    meals = mealRepo(db);
    photos = FakeMealPhotoService(db, meals);
    cloud = FakeMealAnalysisCloud();
    bls = FakeBlsFoodSearch(foods: const [_banane]);
  });
  tearDown(() => db.close());

  Widget host({Meal? existing}) => ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          mealRepositoryProvider.overrideWithValue(meals),
          productRepositoryProvider.overrideWithValue(productRepo(db)),
          inventoryRepositoryProvider.overrideWithValue(inventoryRepo(db)),
          foodLinkRepositoryProvider.overrideWithValue(foodLinkRepo(db)),
          foodUnitsSourceProvider.overrideWithValue(FakeFoodUnitsSource()),
          productsStreamProvider.overrideWith((ref) => Stream.value(const <Product>[])),
          activeInventoryStreamProvider.overrideWith((ref) => Stream.value(const <InventoryItem>[])),
          mealPhotoServiceProvider.overrideWithValue(photos),
          mealPhotoPickerProvider.overrideWithValue(({required bool camera}) async => _png()),
          mealAnalysisCloudProvider.overrideWithValue(cloud),
          blsFoodSearchProvider.overrideWithValue(bls),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(routes: [
            GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('START'))),
            GoRoute(path: '/form', builder: (_, _) => MealFormPage(existing: existing)),
          ]),
        ),
      );

  Future<void> open(WidgetTester tester, {Meal? existing}) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(existing: existing));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('START'))).push('/form');
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester, {String title = 'Test'}) async {
    await tester.enterText(find.byKey(const Key('meal-title')), title);
    await tester.tap(find.byKey(const Key('meal-save')));
    await tester.pumpAndSettle();
  }

  Future<void> analyze(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('meal-photo-camera')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('meal-analyze')));
    await tester.pumpAndSettle();
    if (find.byKey(const Key('meal-analyze-confirm')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('meal-analyze-confirm')));
      await tester.pumpAndSettle();
    }
  }

  formTest('Zutat aus der Datenbank: die Mikronaehrstoffe der Menge stehen im gespeicherten Snapshot', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('meal-add-ingredient')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('picker-search')), 'Banane');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick-bls-F503100')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ingredient-quantity')), '200');
    await tester.pump();
    await tester.tap(find.byKey(const Key('ingredient-quantity-ok')));
    await tester.pumpAndSettle();
    await save(tester);

    final ing = await db.select(db.mealIngredients).getSingle();
    final micros = parseMicros(ing.micros)!;
    expect(micros['vit_c_mg'], closeTo(22, 1e-9));
    expect(micros['iron_mg'], closeTo(0.8, 1e-9));
    expect(micros['vit_d_ug'], 0, reason: 'echte Null');
    expect(micros.containsKey('zinc_mg'), isFalse);
  });

  formTest('Treffer der Foto-Analyse bringt die Mikronaehrstoffe mit, eine Zutat ohne Treffer hat keine', (tester) async {
    cloud.analysis = const MealAnalysis(dishTitle: 'Fruehstueck', ingredients: [
      AnalyzedIngredient(
        name: 'Banane',
        estimatedGrams: 120,
        confidence: 0.8,
        match: FoodMatch(code: 'F503100', name: 'Banane roh', per100: NutrientsPer100(kcal: 79), method: 'synonym', trust: MatchTrust.sure, micros: _micros),
      ),
      AnalyzedIngredient(name: 'Gewuerzmischung', estimatedGrams: 5, confidence: 0.3),
    ]);
    await open(tester);
    await analyze(tester);
    await save(tester, title: 'Fruehstueck');

    final rows = await db.select(db.mealIngredients).get();
    final banana = rows.firstWhere((r) => r.freeText == 'Banane');
    expect(parseMicros(banana.micros)!['vit_c_mg'], closeTo(13.2, 1e-9));
    expect(rows.firstWhere((r) => r.freeText == 'Gewuerzmischung').micros, isNull);
  });

  formTest('Nachschlagen ueber die Suche setzt die Mikronaehrstoffe nachtraeglich', (tester) async {
    cloud.analysis = const MealAnalysis(dishTitle: 'x', ingredients: [AnalyzedIngredient(name: 'Banane', estimatedGrams: 100, confidence: 0.4)]);
    await open(tester);
    await analyze(tester);
    await tester.tap(find.byKey(const Key('ingredient-lookup-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick-bls-F503100')));
    await tester.pumpAndSettle();
    await save(tester);
    expect(parseMicros((await db.select(db.mealIngredients).getSingle()).micros)!['vit_c_mg'], closeTo(11, 1e-9));
  });

  formTest('Bearbeiten: die Menge aendern rechnet die Mikronaehrstoffe aus dem Snapshot neu', (tester) async {
    final meal = await meals.create(MealDraft(title: 'Banane', eatenAt: DateTime.utc(2026, 10, 3, 8), ingredients: const [
      IngredientDraft(
        freeText: 'Banane roh',
        quantity: 100,
        entryUnit: EntryUnit.g,
        per100: NutrientsPer100(kcal: 79),
        per100Basis: 'g',
        blsCode: 'F503100',
        microsPer100: _micros,
      ),
    ]));
    await open(tester, existing: meal);
    await tester.tap(find.byKey(const Key('ingredient-row-0')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ingredient-quantity')), '300');
    await tester.pump();
    await tester.tap(find.byKey(const Key('ingredient-quantity-ok')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('meal-save')));
    await tester.pumpAndSettle();

    final rows = (await db.select(db.mealIngredients).get()).where((i) => i.deletedAt == null).toList();
    expect(rows, hasLength(1));
    expect(parseMicros(rows.single.micros)!['vit_c_mg'], closeTo(33, 1e-9));
    expect(parseMicros(rows.single.micros)!['iron_mg'], closeTo(1.2, 1e-9));
  });

  formTest('Bearbeiten ohne Aenderung der Zutat behaelt die Mikronaehrstoffe', (tester) async {
    final meal = await meals.create(MealDraft(title: 'Banane', eatenAt: DateTime.utc(2026, 10, 3, 8), ingredients: const [
      IngredientDraft(freeText: 'Banane roh', quantity: 150, entryUnit: EntryUnit.g, per100: NutrientsPer100(kcal: 79), per100Basis: 'g', blsCode: 'F503100', microsPer100: _micros),
    ]));
    await open(tester, existing: meal);
    await tester.tap(find.byKey(const Key('meal-save')));
    await tester.pumpAndSettle();
    final rows = (await db.select(db.mealIngredients).get()).where((i) => i.deletedAt == null).toList();
    expect(parseMicros(rows.single.micros)!['vit_c_mg'], closeTo(16.5, 1e-9));
  });
}
