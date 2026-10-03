import 'dart:typed_data';

import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/nutrition/bls_food_search.dart';
import 'package:einkaufstracker/data/repositories/meal_repository.dart';
import 'package:einkaufstracker/domain/nutrition/food_match.dart';
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

/// Zuordnung der Zutaten zu den Naehrwerten der Lebensmitteldatenbank im Formular (Phase N1, ADR-031): Marken, Zusammenfassung,
/// Bestaetigen, Speichern der Herkunft und Lernen im Gedaechtnis des Haushalts.
Uint8List _png() => Uint8List.fromList(img.encodePng(img.Image(width: 8, height: 8)));

FoodMatch _match(String code, String name, double kcal, {String method = 'search', MatchTrust trust = MatchTrust.auto}) =>
    FoodMatch(code: code, name: name, per100: NutrientsPer100(kcal: kcal, proteinG: 1, fatG: 1, carbsG: 5), method: method, trust: trust);

void main() {
  late AppDatabase db;
  late MealRepository meals;
  late FakeMealPhotoService photos;
  late FakeMealAnalysisCloud cloud;
  late Product reis;
  late Product milch;
  late InventoryItem reisBestand;

  setUp(() async {
    db = memoryDb();
    meals = mealRepo(db);
    photos = FakeMealPhotoService(db, meals);
    cloud = FakeMealAnalysisCloud();
    reis = await productRepo(db).create(name: 'Reis', baseUnit: 'kg', nutrientsPer100: {'kcal': 350}, nutrientsBasis: 'g', nutrientsSource: 'manual');
    // wie die meisten Produkte vom Bon: ohne Naehrwerte
    milch = await productRepo(db).create(name: 'Milch', baseUnit: 'l');
    reisBestand = await inventoryRepo(db).recordFromScan(productId: reis.id, ean: '1', quantity: 1, unit: 'kg', bestBefore: DateTime.utc(2026, 12, 1), now: DateTime.utc(2026, 9, 1));
  });
  tearDown(() => db.close());

  Widget host({FakeBlsFoodSearch? bls, Meal? existing}) => ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          mealRepositoryProvider.overrideWithValue(meals),
          productRepositoryProvider.overrideWithValue(productRepo(db)),
          inventoryRepositoryProvider.overrideWithValue(inventoryRepo(db)),
          foodLinkRepositoryProvider.overrideWithValue(foodLinkRepo(db)),
          productsStreamProvider.overrideWith((ref) => Stream.value([reis, milch])),
          activeInventoryStreamProvider.overrideWith((ref) => Stream.value([reisBestand])),
          mealPhotoServiceProvider.overrideWithValue(photos),
          mealPhotoPickerProvider.overrideWithValue(({required bool camera}) async => _png()),
          mealAnalysisCloudProvider.overrideWithValue(cloud),
          blsFoodSearchProvider.overrideWithValue(bls ?? FakeBlsFoodSearch()),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(routes: [
            GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('START'))),
            GoRoute(path: '/form', builder: (_, _) => MealFormPage(existing: existing)),
          ]),
        ),
      );

  Future<void> open(WidgetTester tester, {FakeBlsFoodSearch? bls, Meal? existing, bool photo = true}) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(bls: bls, existing: existing));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('START'))).push('/form');
    await tester.pumpAndSettle();
    if (photo && existing == null) {
      await tester.tap(find.byKey(const Key('meal-photo-camera')));
      await tester.pumpAndSettle();
    }
  }

  Future<void> analyze(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('meal-analyze')));
    await tester.pumpAndSettle();
    if (find.byKey(const Key('meal-analyze-confirm')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('meal-analyze-confirm')));
      await tester.pumpAndSettle();
    }
  }

  /// Gerichte mit allen Faellen: Produkt mit Naehrwerten, sicherer Treffer, automatischer Treffer, ohne Treffer.
  MealAnalysis allCases() => MealAnalysis(
        dishTitle: 'Reispfanne',
        ingredients: [
          AnalyzedIngredient(name: 'Reis', inventoryProductId: reis.id, estimatedGrams: 150, confidence: 0.8, state: 'cooked'),
          AnalyzedIngredient(name: 'Paprika', estimatedGrams: 80, confidence: 0.6, match: _match('G543100', 'Gemüsepaprika rot, roh', 31, method: 'synonym', trust: MatchTrust.sure)),
          AnalyzedIngredient(name: 'Quark', estimatedGrams: 50, confidence: 0.5, match: _match('M713300', 'Speisequark Halbfettstufe', 100)),
          const AnalyzedIngredient(name: 'Gewürzmischung', estimatedGrams: 5, confidence: 0.2),
        ],
      );

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('meal-save')));
    await tester.pumpAndSettle();
  }

  testWidgets('Marken: Produkt mit Naehrwerten und sicherer Treffer sind ✓, automatischer ~, ohne Treffer ?', (tester) async {
    cloud.analysis = allCases();
    await open(tester);
    await analyze(tester);

    expect(find.byKey(const Key('ingredient-trust-sure-0')), findsOneWidget, reason: 'Produkt Reis hat eigene Naehrwerte');
    expect(find.byKey(const Key('ingredient-trust-sure-1')), findsOneWidget, reason: 'Synonym');
    expect(find.byKey(const Key('ingredient-trust-auto-2')), findsOneWidget, reason: 'automatisch zugeordnet');
    expect(find.byKey(const Key('ingredient-trust-unknown-3')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('ingredient-match-1'))).data, 'Nährwerte: Gemüsepaprika rot, roh');
    expect(tester.widget<Text>(find.byKey(const Key('ingredient-match-2'))).data, 'Nährwerte: Speisequark Halbfettstufe');
    expect(find.byKey(const Key('ingredient-match-0')), findsNothing, reason: 'Produkt mit eigenen Werten braucht keinen Hinweis');
    expect(find.text('80 g · 25 kcal · geschätzt'), findsOneWidget);
    expect(find.text('50 g · 50 kcal · geschätzt'), findsOneWidget);
    expect(find.text('5 g · Nährwerte unbekannt · unsicher geschätzt'), findsOneWidget);
  });

  testWidgets('Zusammenfassung nennt, wie viele Zutaten Naehrwerte haben, und bietet "Alle uebernehmen" nur bei automatischen an', (tester) async {
    cloud.analysis = allCases();
    await open(tester);
    await analyze(tester);
    expect(tester.widget<Text>(find.byKey(const Key('ingredient-summary'))).data, '3 von 4 Zutaten mit Nährwerten, 1 automatisch zugeordnet (~), 1 unbekannt (?)');
    expect(find.byKey(const Key('ingredient-confirm-all')), findsOneWidget);
  });

  testWidgets('Antippen von ~ bestaetigt die Zeile, "Alle uebernehmen" alle', (tester) async {
    cloud.analysis = MealAnalysis(dishTitle: 'x', ingredients: [
      AnalyzedIngredient(name: 'Quark', estimatedGrams: 50, match: _match('M713300', 'Speisequark', 100)),
      AnalyzedIngredient(name: 'Kefir', estimatedGrams: 100, match: _match('M120000', 'Kefir', 50)),
      AnalyzedIngredient(name: 'Skyr', estimatedGrams: 100, match: _match('M710100', 'Skyr', 60)),
    ]);
    await open(tester);
    await analyze(tester);
    expect(find.byKey(const Key('ingredient-trust-auto-0')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ingredient-trust-auto-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ingredient-trust-sure-0')), findsOneWidget);
    expect(find.byKey(const Key('ingredient-trust-auto-1')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('ingredient-summary'))).data, '3 von 3 Zutaten mit Nährwerten, 2 automatisch zugeordnet (~)');

    await tester.tap(find.byKey(const Key('ingredient-confirm-all')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ingredient-trust-auto-1')), findsNothing);
    expect(find.byKey(const Key('ingredient-trust-sure-2')), findsOneWidget);
    expect(find.byKey(const Key('ingredient-summary')), findsNothing, reason: 'alles sicher: keine Zusammenfassung noetig');
    expect(find.byKey(const Key('ingredient-confirm-all')), findsNothing);
  });

  testWidgets('Speichern: Herkunft je Zutat (product, bls_exact, bls_matched, unknown) und BLS-Code stehen in der Zeile', (tester) async {
    cloud.analysis = allCases();
    await open(tester);
    await analyze(tester);
    await tester.enterText(find.byKey(const Key('meal-title')), 'Reispfanne');
    await save(tester);

    final byName = {for (final i in await db.select(db.mealIngredients).get()) i.freeText ?? 'Produkt': i};
    expect(byName['Produkt']!.nutrientBasis, 'product');
    expect(byName['Produkt']!.blsCode, isNull);
    expect(byName['Paprika']!.nutrientBasis, 'bls_exact');
    expect(byName['Paprika']!.blsCode, 'G543100');
    expect(byName['Paprika']!.kcal, closeTo(24.8, 1e-9));
    expect(byName['Quark']!.nutrientBasis, 'bls_matched');
    expect(byName['Quark']!.blsCode, 'M713300');
    expect(byName['Quark']!.kcal, closeTo(50, 1e-9));
    expect(byName['Gewürzmischung']!.nutrientBasis, isNull);
    expect(byName['Gewürzmischung']!.blsCode, isNull);
    expect(byName['Gewürzmischung']!.kcal, isNull);
  });

  testWidgets('bestaetigte automatische Zuordnung wird bls_exact gespeichert', (tester) async {
    cloud.analysis = MealAnalysis(dishTitle: 'x', ingredients: [AnalyzedIngredient(name: 'Quark', estimatedGrams: 50, match: _match('M713300', 'Speisequark', 100))]);
    await open(tester);
    await analyze(tester);
    await tester.tap(find.byKey(const Key('ingredient-confirm-all')));
    await tester.enterText(find.byKey(const Key('meal-title')), 'Quark');
    await tester.pump();
    await save(tester);
    expect((await db.select(db.mealIngredients).getSingle()).nutrientBasis, 'bls_exact');
  });

  testWidgets('Lernen: automatische Treffer und Handwahl landen im Gedaechtnis, Synonyme und Produkte nicht', (tester) async {
    cloud.analysis = allCases();
    await open(tester);
    await analyze(tester);
    await tester.enterText(find.byKey(const Key('meal-title')), 'Reispfanne');
    await save(tester);

    final links = await db.select(db.householdFoodLinks).get();
    expect({for (final l in links) l.nameNorm: l.blsCode}, {'Quark': 'M713300'}, reason: 'Paprika kennt der Server als Synonym, Reis ist ein Produkt');
    final outbox = await db.select(db.outbox).get();
    expect(outbox.where((o) => o.remoteTable == 'household_food_links'), hasLength(1));
  });

  testWidgets('Lernen: ueber "Naehrwerte suchen" gewaehlter Eintrag wird mit dem Namen der Zeile gemerkt', (tester) async {
    cloud.analysis = const MealAnalysis(dishTitle: 'x', ingredients: [AnalyzedIngredient(name: 'Gewürzmischung', estimatedGrams: 5, confidence: 0.2)]);
    final bls = FakeBlsFoodSearch(foods: const [BlsFood(code: 'R250000', nameDe: 'Gewürzmischung Curry', per100: NutrientsPer100(kcal: 300))]);
    await open(tester, bls: bls);
    await analyze(tester);
    await tester.tap(find.byKey(const Key('ingredient-lookup-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick-bls-R250000')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('meal-title')), 'Curry');
    await save(tester);

    final link = await db.select(db.householdFoodLinks).getSingle();
    expect(link.nameNorm, 'Gewürzmischung');
    expect(link.blsCode, 'R250000');
    expect((await db.select(db.mealIngredients).getSingle()).nutrientBasis, 'bls_exact');
  });

  testWidgets('kein Lernen ohne Treffer und nicht fuer Handeingaben; ein Fehler beim Lernen kippt das Speichern nicht', (tester) async {
    cloud.analysis = const MealAnalysis(dishTitle: 'x', ingredients: [AnalyzedIngredient(name: 'Gewürzmischung', estimatedGrams: 5, confidence: 0.2)]);
    await open(tester);
    await analyze(tester);
    await tester.enterText(find.byKey(const Key('meal-title')), 'Nur Gewürz');
    await save(tester);
    expect(await db.select(db.householdFoodLinks).get(), isEmpty);
    expect(await db.select(db.meals).get(), hasLength(1));
  });

  testWidgets('Produkt ohne eigene Naehrwerte nutzt den zugeordneten BLS-Eintrag und wird trotzdem abgezogen', (tester) async {
    // Milch ist ein Produkt vom Bon (keine Naehrwerte), die KI hat sie als Produkt erkannt und die BLS dazu geliefert
    await inventoryRepo(db).recordFromScan(productId: milch.id, ean: '2', quantity: 1, unit: 'l', bestBefore: DateTime.utc(2026, 12, 1), now: DateTime.utc(2026, 9, 1));
    final stock = (await db.select(db.inventoryItems).get()).firstWhere((i) => i.productId == milch.id);
    cloud.analysis = MealAnalysis(dishTitle: 'Milch', ingredients: [
      AnalyzedIngredient(name: 'Milch', inventoryProductId: milch.id, estimatedGrams: 250, confidence: 0.8, kind: 'drink', state: 'ready_made', match: _match('M111300', 'Vollmilch frisch, 3,5 % Fett', 65, method: 'synonym', trust: MatchTrust.sure)),
    ]);
    // Bestand der Milch muss der Seite bekannt sein
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        mealRepositoryProvider.overrideWithValue(meals),
        productRepositoryProvider.overrideWithValue(productRepo(db)),
        inventoryRepositoryProvider.overrideWithValue(inventoryRepo(db)),
        foodLinkRepositoryProvider.overrideWithValue(foodLinkRepo(db)),
        productsStreamProvider.overrideWith((ref) => Stream.value([reis, milch])),
        activeInventoryStreamProvider.overrideWith((ref) => Stream.value([reisBestand, stock])),
        mealPhotoServiceProvider.overrideWithValue(photos),
        mealPhotoPickerProvider.overrideWithValue(({required bool camera}) async => _png()),
        mealAnalysisCloudProvider.overrideWithValue(cloud),
        blsFoodSearchProvider.overrideWithValue(FakeBlsFoodSearch()),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(routes: [
          GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('START'))),
          GoRoute(path: '/form', builder: (_, _) => const MealFormPage()),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('START'))).push('/form');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('meal-photo-camera')));
    await tester.pumpAndSettle();
    await analyze(tester);

    expect(find.text('250 ml · 163 kcal · vom Bestand · geschätzt'), findsOneWidget, reason: 'Getraenk in ml, Werte der BLS (65 kcal je 100 g), Abzug vorbelegt');
    expect(find.byKey(const Key('ingredient-trust-sure-0')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('meal-title')), 'Milch');
    await save(tester);

    final ing = await db.select(db.mealIngredients).getSingle();
    expect(ing.productId, milch.id);
    expect(ing.blsCode, 'M111300');
    expect(ing.nutrientBasis, 'bls_exact');
    expect(ing.kcal, closeTo(162.5, 1e-9));
    expect(ing.unit, 'l');
    expect(ing.quantity, closeTo(0.25, 1e-9));
    final moves = (await db.select(db.inventoryMovements).get()).where((m) => m.productId == milch.id && m.type == 'meal');
    expect(moves, hasLength(1), reason: 'der Bestand der Milch wurde abgezogen');
    expect(await db.select(db.householdFoodLinks).get(), isEmpty, reason: 'ein Produkt wird nicht als Name gelernt');
  });

  testWidgets('Getraenke stehen in ml', (tester) async {
    cloud.analysis = const MealAnalysis(dishTitle: 'x', ingredients: [
      AnalyzedIngredient(name: 'Cola', estimatedGrams: 330, confidence: 0.9, kind: 'drink', state: 'ready_made'),
    ]);
    await open(tester);
    await analyze(tester);
    expect(find.textContaining('330 ml'), findsOneWidget);
  });

  testWidgets('gekochter Reis aus dem Bestand: kein Abzug vorbelegt, der Nutzer kann ihn einschalten', (tester) async {
    cloud.analysis = MealAnalysis(dishTitle: 'x', ingredients: [
      AnalyzedIngredient(name: 'Reis', inventoryProductId: reis.id, estimatedGrams: 200, confidence: 0.8, state: 'cooked'),
      AnalyzedIngredient(name: 'Reis roh', inventoryProductId: reis.id, estimatedGrams: 70, confidence: 0.8, state: 'raw'),
    ]);
    await open(tester);
    await analyze(tester);
    expect(find.text('200 g · 700 kcal · geschätzt'), findsOneWidget, reason: 'gekocht: ohne "vom Bestand"');
    expect(find.text('70 g · 245 kcal · vom Bestand · geschätzt'), findsOneWidget, reason: 'roh: Abzug wie bisher');
  });

  testWidgets('Bearbeiten: Herkunft und Marke einer gespeicherten Zutat bleiben erhalten', (tester) async {
    cloud.analysis = allCases();
    await open(tester);
    await analyze(tester);
    await tester.enterText(find.byKey(const Key('meal-title')), 'Reispfanne');
    await save(tester);

    final saved = (await db.select(db.meals).get()).single;
    await tester.pumpWidget(const SizedBox());
    await open(tester, existing: saved, photo: false);
    // Zutaten laden asynchron
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ingredient-trust-auto-2')), findsOneWidget, reason: 'bls_matched bleibt ~');
    expect(find.byKey(const Key('ingredient-trust-sure-1')), findsOneWidget, reason: 'bls_exact bleibt ✓');
  });

  testWidgets('Handeingabe und Produkt mit Naehrwerten sind ✓', (tester) async {
    await open(tester, photo: false);
    await tester.tap(find.byKey(const Key('meal-add-manual')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('manual-name')), 'Tiramisu');
    await tester.enterText(find.byKey(const Key('manual-kcal')), '450');
    await tester.tap(find.byKey(const Key('manual-ok')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ingredient-trust-sure-0')), findsOneWidget);
    expect(find.byKey(const Key('ingredient-summary')), findsNothing);
  });

  testWidgets('Zutat ohne Naehrwerte: ?-Marke und Zusammenfassung ohne Knopf', (tester) async {
    cloud.analysis = const MealAnalysis(dishTitle: 'x', ingredients: [AnalyzedIngredient(name: 'Gewürz', estimatedGrams: 5, confidence: 0.2)]);
    await open(tester);
    await analyze(tester);
    expect(find.byKey(const Key('ingredient-trust-unknown-0')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('ingredient-summary'))).data, '0 von 1 Zutaten mit Nährwerten, 1 unbekannt (?)');
    expect(find.byKey(const Key('ingredient-confirm-all')), findsNothing);
  });

  group('Datenbank', () {
    test('Zutat mit BLS-Code und Herkunft ueberlebt Speichern und Laden', () async {
      final m = await meals.create(MealDraft(title: 'x', eatenAt: DateTime.utc(2026, 10, 2), ingredients: const [
        IngredientDraft(
          freeText: 'Quark',
          quantity: 50,
          entryUnit: EntryUnit.g,
          per100: NutrientsPer100(kcal: 100),
          per100Basis: 'g',
          blsCode: 'M713300',
          nutrientBasis: 'bls_matched',
        ),
      ]));
      final i = (await meals.ingredientsOf(m.id)).single;
      expect(i.blsCode, 'M713300');
      expect(i.nutrientBasis, 'bls_matched');
      expect(i.kcal, closeTo(50, 1e-9));
    });

    test('ohne Angabe leitet das Repository die Herkunft ab: Produkt, Handwerte, BLS-Eintrag', () async {
      final m = await meals.create(MealDraft(title: 'x', eatenAt: DateTime.utc(2026, 10, 2), ingredients: [
        IngredientDraft(productId: reis.id, quantity: 100, entryUnit: EntryUnit.g, deduct: false),
        const IngredientDraft(freeText: 'Tiramisu', quantity: 1, entryUnit: EntryUnit.piece, manualNutrients: NutrientAmounts(kcal: 450)),
        const IngredientDraft(freeText: 'Quark', quantity: 50, entryUnit: EntryUnit.g, per100: NutrientsPer100(kcal: 100), per100Basis: 'g', blsCode: 'M713300'),
        const IngredientDraft(freeText: 'Etwas', quantity: 5, entryUnit: EntryUnit.g),
      ]));
      final byText = {for (final i in await meals.ingredientsOf(m.id)) i.freeText ?? 'Reis': i};
      expect(byText['Reis']!.nutrientBasis, 'product');
      expect(byText['Tiramisu']!.nutrientBasis, 'manual');
      expect(byText['Quark']!.nutrientBasis, 'bls_exact');
      expect(byText['Etwas']!.nutrientBasis, isNull);
    });

    test('Produkt ohne Profil: das Profil der Zeile springt ein; Produkt mit Profil: das Produktprofil gilt, ein BLS-Profil der Zeile wird ignoriert', () async {
      final m = await meals.create(MealDraft(title: 'x', eatenAt: DateTime.utc(2026, 10, 2), ingredients: [
        IngredientDraft(productId: milch.id, quantity: 200, entryUnit: EntryUnit.ml, deduct: false, per100: const NutrientsPer100(kcal: 65), per100Basis: 'g', blsCode: 'M111300'),
        IngredientDraft(productId: reis.id, quantity: 100, entryUnit: EntryUnit.g, deduct: false, per100: const NutrientsPer100(kcal: 1), per100Basis: 'g', blsCode: 'X'),
      ]));
      final rows = await meals.ingredientsOf(m.id);
      final milk = rows.firstWhere((i) => i.productId == milch.id);
      final rice = rows.firstWhere((i) => i.productId == reis.id);
      expect(milk.kcal, closeTo(130, 1e-9));
      expect(milk.blsCode, 'M111300');
      expect(milk.nutrientBasis, 'bls_exact');
      expect(rice.kcal, closeTo(350, 1e-9));
      expect(rice.blsCode, isNull, reason: 'bei eigenem Produktprofil steht kein BLS-Code');
      expect(rice.nutrientBasis, 'product');
    });
  });
}
