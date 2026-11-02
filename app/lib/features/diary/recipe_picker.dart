import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/clock.dart';
import '../../core/vienna_time.dart';
import '../../data/local/database.dart';
import '../../domain/recipes/meal_plan.dart';
import '../../domain/recipes/saved_recipe.dart';
import 'meal_labels.dart';

/// Ein Gericht, das ins Tagebuch soll (ADR-047): aus "Meine Rezepte" oder dem Wochenplan. [mealType] setzt der Wochenplan, er kennt die Tageszeit.
class RecipeForMeal {
  const RecipeForMeal({required this.title, required this.ingredients, this.mealType});
  final String title;
  final List<SavedIngredient> ingredients;
  final String? mealType;

  factory RecipeForMeal.fromPlan(MealPlanEntry e) => RecipeForMeal(title: e.title, ingredients: decodePlanIngredients(e.ingredients), mealType: e.slot);
  factory RecipeForMeal.fromSaved(SavedRecipe r) => RecipeForMeal(title: r.title, ingredients: r.ingredients);
}

Future<RecipeForMeal?> showRecipePicker(BuildContext context) => showModalBottomSheet<RecipeForMeal>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _RecipePickerSheet(),
    );

class _RecipePickerSheet extends ConsumerStatefulWidget {
  const _RecipePickerSheet();

  @override
  ConsumerState<_RecipePickerSheet> createState() => _RecipePickerSheetState();
}

class _RecipePickerSheetState extends ConsumerState<_RecipePickerSheet> {
  List<SavedRecipe>? _saved;
  var _query = '';

  @override
  void initState() {
    super.initState();
    ref.read(savedRecipeRepositoryProvider).loadAll().then((all) {
      if (mounted) setState(() => _saved = all);
    });
  }

  bool _matches(String title) => title.toLowerCase().contains(_query);

  /// Gestern bis morgen: Was geplant war, isst man nicht immer genau an dem Tag.
  List<MealPlanEntry> _nearPlan(List<MealPlanEntry> entries) {
    final l = utcToViennaLocal(appClock.now().toUtc());
    final today = DateTime.utc(l.year, l.month, l.day);
    return [
      for (final e in entries)
        if (e.plannedOn.difference(today).inDays.abs() <= 1 && _matches(e.title)) e,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final plan = _nearPlan(ref.watch(mealPlanStreamProvider).value ?? const <MealPlanEntry>[]);
    final saved = [for (final r in _saved ?? const <SavedRecipe>[]) if (_matches(r.title)) r];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              key: const Key('recipe-picker-search'),
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Rezept suchen'),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: ListView(children: [
              if (_saved != null && plan.isEmpty && saved.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_query.isEmpty ? 'Noch keine Rezepte gespeichert und nichts im Wochenplan.' : 'Kein Treffer.', key: const Key('recipe-picker-empty')),
                ),
              if (plan.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: Text('Aus dem Wochenplan', style: t.textTheme.titleSmall)),
              for (final e in plan)
                ListTile(
                  key: Key('pick-plan-${e.id}'),
                  leading: Icon(mealTypeIcon(e.slot)),
                  title: Text(e.title),
                  subtitle: Text('${e.plannedOn.day}.${e.plannedOn.month}. · ${mealTypeLabel(e.slot)}'),
                  onTap: () => Navigator.pop(context, RecipeForMeal.fromPlan(e)),
                ),
              if (saved.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: Text('Meine Rezepte', style: t.textTheme.titleSmall)),
              for (final r in saved)
                ListTile(
                  key: Key('pick-recipe-${r.id}'),
                  leading: const Icon(Icons.bookmark_outline),
                  title: Text(r.title),
                  subtitle: Text(r.ingredients.length == 1 ? '1 Zutat' : '${r.ingredients.length} Zutaten'),
                  onTap: () => Navigator.pop(context, RecipeForMeal.fromSaved(r)),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
