import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/meal_plan_repository.dart';
import 'package:einkaufstracker/domain/recipes/saved_recipe.dart';
import 'package:einkaufstracker/features/recipes/meal_plan_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Wochenplan (ADR-042). Heute ist Montag, der 2. November 2026.
final _now = DateTime.utc(2026, 11, 2, 10);

void pageTest(String name, Future<void> Function(WidgetTester tester) body) => testWidgets(name, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

void main() {
  late AppDatabase db;
  late MealPlanRepository repo;

  setUp(() {
    db = memoryDb();
    repo = MealPlanRepository(db, householdId: () async => 'h1');
  });
  tearDown(() => db.close());

  Product product(String id, String name, String unit) =>
      Product(id: id, householdId: 'h1', name: name, baseUnit: unit, restock: false, defaultDateKind: 'best_before', defaultLocation: 'pantry', updatedAt: DateTime.utc(2026));

  Future<void> open(WidgetTester tester, {List<Product> products = const [], List<InventoryItem> active = const []}) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        mealPlanRepositoryProvider.overrideWithValue(repo),
        shoppingListRepositoryProvider.overrideWithValue(shoppingListRepo(db)),
        productsStreamProvider.overrideWith((ref) => Stream.value(products)),
        activeInventoryStreamProvider.overrideWith((ref) => Stream.value(active)),
      ],
      child: MaterialApp(home: MealPlanPage(now: _now)),
    ));
    await tester.pumpAndSettle();
  }

  group('Repository', () {
    test('Plant fuer den Kalendertag und legt eine Outbox-Zeile an, auch beim Verschieben und Loeschen', () async {
      final e = await repo.add(day: DateTime(2026, 11, 4, 18), title: ' Curry ', ingredients: const [SavedIngredient(productId: null, name: 'Reis', unit: 'piece')]);
      expect(e.plannedOn, DateTime.utc(2026, 11, 4));
      expect(e.title, 'Curry');
      await repo.move(e.id, DateTime(2026, 11, 5));
      await repo.delete(e.id);
      expect(await repo.watchEntries().first, isEmpty);
      await repo.restore(e.id);
      final rows = await repo.watchEntries().first;
      expect(rows.single.plannedOn, DateTime.utc(2026, 11, 5));
      final outbox = await db.select(db.outbox).get();
      expect(outbox.where((o) => o.remoteTable == 'meal_plan_entries'), hasLength(4));
    });

    test('Ohne Namen oder mit unbekannter Tageszeit: abgelehnt', () async {
      expect(() => repo.add(day: DateTime(2026, 11, 4), title: '  '), throwsArgumentError);
      expect(() => repo.add(day: DateTime(2026, 11, 4), title: 'Tee', slot: 'drink'), throwsArgumentError);
    });
  });

  group('Seite', () {
    pageTest('Zeigt die laufende Woche und blaettert', (tester) async {
      await open(tester);
      expect(find.text('2.11. – 8.11.2026'), findsOneWidget);
      expect(find.text('Montag, 2.11.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('meal-plan-next')));
      await tester.pumpAndSettle();
      expect(find.text('9.11. – 15.11.2026'), findsOneWidget);
    });

    pageTest('Gericht planen: Name fehlt, dann gespeichert mit Zutaten und Tageszeit', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('meal-plan-add-2026-11-03')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('meal-plan-save')));
      await tester.pumpAndSettle();
      expect(find.text('Bitte einen Namen eingeben'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('meal-plan-title')), 'Linsencurry');
      await tester.enterText(find.byKey(const Key('meal-plan-ingredients')), 'Linsen, Kokosmilch');
      await tester.tap(find.byKey(const Key('meal-plan-save')));
      await tester.pumpAndSettle();

      final row = await db.select(db.mealPlanEntries).getSingle();
      expect(row.title, 'Linsencurry');
      expect(row.plannedOn, DateTime.utc(2026, 11, 3));
      expect(row.slot, 'dinner');
      expect(row.ingredients, contains('Kokosmilch'));
    });

    pageTest('Fehlendes: je Gericht angezeigt, die Woche auf einen Schlag auf die Liste, ohne Doppelte', (tester) async {
      const rice = SavedIngredient(productId: 'p1', name: 'Reis', unit: 'kg');
      const cream = SavedIngredient(productId: null, name: 'Sahne', unit: 'piece');
      final a = await repo.add(day: DateTime(2026, 11, 2), title: 'Curry', ingredients: const [rice, cream]);
      await repo.add(day: DateTime(2026, 11, 3), title: 'Sosse', ingredients: const [cream]);
      final b = await repo.add(day: DateTime(2026, 11, 4), title: 'Reisgericht', ingredients: const [rice]);
      await repo.add(day: DateTime(2026, 11, 20), title: 'Andere Woche', ingredients: const [SavedIngredient(productId: null, name: 'Kaviar', unit: 'piece')]);
      final stock = InventoryItem(
        id: 'i1', householdId: 'h1', productId: 'p1', quantity: 1, unit: 'kg', location: 'pantry', dateKind: 'best_before', status: 'sealed', isSuggestion: false, updatedAt: DateTime.utc(2026));

      await open(tester, products: [product('p1', 'Reis', 'kg')], active: [stock]);

      expect(tester.widget<Text>(find.byKey(Key('meal-plan-status-${a.id}'))).data, 'Abendessen · Fehlt: Sahne');
      expect(tester.widget<Text>(find.byKey(Key('meal-plan-status-${b.id}'))).data, 'Abendessen · Alles im Haus');
      expect(find.text('1 fehlende Zutat auf die Liste'), findsOneWidget);

      await tester.tap(find.byKey(const Key('meal-plan-week-missing')));
      await tester.pumpAndSettle();
      final items = await db.select(db.shoppingListItems).get();
      expect(items.single.freeText, 'Sahne', reason: 'Reis ist im Haus, Kaviar gehoert in eine andere Woche');
      expect(find.text('Eine Zutat auf die Einkaufsliste gesetzt.'), findsOneWidget);
    });

    pageTest('Entfernen laesst sich zuruecknehmen, die Meldung verschwindet von selbst', (tester) async {
      final e = await repo.add(day: DateTime(2026, 11, 2), title: 'Curry');
      await open(tester);
      await tester.tap(find.byKey(Key('meal-plan-menu-${e.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('meal-plan-delete-${e.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('meal-plan-entry-${e.id}')), findsNothing);
      expect(tester.widget<SnackBar>(find.byType(SnackBar)).persist, isFalse);
      await tester.tap(find.text('Rückgängig'));
      await tester.pumpAndSettle();
      expect((await db.select(db.mealPlanEntries).getSingle()).deletedAt, isNull);
    });
  });
}
