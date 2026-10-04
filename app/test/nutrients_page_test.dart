import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
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

/// Seite "Nährstoffe" (Phase N3, ADR-032): Tag und Woche, Abdeckung je Naehrstoff, "Woher kommt das?", optionale Referenzmengen.
/// Heute ist der 3. Oktober 2026 (Wiener Zeit).
final _now = DateTime.utc(2026, 10, 3, 10);

/// Die Seite haengt an echten Drift-Strömen (gemeinsame Einstellungen): am Testende wird sie ausgehaengt, damit keine Timer offen bleiben.
void pageTest(String name, Future<void> Function(WidgetTester tester) body) => testWidgets(name, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

void main() {
  late AppDatabase db;
  late MealRepository meals;
  late HouseholdPrefsRepository prefs;

  setUp(() {
    db = memoryDb();
    meals = mealRepo(db);
    prefs = HouseholdPrefsRepository(db, householdId: () async => 'h1');
  });
  tearDown(() => db.close());

  IngredientDraft food(String name, double grams, Micros? micros) => IngredientDraft(
        freeText: name,
        quantity: grams,
        entryUnit: EntryUnit.g,
        per100: const NutrientsPer100(kcal: 50),
        per100Basis: 'g',
        blsCode: 'X',
        microsPer100: micros,
      );

  Future<Meal> meal(String title, DateTime eatenAt, List<IngredientDraft> ingredients) =>
      meals.create(MealDraft(title: title, eatenAt: eatenAt, ingredients: ingredients));

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final allMeals = await db.select(db.meals).get();
    final allIngredients = await db.select(db.mealIngredients).get();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        householdPrefsRepositoryProvider.overrideWithValue(prefs),
        supplementIntakesStreamProvider.overrideWith((ref) => Stream.value(const <SupplementIntake>[])),
        mealsStreamProvider.overrideWith((ref) => Stream.value(allMeals)),
        mealIngredientsStreamProvider.overrideWith((ref) => Stream.value(allIngredients)),
      ],
      child: MaterialApp(home: NutrientsPage(now: _now)),
    ));
    await tester.pumpAndSettle();
  }

  String text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

  final today = DateTime.utc(2026, 10, 3, 6);

  Future<void> bananaDay() async {
    await meal('Frühstück', today, [
      food('Banane', 118, const {'vit_c_mg': 11.0, 'iron_mg': 0.4, 'vit_d_ug': 0.0}),
      food('Gewürz', 5, null),
    ]);
  }

  pageTest('Tag: Summe mit "mindestens", Abdeckung, unbekannt und echte Null', (tester) async {
    await bananaDay();
    await open(tester);

    expect(text(tester, 'nutrients-title'), 'Heute');
    expect(text(tester, 'nutrient-value-vit_c_mg'), 'mindestens 13 mg');
    expect(text(tester, 'nutrient-coverage-vit_c_mg'), 'aus 1 von 2 Zutaten mit Daten');
    expect(text(tester, 'nutrient-value-iron_mg'), 'mindestens 0,5 mg');
    expect(text(tester, 'nutrient-value-vit_d_ug'), 'mindestens 0,0 µg', reason: 'eine echte Null ist ein Wert, nicht "unbekannt"');
    expect(text(tester, 'nutrient-value-iodine_ug'), 'unbekannt');
    expect(text(tester, 'nutrient-coverage-iodine_ug'), 'keine Daten in 2 Zutaten');
  });

  pageTest('vollstaendig: ohne "mindestens" und ohne Abdeckungszeile', (tester) async {
    await meal('Obst', today, [food('Banane', 100, const {'vit_c_mg': 11.0})]);
    await open(tester);
    expect(text(tester, 'nutrient-value-vit_c_mg'), '11 mg');
    expect(find.byKey(const Key('nutrient-coverage-vit_c_mg')), findsNothing);
  });

  pageTest('Vorauswahl der zwoelf, "Alle zeigen" blendet den Rest ein und wieder aus', (tester) async {
    await bananaDay();
    await open(tester);
    expect(find.byKey(const Key('nutrient-row-vit_c_mg')), findsOneWidget);
    expect(find.byKey(const Key('nutrient-row-omega3_g')), findsOneWidget);
    expect(find.byKey(const Key('nutrient-row-vit_e_mg')), findsNothing);
    expect(find.byKey(const Key('nutrient-row-starch_g')), findsNothing);
    expect(tester.widgetList(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('nutrient-row-'))), hasLength(12));

    await tester.tap(find.byKey(const Key('nutrients-show-all')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nutrient-row-vit_e_mg')), findsOneWidget);
    expect(find.byKey(const Key('nutrient-row-starch_g')), findsOneWidget);
    expect(tester.widgetList(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('nutrient-row-'))), hasLength(38));

    await tester.tap(find.byKey(const Key('nutrients-show-all')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nutrient-row-vit_e_mg')), findsNothing);
  });

  pageTest('Referenzmengen sind standardmaessig aus; eingeschaltet zeigt die Seite "% der Referenzmenge" ohne Bewertung und merkt es sich', (tester) async {
    await bananaDay();
    await open(tester);
    expect(find.byKey(const Key('nutrient-reference-vit_c_mg')), findsNothing);
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('nutrients-reference'))).value, isFalse);
    expect(find.textContaining('keine Empfehlung'), findsWidgets);

    await tester.tap(find.byKey(const Key('nutrients-reference')));
    await tester.pumpAndSettle();
    expect(text(tester, 'nutrient-reference-vit_c_mg'), '16 % der Referenzmenge');
    expect(find.byType(LinearProgressIndicator), findsWidgets);
    expect(find.byKey(const Key('nutrient-reference-omega3_g')), findsNothing, reason: 'fuer Fettsaeuren gibt es keine Kennzeichnungsmenge');
    expect(find.byKey(const Key('nutrient-reference-iodine_ug')), findsNothing, reason: 'unbekannt hat keinen Anteil');
    expect((await prefs.load())[microReferenceOnPref], true);
    expect(find.textContaining('Mangel'), findsNothing);
  });

  pageTest('die gemerkte Einstellung gilt beim naechsten Oeffnen', (tester) async {
    await bananaDay();
    await prefs.set(microReferenceOnPref, true);
    await open(tester);
    expect(text(tester, 'nutrient-reference-vit_c_mg'), '16 % der Referenzmenge');
  });

  pageTest('lokale Referenzmengen aus Version 1.12 werden einmal in die gemeinsamen Einstellungen uebernommen', (tester) async {
    await bananaDay();
    await db.setKv('micro_reference_on', 'true');
    await db.setKv('micro_reference_overrides', jsonEncode({'vit_c_mg': 40}));
    await open(tester);
    expect(text(tester, 'nutrient-reference-vit_c_mg'), '32 % der Referenzmenge');
    expect(await prefs.load(), {microReferenceOnPref: true, microReferenceOverridesPref: {'vit_c_mg': 40}});
  });

  pageTest('gemeinsame Werte gehen den alten lokalen vor und werden nicht ueberschrieben', (tester) async {
    await bananaDay();
    await prefs.set(microReferenceOnPref, true);
    await prefs.set(microReferenceOverridesPref, {'vit_c_mg': 160});
    await db.setKv('micro_reference_on', 'true');
    await db.setKv('micro_reference_overrides', jsonEncode({'vit_c_mg': 40}));
    await open(tester);
    expect(text(tester, 'nutrient-reference-vit_c_mg'), '8 % der Referenzmenge');
    expect((await prefs.load())[microReferenceOverridesPref], {'vit_c_mg': 160});
  });

  pageTest('"Woher kommt das?": groesste Beitraege mit Zutat und Mahlzeit, Abdeckung und Referenzmenge', (tester) async {
    await meal('Frühstück', today, [food('Banane', 118, const {'vit_c_mg': 11.0}), food('Gewürz', 5, null)]);
    await meal('Mittag', today, [food('Paprika', 100, const {'vit_c_mg': 120.0})]);
    await open(tester);

    await tester.tap(find.byKey(const Key('nutrient-row-vit_c_mg')));
    await tester.pumpAndSettle();
    expect(text(tester, 'nutrient-sheet-title'), 'Vitamin C');
    expect(text(tester, 'nutrient-sheet-total'), 'mindestens 133 mg');
    expect(text(tester, 'nutrient-sheet-coverage'), 'Aus 2 von 3 Zutaten mit Daten, der Rest ist unbekannt.');
    expect(find.descendant(of: find.byKey(const Key('nutrient-contrib-0')), matching: find.text('Paprika')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('nutrient-contrib-0')), matching: find.text('Mittag')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('nutrient-contrib-1')), matching: find.text('Banane')), findsOneWidget);
    expect(find.byKey(const Key('nutrient-contrib-2')), findsNothing);
    expect(text(tester, 'nutrient-sheet-reference'), 'Kennzeichnungs-Referenzmenge: 80 mg pro Tag');
  });

  pageTest('Quelle ohne Daten: das Blatt sagt es ehrlich', (tester) async {
    await bananaDay();
    await open(tester);
    await tester.tap(find.byKey(const Key('nutrient-row-iodine_ug')));
    await tester.pumpAndSettle();
    expect(text(tester, 'nutrient-sheet-total'), 'unbekannt');
    expect(text(tester, 'nutrient-sheet-coverage'), 'Für keine der 2 Zutaten gibt es einen Wert.');
    expect(find.byKey(const Key('nutrient-contrib-0')), findsNothing);
  });

  pageTest('eigenen Referenzwert festlegen, gemerkt und zuruecksetzen', (tester) async {
    await bananaDay();
    await prefs.set(microReferenceOnPref, true);
    await open(tester);

    await tester.tap(find.byKey(const Key('nutrient-row-vit_c_mg')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nutrient-override-edit')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('nutrient-override-field'))).controller!.text, '80');
    await tester.enterText(find.byKey(const Key('nutrient-override-field')), '40');
    await tester.tap(find.byKey(const Key('nutrient-override-ok')));
    await tester.pumpAndSettle();
    expect(text(tester, 'nutrient-reference-vit_c_mg'), '32 % der Referenzmenge');
    expect((await prefs.load())[microReferenceOverridesPref], {'vit_c_mg': 40});

    await tester.tap(find.byKey(const Key('nutrient-row-vit_c_mg')));
    await tester.pumpAndSettle();
    expect(text(tester, 'nutrient-sheet-reference'), contains('Du hast 40 mg festgelegt'));
    await tester.tap(find.byKey(const Key('nutrient-override-reset')));
    await tester.pumpAndSettle();
    expect(text(tester, 'nutrient-reference-vit_c_mg'), '16 % der Referenzmenge');
    expect((await prefs.load())[microReferenceOverridesPref], isEmpty);
  });

  pageTest('eigener Referenzwert 0 entfernt ihn; ohne Referenzmenge (Omega-3) laesst sich einer festlegen', (tester) async {
    await meal('Fisch', today, [food('Lachs', 100, const {'omega3_g': 2.6})]);
    await prefs.set(microReferenceOnPref, true);
    await open(tester);

    await tester.tap(find.byKey(const Key('nutrient-row-omega3_g')));
    await tester.pumpAndSettle();
    expect(text(tester, 'nutrient-sheet-reference'), 'Für diesen Wert gibt es keine Kennzeichnungs-Referenzmenge.');
    await tester.tap(find.byKey(const Key('nutrient-override-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('nutrient-override-field')), '2,5');
    await tester.tap(find.byKey(const Key('nutrient-override-ok')));
    await tester.pumpAndSettle();
    expect(text(tester, 'nutrient-reference-omega3_g'), '104 % der Referenzmenge');

    await tester.tap(find.byKey(const Key('nutrient-row-omega3_g')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nutrient-override-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('nutrient-override-field')), '0');
    await tester.tap(find.byKey(const Key('nutrient-override-ok')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nutrient-reference-omega3_g')), findsNothing);
  });

  pageTest('Woche: Durchschnitt je erfasstem Tag und "x von 7 Tagen erfasst"', (tester) async {
    await meal('A', DateTime.utc(2026, 9, 28, 10), [food('x', 100, const {'vit_c_mg': 30.0})]); // Montag
    await meal('B', DateTime.utc(2026, 9, 30, 10), [food('y', 100, const {'vit_c_mg': 60.0})]); // Mittwoch
    await open(tester);

    await tester.tap(find.text('Woche'));
    await tester.pumpAndSettle();
    expect(text(tester, 'nutrients-title'), '28. Sep – 4. Okt');
    expect(text(tester, 'nutrients-week-info'), 'Ø pro erfasstem Tag, 2 von 7 Tagen erfasst');
    expect(text(tester, 'nutrient-value-vit_c_mg'), '45 mg');
  });

  pageTest('Tage blaettern: ein Tag ohne Eintrag sagt "nichts erfasst" statt Nullen', (tester) async {
    await bananaDay();
    await open(tester);
    await tester.tap(find.byKey(const Key('nutrients-prev')));
    await tester.pumpAndSettle();
    expect(text(tester, 'nutrients-title'), 'Gestern');
    expect(find.byKey(const Key('nutrients-none')), findsOneWidget);
    expect(find.byKey(const Key('nutrient-row-vit_c_mg')), findsNothing);
    await tester.tap(find.byKey(const Key('nutrients-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nutrient-row-vit_c_mg')), findsOneWidget);
  });

  pageTest('Woche ohne Eintrag und leere Datenbank', (tester) async {
    await open(tester);
    expect(find.byKey(const Key('nutrients-none')), findsOneWidget);
    await tester.tap(find.text('Woche'));
    await tester.pumpAndSettle();
    expect(text(tester, 'nutrients-none'), 'In dieser Woche ist nichts erfasst.');
  });

  pageTest('ehrliche Hinweise: Grenzen der Tabellenwerte unter den Zeilen und im Info-Dialog', (tester) async {
    await bananaDay();
    await open(tester);
    expect(text(tester, 'nutrients-limits'), contains('Garverluste'));
    expect(text(tester, 'nutrients-limits'), contains('Nahrungsergänzung zählt nur'));
    expect(text(tester, 'nutrients-limits'), contains('Selen und Koffein fehlen'));
    await tester.tap(find.byKey(const Key('nutrients-info')));
    await tester.pumpAndSettle();
    expect(find.text('Woher stammen die Werte?'), findsWidgets);
    expect(find.textContaining('keine Empfehlung für dich'), findsOneWidget);
  });

  pageTest('Schaetzwerte werden genannt', (tester) async {
    final m = await meal('Restaurant', today, [food('x', 100, const {'vit_c_mg': 5.0})]);
    await (db.update(db.meals)..where((t) => t.id.equals(m.id))).write(const MealsCompanion(isEstimate: Value(true)));
    await open(tester);
    expect(find.byKey(const Key('nutrients-estimates')), findsOneWidget);
  });

  pageTest('Portionsanteil: eine Portion von vier', (tester) async {
    await meals.create(MealDraft(
      title: 'Suppe',
      eatenAt: today,
      servingsEaten: 1,
      servingsMade: 4,
      ingredients: [food('Gemuese', 400, const {'vit_c_mg': 20.0})],
    ));
    await open(tester);
    expect(text(tester, 'nutrient-value-vit_c_mg'), '20 mg');
  });
}
