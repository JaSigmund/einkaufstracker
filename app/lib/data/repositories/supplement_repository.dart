import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/clock.dart';
import '../../domain/nutrition/micros.dart';
import '../local/database.dart';
import '../sync/mappers.dart';

/// Nahrungsergaenzung des Haushalts (Phase N4, ADR-035): was genommen wird (Name, Einheit, Mikronaehrstoffe je Einheit laut Packung)
/// und jede Einnahme als Snapshot. Offline-first ueber die Outbox wie die uebrigen Repositories.
///
/// Eine Einnahme speichert Name und absolute Mengen selbst. Wird die Ergaenzung spaeter geaendert oder geloescht, bleibt die
/// Vergangenheit unveraendert (wie bei den Zutaten einer Mahlzeit).
class SupplementRepository {
  static const defaultGlassMl = 250.0;

  SupplementRepository(this._db, {required this.householdId, this.onChanged, Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Future<String> Function() householdId;
  final void Function()? onChanged;
  final Uuid _uuid;

  /// Die Kennung des Eintrags "Wasser" (ADR-041). Fest je Haushalt, damit zwei Geraete dieselbe Zeile anlegen statt zwei verschiedene.
  String waterIdFor(String householdId) => _uuid.v5(Namespace.url.value, 'einkaufstracker:water:$householdId');

  /// Wasser ist eine Ergaenzung mit der Einheit "Glas" und dem Naehrstoff `water_g`. So gelten Sync, Rueckgaengig und die Seite
  /// Naehrstoffe auch dafuer, und die Glasgroesse laesst sich wie jeder andere Wert aendern.
  bool isWater(Supplement s) => s.id == waterIdFor(s.householdId);

  /// Traegt ein Glas Wasser ein und legt den Eintrag beim ersten Mal an (auch wieder, falls er geloescht wurde).
  Future<SupplementIntake> takeWater({DateTime? at}) async {
    final id = waterIdFor(await householdId());
    final existing = await get(id);
    final water = existing != null && existing.deletedAt == null
        ? existing
        : await save(id: id, name: 'Wasser', servingLabel: 'Glas', micros: const {'water_g': defaultGlassMl});
    return take(water, at: at);
  }

  /// Nicht geloeschte Ergaenzungen, alphabetisch.
  Stream<List<Supplement>> watchSupplements() => (_db.select(_db.supplements)
        ..where((s) => s.deletedAt.isNull())
        ..orderBy([(s) => OrderingTerm.asc(s.name)]))
      .watch();

  /// Nicht geloeschte Einnahmen, neueste zuerst.
  Stream<List<SupplementIntake>> watchIntakes() => (_db.select(_db.supplementIntakes)
        ..where((i) => i.deletedAt.isNull())
        ..orderBy([(i) => OrderingTerm.desc(i.takenAt)]))
      .watch();

  Future<Supplement?> get(String id) => (_db.select(_db.supplements)..where((s) => s.id.equals(id))).getSingleOrNull();

  /// Legt eine Ergaenzung an oder ersetzt sie ([id] gesetzt). [micros] sind absolute Mengen **je Einheit** (eine Tablette, eine
  /// Kapsel, ein Messloeffel); es zaehlen nur Schluessel des Registers mit endlichen, nicht negativen Werten. Ohne Namen, ohne Einheit
  /// oder ohne einen einzigen Wert wirft die Methode [ArgumentError]: eine Ergaenzung ohne Inhalt waere nutzlos.
  Future<Supplement> save({String? id, required String name, required String servingLabel, required Micros micros, String? note}) async {
    final label = name.trim();
    final unit = servingLabel.trim();
    if (label.isEmpty) throw ArgumentError('Eine Ergänzung braucht einen Namen');
    if (unit.isEmpty) throw ArgumentError('Eine Ergänzung braucht eine Einheit');
    final cleaned = parseMicros(micros);
    if (cleaned == null) throw ArgumentError('Eine Ergänzung braucht mindestens einen Wert');
    final hid = await householdId();
    final now = appClock.now().toUtc();
    final existing = id == null ? null : await get(id);
    final row = Supplement(
      id: existing?.id ?? id ?? _uuid.v4(),
      householdId: existing?.householdId ?? hid,
      name: label,
      servingLabel: unit,
      micros: encodeMicros(cleaned)!,
      note: note == null || note.trim().isEmpty ? null : note.trim(),
      updatedAt: now,
      deletedAt: null,
    );
    await _db.transaction(() async {
      await _db.into(_db.supplements).insertOnConflictUpdate(row.toCompanion(false));
      await _enqueueSupplement(row);
    });
    onChanged?.call();
    return row;
  }

  /// Loescht eine Ergaenzung (Soft-Delete). Bisherige Einnahmen bleiben, sie tragen ihren eigenen Snapshot.
  Future<void> delete(String id) async {
    final existing = await get(id);
    if (existing == null || existing.deletedAt != null) return;
    final now = appClock.now().toUtc();
    final row = existing.copyWith(deletedAt: Value(now), updatedAt: now);
    await _db.transaction(() async {
      await _db.into(_db.supplements).insertOnConflictUpdate(row.toCompanion(false));
      await _enqueueSupplement(row);
    });
    onChanged?.call();
  }

  /// Haelt fest, dass [servings] Einheiten genommen wurden (Standard: 1 Einheit, jetzt). Die Mengen sind die der Ergaenzung zum
  /// Zeitpunkt der Einnahme mal [servings].
  Future<SupplementIntake> take(Supplement supplement, {DateTime? at, double servings = 1}) async {
    if (!(servings > 0) || !servings.isFinite) throw ArgumentError('Die Anzahl muss größer als 0 sein');
    final perServing = parseMicros(supplement.micros);
    if (perServing == null) throw StateError('Die Ergänzung hat keine Werte');
    final now = appClock.now().toUtc();
    final row = SupplementIntake(
      id: _uuid.v4(),
      householdId: supplement.householdId,
      supplementId: supplement.id,
      name: supplement.name,
      takenAt: (at ?? now).toUtc(),
      servings: servings,
      micros: encodeMicros({for (final e in perServing.entries) e.key: e.value * servings})!,
      updatedAt: now,
      deletedAt: null,
    );
    await _db.transaction(() async {
      await _db.into(_db.supplementIntakes).insertOnConflictUpdate(row.toCompanion(false));
      await _enqueueIntake(row);
    });
    onChanged?.call();
    return row;
  }

  /// Nimmt eine Einnahme zurueck (Soft-Delete).
  Future<void> deleteIntake(String id) async {
    final existing = await (_db.select(_db.supplementIntakes)..where((i) => i.id.equals(id))).getSingleOrNull();
    if (existing == null || existing.deletedAt != null) return;
    final now = appClock.now().toUtc();
    final row = existing.copyWith(deletedAt: Value(now), updatedAt: now);
    await _db.transaction(() async {
      await _db.into(_db.supplementIntakes).insertOnConflictUpdate(row.toCompanion(false));
      await _enqueueIntake(row);
    });
    onChanged?.call();
  }

  Future<void> _enqueueSupplement(Supplement row) => _db.into(_db.outbox).insert(OutboxCompanion.insert(
        remoteTable: 'supplements',
        rowId: row.id,
        payload: jsonEncode(supplementToRemote(row)),
        createdAt: appClock.now().toUtc(),
      ));

  Future<void> _enqueueIntake(SupplementIntake row) => _db.into(_db.outbox).insert(OutboxCompanion.insert(
        remoteTable: 'supplement_intakes',
        rowId: row.id,
        payload: jsonEncode(supplementIntakeToRemote(row)),
        createdAt: appClock.now().toUtc(),
      ));
}
