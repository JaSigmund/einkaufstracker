import 'dart:convert';

import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/drink_repository.dart';
import 'package:einkaufstracker/data/repositories/household_prefs_repository.dart';
import 'package:einkaufstracker/data/repositories/meal_repository.dart';
import 'package:einkaufstracker/data/repositories/supplement_repository.dart';
import 'package:einkaufstracker/domain/nutrition/drink_mix.dart';
import 'package:einkaufstracker/domain/nutrition/fluid_intake.dart';
import 'package:einkaufstracker/domain/nutrition/micros.dart';
import 'package:einkaufstracker/domain/nutrition/nutrient_scaling.dart';
import 'package:einkaufstracker/domain/products/drinkable.dart';
import 'package:einkaufstracker/features/diary/diary_page.dart';
import 'package:einkaufstracker/features/diary/drinks_section.dart';
import 'package:einkaufstracker/features/diary/quick_intake_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Trinkmenge, Erinnerung, Getraenke im Tagebuch, Alkohol und Koffein (ADR-049). Heute ist der 2. November 2026; Wien liegt dann bei UTC+1.
final _now = DateTime.utc(2026, 11, 2, 10);

void main() {
  group('Einstellungen', () {
    test('ohne Angaben: 1,5 l und Erinnerung um 16 Uhr', () {
      final s = FluidSettings.fromPrefs(const {});
      expect(s.targetMl, 1500);
      expect(s.reminderOn, isTrue);
      expect(s.timeText, '16:00');
    });

    test('liest gespeicherte Werte, Unsinn faellt auf die Vorbelegung zurueck', () {
      final s = FluidSettings.fromPrefs(const {fluidTargetPref: 2000, fluidReminderOnPref: false, fluidReminderTimePref: '09:30'});
      expect(s.targetMl, 2000);
      expect(s.reminderOn, isFalse);
      expect(s.timeText, '09:30');
      final bad = FluidSettings.fromPrefs(const {fluidTargetPref: -1, fluidReminderTimePref: '25:99'});
      expect(bad.targetMl, 1500);
      expect(bad.timeText, '16:00');
    });
  });

  group('Erinnerungszeiten', () {
    final morning = DateTime(2026, 11, 2, 11);
    const settings = FluidSettings();

    test('heute und die naechsten sechs Tage, solange unter der Haelfte', () {
      final times = fluidReminderTimes(now: morning, settings: settings, drunkMl: 700);
      expect(times, hasLength(7));
      expect(times.first, DateTime(2026, 11, 2, 16));
      expect(times.last, DateTime(2026, 11, 8, 16));
    });

    test('Haelfte erreicht: heute keine mehr, die naechsten Tage bleiben', () {
      final times = fluidReminderTimes(now: morning, settings: settings, drunkMl: 750);
      expect(times, hasLength(6));
      expect(times.first, DateTime(2026, 11, 3, 16));
    });

    test('Uhrzeit vorbei: heute keine mehr', () {
      final times = fluidReminderTimes(now: DateTime(2026, 11, 2, 16, 1), settings: settings, drunkMl: 0);
      expect(times.first, DateTime(2026, 11, 3, 16));
    });

    test('Monatswechsel und ausgeschaltet', () {
      expect(fluidReminderTimes(now: DateTime(2026, 11, 30, 11), settings: settings, drunkMl: 0)[1], DateTime(2026, 12, 1, 16));
      expect(fluidReminderTimes(now: morning, settings: const FluidSettings(reminderOn: false), drunkMl: 0), isEmpty);
    });
  });

  group('Menge', () {
    test('Liter und Stueck mit Volumen zaehlen, Gewogenes und Beutel nicht', () {
      expect(drinkIngredientMl(unit: 'l', quantity: 0.25), 250);
      expect(drinkIngredientMl(unit: 'piece', quantity: 1, amountG: 330), 330);
      expect(drinkIngredientMl(unit: 'piece', quantity: 1), 0);
      expect(drinkIngredientMl(unit: 'kg', quantity: 0.01, amountG: 10), 0);
    });

    test('nur der gefragte Kalendertag zaehlt', () {
      final entries = [
        (at: DateTime(2026, 11, 2, 0, 30), ml: 250.0),
        (at: DateTime(2026, 11, 2, 23, 59), ml: 100.0),
        (at: DateTime(2026, 11, 1, 23, 59), ml: 999.0),
      ];
      expect(fluidMlOn(DateTime(2026, 11, 2, 12), entries), 350);
      expect(formatLiters(1400), '1,4 l');
    });
  });

  group('Alkohol und Koffein im Profil', () {
    const raw = '{"kcal":70,"carbs_g":2,"alcohol_g":9.5}';

    test('Vol.-% wird zu Gramm, das Glas Wein mit 12 % hat bei 125 ml 11,8 g', () {
      final merged = withDrinkValues('{"kcal":70}', alcoholG: alcoholGramsFromVolPercent(12))!;
      final per100 = parseMicros(merged)!['alcohol_g']!;
      expect(per100, closeTo(9.47, 0.001));
      expect(per100 * 125 / 100, closeTo(11.8, 0.05));
      expect(volPercentFromAlcoholGrams(alcoholGramsFromVolPercent(12)), closeTo(12, 1e-9));
    });

    test('setzt, laesst stehen und nimmt heraus, ohne die Makros anzufassen', () {
      final set = jsonDecode(withDrinkValues(raw, caffeineMg: 32)!) as Map;
      expect(set['caffeine_mg'], 32);
      expect(set['alcohol_g'], 9.5);
      expect(set['kcal'], 70);

      final cleared = jsonDecode(withDrinkValues(raw, clear: const {'alcohol_g'})!) as Map;
      expect(cleared.containsKey('alcohol_g'), isFalse);
      expect(cleared['carbs_g'], 2);
    });

    test('ohne Profil entsteht keines: es wuerde den BLS-Eintrag verdraengen', () {
      expect(withDrinkValues(null, caffeineMg: 32), isNull);
      expect(withDrinkValues('kein json', caffeineMg: 32), 'kein json');
    });

    test('eine Mischung summiert: gespritzter Wein traegt den Alkohol nur vom Wein', () async {
      final db = memoryDb();
      addTearDown(db.close);
      final wein = await productRepo(db).create(
        name: 'Wein',
        baseUnit: 'l',
        nutrientsPer100: const {'kcal': 70.0, 'alcohol_g': 9.47, 'caffeine_mg': 0.0},
        nutrientsBasis: 'g',
        nutrientsSource: 'manual',
      );
      final meals = mealRepo(db);
      final meal = await DrinkRepository(meals).book(
        DrinkDraft(title: 'Spritzer', parts: [DrinkPart(name: 'Wein', amount: 125, productId: wein.id), DrinkPart.water(125)]),
        at: _now,
        inStock: const {},
      );
      final rows = await meals.ingredientsOf(meal.id);
      expect(parseMicros(rows.firstWhere((i) => i.productId == wein.id).micros)!['alcohol_g'], closeTo(11.84, 0.01));
      expect(parseMicros(rows.firstWhere((i) => i.productId == null).micros)!.containsKey('alcohol_g'), isFalse);
      expect(drinkMealMl(meal, rows), 250);
    });
  });

  group('Oberflaeche', () {
    late AppDatabase db;
    late MealRepository meals;
    late FakeNotificationScheduler scheduler;
    late HouseholdPrefsRepository prefs;
    late SupplementRepository supplements;

    setUp(() {
      db = memoryDb();
      meals = mealRepo(db);
      scheduler = FakeNotificationScheduler();
      prefs = HouseholdPrefsRepository(db, householdId: () async => 'h1');
      supplements = SupplementRepository(db, householdId: () async => 'h1');
    });
    tearDown(() => db.close());

    List<Object> overrides({List<Meal> mealRows = const [], List<MealIngredient> ingredients = const [], Map<String, Object?> prefValues = const {}}) => [
          databaseProvider.overrideWithValue(db),
          mealRepositoryProvider.overrideWithValue(meals),
          productRepositoryProvider.overrideWithValue(productRepo(db)),
          notificationSchedulerProvider.overrideWithValue(scheduler),
          householdPrefsRepositoryProvider.overrideWithValue(prefs),
          supplementRepositoryProvider.overrideWithValue(supplements),
          householdPrefsProvider.overrideWith((ref) => Stream.value(prefValues)),
          mealsStreamProvider.overrideWith((ref) => Stream.value(mealRows)),
          mealIngredientsStreamProvider.overrideWith((ref) => Stream.value(ingredients)),
          productsStreamProvider.overrideWith((ref) => Stream.value(const <Product>[])),
          activeInventoryStreamProvider.overrideWith((ref) => Stream.value(const <InventoryItem>[])),
          categoriesStreamProvider.overrideWith((ref) => Stream.value(const <Category>[])),
        ];

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    void uiTest(String name, Future<void> Function(WidgetTester tester) body) => testWidgets(name, (tester) async {
          tester.view.physicalSize = const Size(1200, 3000);
          addTearDown(tester.view.resetPhysicalSize);
          await body(tester);
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 1));
        });

    Future<(List<Meal>, List<MealIngredient>)> twoDrinks({DateTime? at}) async {
      final drinks = DrinkRepository(meals);
      final a = await drinks.book(DrinkDraft(title: 'Saft', parts: [DrinkPart(name: 'Saft', amount: 250, per100: const NutrientsPer100(kcal: 40), nutrientBasis: 'bls_exact', blsCode: 'X')]), at: at ?? _now, inStock: const {});
      final b = await drinks.book(DrinkDraft(title: 'Saft gespritzt', parts: [DrinkPart(name: 'Saft', amount: 100, per100: const NutrientsPer100(kcal: 40), nutrientBasis: 'bls_exact', blsCode: 'X'), DrinkPart.water(150)]), at: at ?? _now, inStock: const {});
      return ([a, b], [...await meals.ingredientsOf(a.id), ...await meals.ingredientsOf(b.id)]);
    }

    uiTest('Trinkmenge zaehlt Wasser, Getraenke und das Wasser in Mischungen', (tester) async {
      final (mealRows, ingredients) = await twoDrinks();
      await tester.pumpWidget(ProviderScope(
        overrides: overrides(mealRows: mealRows, ingredients: ingredients).cast(),
        child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: DrinksSection(now: _now, waterMl: 500)))),
      ));
      await settle(tester);
      expect(find.text('Heute 1,0 l von 1,5 l getrunken'), findsOneWidget);
    });

    uiTest('Ziel aus den Einstellungen, Gestriges zaehlt nicht', (tester) async {
      final (mealRows, ingredients) = await twoDrinks(at: _now.subtract(const Duration(days: 1)));
      await tester.pumpWidget(ProviderScope(
        overrides: overrides(mealRows: mealRows, ingredients: ingredients, prefValues: const {fluidTargetPref: 2000}).cast(),
        child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: DrinksSection(now: _now)))),
      ));
      await settle(tester);
      expect(find.text('Heute 0,0 l von 2,0 l getrunken'), findsOneWidget);
    });

    uiTest('Einstellungen speichern und planen neu, ausgeschaltet wird storniert', (tester) async {
      scheduler.fluidReminders = [DateTime(2026, 11, 3, 16)];
      await tester.pumpWidget(ProviderScope(
        overrides: overrides().cast(),
        child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: DrinksSection(now: _now)))),
      ));
      await settle(tester);
      await tester.tap(find.byKey(const Key('fluid-today')));
      await settle(tester);

      await tester.enterText(find.byKey(const Key('fluid-target')), '2,5');
      await tester.tap(find.byKey(const Key('fluid-reminder-on')));
      await tester.pump();
      expect(find.byKey(const Key('fluid-reminder-time')), findsNothing);
      await tester.tap(find.byKey(const Key('fluid-save')));
      await settle(tester);

      final saved = FluidSettings.fromPrefs(await tester.runAsync(prefs.load) ?? const {});
      expect(saved.targetMl, 2500);
      expect(saved.reminderOn, isFalse);
      expect(scheduler.fluidReminders, isEmpty);
    });

    uiTest('ein unsinniges Ziel wird nicht gespeichert', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: overrides().cast(),
        child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: DrinksSection(now: _now)))),
      ));
      await settle(tester);
      await tester.tap(find.byKey(const Key('fluid-today')));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('fluid-target')), 'viel');
      await tester.tap(find.byKey(const Key('fluid-save')));
      await settle(tester);
      expect(find.textContaining('zwischen 0 und 10 Litern'), findsOneWidget);
      expect(await tester.runAsync(prefs.load), isEmpty);
    });

    uiTest('Neuplanen rechnet aus der Datenbank: unter der Haelfte heute noch, danach nicht mehr', (tester) async {
      late WidgetRef captured;
      await tester.pumpWidget(ProviderScope(
        overrides: overrides().cast(),
        child: MaterialApp(home: Consumer(builder: (context, ref, _) {
          captured = ref;
          return const SizedBox();
        })),
      ));
      await settle(tester);

      await tester.runAsync(() async {
        await rescheduleFluidReminders(captured);
      });
      final before = scheduler.fluidReminders;
      expect(before, isNotEmpty);

      await tester.runAsync(() async {
        await prefs.set(fluidReminderOnPref, false);
        await rescheduleFluidReminders(captured);
      });
      expect(scheduler.fluidReminders, isEmpty);
    });

    uiTest('Schnell eintragen zeigt die Trinkmenge samt Wasser', (tester) async {
      await supplements.takeWater(at: _now);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ...overrides(),
          supplementsStreamProvider.overrideWith((ref) => Stream.value(const <Supplement>[])),
          supplementIntakesStreamProvider.overrideWith((ref) => supplements.watchIntakes()),
        ].cast(),
        child: MaterialApp(home: QuickIntakePage(now: _now)),
      ));
      await settle(tester);
      expect(find.byKey(const Key('fluid-today')), findsOneWidget);
    });

    group('Tagebuch', () {
      Widget diary(List<Meal> mealRows, List<MealIngredient> ingredients) => ProviderScope(
            overrides: [
              ...overrides(mealRows: mealRows, ingredients: ingredients),
              nutritionTargetsProvider.overrideWith((ref) => Stream.empty()),
              balanceMovementsProvider.overrideWith((ref) => Stream.value(const [])),
            ].cast(),
            child: MaterialApp(home: DiaryPage(now: _now)),
          );

      uiTest('ab zwei Getraenken eine aufklappbare Zeile mit Menge, die Tagessumme bleibt', (tester) async {
        final (mealRows, ingredients) = await twoDrinks();
        await tester.pumpWidget(diary(mealRows, ingredients));
        await settle(tester);

        expect(find.textContaining('Getränke · 2 · 500 ml'), findsOneWidget);
        expect(find.byKey(Key('meal-${mealRows.first.id}')), findsNothing, reason: 'zugeklappt');

        await tester.tap(find.textContaining('Getränke · 2'));
        await settle(tester);
        expect(find.byKey(Key('meal-${mealRows.first.id}')), findsOneWidget);
      });

      uiTest('ein einzelnes Getraenk bleibt eine normale Zeile', (tester) async {
        final (mealRows, ingredients) = await twoDrinks();
        await tester.pumpWidget(diary([mealRows.first], [for (final i in ingredients) if (i.mealId == mealRows.first.id) i]));
        await settle(tester);
        expect(find.textContaining('Getränke · '), findsNothing);
        expect(find.byKey(Key('meal-${mealRows.first.id}')), findsOneWidget);
      });
    });
  });
}
