import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/clock.dart';
import '../../domain/products/product_assignment.dart';
import '../local/database.dart';
import '../sync/mappers.dart';

/// Gemeinsame Einstellungen des Haushalts als Schluessel-Wert-Zeilen (Phase N4, ADR-035), offline-first ueber die Outbox. Heute:
/// die Referenzmengen der Seite Naehrstoffe ([microReferenceOnPref], [microReferenceOverridesPref]).
///
/// Je Schluessel eine Zeile, damit zwei Geraete verschiedene Einstellungen aendern koennen, ohne sich zu ueberschreiben. Werte sind
/// beliebiges JSON (Zahl, Text, Wahrheitswert, Objekt).
const microReferenceOnPref = 'micro_reference_on';
const microReferenceOverridesPref = 'micro_reference_overrides';

/// KV-Schluessel der frueheren, nur lokalen Liste "Ueberspringen" (JSON-Liste der Produkt-IDs), siehe [HouseholdPrefsRepository.adoptLocalNutrientSkips].
const productsNutrientsSkippedKey = 'products_nutrients_skipped';

class HouseholdPrefsRepository {
  HouseholdPrefsRepository(this._db, {required this.householdId, this.onChanged});

  final AppDatabase _db;
  final Future<String> Function() householdId;
  final void Function()? onChanged;

  /// Alle Einstellungen als Schluessel -> JSON-Wert. Unlesbare Zeilen fehlen.
  Stream<Map<String, Object?>> watch() => _db.select(_db.householdPrefs).watch().map(_decode);

  Future<Map<String, Object?>> load() async => _decode(await _db.select(_db.householdPrefs).get());

  /// Setzt einen Wert. Derselbe Wert noch einmal: nichts passiert (kein unnoetiger Sync).
  Future<void> set(String key, Object? value) async {
    if (key.isEmpty || key.length > 64) throw ArgumentError('Ungültiger Schlüssel');
    final hid = await householdId();
    final encoded = jsonEncode(value);
    final existing = await (_db.select(_db.householdPrefs)..where((p) => p.householdId.equals(hid) & p.key.equals(key))).getSingleOrNull();
    if (existing != null && existing.value == encoded) return;
    final row = HouseholdPref(householdId: hid, key: key, value: encoded, updatedAt: appClock.now().toUtc());
    await _db.transaction(() async {
      await _db.into(_db.householdPrefs).insertOnConflictUpdate(row.toCompanion(false));
      await _db.into(_db.outbox).insert(OutboxCompanion.insert(
            remoteTable: 'household_prefs',
            rowId: '$hid:$key',
            payload: jsonEncode(householdPrefToRemote(row)),
            createdAt: appClock.now().toUtc(),
          ));
    });
    onChanged?.call();
  }

  /// "Nicht nötig" (Doku 27): dieses Produkt braucht keine Naehrwerte und zaehlt nicht mehr als offen.
  Future<void> setNutrientsNotNeeded(String productId, bool value) => set(noNutrientsPrefFor(productId), value);

  /// Beim Zusammenfuehren wandert "Nicht nötig" mit. Hat das Ziel ein Profil, schadet die Marke nicht, das Profil gilt.
  Future<void> moveNutrientsNotNeeded(String sourceId, String targetId) async {
    if (!nutrientsNotNeeded(await load(), sourceId)) return;
    await set(noNutrientsPrefFor(targetId), true);
    await set(noNutrientsPrefFor(sourceId), false);
  }

  /// Uebernimmt die fruehere, nur lokale Liste "Ueberspringen" einmalig in die gemeinsame Einstellung. Unlesbar: nichts ist uebersprungen.
  Future<void> adoptLocalNutrientSkips() async {
    final raw = await _db.getKv(productsNutrientsSkippedKey);
    if (raw == null || raw == '[]') return;
    var ids = const <String>[];
    try {
      ids = [for (final x in jsonDecode(raw) as List) x as String];
    } catch (_) {
      // bleibt leer
    }
    for (final id in ids) {
      await setNutrientsNotNeeded(id, true);
    }
    await _db.setKv(productsNutrientsSkippedKey, '[]');
  }

  Map<String, Object?> _decode(List<HouseholdPref> rows) {
    final out = <String, Object?>{};
    for (final r in rows) {
      try {
        out[r.key] = jsonDecode(r.value);
      } on FormatException {
        // eine unlesbare Zeile faellt weg, der Rest bleibt nutzbar
      }
    }
    return out;
  }
}
