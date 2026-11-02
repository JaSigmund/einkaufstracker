import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/database.dart';
import '../remote/remote_store.dart';
import 'mappers.dart';

/// Beschreibt, wie eine Serverzeile einer Tabelle lokal gespeichert wird.
class SyncTableDef {
  const SyncTableDef(this.remoteName, this.applyRemote,
      {String Function(Map<String, dynamic> json)? idOf, this.orderKeys = const ['id']})
      : idOf = idOf ?? _defaultId,
        hasPlainId = idOf == null;
  final String remoteName;
  final Future<void> Function(AppDatabase db, Map<String, dynamic> json) applyRemote;

  /// Stabiler Schluessel einer Serverzeile fuer den Abgleich mit ausstehenden lokalen Aenderungen (Outbox).
  /// Standard ist die Spalte "id"; Tabellen ohne diese Spalte (zusammengesetzter Primaerschluessel) geben eine
  /// eigene Funktion an.
  final String Function(Map<String, dynamic> json) idOf;

  /// Die Tabelle hat eine eigene Spalte "id" als Primaerschluessel (nicht zusammengesetzt). Nur dann kann die
  /// Konflikterkennung die Zeile ueber `id` beim Server nachschlagen.
  final bool hasPlainId;

  /// Spalten des Primaerschluessels: stabile Reihenfolge beim Holen fuer Zeilen mit gleichem `updated_at`.
  final List<String> orderKeys;

  static String _defaultId(Map<String, dynamic> j) => j['id'] as String;
}

final syncTables = <SyncTableDef>[
  SyncTableDef('categories', (db, j) => db.into(db.categories).insertOnConflictUpdate(categoryFromRemote(j))),
  SyncTableDef('category_aliases', (db, j) => db.into(db.categoryAliases).insertOnConflictUpdate(categoryAliasFromRemote(j))),
  SyncTableDef('products', (db, j) => db.into(db.products).insertOnConflictUpdate(productFromRemote(j))),
  SyncTableDef('product_barcodes', (db, j) => db.into(db.productBarcodes).insertOnConflictUpdate(productBarcodeFromRemote(j)),
      idOf: (j) => '${j['household_id']}:${j['ean']}', orderKeys: const ['household_id', 'ean']),
  SyncTableDef('product_aliases', (db, j) => db.into(db.productAliases).insertOnConflictUpdate(productAliasFromRemote(j))),
  // Online-Preise (ADR-019): zeigt auf Produkte, deshalb nach den Produkten
  SyncTableDef('product_online_links', (db, j) => db.into(db.productOnlineLinks).insertOnConflictUpdate(productOnlineLinkFromRemote(j))),
  SyncTableDef('bug_reports', (db, j) => db.into(db.bugReports).insertOnConflictUpdate(bugReportFromRemote(j))),
  // Reihenfolge wichtig: Fremdschluessel (Bon -> Filiale, Position -> Bon) zeigen auf zuvor gelieferte Zeilen
  SyncTableDef('stores', (db, j) => db.into(db.stores).insertOnConflictUpdate(storeFromRemote(j))),
  SyncTableDef('receipts', (db, j) => db.into(db.receipts).insertOnConflictUpdate(receiptFromRemote(j))),
  SyncTableDef('receipt_items', (db, j) => db.into(db.receiptItems).insertOnConflictUpdate(receiptItemFromRemote(j))),
  SyncTableDef('receipt_files', (db, j) => db.into(db.receiptFiles).insertOnConflictUpdate(receiptFileFromRemote(j))),
  // Fremdschluessel auf receipt_items (Vorschlaege) und products
  SyncTableDef('inventory_items', (db, j) => db.into(db.inventoryItems).insertOnConflictUpdate(inventoryItemFromRemote(j))),
  SyncTableDef('inventory_movements', (db, j) => db.into(db.inventoryMovements).insertOnConflictUpdate(inventoryMovementFromRemote(j))),
  // Gedaechtnis des Haushalts (Phase N1): Name -> BLS-Eintrag
  SyncTableDef('household_food_links', (db, j) => db.into(db.householdFoodLinks).insertOnConflictUpdate(householdFoodLinkFromRemote(j))),
  // Essenstagebuch (Phase 7): Zutaten zeigen auf ihre Mahlzeit, deshalb zuerst die Mahlzeiten
  SyncTableDef('meals', (db, j) => db.into(db.meals).insertOnConflictUpdate(mealFromRemote(j))),
  SyncTableDef('meal_ingredients', (db, j) => db.into(db.mealIngredients).insertOnConflictUpdate(mealIngredientFromRemote(j))),
  SyncTableDef('nutrition_targets', (db, j) => db.into(db.nutritionTargetRows).insertOnConflictUpdate(nutritionTargetFromRemote(j)),
      idOf: (j) => j['household_id'] as String, orderKeys: const ['household_id']),
  // Nahrungsergaenzung (Phase N4): Einnahmen zeigen auf ihre Ergaenzung, deshalb zuerst die Ergaenzungen; Einstellungen je Schluessel
  SyncTableDef('supplements', (db, j) => db.into(db.supplements).insertOnConflictUpdate(supplementFromRemote(j))),
  SyncTableDef('supplement_intakes', (db, j) => db.into(db.supplementIntakes).insertOnConflictUpdate(supplementIntakeFromRemote(j))),
  SyncTableDef('household_prefs', (db, j) => db.into(db.householdPrefs).insertOnConflictUpdate(householdPrefFromRemote(j)),
      idOf: (j) => '${j['household_id']}:${j['key']}', orderKeys: const ['household_id', 'key']),
  // Wochenplan (ADR-042)
  SyncTableDef('meal_plan_entries', (db, j) => db.into(db.mealPlanEntries).insertOnConflictUpdate(mealPlanEntryFromRemote(j))),
  // Fremdschluessel: shopping_list_items -> shopping_lists, deshalb zuerst die Liste
  SyncTableDef('shopping_lists', (db, j) => db.into(db.shoppingLists).insertOnConflictUpdate(shoppingListFromRemote(j))),
  SyncTableDef('shopping_list_items', (db, j) => db.into(db.shoppingListItems).insertOnConflictUpdate(shoppingListItemFromRemote(j))),
];

