import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/domain/nutrition/nutrition_targets.dart';
import 'package:einkaufstracker/features/diary/targets_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';

/// Richtwerte festlegen (LH-MEAL-09): optionale Felder, keine Vorgaben der App, Pruefung vor dem Speichern.
void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  Widget host({NutritionTargets initial = const NutritionTargets()}) => ProviderScope(
        overrides: [
          nutritionTargetsRepositoryProvider.overrideWithValue(nutritionTargetsRepo(db)),
          nutritionTargetsProvider.overrideWith((ref) => Stream.value(initial)),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(routes: [
            GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('START'))),
            GoRoute(path: '/targets', builder: (_, _) => const TargetsPage()),
          ]),
        ),
      );

  Future<void> open(WidgetTester tester, Widget app) async {
    // Hoher Bildschirm: die Liste baut ihre sieben Zeilen sonst lazy und Felder ausserhalb des Sichtbereichs fehlen
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('START'))).push('/targets');
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String key, String text) async {
    await tester.enterText(find.byKey(Key(key)), text);
    await tester.pump();
  }

  String fieldText(WidgetTester tester, String key) => tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

  testWidgets('ohne Richtwerte sind alle Felder leer, es gibt keine Vorgaben', (tester) async {
    await open(tester, host());
    for (final k in NutrientKey.values) {
      expect(fieldText(tester, 'target-min-${k.jsonKey}'), isEmpty);
      expect(fieldText(tester, 'target-max-${k.jsonKey}'), isEmpty);
    }
    expect(find.textContaining('die App schlägt keine vor'), findsOneWidget);
  });

  testWidgets('vorhandene Richtwerte stehen in den Feldern (ganze Zahlen ohne ".0", Komma als Dezimalzeichen)', (tester) async {
    await open(
      tester,
      host(
        initial: const NutritionTargets()
            .withTarget(NutrientKey.kcal, const NutrientTarget(min: 1800, max: 2200))
            .withTarget(NutrientKey.saltG, const NutrientTarget(max: 5.5)),
      ),
    );
    expect(fieldText(tester, 'target-min-kcal'), '1800');
    expect(fieldText(tester, 'target-max-kcal'), '2200');
    expect(fieldText(tester, 'target-max-salt_g'), '5,5');
    expect(fieldText(tester, 'target-min-salt_g'), isEmpty);
  });

  testWidgets('Speichern legt die Richtwerte ab und schliesst die Seite', (tester) async {
    await open(tester, host());
    await type(tester, 'target-min-kcal', '1800');
    await type(tester, 'target-max-kcal', '2200');
    await type(tester, 'target-min-protein_g', '60');
    await type(tester, 'target-max-salt_g', '6,5');
    await tester.tap(find.byKey(const Key('targets-save')));
    await tester.pumpAndSettle();

    expect(find.text('START'), findsOneWidget);
    final saved = await nutritionTargetsRepo(db).load();
    expect(saved[NutrientKey.kcal], const NutrientTarget(min: 1800, max: 2200));
    expect(saved[NutrientKey.proteinG], const NutrientTarget(min: 60));
    expect(saved[NutrientKey.saltG], const NutrientTarget(max: 6.5));
    expect(saved[NutrientKey.fatG], isNull, reason: 'leere Felder ergeben keinen Richtwert');
  });

  testWidgets('Felder leeren entfernt einen vorhandenen Richtwert', (tester) async {
    await open(tester, host(initial: const NutritionTargets().withTarget(NutrientKey.kcal, const NutrientTarget(max: 2000))));
    await type(tester, 'target-max-kcal', '');
    await tester.tap(find.byKey(const Key('targets-save')));
    await tester.pumpAndSettle();
    expect((await nutritionTargetsRepo(db).load()).isEmpty, isTrue);
  });

  testWidgets('Untergrenze ueber der Obergrenze wird abgelehnt, nichts wird gespeichert', (tester) async {
    await open(tester, host());
    await type(tester, 'target-min-kcal', '2500');
    await type(tester, 'target-max-kcal', '2000');
    await tester.tap(find.byKey(const Key('targets-save')));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.byKey(const Key('targets-error'))).data, 'Energie: Die Untergrenze liegt über der Obergrenze.');
    expect(find.text('START'), findsNothing, reason: 'Seite bleibt offen');
    expect(await db.select(db.nutritionTargetRows).get(), isEmpty);
  });

  testWidgets('Text oder negative Zahl wird abgelehnt und benennt den Naehrwert', (tester) async {
    await open(tester, host());
    await type(tester, 'target-min-protein_g', 'viel');
    await tester.tap(find.byKey(const Key('targets-save')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('targets-error'))).data, startsWith('Eiweiß: Bitte eine Zahl'));

    await type(tester, 'target-min-protein_g', '-5');
    await tester.tap(find.byKey(const Key('targets-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('targets-error')), findsOneWidget);
    expect(await db.select(db.nutritionTargetRows).get(), isEmpty);
  });

  testWidgets('nach korrigierter Eingabe verschwindet die Fehlermeldung und gespeichert wird', (tester) async {
    await open(tester, host());
    await type(tester, 'target-min-kcal', '2500');
    await type(tester, 'target-max-kcal', '2000');
    await tester.tap(find.byKey(const Key('targets-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('targets-error')), findsOneWidget);

    await type(tester, 'target-min-kcal', '1800');
    await tester.tap(find.byKey(const Key('targets-save')));
    await tester.pumpAndSettle();
    expect(find.text('START'), findsOneWidget);
    expect((await nutritionTargetsRepo(db).load())[NutrientKey.kcal], const NutrientTarget(min: 1800, max: 2000));
  });
}
