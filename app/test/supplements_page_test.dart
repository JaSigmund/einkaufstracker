import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/household_prefs_repository.dart';
import 'package:einkaufstracker/data/repositories/supplement_repository.dart';
import 'package:einkaufstracker/domain/nutrition/micros.dart';
import 'package:einkaufstracker/features/diary/nutrients_page.dart';
import 'package:einkaufstracker/features/diary/supplement_form_page.dart';
import 'package:einkaufstracker/features/diary/supplements_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';

/// Nahrungsergaenzung: Liste mit "Genommen", Formular und die Anzeige auf der Seite Naehrstoffe (Phase N4, ADR-035).
/// Heute ist der 3. Oktober 2026 (Wiener Zeit).
final _now = DateTime.utc(2026, 10, 3, 10);

void pageTest(String name, Future<void> Function(WidgetTester tester) body) => testWidgets(name, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

void main() {
  late AppDatabase db;
  late SupplementRepository repo;

  setUp(() {
    db = memoryDb();
    repo = SupplementRepository(db, householdId: () async => 'h1');
  });
  tearDown(() => db.close());

  Future<Supplement> d3() => repo.save(name: 'Vitamin D3', servingLabel: 'Tablette', micros: const {'vit_d_ug': 25.0});

  Future<List<SupplementIntake>> intakes() => db.select(db.supplementIntakes).get();

  group('Liste', () {
    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db), supplementRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(home: SupplementsPage(now: _now)),
      ));
      await tester.pumpAndSettle();
    }

    pageTest('ohne Ergaenzung steht ein Hinweis da, und der Text sagt, dass die App nichts bewertet', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('supplements-empty')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('supplements-hint'))).data, contains('bewertet nicht'));
    });

    pageTest('eine Ergaenzung zeigt ihren Inhalt je Einheit', (tester) async {
      final s = await repo.save(name: 'Multi', servingLabel: 'Kapsel', micros: const {'vit_c_mg': 80.0, 'iron_mg': 14.0});
      await open(tester);
      expect(find.text('Multi'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(Key('supplement-summary-${s.id}'))).data, 'Je Kapsel: Vitamin C 80 mg, Eisen 14,0 mg');
    });

    pageTest('"Genommen" traegt eine Einheit fuer jetzt ein, zeigt sie unter "Heute genommen" und laesst sich zuruecknehmen', (tester) async {
      final s = await d3();
      await open(tester);
      await tester.tap(find.byKey(Key('supplement-take-${s.id}')));
      await tester.pumpAndSettle();

      final rows = await intakes();
      expect(rows, hasLength(1));
      expect(rows.single.servings, 1);
      expect(parseMicros(rows.single.micros), {'vit_d_ug': 25.0});
      expect(rows.single.takenAt, _now);
      expect(find.text('Vitamin D3: 1 × Tablette eingetragen'), findsOneWidget);
      expect(find.text('Heute genommen'), findsOneWidget);
      expect(find.byKey(Key('intake-${rows.single.id}')), findsOneWidget);
      expect(find.text('12:00 · 1 × Tablette'), findsOneWidget, reason: 'Wiener Zeit (UTC+2)');

      await tester.tap(find.text('Rückgängig'));
      await tester.pumpAndSettle();
      expect((await intakes()).single.deletedAt, isNotNull);
      expect(find.text('Heute genommen'), findsNothing);
    });

    pageTest('"Mehrere Einheiten": Anzahl abfragen, ungueltige Eingabe schliesst den Dialog nicht', (tester) async {
      final s = await d3();
      await open(tester);
      await tester.tap(find.byKey(Key('supplement-menu-${s.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('supplement-several-${s.id}')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('supplement-servings-field'))).controller!.text, '2');

      await tester.enterText(find.byKey(const Key('supplement-servings-field')), '0');
      await tester.tap(find.byKey(const Key('supplement-servings-ok')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('supplement-servings-field')), findsOneWidget, reason: '0 ist keine Anzahl');
      expect(await intakes(), isEmpty);

      await tester.enterText(find.byKey(const Key('supplement-servings-field')), '1,5');
      await tester.tap(find.byKey(const Key('supplement-servings-ok')));
      await tester.pumpAndSettle();
      final row = (await intakes()).single;
      expect(row.servings, 1.5);
      expect(parseMicros(row.micros), {'vit_d_ug': 37.5});
      expect(find.text('Vitamin D3: 1,5 × Tablette eingetragen'), findsOneWidget);
    });

    pageTest('Loeschen fragt nach, die Ergaenzung verschwindet, die bisherigen Einnahmen bleiben und heissen weiter wie damals', (tester) async {
      final s = await d3();
      await repo.take(s, at: _now);
      await open(tester);
      await tester.tap(find.byKey(Key('supplement-menu-${s.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('supplement-delete-${s.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Vitamin D3 löschen?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('supplement-delete-ok')));
      await tester.pumpAndSettle();

      expect(find.byKey(Key('supplement-${s.id}')), findsNothing);
      expect(find.byKey(const Key('supplements-empty')), findsOneWidget);
      final row = (await intakes()).single;
      expect(row.deletedAt, isNull);
      expect(find.byKey(Key('intake-${row.id}')), findsOneWidget, reason: 'die Einnahme von heute bleibt sichtbar');
      expect(find.text('12:00 · 1 × Einheit'), findsOneWidget, reason: 'die Einheit der geloeschten Ergaenzung ist nicht mehr bekannt');
    });

    pageTest('"Heute genommen" zeigt nur heute, fruehere Tage nicht', (tester) async {
      final s = await d3();
      await repo.take(s, at: DateTime.utc(2026, 10, 2, 10));
      await repo.take(s, at: DateTime.utc(2026, 10, 3, 7));
      await open(tester);
      expect(find.byType(ListTile), findsNWidgets(2), reason: 'die Karte der Ergaenzung und eine Einnahme von heute');
    });
  });

  group('Formular', () {
    Future<void> open(WidgetTester tester, {Supplement? existing}) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db), supplementRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SupplementFormPage(existing: existing))),
                  child: const Text('OEFFNEN'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('OEFFNEN'));
      await tester.pumpAndSettle();
    }

    Future<void> addNutrient(WidgetTester tester, String filter, String key) async {
      await tester.tap(find.byKey(const Key('supp-add-nutrient')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('supp-picker-filter')), filter);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('supp-pick-$key')));
      await tester.pumpAndSettle();
    }

    pageTest('Name, Einheit und ein Wert genuegen: speichern legt die Ergaenzung an und schliesst das Formular', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const Key('supp-name')), 'Vitamin D3');
      await addNutrient(tester, 'Vitamin D', 'vit_d_ug');
      await tester.enterText(find.byKey(const Key('supp-amount-vit_d_ug')), '12,5');
      await tester.tap(find.byKey(const Key('supp-save')));
      await tester.pumpAndSettle();

      final s = (await db.select(db.supplements).get()).single;
      expect(s.name, 'Vitamin D3');
      expect(s.servingLabel, 'Tablette', reason: 'Vorbelegung');
      expect(parseMicros(s.micros), {'vit_d_ug': 12.5});
      expect(find.text('OEFFNEN'), findsOneWidget, reason: 'zurueck auf die vorige Seite');
    });

    pageTest('ein Tipp auf einen Vorschlag setzt die Einheit', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('supp-unit-chip-1')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('supp-unit'))).controller!.text, supplementUnits[1]);
    });

    pageTest('der Auswahldialog filtert und blendet bereits gewaehlte Werte aus', (tester) async {
      await open(tester);
      await addNutrient(tester, 'Eisen', 'iron_mg');
      await tester.tap(find.byKey(const Key('supp-add-nutrient')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('supp-picker-filter')), 'Eisen');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('supp-pick-iron_mg')), findsNothing);
      expect(find.text('Nichts gefunden.'), findsOneWidget);
    });

    pageTest('fehlender Name, fehlende Einheit oder fehlender Wert: Hinweis statt Speichern', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('supp-save')));
      await tester.pumpAndSettle();
      expect(find.text('Gib einen Namen ein.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('supp-name')), 'X');
      await tester.enterText(find.byKey(const Key('supp-unit')), ' ');
      await tester.tap(find.byKey(const Key('supp-save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Gib an, was eine Einheit ist'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('supp-unit')), 'Tablette');
      await addNutrient(tester, 'Zink', 'zinc_mg');
      await tester.enterText(find.byKey(const Key('supp-amount-zinc_mg')), '0');
      await tester.tap(find.byKey(const Key('supp-save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('mindestens einen Wert'), findsOneWidget);
      expect(await db.select(db.supplements).get(), isEmpty);
    });

    pageTest('Bearbeiten: Felder sind vorbelegt, die id bleibt, ein Wert laesst sich entfernen', (tester) async {
      final s = await repo.save(name: 'Multi', servingLabel: 'Kapsel', micros: const {'vit_c_mg': 80.0, 'iron_mg': 14.0});
      await open(tester, existing: s);
      expect(tester.widget<TextField>(find.byKey(const Key('supp-name'))).controller!.text, 'Multi');
      expect(tester.widget<TextField>(find.byKey(const Key('supp-unit'))).controller!.text, 'Kapsel');
      expect(tester.widget<TextField>(find.byKey(const Key('supp-amount-vit_c_mg'))).controller!.text, '80');

      await tester.tap(find.byKey(const Key('supp-remove-iron_mg')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('supp-amount-vit_c_mg')), '100');
      await tester.tap(find.byKey(const Key('supp-save')));
      await tester.pumpAndSettle();

      final rows = await db.select(db.supplements).get();
      expect(rows, hasLength(1));
      expect(rows.single.id, s.id);
      expect(parseMicros(rows.single.micros), {'vit_c_mg': 100.0});
    });
  });

  group('Seite Naehrstoffe', () {
    var intakeRows = <SupplementIntake>[];

    SupplementIntake intake(String id, DateTime at, Map<String, double> micros, {String name = 'Vitamin D3'}) => SupplementIntake(
          id: id, householdId: 'h1', supplementId: null, name: name, takenAt: at, servings: 1, micros: encodeMicros(micros)!, updatedAt: DateTime.utc(2026),
        );

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          householdPrefsRepositoryProvider.overrideWithValue(HouseholdPrefsRepository(db, householdId: () async => 'h1')),
          mealsStreamProvider.overrideWith((ref) => Stream.value(const <Meal>[])),
          mealIngredientsStreamProvider.overrideWith((ref) => Stream.value(const <MealIngredient>[])),
          supplementIntakesStreamProvider.overrideWith((ref) => Stream.value(intakeRows)),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(routes: [
            GoRoute(path: '/', builder: (_, _) => NutrientsPage(now: _now)),
            GoRoute(path: '/supplements', builder: (_, _) => const Scaffold(body: Text('ERGAENZUNGEN'))),
          ]),
        ),
      ));
      await tester.pumpAndSettle();
    }

    String text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

    pageTest('ein Tag nur mit Einnahme zeigt die Werte, getrennt benannt, und kein "nichts erfasst"', (tester) async {
      intakeRows = [intake('i1', _now, {'vit_d_ug': 25.0})];
      await open(tester);
      expect(find.byKey(const Key('nutrients-none')), findsNothing);
      expect(text(tester, 'nutrient-value-vit_d_ug'), '25,0 µg');
      expect(text(tester, 'nutrient-supplement-vit_d_ug'), 'davon 25,0 µg aus Nahrungsergänzung');
    });

    pageTest('"Woher kommt das?" nennt die Ergaenzung als Quelle', (tester) async {
      intakeRows = [intake('i1', _now, {'vit_d_ug': 25.0}, name: 'Vitamin D3 Tropfen')];
      await open(tester);
      await tester.tap(find.byKey(const Key('nutrient-row-vit_d_ug')));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const Key('nutrient-contrib-0')), matching: find.text('Vitamin D3 Tropfen')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('nutrient-contrib-0')), matching: find.text('Nahrungsergänzung')), findsOneWidget);
    });

    pageTest('die Woche zaehlt Tage nur mit Einnahme nicht als erfasst', (tester) async {
      intakeRows = [intake('i1', _now, {'vit_d_ug': 25.0})];
      await open(tester);
      await tester.tap(find.text('Woche'));
      await tester.pumpAndSettle();
      expect(text(tester, 'nutrients-none'), 'In dieser Woche ist nichts erfasst.');
    });

    pageTest('der Knopf in der Titelleiste fuehrt zur Nahrungsergaenzung', (tester) async {
      intakeRows = [];
      await open(tester);
      await tester.tap(find.byKey(const Key('nutrients-supplements')));
      await tester.pumpAndSettle();
      expect(find.text('ERGAENZUNGEN'), findsOneWidget);
    });
  });
}
