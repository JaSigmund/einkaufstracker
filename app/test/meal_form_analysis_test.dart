import 'dart:typed_data';

import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/cloud/cooking_cloud.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/nutrition/bls_food_search.dart';
import 'package:einkaufstracker/data/repositories/meal_repository.dart';
import 'package:einkaufstracker/domain/app_update/app_update_gate.dart';
import 'package:einkaufstracker/domain/nutrition/meal_analysis.dart';
import 'package:einkaufstracker/domain/nutrition/nutrient_scaling.dart';
import 'package:einkaufstracker/features/diary/meal_form_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;

import 'support/fakes.dart';

/// Foto-KI im Formular (Phase 7c, Doku 15 §6): Vorschlag per Knopfdruck, nichts wird ungeprueft uebernommen,
/// Schaetzungen bleiben erkennbar (FR-17).
Uint8List _png() => Uint8List.fromList(img.encodePng(img.Image(width: 8, height: 8)));

void main() {
  late AppDatabase db;
  late MealRepository meals;
  late FakeMealPhotoService photos;
  late FakeMealAnalysisCloud cloud;
  late Product reis;
  late InventoryItem reisBestand;

  setUp(() async {
    db = memoryDb();
    meals = mealRepo(db);
    photos = FakeMealPhotoService(db, meals);
    cloud = FakeMealAnalysisCloud();
    reis = await productRepo(db).create(
      name: 'Reis',
      baseUnit: 'kg',
      nutrientsPer100: {'kcal': 350, 'protein_g': 7},
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

  Widget host({Meal? existing, bool stock = true, FakeBlsFoodSearch? bls}) => ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          mealRepositoryProvider.overrideWithValue(meals),
          productRepositoryProvider.overrideWithValue(productRepo(db)),
          inventoryRepositoryProvider.overrideWithValue(inventoryRepo(db)),
          productsStreamProvider.overrideWith((ref) => Stream.value([reis])),
          activeInventoryStreamProvider.overrideWith((ref) => Stream.value(stock ? [reisBestand] : const <InventoryItem>[])),
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

  /// Oeffnet das Formular (hoher Bildschirm: die Liste baut ihre Zeilen sonst lazy) und nimmt ein Foto auf.
  Future<void> openWithPhoto(WidgetTester tester, {Meal? existing, bool stock = true, FakeBlsFoodSearch? bls}) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(existing: existing, stock: stock, bls: bls));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('START'))).push('/form');
    await tester.pumpAndSettle();
    if (existing == null) {
      await tester.tap(find.byKey(const Key('meal-photo-camera')));
      await tester.pumpAndSettle();
    }
  }

  /// Tippt "Vorschlagen" und bestaetigt beim ersten Mal den Hinweisdialog.
  Future<void> analyze(WidgetTester tester, {bool confirm = true}) async {
    await tester.tap(find.byKey(const Key('meal-analyze')));
    await tester.pumpAndSettle();
    if (confirm && find.byKey(const Key('meal-analyze-confirm')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('meal-analyze-confirm')));
      await tester.pumpAndSettle();
    }
  }

  MealAnalysis reispfanne({String? productId}) => MealAnalysis(
        dishTitle: 'Reispfanne',
        mealType: 'dinner',
        servingsVisible: 2,
        notes: 'Öl nicht sichtbar',
        ingredients: [
          AnalyzedIngredient(name: 'Reis', inventoryProductId: productId ?? reis.id, estimatedGrams: 150, confidence: 0.8),
          const AnalyzedIngredient(name: 'Paprika', estimatedGrams: 80, confidence: 0.3),
        ],
      );

  testWidgets('ohne Foto gibt es keinen Vorschlag-Knopf', (tester) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('START'))).push('/form');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('meal-analyze')), findsNothing);
  });

  testWidgets('mit Foto: Knopf da, Cloud wird erst beim Tippen gerufen', (tester) async {
    await openWithPhoto(tester);
    expect(find.byKey(const Key('meal-analyze')), findsOneWidget);
    expect(cloud.calls, 0);
  });

  group('Hinweis vor dem ersten Senden', () {
    testWidgets('Abbrechen sendet nichts und fragt beim naechsten Mal wieder', (tester) async {
      await openWithPhoto(tester);
      await tester.tap(find.byKey(const Key('meal-analyze')));
      await tester.pumpAndSettle();
      expect(find.text('Foto in der Cloud auswerten?'), findsOneWidget);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(cloud.calls, 0);

      await tester.tap(find.byKey(const Key('meal-analyze')));
      await tester.pumpAndSettle();
      expect(find.text('Foto in der Cloud auswerten?'), findsOneWidget);
    });

    testWidgets('der Hinweis nennt, was gesendet wird, und sichert keine Loeschung bei Anthropic zu', (tester) async {
      await openWithPhoto(tester);
      await tester.tap(find.byKey(const Key('meal-analyze')));
      await tester.pumpAndSettle();
      final content = tester.widget<AlertDialog>(find.byType(AlertDialog)).content as Text;
      final text = content.data!;
      expect(text, contains('Foto und die Namen deiner Produkte'));
      expect(text, contains('Anthropic'));
      expect(text, contains('Bedingungen'), reason: 'Aufbewahrung bei Anthropic regeln deren Bedingungen');
      expect(text, isNot(contains('nicht gespeichert')), reason: 'eine Zusicherung ueber Anthropic koennen wir nicht geben');
    });

    testWidgets('Bestaetigen sendet, und danach kommt der Hinweis nicht mehr', (tester) async {
      cloud.analysis = reispfanne();
      await openWithPhoto(tester);
      await analyze(tester);
      expect(cloud.calls, 1);

      await tester.tap(find.byKey(const Key('meal-analyze')));
      await tester.pumpAndSettle();
      expect(find.text('Foto in der Cloud auswerten?'), findsNothing);
      expect(cloud.calls, 2);
    });
  });

  testWidgets('Vorschlag: Titel, Mahlzeitentyp und Portionen werden vorbelegt, Zutaten als normale Zeilen', (tester) async {
    cloud.analysis = reispfanne();
    await openWithPhoto(tester);
    await analyze(tester);

    expect(tester.widget<TextField>(find.byKey(const Key('meal-title'))).controller!.text, 'Reispfanne');
    expect(tester.widget<ChoiceChip>(find.byKey(const Key('meal-type-dinner'))).selected, isTrue);
    expect(tester.widget<TextField>(find.byKey(const Key('meal-servings-made'))).controller!.text, '2');
    expect(find.byKey(const Key('ingredient-row-0')), findsOneWidget);
    expect(find.byKey(const Key('ingredient-row-1')), findsOneWidget);
    expect(find.text('Reis'), findsOneWidget);
    expect(find.text('Paprika'), findsOneWidget);
  });

  testWidgets('Produkt-Zutat: Menge, Nährwerte aus dem Produkt, "vom Bestand", als geschaetzt gekennzeichnet', (tester) async {
    cloud.analysis = reispfanne();
    await openWithPhoto(tester);
    await analyze(tester);
    expect(find.text('150 g · 525 kcal · vom Bestand · geschätzt'), findsOneWidget);
  });

  testWidgets('unbekannte Zutat: Freitext ohne Nährwerte, unsicher geschaetzt, mit Knopf zum Nachschlagen', (tester) async {
    cloud.analysis = reispfanne();
    await openWithPhoto(tester);
    await analyze(tester);
    expect(find.text('80 g · Nährwerte unbekannt · unsicher geschätzt'), findsOneWidget);
    expect(find.byKey(const Key('ingredient-lookup-1')), findsOneWidget);
    expect(find.byKey(const Key('ingredient-lookup-0')), findsNothing, reason: 'Reis hat Nährwerte');
  });

  testWidgets('Schaetzung ist erkennbar: "Nur geschaetzt" ist an, der Hinweis nennt verdeckte Zutaten und die Notiz', (tester) async {
    cloud.analysis = reispfanne();
    await openWithPhoto(tester);
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('meal-estimate'))).value, isFalse);
    await analyze(tester);
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('meal-estimate'))).value, isTrue);
    expect(find.byKey(const Key('meal-analysis-info')), findsOneWidget);
    expect(find.textContaining('Öl, Butter, Gewürze'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('meal-analysis-notes'))).data, 'Öl nicht sichtbar');
  });

  group('Angaben des Nutzers gehen mit', () {
    testWidgets('Titel, Notiz, gewaehlter Typ und Portionen landen in der Anfrage', (tester) async {
      cloud.analysis = reispfanne();
      await openWithPhoto(tester);
      await tester.enterText(find.byKey(const Key('meal-title')), 'Pizzabrötchen');
      await tester.enterText(find.byKey(const Key('meal-note')), 'mit Sauerrahm');
      await tester.enterText(find.byKey(const Key('meal-servings-made')), '4');
      await tester.tap(find.byKey(const Key('meal-type-snack')));
      await tester.pumpAndSettle();
      await analyze(tester);

      final c = cloud.lastContext!;
      expect(c.title, 'Pizzabrötchen');
      expect(c.note, 'mit Sauerrahm');
      expect(c.mealType, 'snack');
      expect(c.servingsMade, 4);
      expect(tester.widget<TextField>(find.byKey(const Key('meal-servings-made'))).controller!.text, '4', reason: 'Angabe des Nutzers bleibt');
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('meal-type-snack'))).selected, isTrue, reason: 'gewaehlter Typ bleibt');
    });

    testWidgets('ohne Eingaben geht nichts mit: Vorbelegungen sind keine Angaben', (tester) async {
      cloud.analysis = reispfanne();
      await openWithPhoto(tester);
      await analyze(tester);
      final c = cloud.lastContext!;
      expect(c.toJson(), isEmpty);
    });

    testWidgets('das Foto-Formular sagt, dass die Angaben mitgehen', (tester) async {
      await openWithPhoto(tester);
      expect(find.byKey(const Key('meal-analyze-hint')), findsOneWidget);
    });

    testWidgets('ein zweiter Vorschlag ersetzt den ersten und zaehlt ihn nicht als Angabe des Nutzers', (tester) async {
      cloud.analysis = reispfanne();
      await openWithPhoto(tester);
      await analyze(tester);
      expect(cloud.lastContext!.knownIngredients, isEmpty);

      await analyze(tester);
      expect(cloud.lastContext!.knownIngredients, isEmpty);
      expect(find.byKey(const Key('ingredient-row-1')), findsOneWidget);
      expect(find.byKey(const Key('ingredient-row-2')), findsNothing, reason: 'nichts doppelt');
    });
  });

  testWidgets('vermutete Zutat: als solche erkennbar und ohne Abzug vom Bestand', (tester) async {
    cloud.analysis = MealAnalysis(
      dishTitle: 'Reispfanne',
      ingredients: [AnalyzedIngredient(name: 'Reis', inventoryProductId: reis.id, estimatedGrams: 150, confidence: 0.4, inferred: true)],
    );
    await openWithPhoto(tester);
    await analyze(tester);
    expect(find.text('150 g · 525 kcal · vermutet'), findsOneWidget);
  });

  test('parseMealAnalysis liest die Herkunft der Zutat', () {
    final a = parseMealAnalysis({
      'ingredients': [
        {'name': 'Oel', 'origin': 'inferred'},
        {'name': 'Reis', 'origin': 'visible'},
        {'name': 'Ei'},
      ],
    });
    expect(a.ingredients.map((i) => i.inferred), [true, false, false]);
  });

  testWidgets('ein schon getippter Titel wird nicht ueberschrieben', (tester) async {
    cloud.analysis = reispfanne();
    await openWithPhoto(tester);
    await tester.enterText(find.byKey(const Key('meal-title')), 'Mamas Reis');
    await analyze(tester);
    expect(tester.widget<TextField>(find.byKey(const Key('meal-title'))).controller!.text, 'Mamas Reis');
  });

  testWidgets('Produkt nicht im Bestand: kein Abzug vorgesehen', (tester) async {
    cloud.analysis = reispfanne();
    await openWithPhoto(tester, stock: false);
    await analyze(tester);
    expect(find.text('150 g · 525 kcal · geschätzt'), findsOneWidget);
  });

  testWidgets('erfundene Produkt-ID (nicht im Haushalt): Zutat bleibt Freitext', (tester) async {
    cloud.analysis = reispfanne(productId: 'gibt-es-nicht');
    await openWithPhoto(tester);
    await analyze(tester);
    expect(find.text('150 g · Nährwerte unbekannt · geschätzt'), findsOneWidget);
  });

  testWidgets('der Cloud werden die Produkte des Haushalts mitgegeben, nicht mehr', (tester) async {
    cloud.analysis = reispfanne();
    await openWithPhoto(tester);
    await analyze(tester);
    expect(cloud.lastProducts, [(id: reis.id, name: 'Reis')]);
    expect(cloud.lastPhoto, _png());
  });

  testWidgets('Speichern nach dem Vorschlag: Quelle photo_ai, geschaetzt, Zutaten mit Konfidenz, Bestand abgezogen', (tester) async {
    cloud.analysis = reispfanne();
    await openWithPhoto(tester);
    await analyze(tester);
    // Paprika ohne Naehrwerte bleibt Freitext, Menge ist gesetzt: Speichern geht
    await tester.tap(find.byKey(const Key('meal-save')));
    await tester.pumpAndSettle();

    final meal = (await db.select(db.meals).get()).single;
    expect(meal.source, 'photo_ai');
    expect(meal.isEstimate, isTrue);
    expect(meal.title, 'Reispfanne');
    expect(meal.mealType, 'dinner');
    expect(meal.servingsMade, 2);
    final ingredients = await (db.select(db.mealIngredients)..where((i) => i.mealId.equals(meal.id))).get();
    expect(ingredients, hasLength(2));
    expect(ingredients.every((i) => i.source == 'photo_ai'), isTrue);
    expect(ingredients.map((i) => i.confidence).toList()..sort(), [0.3, 0.8]);
    final reisZeile = ingredients.firstWhere((i) => i.productId == reis.id);
    expect(reisZeile.kcal, closeTo(525, 1e-9));
    final posten = await (db.select(db.inventoryItems)..where((i) => i.id.equals(reisBestand.id))).getSingle();
    expect(posten.quantity, closeTo(0.85, 1e-9), reason: '150 g vom Bestand abgezogen');
  });

  testWidgets('geschaetzte Zutat ohne Menge: Speichern wird abgelehnt und nennt die Zutat', (tester) async {
    cloud.analysis = const MealAnalysis(dishTitle: 'Suppe', ingredients: [AnalyzedIngredient(name: 'Karotte', confidence: 0.5)]);
    await openWithPhoto(tester);
    await analyze(tester);
    expect(find.text('Menge eintragen · Nährwerte unbekannt · geschätzt'), findsOneWidget);

    await tester.tap(find.byKey(const Key('meal-save')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('meal-error'))).data, contains('Bei „Karotte“ fehlt die Menge'));
    expect(await db.select(db.meals).get(), isEmpty);
  });

  testWidgets('Naehrwerte nachschlagen: Picker startet mit dem Namen, ein BLS-Treffer liefert die Werte', (tester) async {
    cloud.analysis = reispfanne();
    final bls = FakeBlsFoodSearch(foods: const [
      BlsFood(code: 'G543100', nameDe: 'Paprika rot, roh', per100: NutrientsPer100(kcal: 36, proteinG: 1.0)),
    ]);
    await openWithPhoto(tester, bls: bls);
    await analyze(tester);

    await tester.tap(find.byKey(const Key('ingredient-lookup-1')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('picker-search'))).controller!.text, 'Paprika');
    expect(bls.queries, contains('Paprika'));

    await tester.tap(find.byKey(const Key('pick-bls-G543100')));
    await tester.pumpAndSettle();
    // Der Name der Zeile bleibt, wie der Nutzer ihn sah; woher die Werte stammen, steht darunter (Phase N1)
    expect(tester.widget<Text>(find.byKey(const Key('ingredient-match-1'))).data, 'Nährwerte: Paprika rot, roh');
    expect(find.text('80 g · 29 kcal · unsicher geschätzt'), findsOneWidget, reason: 'Menge bleibt, Werte kommen aus der Datenbank');
    expect(find.byKey(const Key('ingredient-lookup-1')), findsNothing);
    expect(find.byKey(const Key('ingredient-trust-sure-1')), findsOneWidget, reason: 'vom Nutzer gewaehlt: sicher');
  });

  testWidgets('Bearbeiten einer Mahlzeit mit Foto: Vorschlag nutzt das gespeicherte Foto', (tester) async {
    final m = await meals.create(MealDraft(title: 'Pasta', eatenAt: DateTime.utc(2026, 10, 1, 12)));
    await photos.attach(m, _png());
    final existing = (await meals.get(m.id))!;
    cloud.analysis = reispfanne();
    await openWithPhoto(tester, existing: existing);
    await analyze(tester);
    expect(cloud.calls, 1);
    expect(cloud.lastPhoto, _png());
    expect(tester.widget<TextField>(find.byKey(const Key('meal-title'))).controller!.text, 'Pasta', reason: 'Titel bleibt');
    expect(tester.widget<ChoiceChip>(find.byKey(const Key('meal-type-lunch'))).selected, isTrue, reason: 'Typ einer bestehenden Mahlzeit bleibt');
  });

  testWidgets('Foto nicht abrufbar (anderes Geraet, kein Netz): Meldung statt Absturz, keine Anfrage', (tester) async {
    final m = (await meals.create(MealDraft(title: 'Pasta', eatenAt: DateTime.utc(2026, 10, 1, 12))));
    await meals.setPhotoPath(m.id, 'h1/${m.id}.jpg');
    final existing = (await meals.get(m.id))!;
    await openWithPhoto(tester, existing: existing);
    await tester.tap(find.byKey(const Key('meal-analyze')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('meal-error'))).data, contains('Foto ist gerade nicht verfügbar'));
    expect(cloud.calls, 0);
  });

  testWidgets('kein Essen erkennbar: Hinweis des Modells, keine Zeilen, nichts veraendert', (tester) async {
    cloud.analysis = const MealAnalysis(notes: 'Auf dem Foto ist nur ein leerer Teller.');
    await openWithPhoto(tester);
    await analyze(tester);
    expect(tester.widget<Text>(find.byKey(const Key('meal-error'))).data, 'Auf dem Foto ist nur ein leerer Teller.');
    expect(find.byKey(const Key('ingredient-row-0')), findsNothing);
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('meal-estimate'))).value, isFalse);
  });

  group('Fehler der Cloud', () {
    Future<String> errorTextFor(WidgetTester tester, Object error) async {
      cloud.error = error;
      await openWithPhoto(tester);
      await analyze(tester);
      return tester.widget<Text>(find.byKey(const Key('meal-error'))).data!;
    }

    testWidgets('Einwilligung fehlt', (tester) async {
      expect(await errorTextFor(tester, const CookingCloudNotAllowed()), contains('Cloud-Auswertung ist in den Einstellungen ausgeschaltet'));
    });

    testWidgets('Tageslimit erreicht', (tester) async {
      expect(await errorTextFor(tester, const CookingCloudDailyLimit()), contains('Tageslimit'));
    });

    testWidgets('Update erforderlich (ADR-022)', (tester) async {
      expect(await errorTextFor(tester, const AppUpdateRequiredException()), isNotEmpty);
    });

    testWidgets('nicht erreichbar: Grund wird genannt', (tester) async {
      expect(await errorTextFor(tester, const CookingCloudUnavailable('kein Netz')), 'Die Foto-Analyse ist gerade nicht verfügbar (kein Netz).');
    });

    testWidgets('unerwarteter Fehler: allgemeine Meldung', (tester) async {
      expect(await errorTextFor(tester, StateError('boom')), 'Die Foto-Analyse ist gerade nicht verfügbar.');
    });

    testWidgets('nach einem Fehler laesst sich die Mahlzeit trotzdem speichern und erneut versuchen', (tester) async {
      cloud.error = const CookingCloudUnavailable('kein Netz');
      await openWithPhoto(tester);
      await analyze(tester);
      expect(find.byKey(const Key('meal-error')), findsOneWidget);

      cloud.error = null;
      cloud.analysis = reispfanne();
      await tester.tap(find.byKey(const Key('meal-analyze')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('meal-error')), findsNothing);
      expect(find.byKey(const Key('ingredient-row-0')), findsOneWidget);
    });
  });
}
