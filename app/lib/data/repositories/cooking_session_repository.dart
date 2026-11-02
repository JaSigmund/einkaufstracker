import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/clock.dart';
import '../local/database.dart';
import '../sync/mappers.dart';

/// Abgeschlossene Kochzeiten (ADR-046), die Grundlage fuer spaetere Statistiken. Offline-first ueber die Outbox wie die uebrigen Repositories:
/// anders als die gespeicherten Rezepte ueberleben sie so eine Neuinstallation.
class CookingSessionRepository {
  CookingSessionRepository(this._db, {required this.householdId, this.onChanged, Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Future<String> Function() householdId;
  final void Function()? onChanged;
  final Uuid _uuid;

  /// Alle nicht geloeschten Kochzeiten, neueste zuerst.
  Stream<List<CookingSession>> watchSessions() => (_db.select(_db.cookingSessions)
        ..where((s) => s.deletedAt.isNull())
        ..orderBy([(s) => OrderingTerm.desc(s.startedAt)]))
      .watch();

  Future<CookingSession> add({required String recipeTitle, required DateTime startedAt, required DateTime endedAt, required int activeSeconds}) async {
    final row = CookingSession(
      id: _uuid.v4(),
      householdId: await householdId(),
      recipeTitle: recipeTitle,
      startedAt: startedAt,
      endedAt: endedAt,
      activeSeconds: activeSeconds,
      updatedAt: appClock.now().toUtc(),
    );
    await _put(row);
    return row;
  }

  /// "Rückgängig" direkt nach dem Abschluss.
  Future<void> delete(String id) async {
    final row = await (_db.select(_db.cookingSessions)..where((s) => s.id.equals(id))).getSingle();
    final now = appClock.now().toUtc();
    await _put(row.copyWith(deletedAt: Value(now), updatedAt: now));
  }

  Future<void> _put(CookingSession row) async {
    await _db.transaction(() async {
      await _db.into(_db.cookingSessions).insertOnConflictUpdate(row.toCompanion(false));
      await _db.into(_db.outbox).insert(OutboxCompanion.insert(
            remoteTable: 'cooking_sessions',
            rowId: row.id,
            payload: jsonEncode(cookingSessionToRemote(row)),
            createdAt: appClock.now().toUtc(),
          ));
    });
    onChanged?.call();
  }
}
