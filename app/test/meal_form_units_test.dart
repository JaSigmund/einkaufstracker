import 'dart:typed_data';

import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/nutrition/bls_food_search.dart';
import 'package:einkaufstracker/data/repositories/meal_repository.dart';
import 'package:einkaufstracker/domain/nutrition/food_match.dart';
import 'package:einkaufstracker/domain/nutrition/food_unit.dart';
import 'package:einkaufstracker/domain/nutrition/ingredient_nutrition.dart';
import 'package:einkaufstracker/domain/nutrition/meal_analysis.dart';
import 'package:einkaufstracker/domain/nutrition/nutrient_scaling.dart';
import 'package:einkaufstracker/features/diary/meal_form_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;

import 'support/fakes.dart';

/// Stueckgewichte im Tagebuch-Formular (Phase N2, ADR-033): "2 Bananen", "3 Scheiben Brot", "1 Banane" ohne Gewicht, das Foto
/// zaehlt, die App merkt sich eigene Gewichte.
Uint8List _png() => Uint8List.fromList(img.encodePng(img.Image(width: 8, height: 8)));

const _banane = BlsFood(code: 'F503100', nameDe: 'Banane roh', per100: NutrientsPer100(kcal: 79, proteinG: 1.1, fatG: 0.2, carbsG: 14));
const _gurke = BlsFood(code: 'G520802', nameDe: 'Gewürzgurke', per100: NutrientsPer100(kcal: 11, carbsG: 1.5));

