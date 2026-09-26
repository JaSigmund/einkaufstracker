import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../local/database.dart';
import '../sync/mappers.dart';

class DuplicateCategoryException implements Exception {
  DuplicateCategoryException(this.name);
  final String name;
  @override
  String toString() => 'Die Kategorie "$name" gibt es schon.';
}

/// Kategorien: lesen und schreiben immer lokal, jede Aenderung landet in derselben Transaktion
/// in der Outbox und wird spaeter vom [SyncEngine] hochgeladen (offline-first).
class CategoryRepository {
  CategoryRepository(this._db, {required this.householdId, this.onChanged, Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;

  /// Liefert die Haushalts-ID (wirft, wenn keine bekannt ist).
  final Future<String> Function() householdId;

  /// Wird nach jeder lokalen Aenderung aufgerufen (loest den Sync aus).
  final void Function()? onChanged;
  final Uuid _uuid;

  Stream<List<Category>> watchAll() => (_db.select(_db.categories)
        ..where((c) => c.deletedAt.isNull())
        ..orderBy([(c) => OrderingTerm.asc(c.sortOrder), (c) => OrderingTerm.asc(c.name)]))
      .watch();

  Future<void> add(String name, {bool isStorable = true}) async {
    final n = name.trim();
    if (n.isEmpty) throw ArgumentError('Name darf nicht leer sein');
    final hid = await householdId();
    final existing = await (_db.select(_db.categories)
          ..where((c) => c.householdId.equals(hid) & c.name.equals(n)))
        .getSingleOrNull();
    if (existing != null && existing.deletedAt == null) throw DuplicateCategoryException(n);

    final now = DateTime.now().toUtc();
    if (existing != null) {
      // Geloeschte Kategorie gleichen Namens wieder aktivieren (der Server haelt den Namen reserviert)
      await _write(existing.copyWith(deletedAt: const Value(null), isStorable: isStorable, updatedAt: now));
    } else {
      final maxSort = await (_db.selectOnly(_db.categories)..addColumns([_db.categories.sortOrder.max()]))
          .map((r) => r.read(_db.categories.sortOrder.max()))
          .getSingleOrNull();
      await _write(Category(
        id: _uuid.v4(),
        householdId: hid,
        name: n,
        sortOrder: (maxSort ?? 0) + 10,
        isStorable: isStorable,
        updatedAt: now,
      ));
    }
  }

  Future<void> rename(String id, String newName) async {
    final n = newName.trim();
    if (n.isEmpty) throw ArgumentError('Name darf nicht leer sein');
    final row = await (_db.select(_db.categories)..where((c) => c.id.equals(id))).getSingle();
    if (row.name == n) return;
    final clash = await (_db.select(_db.categories)
          ..where((c) => c.householdId.equals(row.householdId) & c.name.equals(n) & c.id.equals(id).not()))
        .getSingleOrNull();
    if (clash != null) throw DuplicateCategoryException(n);
    await _write(row.copyWith(name: n, updatedAt: DateTime.now().toUtc()));
  }

  Future<void> setStorable(String id, bool value) async {
    final row = await (_db.select(_db.categories)..where((c) => c.id.equals(id))).getSingle();
    await _write(row.copyWith(isStorable: value, updatedAt: DateTime.now().toUtc()));
  }

  Future<void> softDelete(String id) async {
    final row = await (_db.select(_db.categories)..where((c) => c.id.equals(id))).getSingle();
    final now = DateTime.now().toUtc();
    await _write(row.copyWith(deletedAt: Value(now), updatedAt: now));
  }

  Future<void> _write(Category row) async {
    await _db.transaction(() async {
      // toCompanion(false): null bleibt ein ausdruecklicher Wert (sonst wuerde z.B. deleted_at = null beim Update ignoriert)
      await _db.into(_db.categories).insertOnConflictUpdate(row.toCompanion(false));
      await _db.into(_db.outbox).insert(OutboxCompanion.insert(
            remoteTable: 'categories',
            rowId: row.id,
            payload: jsonEncode(categoryToRemote(row)),
            createdAt: DateTime.now().toUtc(),
          ));
    });
    onChanged?.call();
  }
}
