import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../core/clock.dart';
import '../../domain/recipes/meal_plan.dart';
import '../../domain/recipes/saved_recipe.dart';

/// Eigenes Rezept anlegen oder ein gespeichertes bearbeiten (ADR-044): Titel, Zutaten ohne Mengen wie bei allen Rezepten (ADR-021) und eine
/// eigene Zubereitung als freier Text. Die stammt vom Nutzer, nicht von der KI, deshalb gilt die Sperre aus ADR-021 dafuer nicht.
class RecipeFormPage extends ConsumerStatefulWidget {
  const RecipeFormPage({super.key, this.existing});

  final SavedRecipe? existing;

  @override
  ConsumerState<RecipeFormPage> createState() => _RecipeFormPageState();
}

class _RecipeFormPageState extends ConsumerState<RecipeFormPage> {
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _ingredients = TextEditingController(text: widget.existing?.ingredients.map((i) => i.name).join('\n'));
  late final _notes = TextEditingController(text: widget.existing?.notes);
  String? _titleError;

  @override
  void dispose() {
    _title.dispose();
    _ingredients.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'Ein Rezept braucht einen Namen');
      return;
    }
    final existing = widget.existing;
    // Unveraenderte Zutaten behalten ihre Produkt-Zuordnung, wie beim Wochenplan
    final known = {for (final i in existing?.ingredients ?? const <SavedIngredient>[]) i.name.toLowerCase(): i};
    await ref.read(savedRecipeRepositoryProvider).save(SavedRecipe(
          id: existing?.id ?? const Uuid().v4(),
          title: title,
          sourceUrl: existing?.sourceUrl ?? '',
          ingredients: [for (final i in parseIngredientText(_ingredients.text)) known[i.name.toLowerCase()] ?? i],
          notes: _notes.text.trim(),
          savedAt: existing?.savedAt ?? appClock.now().toUtc(),
        ));
    if (mounted) context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Eigenes Rezept' : 'Rezept bearbeiten'),
        actions: [TextButton(key: const Key('recipe-form-save'), onPressed: _save, child: const Text('Speichern'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const Key('recipe-form-title'),
            controller: _title,
            maxLength: 200,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: 'Name', errorText: _titleError),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('recipe-form-ingredients'),
            controller: _ingredients,
            minLines: 4,
            maxLines: null,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Zutaten', helperText: 'Eine je Zeile oder mit Komma getrennt, ohne Mengen', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('recipe-form-notes'),
            controller: _notes,
            minLines: 6,
            maxLines: null,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Zubereitung und Notizen (optional)', alignLabelWithHint: true, border: OutlineInputBorder()),
          ),
        ],
      ),
    );
  }
}
