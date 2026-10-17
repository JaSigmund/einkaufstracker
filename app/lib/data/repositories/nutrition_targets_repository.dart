import 'dart:convert';

import '../../core/clock.dart';
import '../../domain/nutrition/nutrition_targets.dart';
import '../local/database.dart';
import '../sync/mappers.dart';

/// Richtwerte der Naehrwerte (LH-MEAL-09): eine Zeile je Haushalt, offline-first ueber die Outbox wie die
/// uebrigen Repositories. Ohne gespeicherte Zeile gibt es keine Richtwerte, die App setzt nie selbst welche.
class NutritionTargetsRepository {
  NutritionTargetsRepository(this._db, {required this.householdId, this.onChanged});

  final AppDatabase _db;
  final Future<String> Function() householdId;
  final void Function()? onChanged;

  Stream<NutritionTargets> watch() =>
      _db.select(_db.nutritionTargetRows).watchSingleOrNull().map((row) => _parse(row?.targets));

  Future<NutritionTargets> load() async =>
      _parse((await _db.select(_db.nutritionTargetRows).getSingleOrNull())?.targets);

  /// Ersetzt die Richtwerte des Haushalts. Leere Richtwerte werden als leeres JSON gespeichert (statt die Zeile zu
  /// loeschen), damit der Sync die Aenderung auch auf andere Geraete bringt.
  Future<void> save(NutritionTargets targets) async {
    final hid = await householdId();
    final row = NutritionTargetRow(householdId: hid, targets: jsonEncode(targets.toJson()), updatedAt: appClock.now().toUtc());
    await _db.transaction(() async {
      await _db.into(_db.nutritionTargetRows).insertOnConflictUpdate(row.toCompanion(false));
      await _db.into(_db.outbox).insert(OutboxCompanion.insert(
            remoteTable: 'nutrition_targets',
            rowId: hid,
            payload: jsonEncode(nutritionTargetToRemote(row)),
            createdAt: appClock.now().toUtc(),
          ));
    });
    onChanged?.call();
  }

  NutritionTargets _parse(String? json) {
    if (json == null) return const NutritionTargets();
    try {
      return NutritionTargets.fromJson(jsonDecode(json));
    } on FormatException {
      return const NutritionTargets();
    }
  }
}
