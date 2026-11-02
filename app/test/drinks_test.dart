import 'package:drift/drift.dart' show Value;
import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/drink_repository.dart';
import 'package:einkaufstracker/data/repositories/meal_repository.dart';
import 'package:einkaufstracker/domain/nutrition/drink_mix.dart';
import 'package:einkaufstracker/domain/nutrition/ingredient_nutrition.dart';
import 'package:einkaufstracker/domain/products/drinkable.dart';
import 'package:einkaufstracker/features/diary/drinks_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Getraenke unter "Schnell eintragen" (ADR-048). Heute ist der 2. November 2026.
final _now = DateTime.utc(2026, 11, 2, 10);

Product _product(String id, String name, {String baseUnit = 'l', double? packSize, int? pieces, double? unitWeightG, bool? isDrink, String? categoryId}) => Product(
      id: id,
      householdId: 'h1',
      name: name,
      baseUnit: baseUnit,
      packSize: packSize,
      piecesPerPack: pieces,
      unitWeightG: unitWeightG,
      isDrink: isDrink,
      categoryId: categoryId,
      defaultDateKind: 'best_before',
      defaultLocation: 'pantry',
      restock: false,
      updatedAt: DateTime.utc(2026),
    );

void main() {
  group('Regel "trinkbar"', () {
    bool rule(String name, String baseUnit, String? category, {double? packSize, bool? flag}) =>
        isDrinkable(flag: flag, name: name, baseUnit: baseUnit, packSize: packSize, categoryName: category);

    // Die 27 Produkte aus der echten Datenbank vom 2026-11-02 (Doku 26 §1), mit dem Soll je Produkt
    const getraenke = 'Getränke';
    const milch = 'Milch & Milchprodukte';
    const oele = 'Öle, Gewürze & Saucen';
    const tk = 'Tiefkühl';
    for (final (name, unit, category, pack, expected) in const <(String, String, String?, double?, bool)>[
      ('Coca-Cola', 'l', getraenke, 1.5, true),
      ('fritz-kola', 'l', getraenke, 0.33, true),
      ('Happy Day Immun Power', 'l', getraenke, 1, true),
      ('Happy Day Lychee', 'l', getraenke, 1, true),
      ('Happy Day Plus Ballaststoffe', 'l', getraenke, 1, true),
      ('Happy Day Plus Elektrolyte', 'l', getraenke, 1, true),
      ('Happy Day Plus Vitamine', 'l', getraenke, 1, true),
      ('Happy Day Punsch', 'l', getraenke, 1, true),
      ('Happy Day Winterapfel', 'l', getraenke, 1, true),
      ('Innocent Saft', 'piece', getraenke, null, true),
      ('Kirschlimonade', 'l', getraenke, 1.5, true),
      ('Pfanner Pure Tea', 'l', getraenke, 1, true),
      ('Red Bull Organics', 'piece', getraenke, null, true),
      ('Römerquelle Emotion Zitrone-Kaktus', 'l', getraenke, 0.75, true),
      ('SodaStream CO2-Zylinder', 'piece', getraenke, null, false),
      ('Teekanne Alpenkräuter', 'piece', getraenke, 20, false),
      ('Vöslauer Balance', 'l', getraenke, 0.75, true),
      ('Oatly Barista Fiber', 'l', milch, 1, true),
      ('Schlagobers', 'l', milch, 0.5, false),
      ('Vollmilch', 'l', milch, 1, true),
      ('Yakult Drink', 'l', milch, 0.39, true),
      ('Erdnuss-Saté-Sauce', 'l', oele, 0.2, false),
      ('Kürbiskernöl', 'l', oele, 0.5, false),
      ('Cornetto Classico', 'l', tk, 0.125, false),
      ('Pirulo Kaktus', 'l', tk, 0.405, false),
      ('Pirulo Watermelon', 'l', tk, 0.365, false),
      ('Saft happy day | 100% Orange', 'l', null, 1, true),
    ]) {
      test('$name: ${expected ? 'trinkbar' : 'nicht trinkbar'}', () => expect(rule(name, unit, category, packSize: pack), expected));
    }

    test('die eigene Entscheidung gewinnt in beide Richtungen', () {
      expect(rule('Kürbiskernöl', 'l', oele, flag: true), isTrue);
      expect(rule('Coca-Cola', 'l', getraenke, flag: false), isFalse);
    });

    test('Woerter fuehren nicht in die Irre', () {
      expect(rule('Weinessig', 'l', oele), isFalse);
      expect(rule('Kondensmilch', 'l', milch), isFalse);
      expect(rule('Milchschokolade', 'kg', 'Süßes & Snacks'), isFalse);
    });
  });

  group('Mischung', () {
    DrinkDraft saft([double ml = 250]) => DrinkDraft(title: 'Orangensaft', parts: [DrinkPart(name: 'Orangensaft', amount: ml, productId: 'p')]);

    test('1:1 teilt die Gesamtmenge, der Titel wird gespritzt, zurueck zu pur geht auch', () {
      final mixed = saft().mixedAt(1);
      expect(mixed.title, 'Orangensaft gespritzt');
      expect(mixed.parts.first.amount, 125);
      expect(mixed.parts.last.isWater, isTrue);
      expect(mixed.parts.last.amount, 125);
      expect(mixed.totalMl, 250);
      expect(mixed.ratio, 1);

      final pure = mixed.mixedAt(0);
      expect(pure.title, 'Orangensaft');
      expect(pure.parts, hasLength(1));
      expect(pure.parts.single.amount, 250);
      expect(pure.ratio, 0);
    });

    test('alle Verhaeltnisse werden wiedererkannt und halten die Menge', () {
      for (final n in drinkRatios) {
        final m = saft(300).mixedAt(n);
        expect(m.ratio, n, reason: '1:$n');
        expect(m.totalMl, 300, reason: '1:$n');
      }
    });

    test('Sirup heisst auch verduennt Sirup, ein eigener Name bleibt', () {
      final sirup = DrinkDraft(title: 'Holundersirup', parts: const [DrinkPart(name: 'Holundersirup', amount: 240)]);
      expect(sirup.mixedAt(6).title, 'Holundersirup');
      expect(sirup.mixedAt(6).parts.first.amount, closeTo(34, 0.1));
      final named = DrinkDraft(title: 'Mein Morgensaft', parts: saft().parts);
      expect(named.mixedAt(1).title, 'Mein Morgensaft');
    });

    test('neue Menge skaliert die Teile, Gezaehltes bleibt', () {
      final mixed = saft().mixedAt(1).scaledTo(500);
      expect(mixed.parts.first.amount, 250);
      expect(mixed.parts.last.amount, 250);

      final tee = DrinkDraft(title: 'Tee', parts: [const DrinkPart(name: 'Beutel', amount: 1, unit: EntryUnit.piece), DrinkPart.water(250)]);
      final bigger = tee.scaledTo(500);
      expect(bigger.parts.first.amount, 1);
      expect(bigger.parts.last.amount, 500);
      expect(tee.canMix, isFalse, reason: 'ein Beutel laesst sich nicht 1:1 teilen');
    });

    test('mehr als eine Basis: kein Verhaeltnis', () {
      final kaffee = DrinkDraft(title: 'Milchkaffee', parts: const [DrinkPart(name: 'Kaffee', amount: 150), DrinkPart(name: 'Milch', amount: 100)]);
      expect(kaffee.canMix, isFalse);
      expect(kaffee.ratio, isNull);
    });

    test('Zeilen: haeufigste zuerst, Produkte aus dem Bestand fuellen auf, was es pur schon gibt, nicht doppelt', () {
      final rows = rankDrinkRows(
        drinkMeals: [
          (id: 'a1', title: 'Orangensaft gespritzt', eatenAtUtc: _now.subtract(const Duration(days: 3))),
          (id: 'a2', title: 'orangensaft gespritzt ', eatenAtUtc: _now.subtract(const Duration(days: 1))),
          (id: 'b', title: 'Cola', eatenAtUtc: _now.subtract(const Duration(days: 2))),
          (id: 'alt', title: 'Uralt', eatenAtUtc: _now.subtract(const Duration(days: 90))),
        ],
        inStock: const [(id: 'pc', name: 'Coca-Cola'), (id: 'py', name: 'Yakult'), (id: 'pa', name: 'Apfelsaft')],
        pureProductOf: (id) => id == 'b' ? 'pc' : null,
        now: _now,
      );
      expect([for (final r in rows) r.title], ['orangensaft gespritzt', 'Cola', 'Apfelsaft', 'Yakult']);
      expect(rows.first.templateMealId, 'a2', reason: 'der juengste Eintrag ist die Vorlage');
      expect(rows.last.productId, 'py');
    });

    test('Zeilen: das Limit gilt', () {
      final rows = rankDrinkRows(
        drinkMeals: const [],
        inStock: [for (var i = 0; i < 20; i++) (id: 'p$i', name: 'P$i')],
        pureProductOf: (_) => null,
        now: _now,
      );
      expect(rows, hasLength(8));
    });
  });

  group('Erste Menge eines Produkts', () {
    test('Glas, Flaeschchen der Mehrfachpackung, Stueck mit und ohne Volumen', () {
      expect(drinkFromProduct(_product('a', 'Saft', packSize: 1))!.totalMl, 250);
      expect(drinkFromProduct(_product('y', 'Yakult', packSize: 0.39, pieces: 6))!.totalMl, 65);
      expect(drinkFromProduct(_product('r', 'Red Bull', baseUnit: 'piece', unitWeightG: 250))!.totalMl, 250);
      expect(drinkFromProduct(_product('i', 'Innocent', baseUnit: 'piece')), isNull);
    });
  });

  group('Buchen', () {
    late AppDatabase db;
    late MealRepository meals;
    late DrinkRepository drinks;
    setUp(() {
      db = memoryDb();
      meals = mealRepo(db);
      drinks = DrinkRepository(meals);
    });
    tearDown(() => db.close());

    Future<(Product, InventoryItem)> saftImBestand() async {
      final saft = await productRepo(db).create(name: 'Orangensaft', baseUnit: 'l', packSize: 1, nutrientsPer100: const {'kcal': 45.0}, nutrientsBasis: 'g', nutrientsSource: 'off');
      final item = await inventoryRepo(db).recordFromScan(productId: saft.id, ean: '9001234567890', quantity: 1, unit: 'l', now: DateTime.utc(2026, 10, 1));
      return (saft, item);
    }

    Future<InventoryItem> itemOf(String id) => (db.select(db.inventoryItems)..where((i) => i.id.equals(id))).getSingle();

    test('gespritzt: nur der Saft geht vom Bestand, die Kalorien auch nur vom Saft, Rueckgaengig bucht zurueck', () async {
      final (saft, item) = await saftImBestand();
      final meal = await drinks.book(
        DrinkDraft(title: 'Orangensaft gespritzt', parts: [DrinkPart(name: saft.name, amount: 125, productId: saft.id), DrinkPart.water(125)]),
        at: _now,
        inStock: {saft.id},
      );

      expect(meal.mealType, 'drink');
      expect(meal.eatenAt, _now);
      expect((await itemOf(item.id)).quantity, closeTo(0.875, 1e-9));
      final ingredients = await meals.ingredientsOf(meal.id);
      expect(ingredients, hasLength(2));
      final juice = ingredients.firstWhere((i) => i.productId == saft.id);
      final water = ingredients.firstWhere((i) => i.productId == null);
      expect(juice.kcal, closeTo(56.25, 0.01));
      expect(water.freeText, 'Wasser');
      expect(water.blsCode, waterBlsCode);
      expect(water.kcal, 0);
      expect(water.inventoryItemId, isNull);

      await drinks.undo(meal.id);
      expect((await itemOf(item.id)).quantity, closeTo(1, 1e-9));
      expect((await meals.get(meal.id))!.deletedAt, isNotNull);
    });

    test('nicht im Bestand: zaehlt fuer die Naehrwerte, Bestand bleibt', () async {
      final (saft, item) = await saftImBestand();
      final meal = await drinks.book(DrinkDraft(title: 'Saft', parts: [DrinkPart(name: saft.name, amount: 250, productId: saft.id)]), at: _now, inStock: const {});
      expect((await itemOf(item.id)).quantity, 1);
      expect((await meals.ingredientsOf(meal.id)).single.kcal, closeTo(112.5, 0.01));
    });

    test('ein Eintrag wird zur Vorlage: dieselben Teile, Mengen und Naehrwerte', () async {
      final (saft, _) = await saftImBestand();
      final first = await drinks.book(
        DrinkDraft(title: 'Orangensaft gespritzt', parts: [DrinkPart(name: saft.name, amount: 100, productId: saft.id), DrinkPart.water(200)]),
        at: _now,
        inStock: {saft.id},
      );
      final again = drinkFromMeal(first, await meals.ingredientsOf(first.id), {saft.id: saft});
      expect(again.title, 'Orangensaft gespritzt');
      expect(again.totalMl, 300);
      expect(again.ratio, 2);
      expect(again.parts.last.isWater, isTrue);

      final second = await drinks.book(again, at: _now.add(const Duration(hours: 1)), inStock: {saft.id});
      final rows = await meals.ingredientsOf(second.id);
      expect(rows.firstWhere((i) => i.productId == saft.id).kcal, closeTo(45, 0.01));
      expect(rows.firstWhere((i) => i.productId == null).blsCode, waterBlsCode);
    });

    test('Vorlage mit geloeschtem Produkt bleibt mit ihren Werten nutzbar, ohne Abzug', () async {
      final (saft, _) = await saftImBestand();
      final first = await drinks.book(DrinkDraft(title: 'Saft', parts: [DrinkPart(name: saft.name, amount: 200, productId: saft.id)]), at: _now, inStock: {saft.id});
      final ingredient = (await meals.ingredientsOf(first.id)).single.copyWith(freeText: const Value('Alter Saft'));
      final again = drinkFromMeal(first, [ingredient], const {});
      expect(again.parts.single.productId, isNull);
      expect(again.parts.single.name, 'Alter Saft');
      final second = await drinks.book(again, at: _now, inStock: const {});
      expect((await meals.ingredientsOf(second.id)).single.kcal, closeTo(90, 0.01));
    });

    test('Produkt merkt sich die Entscheidung, null gibt sie an die Regel zurueck', () async {
      final repo = productRepo(db);
      final p = await repo.create(name: 'Kürbiskernöl', baseUnit: 'l');
      expect(p.isDrink, isNull);
      await repo.setIsDrink(p.id, true);
      expect((await repo.byId(p.id))!.isDrink, isTrue);
      await repo.setIsDrink(p.id, null);
      expect((await repo.byId(p.id))!.isDrink, isNull);
    });
  });

  group('Abschnitt auf der Seite', () {
    late AppDatabase db;
    late MealRepository meals;
    var products = <Product>[];
    var stock = <InventoryItem>[];
    var categories = <Category>[];
    var mealRows = <Meal>[];
    var ingredients = <MealIngredient>[];

    setUp(() {
      db = memoryDb();
      meals = mealRepo(db);
      products = [];
      stock = [];
      categories = [];
      mealRows = [];
      ingredients = [];
    });
    tearDown(() => db.close());

    InventoryItem inStock(String productId) => InventoryItem(
        id: 'i-$productId', householdId: 'h1', productId: productId, quantity: 1, unit: 'l', location: 'pantry', dateKind: 'best_before', status: 'sealed', isSuggestion: false, updatedAt: DateTime.utc(2026));

    Widget host() => ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            mealRepositoryProvider.overrideWithValue(meals),
            productRepositoryProvider.overrideWithValue(productRepo(db)),
            mealsStreamProvider.overrideWith((ref) => Stream.value(mealRows)),
            mealIngredientsStreamProvider.overrideWith((ref) => Stream.value(ingredients)),
            productsStreamProvider.overrideWith((ref) => Stream.value(products)),
            activeInventoryStreamProvider.overrideWith((ref) => Stream.value(stock)),
            categoriesStreamProvider.overrideWith((ref) => Stream.value(categories)),
            blsFoodSearchProvider.overrideWithValue(FakeBlsFoodSearch()),
          ],
          child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: DrinksSection(now: _now)))),
        );

    /// Ein echtes Produkt in der Datenbank, damit das Buchen es findet.
    Future<Product> saved(String name, {double? packSize = 1, String baseUnit = 'l', bool? isDrink}) async {
      final p = await productRepo(db).create(name: name, baseUnit: baseUnit, packSize: packSize, isDrink: isDrink, nutrientsPer100: const {'kcal': 45.0}, nutrientsBasis: 'g', nutrientsSource: 'off');
      products = [...products, p];
      return p;
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    void sectionTest(String name, Future<void> Function(WidgetTester tester) body) => testWidgets(name, (tester) async {
          tester.view.physicalSize = const Size(1000, 2400);
          addTearDown(tester.view.resetPhysicalSize);
          await body(tester);
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 1));
        });

    sectionTest('Getraenk im Bestand: ein Tipp bucht ein Glas, Rueckgaengig nimmt es zurueck', (tester) async {
      final saft = await saved('Orangensaft');
      stock = [inStock(saft.id)];
      await tester.pumpWidget(host());
      await settle(tester);

      expect(find.text('Orangensaft'), findsOneWidget);
      await tester.tap(find.byKey(const Key('drink-take-0')));
      await settle(tester);

      final booked = (await db.select(db.meals).get()).single;
      expect(booked.mealType, 'drink');
      expect(booked.title, 'Orangensaft');
      expect(find.textContaining('250 ml eingetragen'), findsOneWidget);

      await tester.tap(find.text('Rückgängig'));
      await settle(tester);
      expect((await db.select(db.meals).getSingle()).deletedAt, isNotNull);
    });

    sectionTest('Nicht Trinkbares im Bestand steht nicht in der Liste', (tester) async {
      final oel = await saved('Kürbiskernöl');
      final korrigiert = await saved('Spezialmischung', isDrink: true);
      stock = [inStock(oel.id), inStock(korrigiert.id)];
      await tester.pumpWidget(host());
      await settle(tester);
      expect(find.text('Kürbiskernöl'), findsNothing);
      expect(find.text('Spezialmischung'), findsOneWidget);
    });

    sectionTest('Zeile antippen: 1:1 gemischt wird als eigene Mischung gebucht', (tester) async {
      final saft = await saved('Orangensaft');
      stock = [inStock(saft.id)];
      await tester.pumpWidget(host());
      await settle(tester);

      await tester.tap(find.descendant(of: find.byKey(const Key('drink-row-0')), matching: find.byIcon(Icons.local_drink_outlined)));
      await settle(tester);
      await tester.tap(find.byKey(const Key('drink-ratio-1')));
      await settle(tester);
      expect(tester.widget<TextField>(find.byKey(const Key('drink-name'))).controller!.text, 'Orangensaft gespritzt');

      await tester.tap(find.byKey(const Key('drink-book')));
      await settle(tester);

      final meal = (await db.select(db.meals).get()).single;
      expect(meal.title, 'Orangensaft gespritzt');
      final rows = await meals.ingredientsOf(meal.id);
      expect(rows, hasLength(2));
      expect(rows.firstWhere((i) => i.productId == saft.id).kcal, closeTo(56.25, 0.01));
    });

    sectionTest('Fruehere Mischung: ein Tipp bucht sie wieder', (tester) async {
      final saft = await saved('Orangensaft');
      final first = await DrinkRepository(meals).book(
        DrinkDraft(title: 'Orangensaft gespritzt', parts: [DrinkPart(name: saft.name, amount: 100, productId: saft.id), DrinkPart.water(100)]),
        at: _now.subtract(const Duration(days: 1)),
        inStock: const {},
      );
      mealRows = [first];
      ingredients = await meals.ingredientsOf(first.id);
      await tester.pumpWidget(host());
      await settle(tester);

      expect(find.textContaining('Orangensaft 100 ml + Wasser 100 ml'), findsOneWidget);
      expect(find.text('+ 200 ml'), findsOneWidget);
      await tester.tap(find.byKey(const Key('drink-take-0')));
      await settle(tester);

      final all = await db.select(db.meals).get();
      expect(all, hasLength(2));
      expect(all.every((m) => m.title == 'Orangensaft gespritzt'), isTrue);
    });

    sectionTest('Stueckware ohne Volumen: fragt einmal danach und merkt es sich', (tester) async {
      final innocent = await saved('Innocent Saft', baseUnit: 'piece', packSize: null, isDrink: true);
      stock = [inStock(innocent.id)];
      await tester.pumpWidget(host());
      await settle(tester);

      expect(find.text('Menge'), findsOneWidget);
      await tester.tap(find.byKey(const Key('drink-take-0')));
      await settle(tester);
      expect(await db.select(db.meals).get(), isEmpty, reason: 'ohne Volumen wird nichts gebucht');
      expect(tester.widget<FilledButton>(find.byKey(const Key('drink-book'))).onPressed, isNull);

      await tester.enterText(find.byKey(const Key('drink-piece-ml')), '330');
      await tester.pump();
      await tester.tap(find.byKey(const Key('drink-book')));
      await settle(tester);

      expect((await productRepo(db).byId(innocent.id))!.unitWeightG, 330);
      final meal = (await db.select(db.meals).get()).single;
      expect((await meals.ingredientsOf(meal.id)).single.amountG, closeTo(330, 0.01));
    });

    sectionTest('Menge ueber die Flaschengroesse', (tester) async {
      final cola = await saved('Cola', packSize: 0.33, isDrink: true);
      stock = [inStock(cola.id)];
      await tester.pumpWidget(host());
      await settle(tester);

      await tester.tap(find.descendant(of: find.byKey(const Key('drink-row-0')), matching: find.byIcon(Icons.local_drink_outlined)));
      await settle(tester);
      await tester.tap(find.byKey(const Key('drink-size-330')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('drink-book')));
      await settle(tester);

      final meal = (await db.select(db.meals).get()).single;
      expect((await meals.ingredientsOf(meal.id)).single.amountG, closeTo(330, 0.01));
    });
  });
}
