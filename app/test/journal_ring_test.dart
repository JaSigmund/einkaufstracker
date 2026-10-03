import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/domain/nutrition/nutrition_targets.dart';
import 'package:einkaufstracker/features/diary/journal_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Journal: Ring und Balken je Tag, Tageskarte mit Richtwerten, Schaetzung des Nicht-Erfassten (Phase 7d/7e, Ausbau 1.12).
Meal _meal(String id, DateTime utc, {String title = 'Mahlzeit'}) => Meal(
      id: id, householdId: 'h1', eatenAt: utc, mealType: 'lunch', title: title, servingsEaten: 1, servingsMade: 1,
      source: 'manual', isEstimate: false, updatedAt: DateTime.utc(2026),
    );

MealIngredient _ing(String id, String mealId, {double? kcal, double? amountG, double quantity = 1, String unit = 'kg', String name = 'Zutat'}) => MealIngredient(
      id: id, householdId: 'h1', mealId: mealId, freeText: name, quantity: quantity, unit: unit, amountG: amountG, source: 'manual',
      kcal: kcal, updatedAt: DateTime.utc(2026),
    );

void main() {
  // Freitag, 2. Oktober 2026
  final now = DateTime.utc(2026, 10, 2, 12);
  late AppDatabase db;

  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  Future<void> open(WidgetTester tester, List<Meal> meals, List<MealIngredient> ingredients, {NutritionTargets targets = const NutritionTargets()}) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        nutritionTargetsProvider.overrideWith((ref) => Stream.value(targets)),
        mealsStreamProvider.overrideWith((ref) => Stream.value(meals)),
        mealIngredientsStreamProvider.overrideWith((ref) => Stream.value(ingredients)),
      ],
      child: MaterialApp(home: JournalPage(now: now)),
    ));
    await tester.pumpAndSettle();
  }

  const kcalTarget = NutritionTargets({NutrientKey.kcal: NutrientTarget(max: 2000), NutrientKey.proteinG: NutrientTarget(min: 60)});
  String text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

  group('Ring und Balken im Monats-Mosaik', () {
    final meals = [_meal('a', DateTime.utc(2026, 10, 1, 10)), _meal('b', DateTime.utc(2026, 10, 2, 10)), _meal('c', DateTime.utc(2026, 10, 3, 10))];
    final ingredients = [
      _ing('i1', 'a', kcal: 1000),
      _ing('i2', 'b', kcal: 2500),
      _ing('i3', 'c'), // kcal unbekannt
    ];

    testWidgets('mit kcal-Richtwert: ein Ring an Tagen mit bekannten kcal, keiner bei unbekannten oder leeren Tagen, keine Balken', (tester) async {
      await open(tester, meals, ingredients, targets: kcalTarget);
      expect(find.byKey(const Key('journal-ring-1')), findsOneWidget);
      expect(find.byKey(const Key('journal-ring-2')), findsOneWidget);
      expect(find.byKey(const Key('journal-ring-3')), findsNothing, reason: 'kcal unbekannt ist nicht 0');
      expect(find.byKey(const Key('journal-ring-4')), findsNothing, reason: 'nicht erfasst');
      expect(find.byKey(const Key('journal-bar-1')), findsNothing);
    });

    testWidgets('ohne Richtwert: ein Balken relativ zum kcal-reichsten Tag des Monats', (tester) async {
      await open(tester, meals, ingredients);
      expect(find.byKey(const Key('journal-ring-1')), findsNothing);
      final small = tester.getSize(find.byKey(const Key('journal-bar-1'))).width;
      final full = tester.getSize(find.byKey(const Key('journal-bar-2'))).width;
      expect(small / full, closeTo(0.4, 0.02), reason: '1000 von 2500 kcal');
      expect(find.byKey(const Key('journal-bar-3')), findsNothing);
      expect(find.byKey(const Key('journal-bar-4')), findsNothing);
    });

    testWidgets('ein Ueberschreiten des Richtwerts laesst den Ring nur voll, ohne Warnfarbe oder Zusatz', (tester) async {
      await open(tester, meals, ingredients, targets: kcalTarget);
      await tester.tap(find.byKey(const Key('journal-day-2')));
      await tester.pumpAndSettle();
      expect(find.text('100 %'), findsOneWidget);
    });
  });

  group('Tageskarte', () {
    testWidgets('Ring mit Prozent und Richtwerte-Zeilen fuer den gewaehlten Tag', (tester) async {
      await open(tester, [_meal('a', DateTime.utc(2026, 10, 2, 10))], [_ing('i1', 'a', kcal: 1200)], targets: kcalTarget);
      expect(find.byKey(const Key('journal-day-ring')), findsOneWidget);
      expect(find.text('60 %'), findsOneWidget);
      expect(find.byKey(const Key('target-row-journal-2026-10-2-kcal')), findsOneWidget);
    });

    testWidgets('ohne Richtwert kein Ring und keine Zeilen', (tester) async {
      await open(tester, [_meal('a', DateTime.utc(2026, 10, 2, 10))], [_ing('i1', 'a', kcal: 1200)]);
      expect(find.byKey(const Key('journal-day-ring')), findsNothing);
      expect(find.byKey(const Key('target-row-journal-2026-10-2-kcal')), findsNothing);
    });

    testWidgets('Tag mit unbekannten Naehrwerten: kein Ring', (tester) async {
      await open(tester, [_meal('a', DateTime.utc(2026, 10, 2, 10))], [_ing('i1', 'a')], targets: kcalTarget);
      expect(find.byKey(const Key('journal-day-ring')), findsNothing);
      expect(text(tester, 'journal-day-totals'), 'Nährwerte unbekannt');
    });
  });

  group('Schaetzung des Nicht-Erfassten', () {
    final meals = [_meal('a', DateTime.utc(2026, 10, 2, 10))];

    testWidgets('der Schalter erscheint nur, wenn es Zutaten ohne Naehrwerte gibt, und steht standardmaessig aus', (tester) async {
      await open(tester, meals, [_ing('i1', 'a', kcal: 300, amountG: 200)]);
      expect(find.byKey(const Key('journal-estimate-toggle')), findsNothing);
    });

    testWidgets('an: Dazu etwa 300 kcal aus 1 Zutat (200 g) nach dem Tagesdurchschnitt, und es wird gemerkt', (tester) async {
      await open(tester, meals, [
        _ing('i1', 'a', kcal: 300, amountG: 200, name: 'Reis'),
        _ing('i2', 'a', quantity: 0.2, name: 'Gurke'),
      ]);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('journal-estimate-toggle'))).value, isFalse);
      expect(find.byKey(const Key('journal-estimate-text')), findsNothing);

      await tester.tap(find.byKey(const Key('journal-estimate-toggle')));
      await tester.pumpAndSettle();
      final t = text(tester, 'journal-estimate-text');
      expect(t, contains('Dazu etwa 300 kcal aus 1 Zutat ohne Nährwerte (200 g)'));
      expect(t, contains('geschätzt nach dem Durchschnitt dieses Tages'));
      expect(await db.getKv(journalEstimateKey), 'true');
      expect(text(tester, 'journal-day-totals'), isNot(contains('500')), reason: 'die bekannte Summe bleibt unberuehrt');
    });

    testWidgets('die gemerkte Einstellung gilt beim naechsten Oeffnen', (tester) async {
      await db.setKv(journalEstimateKey, 'true');
      await open(tester, meals, [_ing('i1', 'a', kcal: 300, amountG: 200), _ing('i2', 'a', quantity: 0.2)]);
      expect(find.byKey(const Key('journal-estimate-text')), findsOneWidget);
    });

    testWidgets('Zutaten ohne Menge werden genannt, nicht geschaetzt', (tester) async {
      await db.setKv(journalEstimateKey, 'true');
      await open(tester, meals, [
        _ing('i1', 'a', kcal: 300, amountG: 200),
        _ing('i2', 'a', quantity: 0.2),
        _ing('i3', 'a', quantity: 2, unit: 'piece'),
      ]);
      final t = text(tester, 'journal-estimate-text');
      expect(t, contains('1 weitere Zutat ohne Nährwerte und ohne Menge bleibt unberücksichtigt'));
    });

    testWidgets('nur Zutaten ohne Menge: ehrlicher Hinweis statt einer erfundenen Zahl', (tester) async {
      await db.setKv(journalEstimateKey, 'true');
      await open(tester, meals, [_ing('i1', 'a', quantity: 2, unit: 'piece')]);
      expect(text(tester, 'journal-estimate-text'), contains('hat eine bekannte Menge, deshalb gibt es nichts zu schätzen'));
    });

    testWidgets('ohne jede bekannte Zutat gilt der Faustwert und wird so genannt', (tester) async {
      await db.setKv(journalEstimateKey, 'true');
      await open(tester, meals, [_ing('i1', 'a', quantity: 0.2)]);
      final t = text(tester, 'journal-estimate-text');
      expect(t, contains('Faustwert'));
      expect(t, contains('300 kcal'), reason: '200 g mal 1,5 kcal je g');
    });

    testWidgets('der Verlauf liefert die Dichte, wenn der Tag selbst keine bekannte Zutat hat', (tester) async {
      await db.setKv(journalEstimateKey, 'true');
      await open(
        tester,
        [_meal('a', DateTime.utc(2026, 10, 2, 10)), _meal('b', DateTime.utc(2026, 10, 1, 10))],
        [_ing('i1', 'a', quantity: 0.1), _ing('i2', 'b', kcal: 200, amountG: 100)],
      );
      final t = text(tester, 'journal-estimate-text');
      expect(t, contains('nach dem Durchschnitt deiner erfassten Tage'));
      expect(t, contains('200 kcal'));
    });
  });

  test('ingredientGrams: Snapshot vor erfasster Menge, Stueck ohne Gewicht hat keine Menge', () {
    expect(ingredientGrams(_ing('x', 'm', amountG: 118, quantity: 1, unit: 'piece')), 118);
    expect(ingredientGrams(_ing('x', 'm', quantity: 0.25)), 250);
    expect(ingredientGrams(_ing('x', 'm', quantity: 0.2, unit: 'l')), 200);
    expect(ingredientGrams(_ing('x', 'm', quantity: 3, unit: 'piece')), isNull);
    expect(ingredientGrams(_ing('x', 'm', quantity: 0)), isNull);
  });
}