/// Wie testWidgets, haengt die Seite am Ende aus: echte Drift-Streams (Produkte, Mahlzeiten) halten sonst einen Timer.
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
  late FakeFoodUnitsSource units;
  late FakeBlsFoodSearch bls;
  var products = <Product>[];

  setUp(() {
    db = memoryDb();
    meals = mealRepo(db);
    photos = FakeMealPhotoService(db, meals);
    cloud = FakeMealAnalysisCloud();
    units = FakeFoodUnitsSource(sampleFoodUnits());
    bls = FakeBlsFoodSearch(foods: const [_banane, _gurke]);
    products = [];
  });
  tearDown(() => db.close());

  Widget host({Meal? existing}) => ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          mealRepositoryProvider.overrideWithValue(meals),
          productRepositoryProvider.overrideWithValue(productRepo(db)),
          inventoryRepositoryProvider.overrideWithValue(inventoryRepo(db)),
          foodLinkRepositoryProvider.overrideWithValue(foodLinkRepo(db)),
          foodUnitsSourceProvider.overrideWithValue(units),
          productsStreamProvider.overrideWith((ref) => Stream.value(products)),
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

  /// "Zutat hinzufuegen" -> Suche nach [query] -> den BLS-Treffer [code] waehlen
  Future<void> pickBls(WidgetTester tester, String query, String code) async {
    await tester.tap(find.byKey(const Key('meal-add-ingredient')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('picker-search')), query);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('pick-bls-$code')));
    await tester.pumpAndSettle();
  }

  Future<void> enterQuantity(WidgetTester tester, String q, {Key? unit, String? weight}) async {
    await tester.enterText(find.byKey(const Key('ingredient-quantity')), q);
    await tester.pump();
    if (unit != null) {
      await tester.tap(find.byKey(unit));
      await tester.pumpAndSettle();
    }
    if (weight != null) {
      await tester.enterText(find.byKey(const Key('ingredient-unit-weight')), weight);
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('ingredient-quantity-ok')));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester, {String title = 'Test'}) async {
    await tester.enterText(find.byKey(const Key('meal-title')), title);
    await tester.tap(find.byKey(const Key('meal-save')));
    await tester.pumpAndSettle();
  }

  String subtitleOf(WidgetTester tester, int i) {
    final tile = tester.widget<ListTile>(find.byKey(Key('ingredient-row-$i')));
    final column = tile.subtitle! as Column;
    return (column.children.last as Text).data!;
  }

  formTest('"2 Bananen": Stueck aus der Tabelle, die Zeile nennt Menge, Gramm und kcal, gespeichert wird die Anzahl mit Gewicht', (tester) async {
    await open(tester);
    await pickBls(tester, 'Banane', 'F503100');
    expect(find.byKey(const Key('ingredient-unit-piece')), findsOneWidget);
    await enterQuantity(tester, '2', unit: const Key('ingredient-unit-piece'));

    expect(subtitleOf(tester, 0), '2 Stk · ≈ 236 g · 186 kcal');
    await save(tester);

    final ing = await db.select(db.mealIngredients).getSingle();
    expect(ing.quantity, 2);
    expect(ing.unit, 'piece');
    expect(ing.amountG, 236);
    expect(ing.kcal, closeTo(186.44, 1e-9));
    expect(ing.blsCode, 'F503100');
    expect(await db.select(db.householdFoodLinks).get(), isEmpty, reason: 'ein Tabellenwert wird nie als eigenes Gewicht gemerkt');
  });

  formTest('Groesse und Bruch: 1/2 grosse Banane', (tester) async {
    await open(tester);
    await pickBls(tester, 'Banane', 'F503100');
    await tester.tap(find.byKey(const Key('ingredient-unit-piece')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ingredient-size-large')));
    await tester.tap(find.byKey(const Key('ingredient-frac-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ingredient-quantity-ok')));
    await tester.pumpAndSettle();
    expect(subtitleOf(tester, 0), '0,5 Stk · ≈ 68 g · 54 kcal');
  });

  formTest('Scheiben: nur wenn bekannt, die Zeile sagt "3 Scheiben"', (tester) async {
    bls.foods = [
      const BlsFood(code: 'B311000', nameDe: 'Weizenbrot/Weißbrot', per100: NutrientsPer100(kcal: 260)),
    ];
    await open(tester);
    await pickBls(tester, 'Brot', 'B311000');
    await enterQuantity(tester, '3', unit: const Key('ingredient-unit-slice'));
    expect(subtitleOf(tester, 0), '3 Scheiben · ≈ 84 g · 218 kcal');
    await save(tester);
    final ing = await db.select(db.mealIngredients).getSingle();
    expect([ing.quantity, ing.unit, ing.amountG], [3, 'piece', 84]);
  });

  formTest('unbekanntes Gewicht: der Dialog fragt, die Zeile rechnet, das Gewicht landet beim Speichern im Gedaechtnis', (tester) async {
    await open(tester);
    await pickBls(tester, 'Gurke', 'G520802');
    expect(find.byKey(const Key('ingredient-unit-slice')), findsNothing);
    await enterQuantity(tester, '3', unit: const Key('ingredient-unit-piece'), weight: '35');
    expect(subtitleOf(tester, 0), '3 Stk · ≈ 105 g · 12 kcal');
    await save(tester);

    final link = await db.select(db.householdFoodLinks).getSingle();
    expect(link.nameNorm, 'Gewürzgurke');
    expect(link.blsCode, 'G520802');
    expect(link.unitWeightG, 35);
    expect((await db.select(db.mealIngredients).getSingle()).amountG, 105);
  });

  formTest('beim naechsten Mal ist das eigene Gewicht schon da und geht der Tabelle vor', (tester) async {
    await foodLinkRepo(db).setUnitWeight('Banane', 'F503100', 135);
    await open(tester);
    await pickBls(tester, 'Banane', 'F503100');
    await tester.tap(find.byKey(const Key('ingredient-unit-piece')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('ingredient-unit-info'))).data, '1 Stk ≈ 135 g (dein Gewicht)');
    expect(find.byKey(const Key('ingredient-unit-weight')), findsNothing);
    await tester.enterText(find.byKey(const Key('ingredient-quantity')), '1');
    await tester.pump();
    await tester.tap(find.byKey(const Key('ingredient-quantity-ok')));
    await tester.pumpAndSettle();
    expect(subtitleOf(tester, 0), '1 Stk · ≈ 135 g · 107 kcal');
  });

  formTest('Tabelle nicht erreichbar: Stueck fragt nach dem Gewicht, nichts bricht', (tester) async {
    units.fail = true;
    await open(tester);
    await pickBls(tester, 'Banane', 'F503100');
    await tester.tap(find.byKey(const Key('ingredient-unit-piece')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ingredient-unit-weight')), findsOneWidget);
    expect(find.byKey(const Key('ingredient-sizes')), findsNothing);
  });

  formTest('Produkt mit Stueckware: das eingegebene Gewicht wird am Produkt gemerkt', (tester) async {
    final ei = await productRepo(db).create(
      name: 'Ei',
      baseUnit: 'piece',
      nutrientsPer100: {'kcal': 140, 'protein_g': 12},
      nutrientsBasis: 'g',
      nutrientsSource: 'manual',
    );
    products = [ei];
    await open(tester);
    await tester.tap(find.byKey(const Key('meal-add-ingredient')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('picker-search')), 'Ei');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('pick-product-${ei.id}')));
    await tester.pumpAndSettle();
    // Stueckware: "Stk" ist vorgewaehlt, das Gewicht ist unbekannt
    expect(find.byKey(const Key('ingredient-unit-weight')), findsOneWidget);
    await enterQuantity(tester, '2', weight: '58');
    expect(subtitleOf(tester, 0), '2 Stk · ≈ 116 g · 162 kcal · vom Bestand');
    await save(tester);

    expect((await productRepo(db).byId(ei.id))!.unitWeightG, 58);
    final ing = await db.select(db.mealIngredients).getSingle();
    expect([ing.quantity, ing.unit, ing.amountG], [2, 'piece', 116]);
    expect(await db.select(db.householdFoodLinks).get(), isEmpty, reason: 'ein Produkt merkt das Gewicht am Produkt, nicht im Gedaechtnis');
  });

  group('Foto-Analyse', () {
    MealAnalysis counted() => const MealAnalysis(dishTitle: 'Fruehstueck', ingredients: [
          AnalyzedIngredient(
            name: 'Banane',
            estimatedGrams: 118,
            confidence: 0.8,
            match: FoodMatch(code: 'F503100', name: 'Banane roh', per100: NutrientsPer100(kcal: 79), method: 'synonym', trust: MatchTrust.sure),
            unit: AnalyzedUnit(count: 2, key: FoodUnitKey.piece, weightG: 118, source: 'usda', size: UnitSize.medium),
          ),
          AnalyzedIngredient(name: 'Reis', estimatedGrams: 150, confidence: 0.7),
        ]);

    formTest('gezaehlte Zutat kommt als Stueck mit Gewicht, die uebrigen in Gramm', (tester) async {
      cloud.analysis = counted();
      await open(tester);
      await analyze(tester);
      expect(subtitleOf(tester, 0), '2 Stk · ≈ 236 g · 186 kcal · geschätzt');
      expect(subtitleOf(tester, 1), '150 g · Nährwerte unbekannt · geschätzt');
      await save(tester, title: 'Fruehstueck');
      final rows = await db.select(db.mealIngredients).get();
      final banane = rows.firstWhere((r) => r.freeText == 'Banane');
      expect([banane.quantity, banane.unit, banane.amountG], [2, 'piece', 236]);
      final reis = rows.firstWhere((r) => r.freeText == 'Reis');
      expect([reis.quantity, reis.unit], [0.15, 'kg']);
    });

    formTest('Zeile aus dem Foto antippen: Einheit und Gewicht sind wie vom Server', (tester) async {
      cloud.analysis = counted();
      await open(tester);
      await analyze(tester);
      await tester.tap(find.byKey(const Key('ingredient-row-0')));
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('ingredient-unit-piece'))).selected, isTrue);
      expect(tester.widget<Text>(find.byKey(const Key('ingredient-unit-info'))).data, '1 Stk ≈ 118 g (wie gespeichert)');
      await tester.tap(find.byKey(const Key('ingredient-quantity-ok')));
      await tester.pumpAndSettle();
      expect(subtitleOf(tester, 0), '2 Stk · ≈ 236 g · 186 kcal · geschätzt');
    });

    formTest('ohne Mengenschaetzung, aber mit bekannter Einheit: 1 Einheit vorbelegt statt leerer Menge', (tester) async {
      cloud.analysis = const MealAnalysis(dishTitle: 'x', ingredients: [
        AnalyzedIngredient(
          name: 'Banane',
          confidence: 0.4,
          match: FoodMatch(code: 'F503100', name: 'Banane roh', per100: NutrientsPer100(kcal: 79), method: 'synonym', trust: MatchTrust.sure),
        ),
        AnalyzedIngredient(name: 'Gewürzmischung', confidence: 0.2),
      ]);
      await open(tester);
      await analyze(tester);
      expect(subtitleOf(tester, 0), '1 Stk · ≈ 118 g · 93 kcal · unsicher geschätzt');
      expect(subtitleOf(tester, 1), 'Menge eintragen · Nährwerte unbekannt · unsicher geschätzt', reason: 'ohne bekannte Einheit bleibt die Menge leer');
      expect(units.requested, ['F503100'], reason: 'nur zu Zutaten mit Zuordnung wird die Tabelle gefragt');
    });
  });

  formTest('Bearbeiten: Stueckmenge und Gewicht einer gespeicherten Zeile kommen zurueck', (tester) async {
    final meal = await meals.create(MealDraft(title: 'Banane', eatenAt: DateTime.utc(2026, 10, 3, 8), ingredients: const [
      IngredientDraft(
        freeText: 'Banane roh',
        quantity: 2,
        entryUnit: EntryUnit.piece,
        per100: NutrientsPer100(kcal: 79),
        per100Basis: 'g',
        blsCode: 'F503100',
        unitWeightG: 118,
      ),
    ]));
    await open(tester, existing: meal);
    expect(subtitleOf(tester, 0), '2 Stk · ≈ 236 g · 186 kcal');
    await tester.tap(find.byKey(const Key('ingredient-row-0')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('ingredient-quantity'))).controller!.text, '2');
    await tester.enterText(find.byKey(const Key('ingredient-quantity')), '3');
    await tester.tap(find.byKey(const Key('ingredient-quantity-ok')));
    await tester.pumpAndSettle();
    expect(subtitleOf(tester, 0), '3 Stk · ≈ 354 g · 280 kcal');
    await tester.tap(find.byKey(const Key('meal-save')));
    await tester.pumpAndSettle();
    final ing = (await db.select(db.mealIngredients).get()).firstWhere((i) => i.deletedAt == null);
    expect([ing.quantity, ing.amountG], [3, 354]);
  });

  formTest('Portionen umrechnen skaliert auch Stueckmengen und behaelt das Gewicht', (tester) async {
    await open(tester);
    await pickBls(tester, 'Banane', 'F503100');
    await enterQuantity(tester, '2', unit: const Key('ingredient-unit-piece'));
    await tester.tap(find.byKey(const Key('meal-scale')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('scale-servings')), '2');
    await tester.tap(find.byKey(const Key('scale-ok')));
    await tester.pumpAndSettle();
    expect(subtitleOf(tester, 0), '4 Stk · ≈ 472 g · 373 kcal');
  });
}
