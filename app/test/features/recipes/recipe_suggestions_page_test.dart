import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/cloud/cooking_cloud.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/saved_recipe_repository.dart';
import 'package:einkaufstracker/domain/app_update/app_update_gate.dart';
import 'package:einkaufstracker/domain/recipes/recipe_suggestion.dart';
import 'package:einkaufstracker/features/recipes/recipe_suggestions_page.dart';
import 'package:einkaufstracker/features/recipes/recipe_viewer_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fakes.dart';

InventoryItem _item(String id, String productId, {DateTime? expiresOn, String dateKind = 'best_before', double quantity = 1}) =>
    InventoryItem(
      id: id,
      householdId: 'h1',
      productId: productId,
      quantity: quantity,
      unit: 'piece',
      location: 'pantry',
      dateKind: dateKind,
      status: 'sealed',
      isSuggestion: false,
      expiresOn: expiresOn,
      updatedAt: DateTime.utc(2026),
    );

Product _product(String id, String name) => Product(
      id: id,
      householdId: 'h1',
      name: name,
      baseUnit: 'piece',
      defaultDateKind: 'best_before',
      defaultLocation: 'pantry',
      restock: false,
      updatedAt: DateTime.utc(2026),
    );

/// Die Seite zeigt beim Oeffnen einmalig einen Cloud-Hinweis (Q-23), unabhaengig vom Button. Fuer
/// Tests, die das eigentliche Verhalten pruefen (nicht den Hinweis selbst), wird er hier weggeklickt.
Future<void> _dismissFirstUseNoticeIfShown(WidgetTester tester) async {
  final verstanden = find.text('Verstanden');
  if (verstanden.evaluate().isNotEmpty) {
    await tester.tap(verstanden);
    await tester.pumpAndSettle();
  }
}

