import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/clock.dart';
import '../../core/vienna_time.dart';
import '../../data/local/database.dart';
import '../../domain/recipes/meal_plan.dart';
import '../../domain/recipes/saved_recipe.dart';
import '../diary/meal_form_page.dart';
import '../diary/meal_labels.dart';
import '../diary/recipe_picker.dart';
import 'plan_recipe.dart';
import 'recipe_viewer_page.dart';

const _weekdays = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];

String _dayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Wochenplan (ADR-042): Gerichte je Tag vorplanen und auf einen Schlag einkaufen, was dafuer fehlt. Der Plan gilt fuer den ganzen Haushalt.
class MealPlanPage extends ConsumerStatefulWidget {
  const MealPlanPage({super.key, this.now});

  /// Aktueller Zeitpunkt (UTC), austauschbar fuer Tests.
  final DateTime? now;

  @override
  ConsumerState<MealPlanPage> createState() => _MealPlanPageState();
}

class _MealPlanPageState extends ConsumerState<MealPlanPage> {
  late final DateTime _today = () {
    final l = utcToViennaLocal(widget.now ?? appClock.now().toUtc());
    return DateTime.utc(l.year, l.month, l.day);
  }();
  late DateTime _week = weekStartOf(_today);

  Future<void> _add(DateTime day) async {
    final draft = await showDialog<_Draft>(context: context, builder: (_) => _EntryDialog(day: day));
    if (draft == null) return;
    await ref.read(mealPlanRepositoryProvider).add(day: day, title: draft.title, slot: draft.slot, ingredients: draft.ingredients, sourceUrl: draft.sourceUrl);
  }

  Future<void> _move(MealPlanEntry e) async {
    final day = await showDatePicker(
      context: context,
      helpText: 'Auf welchen Tag verschieben?',
      initialDate: e.plannedOn,
      firstDate: _today.subtract(const Duration(days: 365)),
      lastDate: _today.add(const Duration(days: 365)),
    );
    if (day != null) await ref.read(mealPlanRepositoryProvider).move(e.id, day);
  }

  Future<void> _delete(MealPlanEntry e) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(mealPlanRepositoryProvider);
    await repo.delete(e.id);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('„${e.title}“ entfernt'),
        // mit Aktion bliebe die SnackBar sonst stehen, bis man sie wegwischt
        persist: false,
        action: SnackBarAction(label: 'Rückgängig', onPressed: () => repo.restore(e.id)),
      ));
  }

  void _open(MealPlanEntry e) {
    context.push('/recipe-viewer', extra: RecipeViewerArgs(title: e.title, ingredients: [for (final i in decodePlanIngredients(e.ingredients)) i.name]));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    // ref.watch, nicht read: haelt die Streams abonniert, damit ihr Wert schon beim ersten Tippen bereitsteht
    final entries = ref.watch(mealPlanStreamProvider).value ?? const <MealPlanEntry>[];
    final active = ref.watch(activeInventoryStreamProvider).value ?? const <InventoryItem>[];
    final products = ref.watch(productsStreamProvider).value ?? const <Product>[];

    final days = [for (var i = 0; i < 7; i++) _week.add(Duration(days: i))];
    final byDay = <String, List<MealPlanEntry>>{};
    for (final e in entries) {
      (byDay[_dayKey(e.plannedOn)] ??= []).add(e);
    }
    final weekEntries = [for (final d in days) ...?byDay[_dayKey(d)]];
    final weekIngredients = [for (final e in weekEntries) ...decodePlanIngredients(e.ingredients)];

    List<MissingForPlan> missingOf(Iterable<SavedIngredient> ingredients) => findMissingForPlan(
          ingredients,
          inStock: {for (final i in active) if (i.quantity > 0) i.productId},
          products: [for (final p in products) (id: p.id, name: p.name, baseUnit: p.baseUnit)],
        );
    final productNames = {for (final p in products) p.id: p.name};
    final weekMissing = missingOf(weekIngredients);

    return Scaffold(
      appBar: AppBar(title: const Text('Wochenplan')),
      bottomNavigationBar: weekMissing.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: FilledButton.icon(
                  key: const Key('meal-plan-week-missing'),
                  onPressed: () => addMissingToList(context, ref, weekIngredients, active: active, products: products),
                  icon: const Icon(Icons.add_shopping_cart_outlined),
                  label: Text(weekMissing.length == 1 ? '1 fehlende Zutat auf die Liste' : '${weekMissing.length} fehlende Zutaten auf die Liste'),
                ),
              ),
            ),
      body: ListView(padding: const EdgeInsets.only(bottom: 16), children: [
        Row(children: [
          IconButton(
            key: const Key('meal-plan-prev'),
            tooltip: 'Vorige Woche',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => _week = _week.subtract(const Duration(days: 7))),
          ),
          Expanded(
            child: Text(
              '${days.first.day}.${days.first.month}. – ${days.last.day}.${days.last.month}.${days.last.year}',
              key: const Key('meal-plan-range'),
              textAlign: TextAlign.center,
              style: t.textTheme.titleSmall,
            ),
          ),
          IconButton(
            key: const Key('meal-plan-next'),
            tooltip: 'Nächste Woche',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(() => _week = _week.add(const Duration(days: 7))),
          ),
        ]),
        for (final day in days) ...[
          ListTile(
            dense: true,
            title: Text(
              '${_weekdays[day.weekday - 1]}, ${day.day}.${day.month}.',
              style: t.textTheme.titleSmall?.copyWith(color: day == _today ? t.colorScheme.primary : null),
            ),
            trailing: IconButton(
              key: Key('meal-plan-add-${_dayKey(day)}'),
              tooltip: 'Gericht planen',
              icon: const Icon(Icons.add),
              onPressed: () => _add(day),
            ),
          ),
          for (final e in byDay[_dayKey(day)] ?? const <MealPlanEntry>[])
            () {
              final ingredients = decodePlanIngredients(e.ingredients);
              final missing = missingOf(ingredients);
              final names = [for (final m in missing) m.freeText ?? productNames[m.productId] ?? ''];
              return Card(
                key: Key('meal-plan-entry-${e.id}'),
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: ListTile(
                  leading: Icon(mealTypeIcon(e.slot)),
                  title: Text(e.title),
                  subtitle: Text(
                    [
                      mealTypeLabel(e.slot),
                      if (names.isNotEmpty) 'Fehlt: ${names.join(', ')}' else if (ingredients.isNotEmpty) 'Alles im Haus',
                    ].join(' · '),
                    key: Key('meal-plan-status-${e.id}'),
                  ),
                  onTap: () => _open(e),
                  trailing: PopupMenuButton<String>(
                    key: Key('meal-plan-menu-${e.id}'),
                    onSelected: (v) async {
                      switch (v) {
                        case 'diary':
                          await context.push('/meal-form', extra: MealFormArgs(recipe: RecipeForMeal.fromPlan(e)));
                        case 'missing':
                          await addMissingToList(context, ref, ingredients, active: active, products: products);
                        case 'move':
                          await _move(e);
                        case 'delete':
                          await _delete(e);
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(key: Key('meal-plan-diary-${e.id}'), value: 'diary', child: const Text('Ins Tagebuch eintragen')),
                      if (missing.isNotEmpty) PopupMenuItem(key: Key('meal-plan-missing-${e.id}'), value: 'missing', child: const Text('Fehlendes auf die Liste')),
                      PopupMenuItem(key: Key('meal-plan-move-${e.id}'), value: 'move', child: const Text('Verschieben')),
                      PopupMenuItem(key: Key('meal-plan-delete-${e.id}'), value: 'delete', child: const Text('Entfernen')),
                    ],
                  ),
                ),
              );
            }(),
        ],
      ]),
    );
  }
}

