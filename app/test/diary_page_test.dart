import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/features/diary/diary_page.dart';
import 'package:einkaufstracker/domain/nutrition/nutrition_targets.dart';
import 'package:einkaufstracker/features/diary/meal_form_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;

import 'support/fakes.dart';

/// Tagebuch-Tab (Doku 15 §3.5, Phase 7b/7d): Tage, Tageswerte, Wochendurchschnitt, Datenqualitaet.
Meal _meal(String id, DateTime utc, {String title = 'Mahlzeit', String type = 'lunch', double eaten = 1, double made = 1, bool estimate = false}) => Meal(
      id: id, householdId: 'h1', eatenAt: utc, mealType: type, title: title, servingsEaten: eaten, servingsMade: made,
      source: 'manual', isEstimate: estimate, updatedAt: DateTime.utc(2026),
    );

MealIngredient _ing(String id, String mealId, {double? kcal, double? protein, String? micros, String name = 'Zutat'}) => MealIngredient(
      id: id, householdId: 'h1', mealId: mealId, freeText: name, quantity: 1, unit: 'kg', source: 'manual',
      kcal: kcal, proteinG: protein, micros: micros, updatedAt: DateTime.utc(2026),
    );

void main() {
  // Freitag, 2. Oktober 2026, 12:00 UTC; die Woche beginnt am Montag, 28. September
  final now = DateTime.utc(2026, 10, 2, 12);

  Widget host(List<Meal> meals, List<MealIngredient> ingredients,
          {NutritionTargets targets = const NutritionTargets(), FakeMealPhotoService? photos}) =>
      ProviderScope(
        overrides: [
          if (photos != null) mealPhotoServiceProvider.overrideWithValue(photos),
          nutritionTargetsProvider.overrideWith((ref) => Stream.value(targets)),
          balanceMovementsProvider.overrideWith((ref) => Stream.value(const <InventoryMovement>[])),
          productsStreamProvider.overrideWith((ref) => Stream.value(const <Product>[])),
          mealsStreamProvider.overrideWith((ref) => Stream.value(meals)),
          mealIngredientsStreamProvider.overrideWith((ref) => Stream.value(ingredients)),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(routes: [
            GoRoute(path: '/', builder: (_, _) => Scaffold(body: DiaryPage(now: now))),
            GoRoute(path: '/nutrients', builder: (_, _) => const Scaffold(body: Text('NAEHRSTOFFE'))),
            GoRoute(
              path: '/meal-form',
              builder: (_, s) {
                final a = s.extra as MealFormArgs;
                return Scaffold(
                  body: Text(a.existing != null
                      ? 'BEARBEITEN ${a.existing!.title}'
                      : a.template != null
                          ? '${a.leftover ? 'REST' : 'KOPIE'} ${a.template!.title}'
                          : 'NEU'),
                );
              },
            ),
          ]),
        ),
      );

  testWidgets('ohne Mahlzeiten: Hinweis statt leerer Liste, Knopf zum Anlegen vorhanden', (tester) async {
    await tester.pumpWidget(host(const [], const []));
    await tester.pumpAndSettle();
    expect(find.text('Noch keine Mahlzeit'), findsOneWidget);
    expect(find.byKey(const Key('diary-add')), findsOneWidget);
    expect(find.byKey(const Key('diary-week')), findsNothing);
  });

  testWidgets('Knopf "Mahlzeit" oeffnet das Formular fuer einen neuen Eintrag', (tester) async {
    await tester.pumpWidget(host(const [], const []));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('diary-add')));
    await tester.pumpAndSettle();
    expect(find.text('NEU'), findsOneWidget);
  });

  testWidgets('zeigt Tagesueberschrift, Tageswerte und die Mahlzeit mit Uhrzeit, Typ, Zutaten und kcal', (tester) async {
    await tester.pumpWidget(host(
      [_meal('m1', DateTime.utc(2026, 10, 2, 10, 30), title: 'Reispfanne', type: 'lunch')],
      [_ing('i1', 'm1', kcal: 525, protein: 10.5), _ing('i2', 'm1', kcal: 100)],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Heute'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('day-totals-2026-10-2'))).data, startsWith('625 kcal · 11 g Eiweiß'));
    expect(find.descendant(of: find.byKey(const Key('meal-m1')), matching: find.text('Reispfanne')), findsOneWidget);
    expect(find.text('12:30 · Mittagessen · 2 Zutaten'), findsOneWidget);
    expect(find.text('625 kcal'), findsOneWidget);
    expect(find.byKey(const Key('day-quality-2026-10-2')), findsNothing, reason: 'alle Zutaten haben Naehrwerte');
  });

  testWidgets('Datenqualitaet: fehlende Naehrwerte und Schaetzwerte werden benannt (FR-17)', (tester) async {
    await tester.pumpWidget(host(
      [_meal('m1', DateTime.utc(2026, 10, 2, 10), estimate: true)],
      [_ing('i1', 'm1', kcal: 100), _ing('i2', 'm1')],
    ));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('day-quality-2026-10-2'))).data, 'Nährwerte für 1 von 2 Zutaten bekannt · enthält Schätzwerte');
    expect(find.textContaining('geschätzt'), findsWidgets);
  });

  testWidgets('Mahlzeit ganz ohne Naehrwerte zeigt keine kcal (nicht "0 kcal", FR-15)', (tester) async {
    await tester.pumpWidget(host([_meal('m1', DateTime.utc(2026, 10, 2, 10))], [_ing('i1', 'm1')]));
    await tester.pumpAndSettle();
    expect(find.text('0 kcal'), findsNothing);
  });

  testWidgets('Portionsanteil: 1 von 4 Portionen zaehlt zu einem Viertel', (tester) async {
    await tester.pumpWidget(host([_meal('m1', DateTime.utc(2026, 10, 2, 10), eaten: 1, made: 4)], [_ing('i1', 'm1', kcal: 800)]));
    await tester.pumpAndSettle();
    expect(find.text('200 kcal'), findsWidgets);
  });

  testWidgets('mehrere Tage: neuester zuerst, Gestern und Wochentag-Ueberschriften; Tage ohne Eintrag fehlen', (tester) async {
    // hoher Bildschirm: die Liste baut ihre Abschnitte sonst lazy, und der unterste liegt ausserhalb des Sichtbereichs
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(
      [_meal('a', DateTime.utc(2026, 10, 2, 10), title: 'Heute-Essen'), _meal('b', DateTime.utc(2026, 10, 1, 10), title: 'Gestern-Essen'), _meal('c', DateTime.utc(2026, 9, 28, 10), title: 'Montag-Essen')],
      [_ing('i1', 'a', kcal: 100), _ing('i2', 'b', kcal: 100), _ing('i3', 'c', kcal: 100)],
    ));
    await tester.pumpAndSettle();
    expect(find.text('Heute'), findsOneWidget);
    expect(find.text('Gestern'), findsOneWidget);
    expect(find.text('Montag, 28. September'), findsOneWidget);
    expect(find.text('Donnerstag, 1. Oktober'), findsNothing);
    // in der Liste (nicht in den Chips "Nochmal essen", wo dieselben Titel stehen)
    final heute = tester.getTopLeft(find.descendant(of: find.byKey(const Key('meal-a')), matching: find.text('Heute-Essen'))).dy;
    final gestern = tester.getTopLeft(find.descendant(of: find.byKey(const Key('meal-b')), matching: find.text('Gestern-Essen'))).dy;
    expect(heute, lessThan(gestern), reason: 'neuester Tag oben');
  });

  testWidgets('Wochenkarte: Durchschnitt ueber die erfassten Tage der laufenden Woche, Vorwoche zaehlt nicht', (tester) async {
    await tester.pumpWidget(host(
      [
        _meal('a', DateTime.utc(2026, 10, 2, 10)), // Fr, 2000
        _meal('b', DateTime.utc(2026, 10, 1, 10)), // Do, 1000
        _meal('c', DateTime.utc(2026, 9, 25, 10)), // Vorwoche, darf nicht eingehen
      ],
      [_ing('i1', 'a', kcal: 2000), _ing('i2', 'b', kcal: 1000), _ing('i3', 'c', kcal: 5000)],
    ));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('diary-week-kcal'))).data, 'Ø 1.500 kcal pro erfasstem Tag');
    expect(find.text('2 Tage erfasst'), findsOneWidget);
  });

  testWidgets('Tippen auf eine Mahlzeit oeffnet sie zum Bearbeiten', (tester) async {
    await tester.pumpWidget(host([_meal('m1', DateTime.utc(2026, 10, 2, 10), title: 'Reispfanne')], [_ing('i1', 'm1', kcal: 1)]));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('meal-m1')));
    await tester.pumpAndSettle();
    expect(find.text('BEARBEITEN Reispfanne'), findsOneWidget);
  });

  testWidgets('Tagesgrenze in Wiener Zeit: 23:30 UTC gehoert im Sommer schon zum Folgetag', (tester) async {
    // 2026-10-01 23:30 UTC = 2026-10-02 01:30 MESZ, also "Heute"
    await tester.pumpWidget(host([_meal('m1', DateTime.utc(2026, 10, 1, 23, 30), title: 'Nachtsnack')], [_ing('i1', 'm1', kcal: 100)]));
    await tester.pumpAndSettle();
    expect(find.text('Heute'), findsOneWidget);
    expect(find.text('01:30 · Mittagessen · 1 Zutat'), findsOneWidget);
  });

  group('Richtwerte (LH-MEAL-09)', () {
    final targets = const NutritionTargets()
        .withTarget(NutrientKey.kcal, const NutrientTarget(min: 1800, max: 2200))
        .withTarget(NutrientKey.proteinG, const NutrientTarget(min: 60));

    testWidgets('ohne Richtwerte erscheinen keine Vergleichszeilen', (tester) async {
      await tester.pumpWidget(host([_meal('m1', DateTime.utc(2026, 10, 2, 10))], [_ing('i1', 'm1', kcal: 1000)]));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('target-row-day-2026-10-2-kcal')), findsNothing);
      expect(find.byKey(const Key('target-row-week-kcal')), findsNothing);
    });

    testWidgets('nur Naehrwerte mit Richtwert werden verglichen, neutral benannt', (tester) async {
      await tester.pumpWidget(host([_meal('m1', DateTime.utc(2026, 10, 2, 10))], [_ing('i1', 'm1', kcal: 2500, protein: 40)], targets: targets));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.descendant(of: find.byKey(const Key('target-row-day-2026-10-2-kcal')), matching: find.byType(Text))).data,
          'Energie 2.500 kcal · 1.800–2.200 kcal (darüber)');
      expect(tester.widget<Text>(find.descendant(of: find.byKey(const Key('target-row-day-2026-10-2-protein_g')), matching: find.byType(Text))).data,
          'Eiweiß 40 g · mindestens 60 g (darunter)');
      expect(find.byKey(const Key('target-row-day-2026-10-2-salt_g')), findsNothing);
    });

    testWidgets('im Bereich: kein Zusatz in Klammern', (tester) async {
      await tester.pumpWidget(host([_meal('m1', DateTime.utc(2026, 10, 2, 10))], [_ing('i1', 'm1', kcal: 2000, protein: 70)], targets: targets));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.descendant(of: find.byKey(const Key('target-row-day-2026-10-2-kcal')), matching: find.byType(Text))).data,
          'Energie 2.000 kcal · 1.800–2.200 kcal');
    });

    testWidgets('fehlen Naehrwerte einzelner Zutaten, heisst der Tageswert "mindestens"', (tester) async {
      await tester.pumpWidget(host([_meal('m1', DateTime.utc(2026, 10, 2, 10))], [_ing('i1', 'm1', kcal: 900), _ing('i2', 'm1')], targets: targets));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.descendant(of: find.byKey(const Key('target-row-day-2026-10-2-kcal')), matching: find.byType(Text))).data,
          startsWith('Energie mindestens 900 kcal'));
    });

    testWidgets('Wochenkarte vergleicht den Tagesdurchschnitt mit dem Richtwert', (tester) async {
      await tester.pumpWidget(host(
        [_meal('a', DateTime.utc(2026, 10, 2, 10)), _meal('b', DateTime.utc(2026, 10, 1, 10))],
        [_ing('i1', 'a', kcal: 2000), _ing('i2', 'b', kcal: 1000)],
        targets: targets,
      ));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.descendant(of: find.byKey(const Key('target-row-week-kcal')), matching: find.byType(Text))).data,
          'Energie 1.500 kcal · 1.800–2.200 kcal (darunter)');
    });
  });

  group('Foto (Phase 7b)', () {
    Uint8List png() {
      final image = img.Image(width: 8, height: 8);
      return Uint8List.fromList(img.encodePng(image));
    }

    Meal withPhoto(String id) => _meal(id, DateTime.utc(2026, 10, 2, 10), title: 'Reispfanne').copyWith(photoPath: Value('h1/$id.jpg'));

    testWidgets('Mahlzeit mit Foto zeigt das Bild als Vorschau statt des Typ-Symbols', (tester) async {
      final db = memoryDb();
      addTearDown(db.close);
      final service = FakeMealPhotoService(db, mealRepo(db))..photos['m1'] = png();
      await tester.pumpWidget(host([withPhoto('m1')], [_ing('i1', 'm1', kcal: 100)], photos: service));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const Key('meal-m1')), matching: find.byKey(const Key('meal-photo-image'))), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('meal-m1')), matching: find.byIcon(Icons.lunch_dining_outlined)), findsNothing);
    });

    testWidgets('Foto nicht abrufbar (anderes Geraet, kein Netz): Typ-Symbol bleibt, kein Fehler', (tester) async {
      final db = memoryDb();
      addTearDown(db.close);
      final service = FakeMealPhotoService(db, mealRepo(db));
      await tester.pumpWidget(host([withPhoto('m1')], [_ing('i1', 'm1', kcal: 100)], photos: service));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('meal-photo-image')), findsNothing);
      expect(find.descendant(of: find.byKey(const Key('meal-m1')), matching: find.byIcon(Icons.lunch_dining_outlined)), findsOneWidget);
    });

    testWidgets('Mahlzeit ohne Foto braucht den Foto-Dienst gar nicht', (tester) async {
      await tester.pumpWidget(host([_meal('m1', DateTime.utc(2026, 10, 2, 10))], [_ing('i1', 'm1', kcal: 100)]));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const Key('meal-m1')), matching: find.byIcon(Icons.lunch_dining_outlined)), findsOneWidget);
    });
  });

  group('Nochmal essen (Doku 15 §3.2/§3.3)', () {
    final recent = DateTime.utc(2026, 9, 28, 8);

    List<Meal> repeated() => [
          _meal('a1', DateTime.utc(2026, 9, 29, 8), title: 'Müsli', type: 'breakfast'),
          _meal('a2', DateTime.utc(2026, 9, 30, 8), title: 'Müsli', type: 'breakfast'),
          _meal('a3', DateTime.utc(2026, 10, 1, 8), title: 'Müsli', type: 'breakfast'),
          _meal('b1', recent, title: 'Pizza', type: 'dinner'),
          _meal('b2', DateTime.utc(2026, 9, 27, 18), title: 'Pizza', type: 'dinner'),
        ];

    testWidgets('haeufigste Mahlzeiten stehen als Chips, haeufigste zuerst', (tester) async {
      await tester.pumpWidget(host(repeated(), [_ing('i1', 'a1', kcal: 100)]));
      await tester.pumpAndSettle();
      expect(find.text('Nochmal essen'), findsOneWidget);
      expect(tester.widget<ActionChip>(find.byKey(const Key('frequent-meal-0'))).label, isA<Text>());
      expect(find.descendant(of: find.byKey(const Key('frequent-meal-0')), matching: find.text('Müsli')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('frequent-meal-1')), matching: find.text('Pizza')), findsOneWidget);
    });

    testWidgets('Tippen auf einen Chip oeffnet eine Kopie der juengsten Mahlzeit', (tester) async {
      await tester.pumpWidget(host(repeated(), [_ing('i1', 'a1', kcal: 100)]));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('frequent-meal-0')));
      await tester.pumpAndSettle();
      expect(find.text('KOPIE Müsli'), findsOneWidget);
    });

    testWidgets('Mahlzeiten aelter als 60 Tage zaehlen nicht, ohne Treffer gibt es keinen Bereich', (tester) async {
      await tester.pumpWidget(host([_meal('x', DateTime.utc(2026, 5, 1, 8), title: 'Uralt')], [_ing('i1', 'x', kcal: 100)]));
      await tester.pumpAndSettle();
      expect(find.text('Nochmal essen'), findsNothing);
      expect(find.byKey(const Key('frequent-meal-0')), findsNothing);
    });

    testWidgets('langer Druck zeigt Nochmal erfassen, Als Rest erfassen und Bearbeiten', (tester) async {
      await tester.pumpWidget(host([_meal('m1', DateTime.utc(2026, 10, 2, 10), title: 'Reispfanne')], [_ing('i1', 'm1', kcal: 100)]));
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const Key('meal-m1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('meal-action-repeat')), findsOneWidget);
      expect(find.byKey(const Key('meal-action-leftover')), findsOneWidget);
      expect(find.byKey(const Key('meal-action-shopping')), findsOneWidget);
      expect(find.byKey(const Key('meal-action-micros')), findsOneWidget);
      expect(find.byKey(const Key('meal-action-edit')), findsOneWidget);
    });

    for (final (key, expected) in [
      ('meal-action-repeat', 'KOPIE Reispfanne'),
      ('meal-action-leftover', 'REST Reispfanne'),
      ('meal-action-edit', 'BEARBEITEN Reispfanne'),
    ]) {
      testWidgets('Aktion $key oeffnet das Formular im passenden Modus', (tester) async {
        await tester.pumpWidget(host([_meal('m1', DateTime.utc(2026, 10, 2, 10), title: 'Reispfanne')], [_ing('i1', 'm1', kcal: 100)]));
        await tester.pumpAndSettle();
        await tester.longPress(find.byKey(const Key('meal-m1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();
        expect(find.text(expected), findsOneWidget);
      });
    }
  });

  group('Mikronaehrstoffe (Phase N3)', () {
    testWidgets('die Karte "Nährstoffe" fuehrt zur Seite', (tester) async {
      await tester.pumpWidget(host([_meal('m1', DateTime.utc(2026, 10, 2, 10))], [_ing('i1', 'm1', kcal: 100)]));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('diary-nutrients')), findsOneWidget);
      await tester.tap(find.byKey(const Key('diary-nutrients')));
      await tester.pumpAndSettle();
      expect(find.text('NAEHRSTOFFE'), findsOneWidget);
    });

    testWidgets('ohne Mahlzeit gibt es die Karte nicht', (tester) async {
      await tester.pumpWidget(host(const [], const []));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('diary-nutrients')), findsNothing);
    });

    testWidgets('langer Druck: "Mehr Nährwerte" zeigt die Mikronaehrstoffe der Mahlzeit, "mind." bei Luecken', (tester) async {
      await tester.pumpWidget(host(
        [_meal('m1', DateTime.utc(2026, 10, 2, 10), title: 'Reispfanne')],
        [
          _ing('i1', 'm1', kcal: 100, name: 'Paprika', micros: '{"vit_c_mg":40,"iron_mg":1.2}'),
          _ing('i2', 'm1', kcal: 100, name: 'Reis', micros: '{"iron_mg":0.4}'),
          _ing('i3', 'm1', kcal: 100, name: 'Gewuerz'),
        ],
      ));
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const Key('meal-m1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('meal-action-micros')));
      await tester.pumpAndSettle();

      expect(find.text('Mehr Nährwerte'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('meal-micro-vit_c_mg')), matching: find.text('mind. 40 mg')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('meal-micro-iron_mg')), matching: find.text('mind. 1,6 mg')), findsOneWidget);
      expect(find.byKey(const Key('meal-micro-iodine_ug')), findsNothing, reason: 'unbekannte Werte stehen nicht als 0 da');
      expect(find.textContaining('aus 1 von 3 Zutaten'), findsOneWidget);
      expect(find.textContaining('Garverluste'), findsOneWidget);
    });

    testWidgets('Mahlzeit ohne Mikronaehrstoffdaten: ehrlicher Hinweis', (tester) async {
      await tester.pumpWidget(host([_meal('m1', DateTime.utc(2026, 10, 2, 10))], [_ing('i1', 'm1', kcal: 100)]));
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const Key('meal-m1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('meal-action-micros')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('meal-micros-none')), findsOneWidget);
    });

    testWidgets('Portionsanteil gilt auch im Blatt', (tester) async {
      await tester.pumpWidget(host(
        [_meal('m1', DateTime.utc(2026, 10, 2, 10), eaten: 1, made: 4)],
        [_ing('i1', 'm1', kcal: 100, micros: '{"vit_c_mg":80}')],
      ));
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const Key('meal-m1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('meal-action-micros')));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const Key('meal-micro-vit_c_mg')), matching: find.text('20 mg')), findsOneWidget);
    });
  });
}
