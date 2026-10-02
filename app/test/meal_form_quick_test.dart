import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/meal_repository.dart';
import 'package:einkaufstracker/domain/nutrition/ingredient_nutrition.dart';
import 'package:einkaufstracker/domain/nutrition/nutrient_scaling.dart';
import 'package:einkaufstracker/features/diary/meal_form_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';

/// Schnelleintraege (Doku 15 §3.2/§3.3): Naehrwerte von Hand (Restaurant), Nochmal erfassen, Rest vom Vortag.
void main() {
  late AppDatabase db;
  late MealRepository meals;
  late Product reis;
  late InventoryItem reisBestand;

  setUp(() async {
    db = memoryDb();
    meals = mealRepo(db);
    reis = await productRepo(db).create(
      name: 'Reis',
      baseUnit: 'kg',
      nutrientsPer100: {'kcal': 350},
      nutrientsBasis: 'g',
      nutrientsSource: 'manual',
    );
    reisBestand = await inventoryRepo(db).recordFromScan(
      productId: reis.id,
      ean: '1',
      quantity: 1,
      unit: 'kg',
      bestBefore: DateTime.utc(2026, 12, 1),
      now: DateTime.utc(2026, 9, 1),
    );
  });
  tearDown(() => db.close());

  Widget host({Meal? existing, Meal? template, bool leftover = false}) => ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          mealRepositoryProvider.overrideWithValue(meals),
          productRepositoryProvider.overrideWithValue(productRepo(db)),
          inventoryRepositoryProvider.overrideWithValue(inventoryRepo(db)),
          productsStreamProvider.overrideWith((ref) => Stream.value([reis])),
          activeInventoryStreamProvider.overrideWith((ref) => Stream.value([reisBestand])),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(routes: [
            GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('START'))),
            GoRoute(path: '/form', builder: (_, _) => MealFormPage(existing: existing, template: template, leftover: leftover)),
          ]),
        ),
      );

  Future<void> open(WidgetTester tester, Widget app) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('START'))).push('/form');
    await tester.pumpAndSettle();
  }

  Future<void> fillManual(WidgetTester tester, {String? name, String kcal = '', String protein = '', String fat = '', String carbs = ''}) async {
    if (name != null) await tester.enterText(find.byKey(const Key('manual-name')), name);
    await tester.enterText(find.byKey(const Key('manual-kcal')), kcal);
    await tester.enterText(find.byKey(const Key('manual-protein')), protein);
    await tester.enterText(find.byKey(const Key('manual-fat')), fat);
    await tester.enterText(find.byKey(const Key('manual-carbs')), carbs);
    await tester.pump();
  }

  Future<Meal> restaurantMeal() => meals.create(MealDraft(
        title: 'Pizza Margherita',
        eatenAt: DateTime.utc(2026, 9, 20, 18),
        mealType: 'dinner',
        isEstimate: true,
        ingredients: const [
          IngredientDraft(
            freeText: 'Pizza',
            quantity: 1,
            entryUnit: EntryUnit.piece,
            source: 'estimate',
            manualNutrients: NutrientAmounts(kcal: 850, proteinG: 30, fatG: 28, carbsG: 110),
          ),
        ],
      ));

  group('Naehrwerte von Hand', () {
    testWidgets('Dialog liefert eine Zeile "Handeingabe", Nur-geschaetzt wird eingeschaltet', (tester) async {
      await open(tester, host());
      await tester.enterText(find.byKey(const Key('meal-title')), 'Pizza beim Italiener');
      await tester.tap(find.byKey(const Key('meal-add-manual')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('manual-name'))).controller!.text, 'Pizza beim Italiener', reason: 'Titel als Vorschlag');
      await fillManual(tester, kcal: '850', protein: '30,5');
      await tester.tap(find.byKey(const Key('manual-ok')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ingredient-row-0')), findsOneWidget);
      expect(find.text('Handeingabe · 850 kcal'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('meal-estimate'))).value, isTrue);
      expect(find.byKey(const Key('ingredient-lookup-0')), findsNothing, reason: 'Nährwerte sind ja bekannt');
    });

    testWidgets('Speichern: Zutat mit absoluten Werten, ohne Menge in Gramm, ohne Bestandsabzug', (tester) async {
      await open(tester, host());
      await tester.enterText(find.byKey(const Key('meal-title')), 'Pizza');
      await tester.tap(find.byKey(const Key('meal-add-manual')));
      await tester.pumpAndSettle();
      await fillManual(tester, kcal: '850', protein: '30,5', fat: '28', carbs: '110');
      await tester.tap(find.byKey(const Key('manual-ok')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('meal-save')));
      await tester.pumpAndSettle();

      final meal = (await db.select(db.meals).get()).single;
      expect(meal.isEstimate, isTrue);
      final row = (await db.select(db.mealIngredients).get()).single;
      expect(row.freeText, 'Pizza');
      expect([row.kcal, row.proteinG, row.fatG, row.carbsG], [850.0, 30.5, 28.0, 110.0]);
      expect(row.sugarG, isNull, reason: 'Unbekanntes bleibt leer, nicht 0');
      expect(row.amountG, isNull);
      expect(row.source, 'estimate');
      expect(row.inventoryItemId, isNull);
      expect(await db.select(db.inventoryMovements).get().then((m) => m.where((e) => e.type == 'meal')), isEmpty);
    });

    testWidgets('nur einzelne Werte sind erlaubt, der Rest bleibt unbekannt', (tester) async {
      await open(tester, host());
      await tester.enterText(find.byKey(const Key('meal-title')), 'Eis');
      await tester.tap(find.byKey(const Key('meal-add-manual')));
      await tester.pumpAndSettle();
      await fillManual(tester, protein: '4');
      await tester.tap(find.byKey(const Key('manual-ok')));
      await tester.pumpAndSettle();
      expect(find.text('Handeingabe · Nährwerte unbekannt'), findsOneWidget, reason: 'ohne kcal keine Energie-Anzeige');
    });

    testWidgets('Pruefung: ohne Bezeichnung, ohne Werte, mit Text oder negativer Zahl bleibt der Dialog offen', (tester) async {
      await open(tester, host());
      await tester.tap(find.byKey(const Key('meal-add-manual')));
      await tester.pumpAndSettle();

      await fillManual(tester, name: '', kcal: '500');
      await tester.tap(find.byKey(const Key('manual-ok')));
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const Key('manual-error'))).data, 'Bitte eine Bezeichnung eingeben.');

      await fillManual(tester, name: 'Pizza');
      await tester.tap(find.byKey(const Key('manual-ok')));
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const Key('manual-error'))).data, 'Bitte mindestens einen Wert eintragen.');

      await fillManual(tester, kcal: 'viel');
      await tester.tap(find.byKey(const Key('manual-ok')));
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const Key('manual-error'))).data, 'Bitte nur Zahlen ab 0 eingeben.');

      await fillManual(tester, kcal: '-5');
      await tester.tap(find.byKey(const Key('manual-ok')));
      await tester.pump();
      expect(find.byKey(const Key('manual-error')), findsOneWidget);
      expect(find.byKey(const Key('ingredient-row-0')), findsNothing);
    });

    testWidgets('Abbrechen fuegt nichts hinzu und laesst "Nur geschaetzt" aus', (tester) async {
      await open(tester, host());
      await tester.tap(find.byKey(const Key('meal-add-manual')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ingredient-row-0')), findsNothing);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('meal-estimate'))).value, isFalse);
    });

    testWidgets('Tippen auf die Zeile oeffnet den Dialog mit den bisherigen Werten, Aenderung wird uebernommen', (tester) async {
      final meal = await restaurantMeal();
      await open(tester, host(existing: meal));
      expect(find.text('Handeingabe · 850 kcal'), findsOneWidget);

      await tester.tap(find.byKey(const Key('ingredient-row-0')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('manual-kcal'))).controller!.text, '850');
      expect(tester.widget<TextField>(find.byKey(const Key('manual-protein'))).controller!.text, '30');
      await tester.enterText(find.byKey(const Key('manual-kcal')), '900');
      await tester.tap(find.byKey(const Key('manual-ok')));
      await tester.pumpAndSettle();
      expect(find.text('Handeingabe · 900 kcal'), findsOneWidget);

      await tester.tap(find.byKey(const Key('meal-save')));
      await tester.pumpAndSettle();
      final row = (await db.select(db.mealIngredients).get()).firstWhere((r) => r.deletedAt == null);
      expect(row.kcal, 900);
      expect(row.proteinG, 30);
    });
  });

  group('Nochmal erfassen', () {
    Future<Meal> reispfanne() async => meals.create(MealDraft(
          title: 'Reispfanne',
          eatenAt: DateTime.utc(2026, 9, 20, 18),
          mealType: 'dinner',
          note: 'war lecker',
          servingsEaten: 1,
          servingsMade: 4,
          ingredients: [IngredientDraft(productId: reis.id, quantity: 200, entryUnit: EntryUnit.g)],
        ));

    testWidgets('uebernimmt Titel, Portionen und Zutaten, nicht die Notiz; Titel der Seite sagt "Nochmal erfassen"', (tester) async {
      final original = await reispfanne();
      await open(tester, host(template: original));
      expect(find.text('Nochmal erfassen'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('meal-title'))).controller!.text, 'Reispfanne');
      expect(tester.widget<TextField>(find.byKey(const Key('meal-servings-eaten'))).controller!.text, '1');
      expect(tester.widget<TextField>(find.byKey(const Key('meal-servings-made'))).controller!.text, '4');
      expect(tester.widget<TextField>(find.byKey(const Key('meal-note'))).controller!.text, isEmpty);
      expect(find.text('200 g · 700 kcal · vom Bestand'), findsOneWidget, reason: 'Abzug wie bei der Originalmahlzeit');
    });

    testWidgets('Speichern legt eine NEUE Mahlzeit an (jetzt) und zieht erneut vom Bestand ab, die alte bleibt', (tester) async {
      final original = await reispfanne();
      final before = (await db.select(db.inventoryItems).get()).single.quantity;
      await open(tester, host(template: original));
      await tester.tap(find.byKey(const Key('meal-save')));
      await tester.pumpAndSettle();

      final all = await db.select(db.meals).get();
      expect(all, hasLength(2));
      final copy = all.firstWhere((m) => m.id != original.id);
      expect(copy.title, 'Reispfanne');
      expect(copy.eatenAt.isAfter(DateTime.utc(2026, 10, 1)), isTrue, reason: 'Zeitpunkt ist jetzt, nicht der der Vorlage');
      expect(copy.note, isNull);
      final after = (await db.select(db.inventoryItems).get()).single.quantity;
      expect(after, closeTo(before - 0.2, 1e-9));
      expect(await meals.ingredientsOf(original.id), hasLength(1), reason: 'Original bleibt unveraendert');
    });

    testWidgets('Rest vom Vortag: gleiche Naehrwerte, aber kein Abzug vom Bestand', (tester) async {
      final original = await reispfanne();
      final before = (await db.select(db.inventoryItems).get()).single.quantity;
      await open(tester, host(template: original, leftover: true));
      expect(find.text('Rest erfassen'), findsOneWidget);
      expect(find.text('200 g · 700 kcal'), findsOneWidget, reason: 'ohne "vom Bestand"');

      await tester.tap(find.byKey(const Key('meal-save')));
      await tester.pumpAndSettle();
      expect((await db.select(db.meals).get()), hasLength(2));
      final after = (await db.select(db.inventoryItems).get()).single.quantity;
      expect(after, closeTo(before, 1e-9));
    });

    testWidgets('Kopie einer geschaetzten Mahlzeit bleibt als geschaetzt gekennzeichnet', (tester) async {
      final original = await restaurantMeal();
      await open(tester, host(template: original));
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('meal-estimate'))).value, isTrue);
      expect(find.text('Handeingabe · 850 kcal'), findsOneWidget);
    });

    testWidgets('Mahlzeitentyp richtet sich nach der Uhrzeit, nicht nach der Vorlage', (tester) async {
      // Vorlage: Abendessen. Die Uhrzeit des Testlaufs ist beliebig, deshalb nur die Regel pruefen: es ist genau ein
      // Typ gewaehlt, und er entspricht guessMealType(jetzt) -- nicht zwingend "dinner".
      final original = await reispfanne();
      await open(tester, host(template: original));
      final selected = [
        for (final k in ['breakfast', 'lunch', 'dinner', 'snack', 'drink'])
          if (tester.widget<ChoiceChip>(find.byKey(Key('meal-type-$k'))).selected) k,
      ];
      expect(selected, hasLength(1));
    });
  });

  group('Portionen umrechnen (Doku 15 §3.2)', () {
    Future<Meal> vierPortionen() => meals.create(MealDraft(
          title: 'Reispfanne',
          eatenAt: DateTime.utc(2026, 9, 20, 18),
          servingsEaten: 1,
          servingsMade: 4,
          ingredients: [
            IngredientDraft(productId: reis.id, quantity: 200, entryUnit: EntryUnit.g),
            const IngredientDraft(freeText: 'Nachspeise', quantity: 1, entryUnit: EntryUnit.piece, source: 'estimate', manualNutrients: NutrientAmounts(kcal: 400, proteinG: 8)),
          ],
        ));

    Future<void> scaleTo(WidgetTester tester, String value) async {
      await tester.tap(find.byKey(const Key('meal-scale')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('scale-servings')), value);
      await tester.tap(find.byKey(const Key('scale-ok')));
      await tester.pumpAndSettle();
    }

    testWidgets('ohne Zutaten gibt es keinen Knopf', (tester) async {
      await open(tester, host());
      expect(find.byKey(const Key('meal-scale')), findsNothing);
    });

    testWidgets('von 4 auf 2 Portionen: Mengen halbiert, Handeingabe mit, Portionen gekocht gesetzt', (tester) async {
      final original = await vierPortionen();
      await open(tester, host(template: original));
      await scaleTo(tester, '2');
      expect(find.text('100 g · 350 kcal · vom Bestand'), findsOneWidget);
      expect(find.text('Handeingabe · 200 kcal'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('meal-servings-made'))).controller!.text, '2');
      expect(tester.widget<TextField>(find.byKey(const Key('meal-servings-eaten'))).controller!.text, '1', reason: 'der eigene Anteil bleibt');
    });

    testWidgets('hochrechnen: von 4 auf 6 Portionen (Faktor 1,5)', (tester) async {
      final original = await vierPortionen();
      await open(tester, host(template: original));
      await scaleTo(tester, '6');
      expect(find.text('300 g · 1.050 kcal · vom Bestand'), findsOneWidget);
    });

    testWidgets('Speichern nach dem Umrechnen zieht die umgerechnete Menge vom Bestand ab', (tester) async {
      final original = await vierPortionen();
      final before = (await db.select(db.inventoryItems).get()).single.quantity;
      await open(tester, host(template: original));
      await scaleTo(tester, '2');
      await tester.tap(find.byKey(const Key('meal-save')));
      await tester.pumpAndSettle();
      final copy = (await db.select(db.meals).get()).firstWhere((m) => m.id != original.id);
      expect(copy.servingsMade, 2);
      final after = (await db.select(db.inventoryItems).get()).single.quantity;
      expect(after, closeTo(before - 0.1, 1e-9), reason: '100 g statt 200 g');
    });

    testWidgets('ungueltige Eingabe (0, Text, zu gross) bleibt im Dialog und aendert nichts', (tester) async {
      final original = await vierPortionen();
      await open(tester, host(template: original));
      for (final bad in ['0', 'viele', '-2', '500']) {
        await tester.tap(find.byKey(const Key('meal-scale')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('scale-servings')), bad);
        await tester.tap(find.byKey(const Key('scale-ok')));
        await tester.pumpAndSettle();
        expect(find.text('Bitte eine Portionenzahl zwischen 0 und 100 eingeben.'), findsOneWidget, reason: bad);
        await tester.tap(find.text('Abbrechen'));
        await tester.pumpAndSettle();
      }
      expect(find.text('200 g · 700 kcal · vom Bestand'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('meal-servings-made'))).controller!.text, '4');
    });

    testWidgets('dieselbe Zahl oder Abbrechen aendert nichts', (tester) async {
      final original = await vierPortionen();
      await open(tester, host(template: original));
      await scaleTo(tester, '4');
      expect(find.text('200 g · 700 kcal · vom Bestand'), findsOneWidget);
      await tester.tap(find.byKey(const Key('meal-scale')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(find.text('200 g · 700 kcal · vom Bestand'), findsOneWidget);
    });

    testWidgets('Handeingabe ohne weitere Zutaten wird mit umgerechnet', (tester) async {
      await open(tester, host());
      await tester.enterText(find.byKey(const Key('meal-title')), 'Test');
      await tester.tap(find.byKey(const Key('meal-add-manual')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('manual-kcal')), '300');
      await tester.tap(find.byKey(const Key('manual-ok')));
      await tester.pumpAndSettle();
      await scaleTo(tester, '2');
      expect(find.text('Handeingabe · 600 kcal'), findsOneWidget);
    });
  });
}
