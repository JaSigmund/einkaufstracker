import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/clock.dart';
import '../../domain/recipes/meal_plan.dart';
import '../../domain/recipes/saved_recipe.dart';
import '../local/database.dart';
import '../sync/mappers.dart';

/// Wochenplan des Haushalts (ADR-042). Offline-first ueber die Outbox wie die uebrigen Repositories.
class MealPlanRepository {
  MealPlanRepository(this._db, {required this.householdId, this.onChanged, Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Future<String> Function() householdId;
  final void Function()? onChanged;
  final Uuid _uuid;

  /// Alle nicht geloeschten Eintraege, frueheste zuerst.
  Stream<List<MealPlanEntry>> watchEntries() => (_db.select(_db.mealPlanEntries)
        ..where((e) => e.deletedAt.isNull())
        ..orderBy([(e) => OrderingTerm.asc(e.plannedOn), (e) => OrderingTerm.asc(e.title)]))
      .watch();

  /// Plant ein Gericht fuer den Kalendertag von [day]. Ohne Titel oder mit unbekannter Tageszeit: [ArgumentError].
  Future<MealPlanEntry> add({required DateTime day, required String title, String slot = 'dinner', Iterable<SavedIngredient> ingredients = const [], String? sourceUrl}) async {
    final label = title.trim();
    if (label.isEmpty || label.length > 200) throw ArgumentError('Ein Gericht braucht einen Namen');
    if (!mealPlanSlots.contains(slot)) throw ArgumentError('Unbekannte Tageszeit');
    final row = MealPlanEntry(
      id: _uuid.v4(),
      householdId: await householdId(),
      plannedOn: DateTime.utc(day.year, day.month, day.day),
      slot: slot,
      title: label,
      ingredients: encodePlanIngredients(ingredients),
      sourceUrl: sourceUrl,
      updatedAt: appClock.now().toUtc(),
    );
    await _put(row);
    return row;
  }

  /// Verschiebt ein Gericht auf einen anderen Tag.
  Future<void> move(String id, DateTime day) async {
    final row = await _get(id);
    await _put(row.copyWith(plannedOn: DateTime.utc(day.year, day.month, day.day), updatedAt: appClock.now().toUtc()));
  }

  Future<void> delete(String id) async {
    final row = await _get(id);
    final now = appClock.now().toUtc();
    await _put(row.copyWith(deletedAt: Value(now), updatedAt: now));
  }

  /// Nimmt [delete] zurueck.
  Future<void> restore(String id) async {
    final row = await _get(id);
    await _put(row.copyWith(deletedAt: const Value(null), updatedAt: appClock.now().toUtc()));
  }

  Future<MealPlanEntry> _get(String id) => (_db.select(_db.mealPlanEntries)..where((e) => e.id.equals(id))).getSingle();

  Future<void> _put(MealPlanEntry row) async {
    await _db.transaction(() async {
      await _db.into(_db.mealPlanEntries).insertOnConflictUpdate(row.toCompanion(false));
      await _db.into(_db.outbox).insert(OutboxCompanion.insert(
            remoteTable: 'meal_plan_entries',
            rowId: row.id,
            payload: jsonEncode(mealPlanEntryToRemote(row)),
            createdAt: appClock.now().toUtc(),
          ));
    });
    onChanged?.call();
  }
}