/// Eine Aenderung dieses Geraets hat beim Senden eine neuere Aenderung ueberschrieben, die jemand anderes (ein anderes
/// Geraet oder ein anderes Haushaltsmitglied) seit dem letzten Holen gemacht hat (ADR-018: Last-write-wins, aber sichtbar).
typedef SyncConflict = ({String table, String rowId});

class SyncResult {
  const SyncResult({this.pushed = 0, this.skipped = 0, this.pulled = 0, this.rejected = 0, this.conflicts = const []});
  final int pushed;
  final int skipped;
  final int pulled;

  /// Wartende Aenderungen, die der Server schon mindestens [rejectedAfterAttempts]-mal wegen der Daten abgelehnt hat und
  /// die von selbst nicht mehr durchgehen werden (Codereview-Fund 2026-10-16: vorher nur als "wartend" mitgezaehlt).
  final int rejected;
  final List<SyncConflict> conflicts;
}

/// Ab so vielen Ablehnungen gilt eine wartende Aenderung als abgelehnt (siehe [SyncResult.rejected]).
const rejectedAfterAttempts = 3;

/// Ueberlappung beim Holen: `updated_at` ist der Beginn der schreibenden Transaktion, nicht ihr Ende. Eine Zeile, deren
/// Transaktion vor dem letzten Holen begann, aber erst danach sichtbar wurde, laege sonst hinter dem gemerkten Stand und
/// wuerde nie geholt (Codereview-Fund 2026-10-16). Doppelt geholte Zeilen sind harmlos, das Anwenden ist idempotent.
const pullOverlap = Duration(seconds: 10);

/// Offline-first-Sync nach Doku 03 §2.3: erst die Outbox nach oben schicken, dann Aenderungen holen.
/// Konfliktregel: Last-write-wins. Eine Zeile mit noch nicht gesendeter lokaler Aenderung wird beim
/// Holen nicht ueberschrieben, die lokale Aenderung gewinnt beim naechsten Senden.
class SyncEngine {
  SyncEngine(this._db, this._remote);
  final AppDatabase _db;
  final RemoteStore _remote;

