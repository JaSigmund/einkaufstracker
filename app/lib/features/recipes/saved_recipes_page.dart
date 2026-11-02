import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/local/database.dart';
import '../../domain/recipes/recipe_shopping_gap.dart';
import '../../domain/recipes/saved_recipe.dart';
import 'plan_recipe.dart';
import 'recipe_viewer_page.dart';

/// "Meine Rezepte": gespeicherte Rezeptvorschläge (Jakobs Anforderung "Rezepte sollen auch gespeichert
/// werden können"). Von hier aus lässt sich ein Rezept erneut öffnen oder die fehlenden Zutaten auf
/// einen Schlag zur Einkaufsliste hinzufügen (`findMissingIngredients`, Phase 7f "Einkaufsliste aus
/// Rezept").
class SavedRecipesPage extends ConsumerStatefulWidget {
  const SavedRecipesPage({super.key});

  @override
  ConsumerState<SavedRecipesPage> createState() => _SavedRecipesPageState();
}

class _SavedRecipesPageState extends ConsumerState<SavedRecipesPage> {
  List<SavedRecipe>? _recipes;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final all = await ref.read(savedRecipeRepositoryProvider).loadAll();
    if (!mounted) return;
    setState(() => _recipes = all);
  }

  Future<void> _delete(SavedRecipe r) async {
    await ref.read(savedRecipeRepositoryProvider).delete(r.id);
    await _reload();
  }

  void _open(SavedRecipe r) {
    context.push('/recipe-viewer', extra: RecipeViewerArgs(title: r.title, ingredients: [for (final i in r.ingredients) i.name]));
  }

  /// Gleicht die Zutaten gegen das aktuelle Inventar ab und legt alles Fehlende auf der Einkaufsliste
  /// an. Zutaten ohne bekannte `productId` (z.B. frei benannt, nie im Inventar gesehen) lassen sich
  /// nicht automatisch abgleichen und gelten deshalb immer als fehlend (siehe `saved_recipe.dart`).
  /// [active] kommt aus `build()` (ref.watch), nicht aus einem eigenen `ref.read` hier -- siehe
  /// Kommentar in `recipe_suggestions_page.dart` zum selben, dort schon einmal gefundenen Fehler.
  Future<void> _addMissingToShoppingList(SavedRecipe r, List<InventoryItem> active) async {
    final available = [for (final item in active) (productId: item.productId, quantity: item.quantity)];

    final withProduct = [
      for (final i in r.ingredients)
        if (i.productId != null) (productId: i.productId!, productName: i.name),
    ];
    final withoutProduct = r.ingredients.where((i) => i.productId == null).toList();

    final missing = findMissingIngredients(withProduct, available);
    final repo = ref.read(shoppingListRepositoryProvider);
    // Codereview-Fund 2026-10-01: feste Menge 1 statt einer berechneten Luecke -- wie viel das Rezept
    // tatsaechlich braucht, ist nicht bekannt (siehe recipe_shopping_gap.dart), der Nutzer passt die
    // Menge bei Bedarf selbst an (Mengen-Stepper in der Einkaufsliste).
    for (final m in missing) {
      final unit = r.ingredients.firstWhere((i) => i.productId == m.productId).unit;
      await repo.addManual(productId: m.productId, quantity: 1, unit: unit);
    }
    for (final i in withoutProduct) {
      await repo.addManual(freeText: i.name, quantity: 1, unit: i.unit);
    }

    if (!mounted) return;
    final count = missing.length + withoutProduct.length;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(count == 0 ? 'Schon alles im Haus — nichts hinzugefügt.' : '$count fehlende Zutat(en) zur Einkaufsliste hinzugefügt.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final recipes = _recipes;
    // ref.watch, nicht read: haelt den Stream von Beginn an abonniert (siehe Kommentar oben).
    final active = ref.watch(activeInventoryStreamProvider).value ?? const <InventoryItem>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Meine Rezepte')),
      body: recipes == null
          ? const Center(child: CircularProgressIndicator())
          : recipes.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Noch keine Rezepte gespeichert. Speichere einen Vorschlag über das Lesezeichen-Symbol.', textAlign: TextAlign.center),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final r in recipes)
                      Card(
                        key: Key('saved-recipe-${r.id}'),
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          title: Text(r.title),
                          subtitle: Text('${r.ingredients.length} Zutat(en)'),
                          onTap: () => _open(r),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                              key: Key('plan-recipe-${r.id}'),
                              tooltip: 'In den Wochenplan',
                              icon: const Icon(Icons.calendar_month_outlined),
                              onPressed: () => addRecipeToPlan(context, ref, title: r.title, ingredients: r.ingredients, sourceUrl: r.sourceUrl),
                            ),
                            IconButton(
                              key: Key('add-missing-${r.id}'),
                              tooltip: 'Fehlende Zutaten zur Einkaufsliste',
                              icon: const Icon(Icons.add_shopping_cart_outlined),
                              onPressed: () => _addMissingToShoppingList(r, active),
                            ),
                            IconButton(
                              key: Key('delete-recipe-${r.id}'),
                              tooltip: 'Löschen',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(r),
                            ),
                          ]),
                        ),
                      ),
                  ],
                ),
    );
  }
}
