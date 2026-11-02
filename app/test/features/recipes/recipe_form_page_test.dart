import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/saved_recipe_repository.dart';
import 'package:einkaufstracker/domain/recipes/saved_recipe.dart';
import 'package:einkaufstracker/features/recipes/recipe_form_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fakes.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  Widget app({SavedRecipe? existing}) => ProviderScope(
        overrides: [
          savedRecipeRepositoryProvider.overrideWithValue(SavedRecipeRepository(db)),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(initialLocation: '/start', routes: [
            GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('ZURUECK'))),
            GoRoute(
              path: '/start',
              builder: (context, _) => Scaffold(
                body: TextButton(onPressed: () => context.push('/form'), child: const Text('OEFFNEN')),
              ),
            ),
            GoRoute(path: '/form', builder: (_, _) => RecipeFormPage(existing: existing)),
          ]),
        ),
      );

  Future<void> open(WidgetTester tester, {SavedRecipe? existing}) async {
    await tester.pumpWidget(app(existing: existing));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OEFFNEN'));
    await tester.pumpAndSettle();
  }

  testWidgets('ohne Namen wird nichts gespeichert', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('recipe-form-save')));
    await tester.pumpAndSettle();

    expect(find.text('Ein Rezept braucht einen Namen'), findsOneWidget);
    expect(await SavedRecipeRepository(db).loadAll(), isEmpty);
  });

  testWidgets('legt ein eigenes Rezept mit Zutaten und Zubereitung an', (tester) async {
    await open(tester);
    await tester.enterText(find.byKey(const Key('recipe-form-title')), ' Lasagne ');
    await tester.enterText(find.byKey(const Key('recipe-form-ingredients')), 'Lasagneblätter\nFaschiertes, Tomaten\nfaschiertes');
    await tester.enterText(find.byKey(const Key('recipe-form-notes')), 'Eine Stunde bei 180 Grad.');
    await tester.tap(find.byKey(const Key('recipe-form-save')));
    await tester.pumpAndSettle();

    final saved = (await SavedRecipeRepository(db).loadAll()).single;
    expect(saved.title, 'Lasagne');
    expect(saved.ingredients.map((i) => i.name), ['Lasagneblätter', 'Faschiertes', 'Tomaten']);
    expect(saved.notes, 'Eine Stunde bei 180 Grad.');
    expect(saved.sourceUrl, isEmpty);
    expect(find.text('OEFFNEN'), findsOneWidget, reason: 'nach dem Speichern zurueck');
  });

  testWidgets('Bearbeiten behaelt ID, Link und Produkt-Zuordnung unveraenderter Zutaten', (tester) async {
    final existing = SavedRecipe(
      id: 'r1',
      title: 'Kürbissuppe',
      sourceUrl: 'https://example.test',
      ingredients: const [SavedIngredient(productId: 'p1', name: 'Kürbis', unit: 'kg')],
      savedAt: DateTime.utc(2026, 10, 1),
    );
    await SavedRecipeRepository(db).save(existing);
    await open(tester, existing: existing);

    expect(find.text('Rezept bearbeiten'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('recipe-form-ingredients')), 'Kürbis\nSahne');
    await tester.tap(find.byKey(const Key('recipe-form-save')));
    await tester.pumpAndSettle();

    final saved = (await SavedRecipeRepository(db).loadAll()).single;
    expect(saved.id, 'r1');
    expect(saved.sourceUrl, 'https://example.test');
    expect(saved.savedAt, DateTime.utc(2026, 10, 1));
    expect(saved.ingredients.first.productId, 'p1');
    expect(saved.ingredients.first.unit, 'kg');
    expect(saved.ingredients.last.productId, isNull);
  });
}
