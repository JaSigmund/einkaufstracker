import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../local/database.dart';
import '../sync/mappers.dart';

/// Gedaechtnis des Haushalts (Phase N1, ADR-031): "diesen Namen habe ich diesem BLS-Eintrag zugeordnet". Beim naechsten Foto
/// und in der Handsuche sucht der Server zuerst hier. Offline-first ueber die Outbox wie die uebrigen Repositories.
///
/// Der Server macht aus dem Namen den Schluessel (`food_key`: klein, Singular, ohne Fuellwoerter, Woerter sortiert). Lokal
/// steht der Name, wie der Nutzer ihn sah; der naechste Sync bringt die normalisierte Fassung zurueck. Damit es nie zwei
/// lokale Zeilen fuer denselben Namen gibt, vergleicht [learn] ohne Gross- und Kleinschreibung.
class FoodLinkRepository {
  FoodLinkRepository(this._db, {required this.householdId, this.onChanged, Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Future<String> Function() householdId;
  final void Function()? onChanged;
  final Uuid _uuid;

  /// Alle aktiven Zuordnungen, alphabetisch.
  Stream<List<HouseholdFoodLink>> watchAll() => (_db.select(_db.householdFoodLinks)
        ..where((l) => l.deletedAt.isNull())
        ..orderBy([(l) => OrderingTerm.asc(l.nameNorm)]))
      .watch();

  Future<List<HouseholdFoodLink>> all() => (_db.select(_db.householdFoodLinks)..where((l) => l.deletedAt.isNull())).get();

  /// Merkt sich, dass [name] fuer diesen Haushalt [blsCode] bedeutet. Gibt es den Namen schon, wird der Eintrag ersetzt.
  /// Gleiche Zuordnung noch einmal: nichts passiert (kein unnoetiger Sync). Leerer Name: nichts.
  Future<void> learn(String name, String blsCode) async {
    final label = name.trim();
    if (label.isEmpty || blsCode.isEmpty) return;
    final hid = await householdId();
    final now = DateTime.now().toUtc();
    final existing = (await all()).where((l) => l.nameNorm.toLowerCase() == label.toLowerCase()).firstOrNull;
    if (existing != null && existing.blsCode == blsCode) return;
    // Ein anderer Eintrag heisst: das gemerkte Stueckgewicht galt dem alten Lebensmittel und faellt weg
    final row = existing != null
        ? existing.copyWith(blsCode: blsCode, unitWeightG: const Value(null), updatedAt: now)
        : HouseholdFoodLink(id: _uuid.v4(), householdId: hid, nameNorm: label, blsCode: blsCode, unitWeightG: null, updatedAt: now, deletedAt: null);
    await _db.transaction(() async {
      await _db.into(_db.householdFoodLinks).insertOnConflictUpdate(row.toCompanion(false));
      await _enqueue(row);
    });
    onChanged?.call();
  }

  /// Das eigene Gewicht von 1 Stueck (g, essbarer Anteil), das der Haushalt fuer dieses Lebensmittel angegeben hat, `null` ohne.
  /// Gesucht wird ueber den BLS-Code: egal, unter welchem Namen es angegeben wurde ("Banane", "Bananen"), das juengste gilt.
  Future<double?> unitWeightForCode(String blsCode) async {
    final rows = await (_db.select(_db.householdFoodLinks)
          ..where((l) => l.deletedAt.isNull() & l.blsCode.equals(blsCode) & l.unitWeightG.isNotNull())
          ..orderBy([(l) => OrderingTerm.desc(l.updatedAt)])
          ..limit(1))
        .get();
    return rows.isEmpty ? null : rows.first.unitWeightG;
  }

  /// Merkt sich, dass 1 Stueck von [name] ([blsCode]) [grams] g wiegt (Phase N2, ADR-033). Gibt es die Zuordnung Name -> Eintrag
  /// noch nicht, wird sie dabei angelegt. Dasselbe Gewicht noch einmal: nichts passiert. Ein Gewicht ohne Sinn (null, ueber 5 kg):
  /// nichts.
  Future<void> setUnitWeight(String name, String blsCode, double grams) async {
    final label = name.trim();
    if (label.isEmpty || blsCode.isEmpty || !(grams > 0) || grams > 5000) return;
    final hid = await householdId();
    final now = DateTime.now().toUtc();
    final existing = (await all()).where((l) => l.nameNorm.toLowerCase() == label.toLowerCase()).firstOrNull;
    if (existing != null && existing.blsCode == blsCode && existing.unitWeightG == grams) return;
    final row = existing != null && existing.blsCode == blsCode
        ? existing.copyWith(unitWeightG: Value(grams), updatedAt: now)
        : existing != null
            ? existing.copyWith(blsCode: blsCode, unitWeightG: Value(grams), updatedAt: now)
            : HouseholdFoodLink(id: _uuid.v4(), householdId: hid, nameNorm: label, blsCode: blsCode, unitWeightG: grams, updatedAt: now, deletedAt: null);
    await _db.transaction(() async {
      await _db.into(_db.householdFoodLinks).insertOnConflictUpdate(row.toCompanion(false));
      await _enqueue(row);
    });
    onChanged?.call();
  }

  /// Vergisst eine Zuordnung (Soft-Delete, damit der Sync sie auf andere Geraete bringt).
  Future<void> forget(String id) async {
    final link = await (_db.select(_db.householdFoodLinks)..where((l) => l.id.equals(id))).getSingleOrNull();
    if (link == null || link.deletedAt != null) return;
    final now = DateTime.now().toUtc();
    final row = link.copyWith(deletedAt: Value(now), updatedAt: now);
    await _db.transaction(() async {
      await _db.into(_db.householdFoodLinks).insertOnConflictUpdate(row.toCompanion(false));
      await _enqueue(row);
    });
    onChanged?.call();
  }

  Future<void> _enqueue(HouseholdFoodLink row) => _db.into(_db.outbox).insert(OutboxCompanion.insert(
        remoteTable: 'household_food_links',
        rowId: row.id,
        payload: jsonEncode(householdFoodLinkToRemote(row)),
        createdAt: DateTime.now().toUtc(),
      ));
}