  bool _running = false;
  bool get isRunning => _running;

  /// Server-Zeitstempel der Zeilen, die dieses Geraet in dieser Sitzung selbst geschrieben hat (Schluessel
  /// "tabelle:id"). Ohne sie wuerde ein eigener, noch nicht wieder geholter Schreibvorgang bei der naechsten Aenderung
  /// derselben Zeile als fremde Aenderung gelten.
  final _ownWrites = <String, DateTime>{};

  /// Fuehrt einen kompletten Sync aus. Netzfehler werden weitergereicht (die Outbox bleibt erhalten).
  Future<SyncResult> sync() async {
    if (_running) return const SyncResult();
    _running = true;
    try {
      final push = await _push();
      final pulled = await _pull();
      final rejected = await (_db.select(_db.outbox)..where((t) => t.attempts.isBiggerOrEqualValue(rejectedAfterAttempts))).get();
      return SyncResult(pushed: push.pushed, skipped: push.skipped, pulled: pulled, rejected: rejected.length, conflicts: push.conflicts);
    } finally {
      _running = false;
    }
  }

  /// Findet die Zeilen, die beim Senden eine neuere fremde Aenderung ueberschreiben wuerden (ADR-018).
  ///
  /// **Best effort:** Die Erkennung ist ein Hinweis fuer den Nutzer und darf das Senden nie verhindern. Scheitert die
  /// Abfrage einer Tabelle (Netz, Rechte, unerwartete Antwort), gilt diese Tabelle als "ohne Befund" und es wird normal
  /// gesendet; ein echter Netzfehler faellt dann beim Senden selbst auf, wie vorher.
  ///
  /// Je Tabelle mit wartenden Aenderungen EINE Anfrage nach den Server-Zeitstempeln. Eine Zeile gilt als Konflikt, wenn
  /// ihr `updated_at` beim Server NEUER ist als alles, was dieses Geraet von ihr weiss: der Stand des letzten Holens der
  /// Tabelle und der eigene letzte Schreibvorgang. Zeilen, die es beim Server noch nicht gibt (neu angelegt), und Tabellen,
  /// die noch nie geholt wurden (erster Sync), sind kein Konflikt. Gesendet wird trotzdem, die Aenderung gewinnt.
  Future<List<SyncConflict>> _detectConflicts(List<OutboxEntry> entries) async {
    final idsByTable = <String, Set<String>>{};
    for (final e in entries) {
      final def = syncTables.where((t) => t.remoteName == e.remoteTable).firstOrNull;
      if (def == null || !def.hasPlainId) continue;
      idsByTable.putIfAbsent(e.remoteTable, () => {}).add(e.rowId);
    }
    final conflicts = <SyncConflict>[];
    for (final MapEntry(key: table, value: ids) in idsByTable.entries) {
      final state = await (_db.select(_db.syncStates)..where((t) => t.remoteTable.equals(table))).getSingleOrNull();
      final lastPulled = state?.lastPulledAt == null ? null : DateTime.tryParse(state!.lastPulledAt!);
      if (lastPulled == null) continue;
      final idList = ids.toList();
      final found = <SyncConflict>[];
      try {
        for (var i = 0; i < idList.length; i += 100) {
          final chunk = idList.sublist(i, i + 100 > idList.length ? idList.length : i + 100);
          final serverAt = await _remote.fetchUpdatedAt(table, chunk);
          for (final MapEntry(key: id, value: stamp) in serverAt.entries) {
            final remoteAt = DateTime.tryParse(stamp);
            if (remoteAt == null) continue;
            final own = _ownWrites['$table:$id'];
            final known = own != null && own.isAfter(lastPulled) ? own : lastPulled;
            if (remoteAt.isAfter(known)) found.add((table: table, rowId: id));
          }
        }
      } on Object {
        continue; // siehe oben: kein Befund fuer diese Tabelle, gesendet wird trotzdem
      }
      conflicts.addAll(found);
    }
    return conflicts;
  }