typedef _Draft = ({String title, String slot, List<SavedIngredient> ingredients, String? sourceUrl});

/// Ein Gericht planen: frei eingeben oder aus "Meine Rezepte" uebernehmen.
class _EntryDialog extends ConsumerStatefulWidget {
  const _EntryDialog({required this.day});

  final DateTime day;

  @override
  ConsumerState<_EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends ConsumerState<_EntryDialog> {
  final _title = TextEditingController();
  final _ingredients = TextEditingController();
  var _slot = 'dinner';
  List<SavedRecipe> _recipes = const [];
  SavedRecipe? _picked;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.read(savedRecipeRepositoryProvider).loadAll().then((all) {
      if (mounted) setState(() => _recipes = all);
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _ingredients.dispose();
    super.dispose();
  }

  void _pick(SavedRecipe r) => setState(() {
        _picked = r;
        _title.text = r.title;
        _ingredients.text = r.ingredients.map((i) => i.name).join(', ');
      });

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Bitte einen Namen eingeben');
      return;
    }
    final known = {for (final i in _picked?.ingredients ?? const <SavedIngredient>[]) i.name.toLowerCase(): i};
    Navigator.pop<_Draft>(context, (
      title: title,
      slot: _slot,
      // Zutaten aus einem Rezept behalten ihre Produkt-Zuordnung, solange man sie nicht aendert
      ingredients: [for (final i in parseIngredientText(_ingredients.text)) known[i.name.toLowerCase()] ?? i],
      sourceUrl: _picked?.title == title ? _picked?.sourceUrl : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${_weekdays[widget.day.weekday - 1]}, ${widget.day.day}.${widget.day.month}.'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_recipes.isNotEmpty)
            DropdownButton<SavedRecipe>(
              key: const Key('meal-plan-recipe'),
              isExpanded: true,
              hint: const Text('Aus „Meine Rezepte“'),
              value: _picked,
              items: [for (final r in _recipes) DropdownMenuItem(value: r, child: Text(r.title, overflow: TextOverflow.ellipsis))],
              onChanged: (r) {
                if (r != null) _pick(r);
              },
            ),
          TextField(
            key: const Key('meal-plan-title'),
            controller: _title,
            autofocus: true,
            maxLength: 200,
            decoration: InputDecoration(labelText: 'Gericht', counterText: '', errorText: _error),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('meal-plan-ingredients'),
            controller: _ingredients,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Zutaten (optional)', helperText: 'Mit Komma getrennt, zum Beispiel Reis, Linsen'),
          ),
          const SizedBox(height: 8),
          DropdownButton<String>(
            key: const Key('meal-plan-slot'),
            isExpanded: true,
            value: _slot,
            items: [for (final s in mealPlanSlots) DropdownMenuItem(value: s, child: Text(mealTypeLabel(s)))],
            onChanged: (s) => setState(() => _slot = s ?? _slot),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(key: const Key('meal-plan-save'), onPressed: _submit, child: const Text('Planen')),
      ],
    );
  }
}
