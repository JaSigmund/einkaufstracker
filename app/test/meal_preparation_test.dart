import 'dart:convert';

import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/nutrition/bls_food_search.dart';
import 'package:einkaufstracker/data/repositories/meal_repository.dart';
import 'package:einkaufstracker/domain/nutrition/ingredient_nutrition.dart';
import 'package:einkaufstracker/domain/nutrition/micros.dart';
import 'package:einkaufstracker/domain/nutrition/nutrient_scaling.dart';
import 'package:einkaufstracker/features/diary/meal_form_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';

/// Garfaktoren (Phase N4, ADR-037): Zubereitung einer Zutat, Minderung der Mikronaehrstoffe beim Speichern, Bearbeiten ohne doppelte
/// Minderung.
const _micros = {'vit_c_mg': 100.0, 'folate_ug': 50.0, 'vit_d_ug': 1.0};
const _paprika = BlsFood(code: 'G543100', nameDe: 'Gemüsepaprika rot, roh', per100: NutrientsPer100(kcal: 36, fatG: 0.2), micros: _micros);

void formTest(String name, Future<void> Function(WidgetTester tester) body) => testWidgets(name, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

void main() {
  late AppDatabase db;
  late MealRepository meals;
  late FakeBlsFoodSearch bls;

  setUp(() {
    db = memoryDb();
    meals = mealRepo(db);
    bls = FakeBlsFoodSearch(foods: const [_paprika]);
  });
  tearDown(() => db.close());

  IngredientDraft paprika({String? preparation, double grams = 200, Micros? micros = _micros}) => IngredientDraft(
        freeText: 'Gemüsepaprika rot, roh',
        quantity: grams,
        entryUnit: EntryUnit.g,
        per100: const NutrientsPer100(kcal: 36, fatG: 0.2),
        per100Basis: 'g',
        blsCode: 'G543100',
        microsPer100: micros,
        preparation: preparation,
      );

  Future<MealIngredient> savedIngredient() async => (await db.select(db.mealIngredients).get()).single;

  Future<Meal> create(IngredientDraft i) => meals.create(MealDraft(title: 'Pfanne', eatenAt: DateTime.utc(2026, 10, 4, 12), ingredients: [i]));

  group('MealRepository', () {
    test('mit Zubereitung werden die Mikronaehrstoffe gemindert, Makros und Menge bleiben, die Zubereitung wird gespeichert', () async {
      await create(paprika(preparation: 'veg_other:boiled'));
      final row = await savedIngredient();
      final micros = parseMicros(row.micros)!;
      expect(micros['vit_c_mg'], closeTo(150, 1e-9), reason: '100 mg je 100 g, 200 g, mal 0,75');
      expect(micros['folate_ug'], closeTo(65, 1e-9), reason: '50 µg je 100 g, 200 g, mal 0,65');
      expect(micros['vit_d_ug'], closeTo(2, 1e-9), reason: 'fuer Vitamin D gibt es keinen Faktor');
      expect(row.preparation, 'veg_other:boiled');
      expect(row.kcal, 72, reason: 'Energie bleibt');
      expect(row.amountG, 200);
    });

    test('ohne Zubereitung bleibt alles wie roh', () async {
      await create(paprika());
      final row = await savedIngredient();
      expect(parseMicros(row.micros)!['vit_c_mg'], closeTo(200, 1e-9));
      expect(row.preparation, isNull);
    });

    test('ein unbekannter oder unpassender Wert wird ignoriert und nicht gespeichert', () async {
      for (final prep in ['unsinn', 'veg_other:smoked', 'rice:fried', 'a:b:c', '']) {
        await db.delete(db.mealIngredients).go();
        await create(paprika(preparation: prep));
        final row = await savedIngredient();
        expect(row.preparation, isNull, reason: prep);
        expect(parseMicros(row.micros)!['vit_c_mg'], closeTo(200, 1e-9), reason: prep);
      }
    });

    test('Produkte mit eigenem Profil und Handwerte werden nicht gemindert', () async {
      final product = await productRepo(db).create(name: 'Paprika', baseUnit: 'kg', nutrientsPer100: {'kcal': 30, 'vit_c_mg': 120.0}, nutrientsBasis: 'g', nutrientsSource: 'manual');
      await meals.create(MealDraft(title: 'x', eatenAt: DateTime.utc(2026, 10, 4, 12), ingredients: [
        IngredientDraft(productId: product.id, quantity: 100, entryUnit: EntryUnit.g, deduct: false, preparation: 'veg_other:boiled'),
        const IngredientDraft(freeText: 'Handeingabe', quantity: 1, entryUnit: EntryUnit.piece, manualNutrients: NutrientAmounts(kcal: 100), preparation: 'veg_other:boiled'),
      ]));
      for (final row in await db.select(db.mealIngredients).get()) {
        expect(row.preparation, isNull, reason: row.freeText ?? 'Produkt');
      }
      final productRow = (await db.select(db.mealIngredients).get()).firstWhere((r) => r.productId != null);
      expect(parseMicros(productRow.micros)!['vit_c_mg'], closeTo(120, 1e-9));
    });

    test('ohne Mikronaehrstoff-Profil gibt es nichts zu mindern, die Zubereitung bleibt trotzdem festgehalten', () async {
      await create(paprika(preparation: 'veg_other:boiled', micros: null));
      final row = await savedIngredient();
      expect(row.micros, isNull);
      expect(row.preparation, 'veg_other:boiled');
    });

    test('die Zubereitung geht in die Outbox', () async {
      await create(paprika(preparation: 'veg_other:steamed'));
      final box = (await db.select(db.outbox).get()).where((e) => e.remoteTable == 'meal_ingredients').single;
      expect((jsonDecode(box.payload) as Map)['preparation'], 'veg_other:steamed');
    });
  });

  group('Formular', () {
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

    Future<void> save(WidgetTester tester) async {
      if (find.byKey(const Key('meal-title')).evaluate().isNotEmpty && (tester.widget<TextField>(find.byKey(const Key('meal-title'))).controller?.text ?? '').isEmpty) {
        await tester.enterText(find.byKey(const Key('meal-title')), 'Test');
      }
      await tester.tap(find.byKey(const Key('meal-save')));
      await tester.pumpAndSettle();
    }

    Future<void> addPaprika(WidgetTester tester, {String grams = '200'}) async {
      await tester.tap(find.byKey(const Key('meal-add-ingredient')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('picker-search')), 'Paprika');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-bls-G543100')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('ingredient-quantity')), grams);
      await tester.pump();
      await tester.tap(find.byKey(const Key('ingredient-quantity-ok')));
      await tester.pumpAndSettle();
    }

    String text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;
    bool selected(WidgetTester tester, String key) => tester.widget<ChoiceChip>(find.byKey(Key(key))).selected;

    formTest('eine rohe BLS-Zutat zeigt die Zubereitungen, "gekocht" mindert beim Speichern und nennt die Verluste', (tester) async {
      await open(tester);
      await addPaprika(tester);
      expect(selected(tester, 'prep-0-raw'), isTrue);
      expect(find.byKey(const Key('prep-0-boiled')), findsOneWidget);
      expect(find.byKey(const Key('prep-0-steamed')), findsOneWidget);
      expect(find.byKey(const Key('prep-0-grilled')), findsNothing, reason: 'fuer Gemuese gibt es kein Grillen in den Daten');
      expect(find.byKey(const Key('prep-info-0')), findsNothing);

      await tester.tap(find.byKey(const Key('prep-0-boiled')));
      await tester.pumpAndSettle();
      expect(selected(tester, 'prep-0-boiled'), isTrue);
      expect(text(tester, 'prep-info-0'), 'Menge als Rohgewicht · Folat −35 %, Vitamin C −25 % · USDA-Durchschnitt');

      await save(tester);
      final row = await savedIngredient();
      expect(row.preparation, 'veg_other:boiled');
      expect(parseMicros(row.micros)!['vit_c_mg'], closeTo(150, 1e-9));
    });

    formTest('zurueck auf "roh" nimmt die Minderung wieder weg', (tester) async {
      await open(tester);
      await addPaprika(tester);
      await tester.tap(find.byKey(const Key('prep-0-fried')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('prep-0-raw')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('prep-info-0')), findsNothing);
      await save(tester);
      final row = await savedIngredient();
      expect(row.preparation, isNull);
      expect(parseMicros(row.micros)!['vit_c_mg'], closeTo(200, 1e-9));
    });

    formTest('Bearbeiten: die gespeicherte Zubereitung ist gewaehlt, die Menge aendern mindert nicht doppelt', (tester) async {
      final meal = await create(paprika(preparation: 'veg_other:boiled'));
      await open(tester, existing: meal);
      expect(selected(tester, 'prep-0-boiled'), isTrue);
      // auf den Namen tippen: die Mitte der Zeile liegt jetzt auf den Chips der Zubereitung
      await tester.tap(find.descendant(of: find.byKey(const Key('ingredient-row-0')), matching: find.text('Gemüsepaprika rot, roh')).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('ingredient-quantity')), '300');
      await tester.pump();
      await tester.tap(find.byKey(const Key('ingredient-quantity-ok')));
      await tester.pumpAndSettle();
      await save(tester);
      final row = (await db.select(db.mealIngredients).get()).firstWhere((r) => r.deletedAt == null);
      expect(parseMicros(row.micros)!['vit_c_mg'], closeTo(225, 1e-9), reason: '100 mg je 100 g, 300 g, einmal mal 0,75');
      expect(row.preparation, 'veg_other:boiled');
    });

    formTest('Bearbeiten ohne Aenderung der Zubereitung laesst die Werte unveraendert (Speichern ist stabil)', (tester) async {
      final meal = await create(paprika(preparation: 'veg_other:boiled'));
      await open(tester, existing: meal);
      await save(tester);
      final row = (await db.select(db.mealIngredients).get()).firstWhere((r) => r.deletedAt == null);
      expect(parseMicros(row.micros)!['vit_c_mg'], closeTo(150, 1e-9));
      expect(parseMicros(row.micros)!['folate_ug'], closeTo(65, 1e-9));
    });

    formTest('eine Zeile aus frueherer Zeit ohne Zubereitung bekommt die Auswahl, sobald der Name des Eintrags geholt ist', (tester) async {
      final meal = await create(paprika());
      await open(tester, existing: meal);
      expect(bls.codeQueries, [['G543100']]);
      expect(find.byKey(const Key('prep-0-boiled')), findsOneWidget);
      await tester.tap(find.byKey(const Key('prep-0-baked')));
      await tester.pumpAndSettle();
      await save(tester);
      final row = (await db.select(db.mealIngredients).get()).firstWhere((r) => r.deletedAt == null);
      expect(row.preparation, 'veg_other:baked');
      expect(parseMicros(row.micros)!['vit_c_mg'], lessThan(200));
    });

    formTest('ohne Netz fuer den Namen: keine Auswahl, alles andere funktioniert', (tester) async {
      bls.fail = true;
      final meal = await create(paprika());
      await open(tester, existing: meal);
      expect(find.byKey(const Key('prep-0-boiled')), findsNothing);
      await save(tester);
      expect(parseMicros((await db.select(db.mealIngredients).get()).firstWhere((r) => r.deletedAt == null).micros)!['vit_c_mg'], closeTo(200, 1e-9));
    });

    formTest('Produkte und Handwerte bieten keine Zubereitung an', (tester) async {
      final product = await productRepo(db).create(name: 'Paprika', baseUnit: 'kg', nutrientsPer100: {'kcal': 30, 'vit_c_mg': 120.0}, nutrientsBasis: 'g', nutrientsSource: 'manual');
      final meal = await meals.create(MealDraft(title: 'x', eatenAt: DateTime.utc(2026, 10, 4, 12), ingredients: [
        IngredientDraft(productId: product.id, quantity: 100, entryUnit: EntryUnit.g, deduct: false),
      ]));
      await open(tester, existing: meal);
      expect(find.byKey(const Key('prep-0-raw')), findsNothing);
    });
  });
}