  Future<({int pushed, int skipped, List<SyncConflict> conflicts})> _push() async {
    var pushed = 0, skipped = 0;
    final entries = await (_db.select(_db.outbox)..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
    final conflicts = await _detectConflicts(entries);
    for (final e in entries) {
      try {
        final stamp = await _remote.upsert(e.remoteTable, jsonDecode(e.payload) as Map<String, dynamic>);
        final at = stamp == null ? null : DateTime.tryParse(stamp);
        if (at != null) _ownWrites['${e.remoteTable}:${e.rowId}'] = at;
        await (_db.delete(_db.outbox)..where((t) => t.id.equals(e.id))).go();
        pushed++;
      } on RemoteDataException catch (ex) {
        // Datenfehler: markieren und weitermachen, damit ein Problemeintrag die Queue nicht blockiert
        await (_db.update(_db.outbox)..where((t) => t.id.equals(e.id))).write(
          OutboxCompanion(attempts: Value(e.attempts + 1), lastError: Value(ex.message)),
        );
        skipped++;
      }
      // Netzwerk- oder Auth-Fehler: bewusst nicht gefangen, der Sync bricht ab und versucht es spaeter erneut
    }
    return (pushed: pushed, skipped: skipped, conflicts: conflicts);
  }

  Future<int> _pull() async {
    var total = 0;
    for (final def in syncTables) {
      final state = await (_db.select(_db.syncStates)..where((t) => t.remoteTable.equals(def.remoteName))).getSingleOrNull();
      final stored = state?.lastPulledAt == null ? null : DateTime.tryParse(state!.lastPulledAt!);
      var since = stored == null ? state?.lastPulledAt : stored.toUtc().subtract(pullOverlap).toIso8601String();
      // Zeilen mit genau dem Zeitstempel [since], die schon geholt sind. Codereview-Fund 2026-10-16: ohne diesen Versatz
      // blieb das Holen fuer immer haengen, sobald mehr als eine Seite (500) Zeilen denselben `updated_at` hat (alle
      // Zeilen einer Transaktion bekommen dasselbe now(), z.B. bei einer Daten-Migration): jede Seite lieferte wieder
      // dieselben 500 Zeilen, [since] kam nie weiter, und spaetere Aenderungen der Tabelle wurden nie mehr geholt.
      var skip = 0;
      for (var page = 0; page < 20; page++) {
        final rows = await _remote.fetchChanges(def.remoteName, since: since, offset: skip, orderKeys: def.orderKeys);
        if (rows.isEmpty) break;

        final ids = rows.map(def.idOf).toList();
        // Codereview-Fund 2026-10-01: die Pruefung auf ausstehende lokale Aenderungen muss in DERSELBEN
        // Transaktion wie das Anwenden stehen, sonst koennte zwischen beiden Schritten ein neuer, lokaler
        // Schreibvorgang auf genau dieser Zeile landen (Outbox-Eintrag entsteht nach der Pruefung, aber vor
        // dem Anwenden) -- der aeltere Server-Stand wuerde die frische lokale Aenderung dann kurzzeitig
        // ueberschreiben, bis der naechste Sync sie erneut hochlaedt. In einer Transaktion serialisiert
        // drift/SQLite alle Operationen auf der Verbindung, ein paralleler Schreibzugriff muss warten.
        await _db.transaction(() async {
          // Zeilen mit ausstehender lokaler Aenderung nicht ueberschreiben
          final pending = (await (_db.select(_db.outbox)
                    ..where((t) => t.remoteTable.equals(def.remoteName) & t.rowId.isIn(ids)))
                  .get())
              .map((e) => e.rowId)
              .toSet();
          for (final r in rows) {
            if (pending.contains(def.idOf(r))) continue;
            await def.applyRemote(_db, r);
            total++;
          }
        });

        final last = rows.last['updated_at'] as String;
        final tied = rows.reversed.takeWhile((r) => r['updated_at'] == last).length;
        skip = last == since ? skip + tied : tied;
        since = last;
        await _db.into(_db.syncStates).insertOnConflictUpdate(
              SyncStatesCompanion.insert(remoteTable: def.remoteName, lastPulledAt: Value(since)),
            );
        if (rows.length < 500) break;
      }
    }
    return total;
  }
}
