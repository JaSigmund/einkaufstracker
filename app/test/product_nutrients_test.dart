import 'dart:convert';

import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/nutrition/bls_food_search.dart';
import 'package:einkaufstracker/domain/nutrition/nutrient_scaling.dart';
import 'package:einkaufstracker/features/diary/product_nutrients_card.dart';
import 'package:einkaufstracker/features/diary/product_nutrients_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';

/// Produkte ohne Naehrwerte (Phase N1, ADR-031): die Hinweiskarte im Tagebuch und die Seite "Nährwerte zuordnen".
BlsFood _food(String code, String name, double kcal, {String confidence = 'sure', String method = 'synonym'}) =>
    BlsFood(code: code, nameDe: name, per100: NutrientsPer100(kcal: kcal, proteinG: 1), method: method, confidence: confidence);

/// Wie testWidgets, haengt die Seite am Ende aus: echte Drift-Streams halten sonst einen Timer ("A Timer is still pending").
void pageTest(String name, Future<void> Function(WidgetTester tester) body) => testWidgets(name, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

void main() {
  late AppDatabase db;
  late FakeBlsFoodSearch bls;
  late Product milch;
  late Product quark;
  late Product gewuerz;
  late Product reis;

  setUp(() async {
    db = memoryDb();
    bls = FakeBlsFoodSearch(resolved: {
      'milch': [_food('M111300', 'Vollmilch frisch, 3,5 % Fett', 65)],
      'quark': [_food('M713300', 'Speisequark Halbfettstufe', 100, confidence: 'auto', method: 'search')],
    });
    final products = productRepo(db);
    milch = await products.create(name: 'Milch', baseUnit: 'l');
    quark = await products.create(name: 'Quark', baseUnit: 'kg');
    gewuerz = await products.create(name: 'Gewürzmischung', baseUnit: 'g');
    reis = await products.create(name: 'Reis', baseUnit: 'kg', nutrientsPer100: {'kcal': 350}, nutrientsBasis: 'g', nutrientsSource: 'manual');
  });
  tearDown(() => db.close());

  overrides() => [
        databaseProvider.overrideWithValue(db),
        productRepositoryProvider.overrideWithValue(productRepo(db)),
        foodLinkRepositoryProvider.overrideWithValue(foodLinkRepo(db)),
        blsFoodSearchProvider.overrideWithValue(bls),
      ];

  Future<void> openPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(overrides: overrides(), child: const MaterialApp(home: ProductNutrientsPage())));
    await tester.pumpAndSettle();
  }

  Future<Product> reload(Product p) async => (await productRepo(db).byId(p.id))!;

  group('Seite', () {
    pageTest('listet nur Produkte ohne Naehrwerte, alphabetisch, mit Vorschlag und Sicherheit', (tester) async {
      await openPage(tester);

      expect(find.byKey(Key('nutrients-row-${reis.id}')), findsNothing, reason: 'hat schon Naehrwerte');
      expect(find.byKey(Key('nutrients-row-${milch.id}')), findsOneWidget);
      expect(find.byKey(Key('nutrients-row-${quark.id}')), findsOneWidget);
      expect(find.byKey(Key('nutrients-row-${gewuerz.id}')), findsOneWidget);

      final order = [for (final p in [gewuerz, milch, quark]) tester.getTopLeft(find.byKey(Key('nutrients-row-${p.id}'))).dy];
      expect(order, [...order]..sort(), reason: 'Gewürzmischung, Milch, Quark');

      expect(tester.widget<Text>(find.byKey(Key('nutrients-suggestion-${milch.id}'))).data, 'Vollmilch frisch, 3,5 % Fett · 65 kcal je 100 g');
      expect(find.byKey(Key('nutrients-suggestion-${quark.id}')), findsOneWidget);
      expect(find.byKey(Key('nutrients-none-${gewuerz.id}')), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget, reason: 'Milch: sicher');
      expect(find.byIcon(Icons.change_circle_outlined), findsOneWidget, reason: 'Quark: automatisch');
      expect(find.byKey(Key('nutrients-apply-${gewuerz.id}')), findsNothing, reason: 'ohne Vorschlag nichts zu uebernehmen');
      expect(bls.resolveQueries, containsAll(['Milch', 'Quark', 'Gewürzmischung']));
    });

    pageTest('Uebernehmen: Profil im Produkt, Herkunft bls, Name im Gedaechtnis, Zeile verschwindet', (tester) async {
      await openPage(tester);
      await tester.tap(find.byKey(Key('nutrients-apply-${milch.id}')));
      await tester.pumpAndSettle();

      final p = await reload(milch);
      expect(jsonDecode(p.nutrientsPer100!)['kcal'], 65);
      expect(p.nutrientsSource, 'bls');
      expect(p.blsCode, 'M111300');
      final links = await foodLinkRepo(db).all();
      expect({for (final l in links) l.nameNorm: l.blsCode}, {'Milch': 'M111300'});
      expect(find.byKey(Key('nutrients-row-${milch.id}')), findsNothing);
      expect(find.byKey(Key('nutrients-row-${quark.id}')), findsOneWidget);
    });

    pageTest('"Alle uebernehmen" nimmt sichere und automatische Vorschlaege, Produkte ohne Vorschlag bleiben', (tester) async {
      await openPage(tester);
      expect(find.text('Alle sicheren und automatischen übernehmen (2)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('nutrients-apply-all')));
      await tester.pumpAndSettle();

      expect((await reload(milch)).blsCode, 'M111300');
      expect((await reload(quark)).blsCode, 'M713300');
      expect((await reload(gewuerz)).nutrientsPer100, isNull);
      expect(find.byKey(Key('nutrients-row-${gewuerz.id}')), findsOneWidget);
      expect(find.byKey(const Key('nutrients-apply-all')), findsNothing, reason: 'nichts mehr zu uebernehmen');
      expect(await foodLinkRepo(db).all(), hasLength(2));
    });

    pageTest('unsichere Vorschlaege zaehlen nicht zu "Alle uebernehmen", lassen sich aber einzeln uebernehmen', (tester) async {
      bls.resolved['milch'] = [_food('M111300', 'Vollmilch frisch, 3,5 % Fett', 65, confidence: 'unsure', method: 'search')];
      bls.resolved['quark'] = [];
      await openPage(tester);
      expect(find.byKey(const Key('nutrients-apply-all')), findsNothing);
      expect(find.text('Unsicher: bitte prüfen oder einen anderen Eintrag wählen.'), findsOneWidget);
      expect(find.byIcon(Icons.help_outline), findsOneWidget);

      await tester.tap(find.byKey(Key('nutrients-apply-${milch.id}')));
      await tester.pumpAndSettle();
      expect((await reload(milch)).blsCode, 'M111300');
    });

    pageTest('Ueberspringen: Zeile verschwindet, bleibt weg (auch nach erneutem Oeffnen) und aendert das Produkt nicht', (tester) async {
      await openPage(tester);
      await tester.tap(find.byKey(Key('nutrients-skip-${quark.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('nutrients-row-${quark.id}')), findsNothing);
      expect((await reload(quark)).nutrientsPer100, isNull);
      expect(jsonDecode((await db.getKv(productsNutrientsSkippedKey))!), [quark.id]);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(ProviderScope(overrides: overrides(), child: const MaterialApp(home: ProductNutrientsPage())));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('nutrients-row-${quark.id}')), findsNothing);
      expect(find.byKey(Key('nutrients-row-${milch.id}')), findsOneWidget);
    });

    pageTest('Anderen waehlen: der Picker startet mit dem Namen, der gewaehlte Eintrag wird uebernommen und gelernt', (tester) async {
      bls.foods = const [BlsFood(code: 'M120000', nameDe: 'Quark mager', per100: NutrientsPer100(kcal: 67, proteinG: 12))];
      await openPage(tester);
      await tester.tap(find.byKey(Key('nutrients-change-${quark.id}')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('picker-search'))).controller!.text, 'Quark');

      await tester.tap(find.byKey(const Key('pick-bls-M120000')));
      await tester.pumpAndSettle();

      final p = await reload(quark);
      expect(p.blsCode, 'M120000');
      expect(jsonDecode(p.nutrientsPer100!)['kcal'], 67);
      expect({for (final l in await foodLinkRepo(db).all()) l.nameNorm: l.blsCode}, {'Quark': 'M120000'});
      expect(find.byKey(Key('nutrients-row-${quark.id}')), findsNothing);
    });

    pageTest('Datenbank nicht erreichbar: "Kein passender Eintrag", Handwahl und Ueberspringen bleiben moeglich', (tester) async {
      bls.fail = true;
      await openPage(tester);
      expect(find.byKey(Key('nutrients-none-${milch.id}')), findsOneWidget);
      expect(find.byKey(Key('nutrients-change-${milch.id}')), findsOneWidget);
      expect(find.byKey(Key('nutrients-skip-${milch.id}')), findsOneWidget);
      expect(find.byKey(const Key('nutrients-apply-all')), findsNothing);
    });

    pageTest('alles zugeordnet oder uebersprungen: Hinweis statt Liste', (tester) async {
      await db.setKv(productsNutrientsSkippedKey, jsonEncode([milch.id, quark.id, gewuerz.id]));
      await openPage(tester);
      expect(tester.widget<Text>(find.byKey(const Key('nutrients-empty'))).data, 'Alle Produkte haben Nährwerte oder wurden übersprungen.');
    });

    pageTest('geloeschte Produkte erscheinen nicht', (tester) async {
      await productRepo(db).softDelete(gewuerz.id);
      await openPage(tester);
      expect(find.byKey(Key('nutrients-row-${gewuerz.id}')), findsNothing);
      expect(find.byKey(Key('nutrients-row-${milch.id}')), findsOneWidget);
    });

    pageTest('unlesbare Ablage der uebersprungenen Produkte: nichts ist uebersprungen', (tester) async {
      await db.setKv(productsNutrientsSkippedKey, 'kaputt');
      await openPage(tester);
      expect(find.byKey(Key('nutrients-row-${milch.id}')), findsOneWidget);
    });
  });

  group('Karte im Tagebuch', () {
    final now = DateTime.utc(2026, 10, 3, 10);

    Future<void> openCard(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => Scaffold(body: ProductNutrientsCard(now: now))),
        GoRoute(path: '/products-nutrients', builder: (_, _) => const ProductNutrientsPage()),
      ]);
      await tester.pumpWidget(ProviderScope(overrides: overrides(), child: MaterialApp.router(routerConfig: router)));
      await tester.pumpAndSettle();
    }

    pageTest('nennt die Zahl der Produkte ohne Naehrwerte (Einzahl bei einem)', (tester) async {
      await openCard(tester);
      expect(find.text('3 Produkte ohne Nährwerte'), findsOneWidget);
    });

    pageTest('Einzahl', (tester) async {
      await productRepo(db).softDelete(milch.id);
      await productRepo(db).softDelete(quark.id);
      await openCard(tester);
      expect(find.text('1 Produkt ohne Nährwerte'), findsOneWidget);
    });

    pageTest('keine Karte, wenn alle Produkte Naehrwerte haben oder uebersprungen wurden', (tester) async {
      await db.setKv(productsNutrientsSkippedKey, jsonEncode([milch.id, quark.id, gewuerz.id]));
      await openCard(tester);
      expect(find.byKey(const Key('products-nutrients-card')), findsNothing);
    });

    pageTest('Jetzt zuordnen oeffnet die Seite', (tester) async {
      await openCard(tester);
      await tester.tap(find.byKey(const Key('products-nutrients-open')));
      await tester.pumpAndSettle();
      expect(find.text('Nährwerte zuordnen'), findsOneWidget);
    });

    pageTest('Später blendet die Karte zwei Wochen aus und merkt sich das', (tester) async {
      await openCard(tester);
      await tester.tap(find.byKey(const Key('products-nutrients-later')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('products-nutrients-card')), findsNothing);
      expect(DateTime.parse((await db.getKv(productsNutrientsCardHiddenUntilKey))!), now.add(productsNutrientsCardHideFor));
    });

    pageTest('solange die Frist laeuft bleibt die Karte weg, danach kommt sie wieder', (tester) async {
      await db.setKv(productsNutrientsCardHiddenUntilKey, now.add(const Duration(days: 1)).toIso8601String());
      await openCard(tester);
      expect(find.byKey(const Key('products-nutrients-card')), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await db.setKv(productsNutrientsCardHiddenUntilKey, now.subtract(const Duration(days: 1)).toIso8601String());
      await openCard(tester);
      expect(find.byKey(const Key('products-nutrients-card')), findsOneWidget);
    });
  });
}
