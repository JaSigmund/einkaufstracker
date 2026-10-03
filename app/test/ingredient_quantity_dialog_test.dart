import 'package:einkaufstracker/domain/nutrition/food_unit.dart';
import 'package:einkaufstracker/domain/nutrition/ingredient_nutrition.dart';
import 'package:einkaufstracker/domain/nutrition/nutrient_scaling.dart';
import 'package:einkaufstracker/features/diary/ingredient_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Mengen-Dialog mit Haushaltsmassen (Phase N2, ADR-033): nur bekannte Einheiten, "1 Stk ≈ 118 g", einmalige Rueckfrage nach dem
/// Stueckgewicht, Groessen, Brueche und die Vorschau der Naehrwerte.
const _banane = NutrientsPer100(kcal: 79, proteinG: 1.1);

void main() {
  IngredientQuantity? result;
  var closed = false;

  Future<void> open(
    WidgetTester tester, {
    String label = 'Banane',
    EntryUnit initialUnit = EntryUnit.g,
    double? initialQuantity,
    List<FoodUnit>? units,
    double? pieceWeightG,
    String pieceWeightSource = 'household',
    NutrientsPer100? per100 = _banane,
    FoodUnitKey? initialUnitKey,
    double? initialUnitWeightG,
  }) async {
    result = null;
    closed = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const Key('open'),
              onPressed: () async {
                result = await askIngredientQuantity(
                  context,
                  label: label,
                  initialUnit: initialUnit,
                  initialQuantity: initialQuantity,
                  units: units ?? sampleFoodUnits()['F503100']!,
                  pieceWeightG: pieceWeightG,
                  pieceWeightSource: pieceWeightSource,
                  per100: per100,
                  initialUnitKey: initialUnitKey,
                  initialUnitWeightG: initialUnitWeightG,
                );
                closed = true;
              },
              child: const Text('offen'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
  }

  Future<void> quantity(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('ingredient-quantity')), text);
    await tester.pump();
  }

  Future<void> ok(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('ingredient-quantity-ok')));
    await tester.pumpAndSettle();
  }

  String text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

  testWidgets('bietet Gramm, Milliliter und Stueck, sonst nur Bekanntes; Gramm zeigt die Naehrwerte sofort', (tester) async {
    await open(tester);
    expect(find.byKey(const Key('ingredient-unit-g')), findsOneWidget);
    expect(find.byKey(const Key('ingredient-unit-ml')), findsOneWidget);
    expect(find.byKey(const Key('ingredient-unit-piece')), findsOneWidget);
    expect(find.byKey(const Key('ingredient-unit-slice')), findsNothing, reason: 'Bananen haben keine Scheiben in der Tabelle');
    expect(find.byKey(const Key('ingredient-unit-tbsp')), findsNothing);
    await quantity(tester, '150');
    expect(text(tester, 'ingredient-preview'), '119 kcal');
    await ok(tester);
    expect(result!.unit, EntryUnit.g);
    expect(result!.unitKey, isNull);
    expect(result!.unitWeightG, isNull);
    expect(result!.quantity, 150);
  });

  testWidgets('Stueck mit bekannten Groessen: mittel ist vorgewaehlt, "1 Stk ≈ 118 g", Vorschau fuer die ganze Menge', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('ingredient-unit-piece')));
    await tester.pumpAndSettle();
    expect(text(tester, 'ingredient-unit-info'), '1 Stk ≈ 118 g (Richtwert)');
    expect(find.byKey(const Key('ingredient-unit-weight')), findsNothing, reason: 'Gewicht ist bekannt, keine Rueckfrage');
    expect(find.byKey(const Key('ingredient-sizes')), findsOneWidget);
    expect(tester.widget<ChoiceChip>(find.byKey(const Key('ingredient-size-medium'))).selected, isTrue);

    await quantity(tester, '2');
    expect(text(tester, 'ingredient-preview'), '2 Stk = 236 g · 186 kcal');
    await ok(tester);
    expect(result!.unit, EntryUnit.piece);
    expect(result!.unitKey, FoodUnitKey.piece);
    expect(result!.unitWeightG, 118);
    expect(result!.learnWeight, isFalse, reason: 'ein Tabellenwert wird nie als eigenes Gewicht gemerkt');
    expect(result!.quantity, 2);
  });

  testWidgets('Groesse waehlen setzt das Gewicht', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('ingredient-unit-piece')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ingredient-size-large')));
    await tester.pumpAndSettle();
    expect(text(tester, 'ingredient-unit-info'), '1 Stk ≈ 136 g (Richtwert)');
    await quantity(tester, '1');
    await ok(tester);
    expect(result!.unitWeightG, 136);
    expect(result!.learnWeight, isFalse);

    await open(tester);
    await tester.tap(find.byKey(const Key('ingredient-unit-piece')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ingredient-size-small')));
    await tester.pumpAndSettle();
    await quantity(tester, '3');
    await ok(tester);
    expect(result!.unitWeightG, 101);
  });

  testWidgets('Brueche als Schnellwahl', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('ingredient-unit-piece')));
    await tester.pumpAndSettle();
    expect(tester.widgetList(find.byType(ActionChip)), hasLength(5));
    await tester.tap(find.byKey(const Key('ingredient-frac-1')));
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(const Key('ingredient-quantity'))).controller!.text, '0,5');
    expect(text(tester, 'ingredient-preview'), '0,5 Stk = 59 g · 47 kcal');
    await tester.tap(find.byKey(const Key('ingredient-frac-3')));
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(const Key('ingredient-quantity'))).controller!.text, '1,5');
    await ok(tester);
    expect(result!.quantity, 1.5);
  });

  testWidgets('Brueche gibt es nur bei Haushaltseinheiten, nicht bei Gramm', (tester) async {
    await open(tester);
    expect(find.byKey(const Key('ingredient-fractions')), findsNothing);
  });

  testWidgets('Stueck ohne bekanntes Gewicht: der Dialog fragt einmal, das eigene Gewicht wird gemerkt', (tester) async {
    await open(tester, label: 'Gewürzgurke', units: const [], per100: const NutrientsPer100(kcal: 11));
    await tester.tap(find.byKey(const Key('ingredient-unit-piece')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ingredient-unit-weight')), findsOneWidget);
    expect(find.textContaining('Wie viel wiegt 1 Stück Gewürzgurke'), findsOneWidget);
    expect(find.byKey(const Key('ingredient-unit-info')), findsNothing);

    await quantity(tester, '2');
    await tester.enterText(find.byKey(const Key('ingredient-unit-weight')), '35');
    await tester.pump();
    expect(text(tester, 'ingredient-unit-info'), '1 Stk ≈ 35 g (dein Gewicht)');
    expect(text(tester, 'ingredient-preview'), '2 Stk = 70 g · 8 kcal');
    await ok(tester);
    expect(result!.unitWeightG, 35);
    expect(result!.learnWeight, isTrue);
    expect(result!.unitKey, FoodUnitKey.piece);
  });

  testWidgets('Stueck ohne Gewicht bleibt moeglich (Hinweis statt Zwang): die Zutat zaehlt dann nicht in den Naehrwerten', (tester) async {
    await open(tester, label: 'Gewürzgurke', units: const [], per100: null);
    await tester.tap(find.byKey(const Key('ingredient-unit-piece')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ohne Gewicht zählt die Zutat nicht in den Nährwerten'), findsOneWidget);
    await quantity(tester, '1');
    await ok(tester);
    expect(result!.unitWeightG, isNull);
    expect(result!.learnWeight, isFalse);
  });

  testWidgets('unsinniges Gewicht (0, Text, ueber 5 kg) zaehlt nicht', (tester) async {
    await open(tester, units: const []);
    await tester.tap(find.byKey(const Key('ingredient-unit-piece')));
    await tester.pumpAndSettle();
    for (final bad in ['0', 'viel', '6000', '-3']) {
      await tester.enterText(find.byKey(const Key('ingredient-unit-weight')), bad);
      await tester.pump();
      expect(find.byKey(const Key('ingredient-unit-info')), findsNothing, reason: bad);
    }
  });

  testWidgets('bekanntes Haushaltsgewicht: "dein Gewicht", "Gewicht aendern" macht daraus ein neu gemerktes', (tester) async {
    await open(tester, pieceWeightG: 135);
    await tester.tap(find.byKey(const Key('ingredient-unit-piece')));
    await tester.pumpAndSettle();
    expect(text(tester, 'ingredient-unit-info'), '1 Stk ≈ 135 g (dein Gewicht)');
    expect(find.byKey(const Key('ingredient-unit-weight')), findsNothing);
    await quantity(tester, '1');
    await ok(tester);
    expect(result!.unitWeightG, 135);
    expect(result!.learnWeight, isFalse, reason: 'schon gemerkt');

    await open(tester, pieceWeightG: 135);
    await tester.tap(find.byKey(const Key('ingredient-unit-piece')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ingredient-unit-weight-edit')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('ingredient-unit-weight'))).controller!.text, '135');
    await tester.enterText(find.byKey(const Key('ingredient-unit-weight')), '150');
    await quantity(tester, '1');
    await ok(tester);
    expect(result!.unitWeightG, 150);
    expect(result!.learnWeight, isTrue);
  });

  testWidgets('Gewicht vom Produkt wird als solches genannt', (tester) async {
    await open(tester, pieceWeightG: 60, pieceWeightSource: 'product', units: const []);
    await tester.tap(find.byKey(const Key('ingredient-unit-piece')));
    await tester.pumpAndSettle();
    expect(text(tester, 'ingredient-unit-info'), '1 Stk ≈ 60 g (vom Produkt)');
  });

  testWidgets('Scheibe und EL: nur wenn die Tabelle sie kennt, Rechnung ueber das Gewicht, Name der Einheit im Ergebnis', (tester) async {
    await open(tester, label: 'Weizenbrot', units: sampleFoodUnits()['B311000']!, per100: const NutrientsPer100(kcal: 260));
    expect(find.byKey(const Key('ingredient-unit-slice')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ingredient-unit-slice')));
    await tester.pumpAndSettle();
    await quantity(tester, '3');
    expect(text(tester, 'ingredient-unit-info'), '1 Scheibe ≈ 28 g (Richtwert)');
    expect(text(tester, 'ingredient-preview'), '3 Scheiben = 84 g · 218 kcal');
    await ok(tester);
    expect(result!.unit, EntryUnit.piece);
    expect(result!.unitKey, FoodUnitKey.slice);
    expect(result!.unitWeightG, 28);
    expect(result!.learnWeight, isFalse);

    await open(tester, label: 'Olivenöl', units: sampleFoodUnits()['Q120000']!, per100: const NutrientsPer100(kcal: 884));
    await tester.tap(find.byKey(const Key('ingredient-unit-tbsp')));
    await tester.pumpAndSettle();
    await quantity(tester, '2');
    expect(text(tester, 'ingredient-preview'), '2 EL = 27 g · 239 kcal');
    expect(find.byKey(const Key('ingredient-unit-tsp')), findsOneWidget);
    await ok(tester);
    expect(result!.unitKey, FoodUnitKey.tbsp);
    expect(result!.unitWeightG, 13.5);
  });

  testWidgets('Zeile wiederherstellen: gespeicherte Einheit und Gewicht sind vorgewaehlt und werden nicht neu "gelernt"', (tester) async {
    await open(
      tester,
      label: 'Weizenbrot',
      units: sampleFoodUnits()['B311000']!,
      initialUnit: EntryUnit.piece,
      initialUnitKey: FoodUnitKey.slice,
      initialUnitWeightG: 31,
      initialQuantity: 2,
    );
    expect(tester.widget<ChoiceChip>(find.byKey(const Key('ingredient-unit-slice'))).selected, isTrue);
    expect(text(tester, 'ingredient-unit-info'), '1 Scheibe ≈ 31 g (wie gespeichert)');
    await ok(tester);
    expect(result!.quantity, 2);
    expect(result!.unitKey, FoodUnitKey.slice);
    expect(result!.unitWeightG, 31, reason: 'das gespeicherte Gewicht bleibt, auch wenn die Tabelle 28 g sagt');
    expect(result!.learnWeight, isFalse);
  });

  testWidgets('Wechsel von Stueck zu Gramm vergisst die Einheit', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('ingredient-unit-piece')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ingredient-unit-g')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ingredient-fractions')), findsNothing);
    await quantity(tester, '100');
    await ok(tester);
    expect(result!.unit, EntryUnit.g);
    expect(result!.unitKey, isNull);
    expect(result!.unitWeightG, isNull);
  });

  testWidgets('ohne Naehrwerte keine kcal-Vorschau, aber die Umrechnung in Gramm steht da', (tester) async {
    await open(tester, per100: null);
    await tester.tap(find.byKey(const Key('ingredient-unit-piece')));
    await tester.pumpAndSettle();
    await quantity(tester, '2');
    expect(find.byKey(const Key('ingredient-preview')), findsNothing);
    expect(text(tester, 'ingredient-unit-info'), '1 Stk ≈ 118 g (Richtwert)');
  });

  testWidgets('Abbrechen liefert nichts', (tester) async {
    await open(tester);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, isNull);
  });

  testWidgets('Uebernehmen ist ohne Menge gesperrt', (tester) async {
    await open(tester);
    expect(tester.widget<FilledButton>(find.byKey(const Key('ingredient-quantity-ok'))).onPressed, isNull);
    await quantity(tester, '0');
    expect(tester.widget<FilledButton>(find.byKey(const Key('ingredient-quantity-ok'))).onPressed, isNull);
    await quantity(tester, '1');
    expect(tester.widget<FilledButton>(find.byKey(const Key('ingredient-quantity-ok'))).onPressed, isNotNull);
  });
}
