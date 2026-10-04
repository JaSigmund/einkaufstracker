import 'package:drift/drift.dart' show Value;
import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/nutrition/bls_food_search.dart';
import 'package:einkaufstracker/data/repositories/household_prefs_repository.dart';
import 'package:einkaufstracker/data/repositories/meal_repository.dart';
import 'package:einkaufstracker/domain/nutrition/ingredient_nutrition.dart';
import 'package:einkaufstracker/domain/nutrition/micros.dart';
import 'package:einkaufstracker/domain/nutrition/nutrient_scaling.dart';
import 'package:einkaufstracker/features/diary/nutrients_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Mikronaehrstoffe aelterer Mahlzeiten nachrechnen (Phase N4, ADR-035): Karte auf der Seite "Naehrstoffe" und Repository.
final _now = DateTime.utc(2026, 10, 3, 10);

BlsFood _bls(String code, Micros micros) => BlsFood(code: code, nameDe: 'Eintrag $code', per100: const NutrientsPer100(kcal: 50), micros: micros);

/// Die Seite haengt an echten Drift-Stroemen (gemeinsame Einstellungen): am Testende wird sie ausgehaengt, damit keine Timer offen bleiben.
void pageTest(String name, Future<void> Function(WidgetTester tester) body) => testWidgets(name, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

void main() {
  late AppDatabase db;
  late MealRepository meals;
  late FakeBlsFoodSearch search;
  var products = <Product>[];

  setUp(() {
    db = memoryDb();
    meals = mealRepo(db);
    search = FakeBlsFoodSearch(foods: [_bls('F1', const {'vit_c_mg': 50.0, 'iron_mg': 2.0})]);
    products = [];
  });
  tearDown(() => db.close());

  IngredientDraft food(String name, double grams, {String? blsCode, Micros? micros}) => IngredientDraft(
        freeText: name,
        quantity: grams,
        entryUnit: EntryUnit.g,
        per100: const NutrientsPer100(kcal: 50),
        per100Basis: 'g',
        blsCode: blsCode,
        microsPer100: micros,
      );

  Future<Meal> meal(List<IngredientDraft> ingredients) =>
      meals.create(MealDraft(title: 'Essen', eatenAt: DateTime.utc(2026, 10, 3, 6), ingredients: ingredients));

  Future<MealIngredient> ingredientNamed(String name) async => (await db.select(db.mealIngredients).get()).firstWhere((i) => i.freeText == name);

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final allMeals = await db.select(db.meals).get();
    final allIngredients = await db.select(db.mealIngredients).get();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        householdPrefsRepositoryProvider.overrideWithValue(HouseholdPrefsRepository(db, householdId: () async => 'h1')),
        supplementIntakesStreamProvider.overrideWith((ref) => Stream.value(const <SupplementIntake>[])),
        mealRepositoryProvider.overrideWithValue(meals),
        blsFoodSearchProvider.overrideWithValue(search),
        mealsStreamProvider.overrideWith((ref) => Stream.value(allMeals)),
        mealIngredientsStreamProvider.overrideWith((ref) => Stream.value(allIngredients)),
        productsStreamProvider.overrideWith((ref) => Stream.value(products)),
      ],
      child: MaterialApp(home: NutrientsPage(now: _now)),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> run(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('nutrients-backfill-run')));
    await tester.pumpAndSettle();
  }

  group('Karte auf der Seite', () {
    pageTest('sie erscheint mit der Zahl der Zutaten, die nachgerechnet werden koennen', (tester) async {
      await meal([food('Banane', 200, blsCode: 'F1'), food('Apfel', 100, blsCode: 'F1'), food('Eigenes', 50)]);
      await open(tester);
      expect(find.byKey(const Key('nutrients-backfill')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('nutrients-backfill-text'))).data, startsWith('2 Zutaten aus früheren Mahlzeiten haben'));
    });

    pageTest('ohne Kandidaten keine Karte: Handwerte und Zutaten mit Snapshot zaehlen nicht', (tester) async {
      await meal([food('Eigenes', 50), food('Schon da', 100, blsCode: 'F1', micros: const {'vit_c_mg': 50.0})]);
      await open(tester);
      expect(find.byKey(const Key('nutrients-backfill')), findsNothing);
    });

    pageTest('Antippen rechnet die Menge ein, ergaenzt nur und meldet das Ergebnis', (tester) async {
      await meal([food('Banane', 200, blsCode: 'F1'), food('Schon da', 100, blsCode: 'F1', micros: const {'vit_c_mg': 1.0})]);
      await open(tester);
      await run(tester);

      final banana = await ingredientNamed('Banane');
      final micros = parseMicros(banana.micros)!;
      expect(micros['vit_c_mg'], closeTo(100, 1e-9), reason: '50 mg je 100 g mal 200 g');
      expect(micros['iron_mg'], closeTo(4, 1e-9));
      expect(banana.kcal, 100, reason: 'Makros bleiben unveraendert');
      expect(parseMicros((await ingredientNamed('Schon da')).micros), {'vit_c_mg': 1.0}, reason: 'ein vorhandener Snapshot wird nie ueberschrieben');
      expect(search.codeQueries, [['F1']]);
      expect(find.text('1 Zutat ergänzt.'), findsOneWidget);
    });

    pageTest('Zutaten ohne Werte in der Quelle werden genannt', (tester) async {
      search = FakeBlsFoodSearch(foods: [_bls('F1', const {'vit_c_mg': 50.0}), BlsFood(code: 'F2', nameDe: 'ohne', per100: const NutrientsPer100(kcal: 10))]);
      await meal([food('Banane', 200, blsCode: 'F1'), food('Leer', 100, blsCode: 'F2')]);
      await open(tester);
      await run(tester);
      expect(find.text('1 Zutat ergänzt, 1 ohne Werte in der Quelle.'), findsOneWidget);
      expect((await ingredientNamed('Leer')).micros, isNull);
    });

    pageTest('ohne Netz bleibt alles wie es ist und die Meldung sagt es', (tester) async {
      search.fail = true;
      await meal([food('Banane', 200, blsCode: 'F1')]);
      await open(tester);
      await run(tester);
      expect((await ingredientNamed('Banane')).micros, isNull);
      expect(find.textContaining('nicht erreichbar'), findsOneWidget);
      expect(tester.widget<TextButton>(find.byKey(const Key('nutrients-backfill-run'))).onPressed, isNotNull, reason: 'erneut versuchbar');
    });

    pageTest('ein Produkt mit Mikronaehrstoffen braucht keine Anfrage an den Server', (tester) async {
      final p = await productRepo(db).create(
        name: 'Orange',
        baseUnit: 'g',
        nutrientsPer100: {'kcal': 40, 'vit_c_mg': 30.0},
        nutrientsBasis: 'g',
        nutrientsSource: 'manual',
      );
      products = [p];
      await meal([IngredientDraft(productId: p.id, quantity: 150, entryUnit: EntryUnit.g, deduct: false)]);
      // Snapshot wie vor 1.11: Mikros weglassen
      final row = (await db.select(db.mealIngredients).get()).single;
      await (db.update(db.mealIngredients)..where((i) => i.id.equals(row.id))).write(const MealIngredientsCompanion(micros: Value(null)));
      await open(tester);
      await run(tester);
      expect(search.codeQueries, isEmpty);
      expect(parseMicros((await db.select(db.mealIngredients).get()).single.micros)!['vit_c_mg'], closeTo(45, 1e-9));
    });
  });

  group('MealRepository.applyMicros', () {
    test('ergaenzt, ueberschreibt nie und schreibt in die Outbox', () async {
      await meal([food('A', 100, blsCode: 'F1'), food('B', 100, blsCode: 'F1', micros: const {'iron_mg': 9.0})]);
      final a = await ingredientNamed('A');
      final b = await ingredientNamed('B');
      final before = (await db.select(db.outbox).get()).length;
      final n = await meals.applyMicros({a.id: const {'vit_c_mg': 5.0}, b.id: const {'vit_c_mg': 7.0}, 'gibt-es-nicht': const {'vit_c_mg': 1.0}});
      expect(n, 1);
      expect(parseMicros((await ingredientNamed('A')).micros), {'vit_c_mg': 5.0});
      expect(parseMicros((await ingredientNamed('B')).micros), {'iron_mg': 9.0});
      expect((await db.select(db.outbox).get()).length, greaterThan(before), reason: 'die Aenderung wird synchronisiert');
    });

    test('eine geloeschte Zutat und eine leere Tabelle bleiben ausser Betracht', () async {
      final m = await meal([food('A', 100, blsCode: 'F1')]);
      final a = await ingredientNamed('A');
      expect(await meals.applyMicros(const {}), 0);
      expect(await meals.applyMicros({a.id: const <String, double>{}}), 0);
      await meals.delete(m.id);
      expect(await meals.applyMicros({a.id: const {'vit_c_mg': 5.0}}), 0);
    });
  });
}
