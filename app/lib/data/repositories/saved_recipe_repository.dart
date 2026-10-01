import 'dart:convert';

import '../../domain/recipes/saved_recipe.dart';
import '../local/database.dart';

/// Verwaltet gespeicherte Rezepte lokal (siehe `saved_recipe.dart` zur Begruendung: kein Sync, bis
/// die Server-Tabelle aus `recipes_draft.sql` eingespielt ist).
class SavedRecipeRepository {
  SavedRecipeRepository(this._db);

  final AppDatabase _db;
  static const _kvKey = 'saved_recipes';

  /// Codereview-Fund 2026-10-01: ein einzelner beschaedigter Eintrag (z.B. durch einen kuenftigen
  /// Formatwechsel oder einen abgebrochenen Schreibvorgang) darf nicht alle anderen mit sich reissen --
  /// gleiches Prinzip wie beim defensiven Parsen der Cloud-Antwort (`parseRecipeSuggestions`).
  Future<List<SavedRecipe>> loadAll() async {
    final raw = await _db.getKv(_kvKey);
    if (raw == null) return const [];
    final list = jsonDecode(raw) as List;
    final recipes = <SavedRecipe>[];
    for (final e in list) {
      try {
        recipes.add(SavedRecipe.fromJson(e as Map<String, dynamic>));
      } catch (_) {
        // dieser eine Eintrag ist nicht mehr lesbar, der Rest bleibt verfuegbar
      }
    }
    recipes.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return recipes;
  }

  /// Speichert oder ersetzt (gleiche `id`).
  Future<void> save(SavedRecipe recipe) async {
    final all = await loadAll();
    final updated = [...all.where((r) => r.id != recipe.id), recipe];
    await _writeAll(updated);
  }

  Future<void> delete(String id) async {
    final all = await loadAll();
    await _writeAll(all.where((r) => r.id != id).toList());
  }

  Future<void> _writeAll(List<SavedRecipe> recipes) => _db.setKv(_kvKey, jsonEncode([for (final r in recipes) r.toJson()]));
}
