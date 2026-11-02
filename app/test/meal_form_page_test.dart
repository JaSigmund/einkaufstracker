import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/nutrition/bls_food_search.dart';
import 'package:einkaufstracker/data/repositories/meal_repository.dart';
import 'package:einkaufstracker/domain/nutrition/ingredient_nutrition.dart';
import 'package:einkaufstracker/domain/nutrition/nutrient_scaling.dart';
import 'package:einkaufstracker/features/diary/meal_form_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';

/// Formular fuer Mahlzeiten (Doku 15 §3.1, Phase 7b). Die Datums-/Zeit-Dialoge von Material werden hier bewusst nicht
/// bedient (ihre Animationen lassen pumpAndSettle haengen, bekannte Grenze dieses Projekts); die Wirkung auf die Daten
/// ist ueber meal_repository_test abgedeckt.
DateTime _d(int y, int m, int d, [int h = 12]) => DateTime.utc(y, m, d, h);

void main() {
  late AppDatabase db;
  late Product reis;
  late FakeBlsFoodSearch bls;

  setUp(() async {
    db = memoryDb();
    bls = FakeBlsFoodSearch(foods: const [
      BlsFood(code: 'G543100', nameDe: 'Gemüsepaprika rot, roh', per100: NutrientsPer100(kcal: 36, proteinG: 1.0)),
    ]);
    reis = await productRepo(db).create(
      name: 'Reis',
      baseUnit: 'kg',
      nutrientsPer100: {'kcal': 350, 'protein_g': 7},
      nutrientsBasis: 'g',
      nutrientsSource: 'manual',
    );
  });
  tearDown(() => db.close());

  Future<InventoryItem> stock(double qty) =>
      inventoryRepo(db).recordFromScan(productId: reis.id, ean: '1', quantity: qty, unit: 'kg', bestBefore: _d(2026, 12, 1), now: _d(2026, 9, 1));

  Widget host({Meal? existing, List<InventoryItem> active = const []}) => ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          mealRepositoryProvider.overrideWithValue(mealRepo(db)),
          productRepositoryProvider.overrideWithValue(productRepo(db)),
          inventoryRepositoryProvider.overrideWithValue(inventoryRepo(db)),
          productsStreamProvider.overrideWith((ref) => Stream.value([reis])),
          activeInventoryStreamProvider.overrideWith((ref) => Stream.value(active)),
          blsFoodSearchProvider.overrideWithValue(bls),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(initialLocation: '/', routes: [
            GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('START'))),
            GoRoute(path: '/form', builder: (_, _) => MealFormPage(existing: existing)),
          ]),
        ),
      );

  Future<void> open(WidgetTester tester, Widget app) async {
    // Hoher Bildschirm: die Liste baut ihre Zeilen lazy, die Summenkarte unter den Knoepfen liegt sonst ausserhalb
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('START'))).push('/form');
    await tester.pumpAndSettle();
  }

  Future<void> addIngredientViaSearch(WidgetTester tester, String query, Key pick, String quantity) async {
    await tester.tap(find.byKey(const Key('meal-add-ingredient')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('picker-search')), query);
    await tester.pump(const Duration(milliseconds: 500)); // Entprellung der BLS-Suche
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(pick));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ingredient-quantity')), quantity);
    await tester.pump();
    await tester.tap(find.byKey(const Key('ingredient-quantity-ok')));
    await tester.pumpAndSettle();
  }

  testWidgets('Produkt-Zutat: Zeile mit Menge und kcal, Summe, Speichern zieht den Bestand ab und kehrt zurueck', (tester) async {
    final item = await stock(1);
    await open(tester, host(active: [item]));

    await tester.enterText(find.byKey(const Key('meal-title')), 'Reispfanne');
    await addIngredientViaSearch(tester, 'Reis', Key('pick-product-${reis.id}'), '150');

    expect(find.text('Reis'), findsOneWidget);
    expect(find.textContaining('150 g · 525 kcal · vom Bestand'), findsOneWidget);
    expect(find.byKey(const Key('meal-totals-text')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('meal-totals-text'))).data, startsWith('525 kcal'));

    await tester.tap(find.byKey(const Key('meal-save')));
    await tester.pumpAndSettle();

    expect(find.text('START'), findsOneWidget, reason: 'nach dem Speichern zurueck zur Liste');
    final meal = (await db.select(db.meals).get()).single;
    expect(meal.title, 'Reispfanne');
    expect(meal.mealType, isNotEmpty);
    final posten = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
    expect(posten.quantity, closeTo(0.85, 1e-9));
    expect((await db.select(db.inventoryMovements).get()).where((m) => m.mealId == meal.id), hasLength(1));
  });

  testWidgets('BLS-Treffer: Naehrwerte aus der Datenbank, kein Abzug, keine Option "vom Bestand abziehen"', (tester) async {
    await open(tester, host());
    await tester.enterText(find.byKey(const Key('meal-title')), 'Salat');
    await tester.tap(find.byKey(const Key('meal-add-ingredient')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('picker-search')), 'paprika');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick-bls-G543100')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ingredient-deduct')), findsNothing);
    await tester.enterText(find.byKey(const Key('ingredient-quantity')), '120');
    await tester.pump();
    await tester.tap(find.byKey(const Key('ingredient-quantity-ok')));
    await tester.pumpAndSettle();

    expect(find.textContaining('120 g · 43 kcal'), findsOneWidget);
    await tester.tap(find.byKey(const Key('meal-save')));
    await tester.pumpAndSettle();

    final ing = (await db.select(db.mealIngredients).get()).single;
    expect(ing.freeText, 'Gemüsepaprika rot, roh');
    expect(ing.productId, isNull);
    expect(ing.kcal, closeTo(43.2, 1e-9));
    expect(await db.select(db.inventoryMovements).get(), isEmpty);
  });

  testWidgets('BLS nicht erreichbar: Hinweis, Freitext funktioniert weiter (Eingabe blockiert nie)', (tester) async {
    bls.fail = true;
    await open(tester, host());
    await tester.enterText(find.byKey(const Key('meal-title')), 'Suppe');
    await tester.tap(find.byKey(const Key('meal-add-ingredient')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('picker-search')), 'Kuerbis');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('picker-bls-error')), findsOneWidget);

    await tester.tap(find.byKey(const Key('pick-freetext')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ingredient-quantity')), '300');
    await tester.pump();
    await tester.tap(find.byKey(const Key('ingredient-quantity-ok')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Nährwerte unbekannt'), findsOneWidget);
    expect(find.byKey(const Key('meal-totals-unknown')), findsOneWidget);
    await tester.tap(find.byKey(const Key('meal-save')));
    await tester.pumpAndSettle();
    expect((await db.select(db.mealIngredients).get()).single.kcal, isNull);
  });

  testWidgets('BLS ohne Treffer: eigener Hinweis', (tester) async {
    await open(tester, host());
    await tester.tap(find.byKey(const Key('meal-add-ingredient')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('picker-search')), 'xyzxyz');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('picker-bls-empty')), findsOneWidget);
  });

  testWidgets('Dialog zeigt den Bestand als Hinweis; ohne Bestand den Hinweis, dass die Naehrwerte trotzdem zaehlen', (tester) async {
    final item = await stock(0.5);
    await open(tester, host(active: [item]));
    await tester.tap(find.byKey(const Key('meal-add-ingredient')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('picker-search')), 'Reis');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('pick-product-${reis.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Im Bestand: 500 g'), findsOneWidget);
  });

  testWidgets('ohne Titel: Fehlermeldung statt Speichern', (tester) async {
    await open(tester, host());
    await tester.tap(find.byKey(const Key('meal-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('meal-error')), findsOneWidget);
    expect(await db.select(db.meals).get(), isEmpty);
  });

  testWidgets('Portionen 0: Fehlermeldung statt Speichern', (tester) async {
    await open(tester, host());
    await tester.enterText(find.byKey(const Key('meal-title')), 'x');
    await tester.enterText(find.byKey(const Key('meal-servings-made')), '0');
    await tester.tap(find.byKey(const Key('meal-save')));
    await tester.pumpAndSettle();
    expect(find.text('Portionen müssen größer als 0 sein.'), findsOneWidget);
  });

  testWidgets('Zutat entfernen nimmt die Zeile und ihre Summe heraus', (tester) async {
    await open(tester, host());
    await addIngredientViaSearch(tester, 'Reis', Key('pick-product-${reis.id}'), '100');
    expect(find.byKey(const Key('ingredient-row-0')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ingredient-remove-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ingredient-row-0')), findsNothing);
    expect(find.byKey(const Key('meal-totals')), findsNothing);
  });

  testWidgets('Anteil: bei 1 von 4 Portionen zeigt die Karte "Dein Anteil" und das ganze Gericht', (tester) async {
    await open(tester, host());
    await addIngredientViaSearch(tester, 'Reis', Key('pick-product-${reis.id}'), '400'); // 1400 kcal
    await tester.enterText(find.byKey(const Key('meal-servings-made')), '4');
    await tester.pump();
    expect(find.text('Dein Anteil'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('meal-totals-text'))).data, startsWith('350 kcal'));
    expect(find.text('Ganzes Gericht: 1.400 kcal'), findsOneWidget);
  });

  group('Bearbeiten', () {
    Future<Meal> cooked(InventoryItem item) async => mealRepo(db).create(MealDraft(
          title: 'Reispfanne',
          eatenAt: _d(2026, 9, 22),
          ingredients: [IngredientDraft(productId: reis.id, quantity: 150, entryUnit: EntryUnit.g)],
        ));

    testWidgets('laedt Titel und Zutaten, Aenderung der Menge bucht den Bestand um', (tester) async {
      final item = await stock(1);
      final meal = await cooked(item);
      await open(tester, host(existing: meal, active: [item]));

      expect(tester.widget<TextField>(find.byKey(const Key('meal-title'))).controller!.text, 'Reispfanne');
      expect(find.textContaining('150 g · 525 kcal'), findsOneWidget);

      await tester.tap(find.byKey(const Key('ingredient-row-0')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('ingredient-quantity')), '300');
      await tester.pump();
      await tester.tap(find.byKey(const Key('ingredient-quantity-ok')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('meal-save')));
      await tester.pumpAndSettle();

      final posten = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
      expect(posten.quantity, closeTo(0.7, 1e-9), reason: 'alter Abzug zurueck, neuer Abzug von 300 g');
      expect((await mealRepo(db).ingredientsOf(meal.id)).single.kcal, closeTo(1050, 1e-9));
    });

    testWidgets('Loeschen mit Rueckfrage stellt den Bestand wieder her', (tester) async {
      final item = await stock(1);
      final meal = await cooked(item);
      await open(tester, host(existing: meal, active: [item]));

      await tester.tap(find.byKey(const Key('meal-delete')));
      await tester.pumpAndSettle();
      expect(find.text('Mahlzeit löschen?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('meal-delete-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('START'), findsOneWidget);
      expect((await mealRepo(db).get(meal.id))!.deletedAt, isNotNull);
      final posten = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
      expect(posten.quantity, closeTo(1, 1e-9));
    });

    testWidgets('Abbrechen der Loeschfrage laesst alles unveraendert', (tester) async {
      final item = await stock(1);
      final meal = await cooked(item);
      await open(tester, host(existing: meal, active: [item]));
      await tester.tap(find.byKey(const Key('meal-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect((await mealRepo(db).get(meal.id))!.deletedAt, isNull);
    });

    testWidgets('Freitext-Zutat mit Snapshot bleibt in der Menge aenderbar (je 100 g zurueckgerechnet)', (tester) async {
      final meal = await mealRepo(db).create(MealDraft(
        title: 'Salat',
        eatenAt: _d(2026, 9, 22),
        ingredients: const [
          IngredientDraft(freeText: 'Paprika', quantity: 100, entryUnit: EntryUnit.g, per100: NutrientsPer100(kcal: 36), per100Basis: 'g'),
        ],
      ));
      await open(tester, host(existing: meal));
      expect(find.textContaining('100 g · 36 kcal'), findsOneWidget);

      await tester.tap(find.byKey(const Key('ingredient-row-0')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('ingredient-quantity')), '200');
      await tester.pump();
      await tester.tap(find.byKey(const Key('ingredient-quantity-ok')));
      await tester.pumpAndSettle();
      expect(find.textContaining('200 g · 72 kcal'), findsOneWidget);
    });
  });
}
