import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/clock.dart';
import '../../core/vienna_time.dart';
import '../../data/local/database.dart';
import '../../domain/recipes/meal_plan.dart';
import '../../domain/recipes/saved_recipe.dart';

/// Setzt, was von [ingredients] fehlt, auf die Einkaufsliste und meldet das Ergebnis. [active] und [products] kommen aus dem `build()` der
/// Seite (ref.watch), siehe Kommentar in `recipe_suggestions_page.dart`: per `ref.read` waeren sie beim ersten Tippen noch leer.
Future<void> addMissingToList(
  BuildContext context,
  WidgetRef ref,
  Iterable<SavedIngredient> ingredients, {
  required List<InventoryItem> active,
  required List<Product> products,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final missing = findMissingForPlan(
    ingredients,
    inStock: {for (final i in active) if (i.quantity > 0) i.productId},
    products: [for (final p in products) (id: p.id, name: p.name, baseUnit: p.baseUnit)],
  );
  final added = await ref.read(shoppingListRepositoryProvider).addMany(missing);
  final text = missing.isEmpty
      ? 'Schon alles im Haus.'
      : added == 0
          ? 'Steht schon alles auf der Einkaufsliste.'
          : added == 1
              ? 'Eine Zutat auf die Einkaufsliste gesetzt.'
              : '$added Zutaten auf die Einkaufsliste gesetzt.';
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Fragt nach dem Tag und plant das Gericht dort ein.
Future<void> addRecipeToPlan(BuildContext context, WidgetRef ref, {required String title, required Iterable<SavedIngredient> ingredients, String? sourceUrl}) async {
  final messenger = ScaffoldMessenger.of(context);
  final today = utcToViennaLocal(appClock.now().toUtc());
  final day = await showDatePicker(
    context: context,
    helpText: 'Für welchen Tag?',
    initialDate: today,
    firstDate: today.subtract(const Duration(days: 7)),
    lastDate: today.add(const Duration(days: 365)),
  );
  if (day == null) return;
  await ref.read(mealPlanRepositoryProvider).add(day: day, title: title, ingredients: ingredients, sourceUrl: sourceUrl);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('„$title“ steht im Wochenplan.')));
}
