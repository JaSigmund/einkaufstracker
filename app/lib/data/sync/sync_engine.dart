import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/database.dart';
import '../remote/remote_store.dart';
import 'mappers.dart';

/// Beschreibt, wie eine Serverzeile einer Tabelle lokal gespeichert wird.
class SyncTableDef {
  const SyncTableDef(this.remoteName, this.applyRemote, {String Function(Map<String, dynamic> json)? idOf})
      : idOf = idOf ?? _defaultId;
  final String remoteName;
  final Future<void> Function(AppDatabase db, Map<String, dynamic> json) applyRemote;

  /// Stabiler Schluessel einer Serverzeile fuer den Abgleich mit ausstehenden lokalen Aenderungen (Outbox).
  /// Standard ist die Spalte "id"; Tabellen ohne diese Spalte (zusammengesetzter Primaerschluessel) geben eine
  /// eigene Funktion an.
  final String Function(Map<String, dynamic> json) idOf;

  static String _defaultId(Map<String, dynamic> j) => j['id'] as String;
}

final syncTables = <SyncTableDef>[
  SyncTableDef('categories', (db, j) => db.into(db.categories).insertOnConflictUpdate(categoryFromRemote(j))),
  SyncTableDef('category_aliases', (db, j) => db.into(db.categoryAliases).insertOnConflictUpdate(categoryAliasFromRemote(j))),
  SyncTableDef('products', (db, j) => db.into(db.products).insertOnConflictUpdate(productFromRemote(j))),
  SyncTableDef('product_barcodes', (db, j) => db.into(db.productBarcodes).insertOnConflictUpdate(productBarcodeFromRemote(j)),
      idOf: (j) => '${j['household_id']}:${j['ean']}'),
  SyncTableDef('product_aliases', (db, j) => db.into(db.productAliases).insertOnConflictUpdate(productAliasFromRemote(j))),
  SyncTableDef('bug_reports', (db, j) => db.into(db.bugReports).insertOnConflictUpdate(bugReportFromRemote(j))),
  // Reihenfolge wichtig: Fremdschluessel (Bon -> Filiale, Position -> Bon) zeigen auf zuvor gelieferte Zeilen
  SyncTableDef('stores', (db, j) => db.into(db.stores).insertOnConflictUpdate(storeFromRemote(j))),
  SyncTableDef('receipts', (db, j) => db.into(db.receipts).insertOnConflictUpdate(receiptFromRemote(j))),
  SyncTableDef('receipt_items', (db, j) => db.into(db.receiptItems).insertOnConflictUpdate(receiptItemFromRemote(j))),
  SyncTableDef('receipt_files', (db, j) => db.into(db.receiptFiles).insertOnConflictUpdate(receiptFileFromRemote(j))),
  // Fremdschluessel auf receipt_items (Vorschlaege) und products
  SyncTableDef('inventory_items', (db, j) => db.into(db.inventoryItems).insertOnConflictUpdate(inventoryItemFromRemote(j))),
  SyncTableDef('inventory_movements', (db, j) => db.into(db.inventoryMovements).insertOnConflictUpdate(inventoryMovementFromRemote(j))),
];

class SyncResult {
  const SyncResult({this.pushed = 0, this.skipped = 0, this.pulled = 0});
  final int pushed;
  final int skipped;
  final int pulled;
}

/// Offline-first-Sync nach Doku 03 §2.3: erst die Outbox nach oben schicken, dann Aenderungen holen.
/// Konfliktregel: Last-write-wins. Eine Zeile mit noch nicht gesendeter lokaler Aenderung wird beim
/// Holen nicht ueberschrieben, die lokale Aenderung gewinnt beim naechsten Senden.
class SyncEngine {
  SyncEngine(this._db, this._remote);
  final AppDatabase _db;
  final RemoteStore _remote;

  bool _running = false;
  bool get isRunning => _running;

  /// Fuehrt einen kompletten Sync aus. Netzfehler werden weitergereicht (die Outbox bleibt erhalten).
  Future<SyncResult> sync() async {
    if (_running) return const SyncResult();
    _running = true;
    try {
      final push = await _push();
      final pulled = await _pull();
      return SyncResult(pushed: push.$1, skipped: push.$2, pulled: pulled);
    } finally {
      _running = false;
    }
  }

  Future<(int, int)> _push() async {
    var pushed = 0, skipped = 0;
    final entries = await (_db.select(_db.outbox)..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
    for (final e in entries) {
      try {
        await _remote.upsert(e.remoteTable, jsonDecode(e.payload) as Map<String, dynamic>);
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
    return (pushed, skipped);
  }

  Future<int> _pull() async {
    var total = 0;
    for (final def in syncTables) {
      final state = await (_db.select(_db.syncStates)..where((t) => t.remoteTable.equals(def.remoteName))).getSingleOrNull();
      var since = state?.lastPulledAt;
      for (var page = 0; page < 20; page++) {
        final rows = await _remote.fetchChanges(def.remoteName, since: since);
        if (rows.isEmpty) break;

        // Zeilen mit ausstehender lokaler Aenderung nicht ueberschreiben
        final ids = rows.map(def.idOf).toList();
        final pending = (await (_db.select(_db.outbox)
                  ..where((t) => t.remoteTable.equals(def.remoteName) & t.rowId.isIn(ids)))
                .get())
            .map((e) => e.rowId)
            .toSet();

        await _db.transaction(() async {
          for (final r in rows) {
            if (pending.contains(def.idOf(r))) continue;
            await def.applyRemote(_db, r);
            total++;
          }
        });

        since = rows.last['updated_at'] as String;
        await _db.into(_db.syncStates).insertOnConflictUpdate(
              SyncStatesCompanion.insert(remoteTable: def.remoteName, lastPulledAt: Value(since)),
            );
        if (rows.length < 500) break;
      }
    }
    return total;
  }
}
