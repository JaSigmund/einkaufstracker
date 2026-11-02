import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/meal_repository.dart';
import 'package:einkaufstracker/domain/nutrition/food_unit.dart';
import 'package:einkaufstracker/domain/nutrition/ingredient_nutrition.dart';
import 'package:einkaufstracker/domain/nutrition/meal_shortage.dart';
import 'package:einkaufstracker/domain/nutrition/nutrient_scaling.dart';
import 'package:einkaufstracker/features/diary/meal_shopping_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Fehlende Zutaten einer Mahlzeit auf die Einkaufsliste (Ausbau 1.12): Domain, Repository und Dialog.
ShortageInput need(String? id, String name, double? needed, {String? unit = 'kg'}) => (productId: id, name: name, needed: needed, baseUnit: unit);

void main() {
  group('findMealShortages', () {
    test('fehlt gar nichts im Bestand, ist die Zutat vorgeschlagen und vorausgewaehlt', () {
      final c = findMealShortages([need('reis', 'Reis', 0.2)], stock: const {});
      expect(c, hasLength(1));
      expect(c.single.kind, ShortageKind.missing);
      expect(c.single.preselected, isTrue);
      expect(c.single.name, 'Reis');
      expect(c.single.baseUnit, 'kg');
    });

    test('gedeckt: der Bestand reicht (auch genau), die Zutat kommt nicht vor', () {
      expect(findMealShortages([need('reis', 'Reis', 0.2)], stock: const {'reis': 0.5}), isEmpty);
      expect(findMealShortages([need('reis', 'Reis', 0.2)], stock: const {'reis': 0.2}), isEmpty);
    });

    test('zu wenig: der Bestand liegt unter der gebrauchten Menge', () {
      final c = findMealShortages([need('reis', 'Reis', 0.5)], stock: const {'reis': 0.2});
      expect(c.single.kind, ShortageKind.insufficient);
      expect([c.single.needed, c.single.available], [0.5, 0.2]);
      expect(c.single.preselected, isTrue);
    });

    test('Menge nicht umrechenbar: nur "gar nichts da" zaehlt als fehlend', () {
      expect(findMealShortages([need('ei', 'Eier', null, unit: 'piece')], stock: const {'ei': 2}), isEmpty);
      expect(findMealShortages([need('ei', 'Eier', null, unit: 'piece')], stock: const {}).single.kind, ShortageKind.missing);
    });

    test('dieselbe Zutat zweimal wird zusammengezaehlt', () {
      final c = findMealShortages([need('z', 'Zwiebel', 0.1), need('z', 'Zwiebel', 0.2)], stock: const {'z': 0.25});
      expect(c, hasLength(1));
      expect(c.single.needed, closeTo(0.3, 1e-9));
      expect(c.single.kind, ShortageKind.insufficient);
    });

    test('ist eine Teilmenge nicht umrechenbar, bleibt die Summe unbekannt und es zaehlt nur "nichts da"', () {
      expect(findMealShortages([need('z', 'Zwiebel', 0.1), need('z', 'Zwiebel', null)], stock: const {'z': 0.01}), isEmpty);
    });

    test('Zutaten ohne Produkt werden angeboten, aber nicht vorausgewaehlt; doppelte Namen nur einmal', () {
      final c = findMealShortages([need(null, 'Gewürzgurke', null, unit: null), need(null, 'gewürzgurke ', null, unit: null)], stock: const {});
      expect(c, hasLength(1));
      expect(c.single.kind, ShortageKind.unchecked);
      expect(c.single.preselected, isFalse);
    });

    test('was schon auf der Liste steht, ist markiert und nicht vorausgewaehlt', () {
      final c = findMealShortages(
        [need('reis', 'Reis', 0.2), need(null, 'Gewürzgurke', null, unit: null)],
        stock: const {},
        listedProductIds: const {'reis'},
        listedTexts: const {'GEWÜRZGURKE'},
      );
      expect(c.map((x) => x.alreadyOnList), [true, true]);
      expect(c.map((x) => x.preselected), [false, false]);
    });

    test('Reihenfolge: zuerst, was sicher fehlt, dann das Nichtpruefbare, jeweils wie in der Mahlzeit', () {
      final c = findMealShortages(
        [need(null, 'Salz', null, unit: null), need('a', 'Apfel', 1), need('b', 'Birne', 1)],
        stock: const {},
      );
      expect(c.map((x) => x.name), ['Apfel', 'Birne', 'Salz']);
    });

    test('ohne Zutaten nichts', () {
      expect(findMealShortages(const [], stock: const {}), isEmpty);
    });
  });

  group('ShoppingListRepository.addMany', () {
    late AppDatabase db;
    setUp(() => db = memoryDb());
    tearDown(() => db.close());

    test('legt Eintraege mit Menge 1 an, ueberspringt Doppelte (Produkt oder Freitext) und meldet die Zahl', () async {
      var changed = 0;
      final repo = shoppingListRepo(db, onChanged: () => changed++);
      await repo.addManual(freeText: 'Gewürzgurke');
      changed = 0;
      final added = await repo.addMany([
        (productId: 'p1', freeText: null, unit: 'kg'),
        (productId: 'p1', freeText: null, unit: 'kg'),
        (productId: null, freeText: 'gewürzgurke', unit: 'piece'),
        (productId: null, freeText: ' Senf ', unit: 'piece'),
        (productId: null, freeText: '  ', unit: 'piece'),
        (productId: null, freeText: null, unit: 'piece'),
      ]);
      expect(added, 2);
      expect(changed, 1, reason: 'der Sync wird nur einmal angestossen');
      final open = await repo.openItems();
      expect(open.map((i) => i.productId ?? i.freeText), unorderedEquals(['Gewürzgurke', 'p1', 'Senf']));
      expect(open.every((i) => i.quantity == 1 && !i.checked && !i.isSuggestion), isTrue);
      expect(open.firstWhere((i) => i.productId == 'p1').unit, 'kg');
    });

    test('ein abgehakter Eintrag zaehlt nicht als vorhanden', () async {
      final repo = shoppingListRepo(db);
      final item = await repo.addManual(productId: 'p1');
      await repo.setChecked(item.id, true);
      expect(await repo.addMany([(productId: 'p1', freeText: null, unit: 'piece')]), 1);
    });

    test('nichts Neues: kein Sync-Anstoss', () async {
      var changed = 0;
      final repo = shoppingListRepo(db, onChanged: () => changed++);
      expect(await repo.addMany(const []), 0);
      expect(changed, 0);
    });
  });

  group('Dialog', () {
    late AppDatabase db;
    late MealRepository meals;
    setUp(() {
      db = memoryDb();
      meals = mealRepo(db);
    });
    tearDown(() => db.close());

    Future<(Meal, List<MealIngredient>)> reispfanne({double milkGrams = 500}) async {
      final reis = await productRepo(db).create(name: 'Reis', baseUnit: 'kg');
      final milch = await productRepo(db).create(name: 'Milch', baseUnit: 'l');
      await inventoryRepo(db).recordFromScan(productId: milch.id, ean: '1', quantity: 0.2, unit: 'l', bestBefore: DateTime.utc(2026, 12, 1), now: DateTime.utc(2026, 9, 1));
      final m = await meals.create(MealDraft(title: 'Reispfanne', eatenAt: DateTime.utc(2026, 10, 3, 12), ingredients: [
        IngredientDraft(productId: reis.id, quantity: 200, entryUnit: EntryUnit.g, deduct: false),
        IngredientDraft(productId: milch.id, quantity: milkGrams, entryUnit: EntryUnit.ml, deduct: false),
        const IngredientDraft(freeText: 'Gewürzgurke', quantity: 50, entryUnit: EntryUnit.g, per100: NutrientsPer100(kcal: 11), per100Basis: 'g'),
      ]));
      return (m, await meals.ingredientsOf(m.id));
    }

    Future<int?> open(WidgetTester tester, Meal meal, List<MealIngredient> ingredients) async {
      int? result;
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          productRepositoryProvider.overrideWithValue(productRepo(db)),
          inventoryRepositoryProvider.overrideWithValue(inventoryRepo(db)),
          shoppingListRepositoryProvider.overrideWithValue(shoppingListRepo(db)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                key: const Key('go'),
                onPressed: () async => result = await showMealShoppingDialog(context, meal, ingredients),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('Reis fehlt (vorausgewaehlt), Milch reicht nicht (vorausgewaehlt), die Gurke ist nicht pruefbar (nicht vorausgewaehlt)', (tester) async {
      final (meal, ings) = await reispfanne();
      await open(tester, meal, ings);
      expect(find.byKey(const Key('meal-shopping-dialog')), findsOneWidget);
      CheckboxListTile tile(int n) => tester.widget<CheckboxListTile>(find.byKey(Key('meal-shopping-item-$n')));
      expect(tile(0).value, isTrue);
      expect(tile(1).value, isTrue);
      expect(tile(2).value, isFalse);
      expect(find.text('nicht im Bestand'), findsOneWidget);
      expect(find.text('Bestand 0,2 l, gebraucht 0,5 l'), findsOneWidget);
      expect(find.text('ohne Bestandsprüfung (kein Produkt)'), findsOneWidget);
      expect(find.text('2 auf die Liste'), findsOneWidget);
    });

    testWidgets('Auswahl uebernehmen: die Eintraege landen auf der Liste, Hinweis mit der Zahl', (tester) async {
      final (meal, ings) = await reispfanne();
      await open(tester, meal, ings);
      await tester.tap(find.byKey(const Key('meal-shopping-item-2'))); // Gurke dazunehmen
      await tester.pumpAndSettle();
      expect(find.text('3 auf die Liste'), findsOneWidget);
      await tester.tap(find.byKey(const Key('meal-shopping-add')));
      await tester.pumpAndSettle();
      expect(find.text('3 Einträge auf der Einkaufsliste'), findsOneWidget);
      final open0 = await shoppingListRepo(db).openItems();
      expect(open0, hasLength(3));
      expect(open0.where((i) => i.productId != null), hasLength(2));
      expect(open0.where((i) => i.freeText == 'Gewürzgurke'), hasLength(1));
    });

    testWidgets('abgewaehlt wird nicht angelegt; ohne Auswahl ist der Knopf gesperrt', (tester) async {
      final (meal, ings) = await reispfanne();
      await open(tester, meal, ings);
      await tester.tap(find.byKey(const Key('meal-shopping-item-0')));
      await tester.tap(find.byKey(const Key('meal-shopping-item-1')));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.byKey(const Key('meal-shopping-add'))).onPressed, isNull);
      await tester.tap(find.byKey(const Key('meal-shopping-item-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('meal-shopping-add')));
      await tester.pumpAndSettle();
      expect(await shoppingListRepo(db).openItems(), hasLength(1));
    });

    testWidgets('was schon auf der Liste steht, ist markiert und nicht waehlbar', (tester) async {
      final (meal, ings) = await reispfanne();
      final reis = (await productRepo(db).allSnapshot()).firstWhere((p) => p.name == 'Reis');
      await shoppingListRepo(db).addManual(productId: reis.id, unit: 'kg');
      await open(tester, meal, ings);
      expect(tester.widget<CheckboxListTile>(find.byKey(const Key('meal-shopping-item-0'))).onChanged, isNull);
      expect(tester.widget<CheckboxListTile>(find.byKey(const Key('meal-shopping-item-0'))).value, isFalse);
      expect(find.text('steht schon auf der Liste'), findsOneWidget);
      expect(find.text('1 auf die Liste'), findsOneWidget);
    });

    testWidgets('alles gedeckt: "Alles da" und nichts zu tun', (tester) async {
      final reis = await productRepo(db).create(name: 'Reis', baseUnit: 'kg');
      await inventoryRepo(db).recordFromScan(productId: reis.id, ean: '1', quantity: 1, unit: 'kg', bestBefore: DateTime.utc(2026, 12, 1), now: DateTime.utc(2026, 9, 1));
      final m = await meals.create(MealDraft(title: 'Reis', eatenAt: DateTime.utc(2026, 10, 3, 12), ingredients: [
        IngredientDraft(productId: reis.id, quantity: 200, entryUnit: EntryUnit.g, deduct: false),
      ]));
      await open(tester, m, await meals.ingredientsOf(m.id));
      expect(find.byKey(const Key('meal-shopping-empty')), findsOneWidget);
      expect(find.byKey(const Key('meal-shopping-add')), findsNothing);
    });

    testWidgets('Abbrechen legt nichts an', (tester) async {
      final (meal, ings) = await reispfanne();
      await open(tester, meal, ings);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(await shoppingListRepo(db).openItems(), isEmpty);
    });
  });

  test('neededInBaseUnit: gespeicherte Scheiben zaehlen anteilig, ohne Stueckgewicht ist der Bedarf unbekannt', () async {
    final db = memoryDb();
    addTearDown(db.close);
    final mitGewicht = await productRepo(db).create(name: 'Brot', baseUnit: 'piece', unitWeightG: 560, nutrientsPer100: {'kcal': 260}, nutrientsBasis: 'g', nutrientsSource: 'manual');
    final ohneGewicht = await productRepo(db).create(name: 'Zopf', baseUnit: 'piece', nutrientsPer100: {'kcal': 300}, nutrientsBasis: 'g', nutrientsSource: 'manual');
    final m = await mealRepo(db).create(MealDraft(title: 'x', eatenAt: DateTime.utc(2026, 10, 3, 12), ingredients: [
      IngredientDraft(productId: mitGewicht.id, quantity: 2, entryUnit: EntryUnit.piece, unitKey: FoodUnitKey.slice, unitWeightG: 28, deduct: false),
      IngredientDraft(productId: ohneGewicht.id, quantity: 2, entryUnit: EntryUnit.piece, unitKey: FoodUnitKey.slice, unitWeightG: 28, deduct: false),
    ]));
    final rows = await mealRepo(db).ingredientsOf(m.id);
    double? of(Product p) => neededInBaseUnit(rows.firstWhere((r) => r.productId == p.id), p);
    expect(of(mitGewicht), closeTo(0.1, 1e-9));
    expect(of(ohneGewicht), isNull);
  });

  test('neededInBaseUnit rechnet g und ml in kg und l um, Stueck ueber das Gewicht im Snapshot oder am Produkt', () async {
    final db = memoryDb();
    addTearDown(db.close);
    final reis = await productRepo(db).create(name: 'Reis', baseUnit: 'kg');
    final ei = await productRepo(db).create(name: 'Ei', baseUnit: 'piece');
    final eiWithWeight = await productRepo(db).create(name: 'Ei mit Gewicht', baseUnit: 'kg', unitWeightG: 60);
    final m = await mealRepo(db).create(MealDraft(title: 'x', eatenAt: DateTime.utc(2026, 10, 3, 12), ingredients: [
      IngredientDraft(productId: reis.id, quantity: 250, entryUnit: EntryUnit.g, deduct: false),
      IngredientDraft(productId: ei.id, quantity: 3, entryUnit: EntryUnit.piece, deduct: false),
      IngredientDraft(productId: eiWithWeight.id, quantity: 2, entryUnit: EntryUnit.piece, deduct: false),
    ]));
    final rows = await mealRepo(db).ingredientsOf(m.id);
    double? of(Product p) => neededInBaseUnit(rows.firstWhere((r) => r.productId == p.id), p);
    expect(of(reis), closeTo(0.25, 1e-9));
    expect(of(ei), 3);
    expect(of(eiWithWeight), closeTo(0.12, 1e-9));
  });
}