void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  Widget app({
    required List<InventoryItem> active,
    required List<Product> products,
    required FakeCookingCloud cloud,
  }) =>
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          activeInventoryStreamProvider.overrideWith((ref) => Stream.value(active)),
          productsStreamProvider.overrideWith((ref) => Stream.value(products)),
          cookingCloudProvider.overrideWithValue(cloud),
          savedRecipeRepositoryProvider.overrideWithValue(SavedRecipeRepository(db)),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(initialLocation: '/', routes: [
            GoRoute(path: '/', builder: (_, _) => const RecipeSuggestionsPage()),
            GoRoute(
              path: '/recipe-viewer',
              builder: (_, state) {
                final a = state.extra as RecipeViewerArgs;
                return Scaffold(body: Text('VIEWER: ${a.title} (${a.ingredients.join(", ")})'));
              },
            ),
            GoRoute(path: '/saved-recipes', builder: (_, _) => const Scaffold(body: Text('SAVED-RECIPES'))),
          ]),
        ),
      );

  testWidgets('Vorschläge erzeugen: Inventar wird gesendet, Ergebnis wird als Liste angezeigt', (tester) async {
    final cloud = FakeCookingCloud(suggestions: const [
      RecipeSuggestion(title: 'Kürbissuppe', reason: 'nutzt den Kürbis', matchingIngredients: ['Kürbis']),
    ]);
    await tester.pumpWidget(app(
      active: [_item('i1', 'p1', expiresOn: DateTime.utc(2026, 10, 2))],
      products: [_product('p1', 'Kürbis')],
      cloud: cloud,
    ));
    await tester.pumpAndSettle();
    await _dismissFirstUseNoticeIfShown(tester);

    await tester.tap(find.byKey(const Key('fetch-suggestions')));
    await tester.pumpAndSettle();

    expect(cloud.suggestCalls, 1);
    expect(cloud.lastIngredients!.single.name, 'Kürbis');
    expect(find.text('Kürbissuppe'), findsOneWidget);
    expect(find.text('nutzt den Kürbis'), findsOneWidget);
  });

  testWidgets('Gericht suchen: geht auch mit leerem Inventar und schickt den Namen mit', (tester) async {
    final cloud = FakeCookingCloud(suggestions: const [
      RecipeSuggestion(title: 'Lasagne Bolognese', reason: 'der Klassiker', matchingIngredients: [], missingIngredients: ['Lasagneblätter', 'Faschiertes']),
    ]);
    await tester.pumpWidget(app(active: const [], products: const [], cloud: cloud));
    await tester.pumpAndSettle();
    await _dismissFirstUseNoticeIfShown(tester);

    await tester.enterText(find.byKey(const Key('recipe-dish-input')), '  Lasagne ');
    await tester.tap(find.byKey(const Key('recipe-dish-search')));
    await tester.pumpAndSettle();

    expect(cloud.lastDish, 'Lasagne');
    expect(cloud.lastAllowMissing, isFalse);
    expect(cloud.lastIngredients, isEmpty);
    expect(find.text('Lasagne Bolognese'), findsOneWidget);
    expect(find.textContaining('Fehlt: Lasagneblätter, Faschiertes'), findsOneWidget);

    // Gefundenes laesst sich speichern, wie jeder andere Vorschlag
    await tester.tap(find.byKey(const Key('save-Lasagne Bolognese')));
    await tester.pumpAndSettle();
    final saved = (await SavedRecipeRepository(db).loadAll()).single;
    expect(saved.title, 'Lasagne Bolognese');
    expect(saved.ingredients.map((i) => i.name), ['Lasagneblätter', 'Faschiertes']);
    expect(saved.sourceUrl, isNotEmpty);
  });

  testWidgets('Gericht suchen: leere Eingabe ruft die Cloud nicht, kein Treffer wird gesagt', (tester) async {
    final cloud = FakeCookingCloud();
    await tester.pumpWidget(app(active: const [], products: const [], cloud: cloud));
    await tester.pumpAndSettle();
    await _dismissFirstUseNoticeIfShown(tester);

    await tester.tap(find.byKey(const Key('recipe-dish-search')));
    await tester.pumpAndSettle();
    expect(cloud.suggestCalls, 0);

    await tester.enterText(find.byKey(const Key('recipe-dish-input')), 'Fahrrad');
    await tester.tap(find.byKey(const Key('recipe-dish-search')));
    await tester.pumpAndSettle();
    expect(cloud.suggestCalls, 1);
    expect(find.textContaining('kein Gericht gefunden'), findsOneWidget);
  });

  testWidgets('Leeres Inventar: Hinweis statt Cloud-Aufruf', (tester) async {
    final cloud = FakeCookingCloud();
    await tester.pumpWidget(app(active: const [], products: const [], cloud: cloud));
    await tester.pumpAndSettle();
    await _dismissFirstUseNoticeIfShown(tester);

    await tester.tap(find.byKey(const Key('fetch-suggestions')));
    await tester.pumpAndSettle();

    expect(cloud.suggestCalls, 0);
    expect(find.byKey(const Key('suggestions-error')), findsOneWidget);
  });

  testWidgets('Update-Sperre (ADR-022): klarer Hinweis auf das Update statt "gerade nicht verfuegbar"', (tester) async {
    final cloud = FakeCookingCloud(error: const AppUpdateRequiredException());
    await tester.pumpWidget(app(
      active: [_item('i1', 'p1')],
      products: [_product('p1', 'Kürbis')],
      cloud: cloud,
    ));
    await tester.pumpAndSettle();
    await _dismissFirstUseNoticeIfShown(tester);

    await tester.tap(find.byKey(const Key('fetch-suggestions')));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.byKey(const Key('suggestions-error'))).data, const AppUpdateRequiredException().toString());
    expect(find.textContaining('gerade nicht verfügbar'), findsNothing);
  });

  testWidgets('Fehler der Cloud: Fehlermeldung statt Absturz', (tester) async {
    final cloud = FakeCookingCloud(error: const CookingCloudNotAllowed());
    await tester.pumpWidget(app(
      active: [_item('i1', 'p1')],
      products: [_product('p1', 'Kürbis')],
      cloud: cloud,
    ));
    await tester.pumpAndSettle();
    await _dismissFirstUseNoticeIfShown(tester);

    await tester.tap(find.byKey(const Key('fetch-suggestions')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('suggestions-error')), findsOneWidget);
  });

  testWidgets('Tippen auf einen Vorschlag oeffnet den Rezept-Viewer mit Titel und Zutaten', (tester) async {
    final cloud = FakeCookingCloud(suggestions: const [
      RecipeSuggestion(title: 'Kürbissuppe', reason: '', matchingIngredients: ['Kürbis', 'Zwiebel']),
    ]);
    await tester.pumpWidget(app(
      active: [_item('i1', 'p1')],
      products: [_product('p1', 'Kürbis')],
      cloud: cloud,
    ));
    await tester.pumpAndSettle();
    await _dismissFirstUseNoticeIfShown(tester);

    await tester.tap(find.byKey(const Key('fetch-suggestions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kürbissuppe'));
    await tester.pumpAndSettle();

    expect(find.text('VIEWER: Kürbissuppe (Kürbis, Zwiebel)'), findsOneWidget);
  });

  testWidgets('Vorschlag speichern: Zutat mit bekanntem Produkt wird mit productId gespeichert (Codereview-Fund 2026-10-01: keine Menge, Lagerbestand ist kein Rezeptbedarf)', (tester) async {
    final cloud = FakeCookingCloud(suggestions: const [
      RecipeSuggestion(title: 'Kürbissuppe', reason: '', matchingIngredients: ['Kürbis', 'Muskat']),
    ]);
    await tester.pumpWidget(app(
      active: [_item('i1', 'p1', quantity: 2)],
      products: [_product('p1', 'Kürbis')],
      cloud: cloud,
    ));
    await tester.pumpAndSettle();
    await _dismissFirstUseNoticeIfShown(tester);
    await tester.tap(find.byKey(const Key('fetch-suggestions')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('save-Kürbissuppe')));
    await tester.pumpAndSettle();

    final saved = await SavedRecipeRepository(db).loadAll();
    expect(saved, hasLength(1));
    expect(saved.single.title, 'Kürbissuppe');
    final kuerbis = saved.single.ingredients.firstWhere((i) => i.name == 'Kürbis');
    expect(kuerbis.productId, 'p1');
    final muskat = saved.single.ingredients.firstWhere((i) => i.name == 'Muskat');
    expect(muskat.productId, isNull); // kam nicht aus dem Inventar-Kontext, keine Produkt-Zuordnung bekannt
    expect(find.textContaining('gespeichert'), findsOneWidget);
  });

  testWidgets('Symbol in der App-Leiste fuehrt zu "Meine Rezepte"', (tester) async {
    await tester.pumpWidget(app(active: const [], products: const [], cloud: FakeCookingCloud()));
    await tester.pumpAndSettle();
    await _dismissFirstUseNoticeIfShown(tester);

    await tester.tap(find.byKey(const Key('open-saved-recipes')));
    await tester.pumpAndSettle();

    expect(find.text('SAVED-RECIPES'), findsOneWidget);
  });

  testWidgets('Hinweis erscheint beim Oeffnen einmalig, nicht beim naechsten Mal', (tester) async {
    final cloud = FakeCookingCloud(suggestions: const []);
    final widget = app(active: [_item('i1', 'p1')], products: [_product('p1', 'Kürbis')], cloud: cloud);

    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
    expect(find.text('Rezeptvorschläge aus der Cloud'), findsOneWidget);

    await tester.tap(find.text('Verstanden'));
    await tester.pumpAndSettle();

    // Seite neu aufgebaut (z.B. erneuter Besuch) -- derselbe Haushalt/dieselbe DB, kein Hinweis mehr.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
    expect(find.text('Rezeptvorschläge aus der Cloud'), findsNothing);
  });
}
