import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/local/database.dart';
import '../../domain/recipes/saved_recipe.dart';
import 'plan_recipe.dart';
import 'recipe_viewer_page.dart';

/// "Meine Rezepte": gespeicherte Rezeptvorschläge und eigene Rezepte (ADR-044). Von hier aus lässt sich ein Rezept erneut öffnen,
/// bearbeiten oder die fehlenden Zutaten auf einen Schlag zur Einkaufsliste hinzufügen (Phase 7f "Einkaufsliste aus Rezept").
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

  /// Ein eigenes Rezept hat keine Seite im Netz, die Zubereitung steht im Formular.
  void _open(SavedRecipe r) {
    if (r.sourceUrl.isEmpty) {
      _edit(r);
    } else {
      context.push('/recipe-viewer', extra: RecipeViewerArgs(title: r.title, ingredients: [for (final i in r.ingredients) i.name]));
    }
  }

  Future<void> _edit(SavedRecipe? r) async {
    await context.push('/recipe-form', extra: r);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final recipes = _recipes;
    // ref.watch, nicht read: haelt den Stream von Beginn an abonniert (siehe Kommentar oben).
    final active = ref.watch(activeInventoryStreamProvider).value ?? const <InventoryItem>[];
    final products = ref.watch(productsStreamProvider).value ?? const <Product>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Meine Rezepte')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-own-recipe'),
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add),
        label: const Text('Eigenes Rezept'),
      ),
      body: recipes == null
          ? const Center(child: CircularProgressIndicator())
          : recipes.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Noch keine Rezepte gespeichert. Speichere einen Vorschlag über das Lesezeichen-Symbol oder lege ein eigenes Rezept an.', textAlign: TextAlign.center),
                  ),
                )
              : ListView(
                  // Platz fuer den schwebenden Knopf
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                  children: [
                    for (final r in recipes)
                      Card(
                        key: Key('saved-recipe-${r.id}'),
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          ListTile(
                            title: Text(r.title),
                            subtitle: Text([
                              r.ingredients.length == 1 ? '1 Zutat' : '${r.ingredients.length} Zutaten',
                              if (r.sourceUrl.isEmpty) 'eigenes Rezept',
                            ].join(' · ')),
                            onTap: () => _open(r),
                          ),
                          OverflowBar(alignment: MainAxisAlignment.end, children: [
                            IconButton(
                              key: Key('edit-recipe-${r.id}'),
                              tooltip: 'Bearbeiten',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _edit(r),
                            ),
                            IconButton(
                              key: Key('plan-recipe-${r.id}'),
                              tooltip: 'In den Wochenplan',
                              icon: const Icon(Icons.calendar_month_outlined),
                              onPressed: () => addRecipeToPlan(context, ref, title: r.title, ingredients: r.ingredients, sourceUrl: r.sourceUrl.isEmpty ? null : r.sourceUrl),
                            ),
                            IconButton(
                              key: Key('add-missing-${r.id}'),
                              tooltip: 'Fehlende Zutaten zur Einkaufsliste',
                              icon: const Icon(Icons.add_shopping_cart_outlined),
                              onPressed: () => addMissingToList(context, ref, r.ingredients, active: active, products: products),
                            ),
                            IconButton(
                              key: Key('delete-recipe-${r.id}'),
                              tooltip: 'Löschen',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(r),
                            ),
                          ]),
                        ]),
                      ),
                  ],
                ),
    );
  }
}
