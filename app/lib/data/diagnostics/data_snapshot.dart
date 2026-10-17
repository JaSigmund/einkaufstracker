import 'package:drift/drift.dart';

import '../local/database.dart';

/// Wie viele juengste Zeilen je Tabelle in den Ausschnitt kommen (Doku-Wunsch: genug fuer 1:1-Reproduktion,
/// aber begrenzt, damit der Bericht nicht unnoetig gross wird).
const _rowsPerTable = 20;

/// Ausschnitt der lokalen Daten zum Zeitpunkt eines Fehlerberichts: die juengsten, nicht geloeschten Zeilen
/// der fachlich wichtigsten Tabellen. `toJson()` kommt von drift (siehe database.g.dart), Betraege bleiben
/// also z.B. als Cent-Ganzzahlen erhalten, keine eigene Formatierung noetig.
Future<Map<String, dynamic>> buildDataSnapshot(AppDatabase db) async {
  Future<List<Map<String, dynamic>>> recent<T extends Table, D>(
    TableInfo<T, D> table,
    Expression<DateTime> Function(T) updatedAt,
    Expression<bool> Function(T) notDeleted,
    Map<String, dynamic> Function(D) toJson,
  ) async {
    final rows = await (db.select(table)
          ..where(notDeleted)
          ..orderBy([(t) => OrderingTerm.desc(updatedAt(t))])
          ..limit(_rowsPerTable))
        .get();
    return rows.map(toJson).toList();
  }

  return {
    'receipts': await recent(db.receipts, (t) => t.updatedAt, (t) => t.deletedAt.isNull(), (r) => r.toJson()),
    'receipt_items': await recent(db.receiptItems, (t) => t.updatedAt, (t) => t.deletedAt.isNull(), (r) => r.toJson()),
    'products': await recent(db.products, (t) => t.updatedAt, (t) => t.deletedAt.isNull(), (r) => r.toJson()),
    'product_barcodes': (await db.select(db.productBarcodes).get()).map((r) => r.toJson()).toList(),
    'product_aliases': await recent(db.productAliases, (t) => t.updatedAt, (t) => t.deletedAt.isNull(), (r) => r.toJson()),
    'inventory_items': await recent(db.inventoryItems, (t) => t.updatedAt, (t) => t.deletedAt.isNull(), (r) => r.toJson()),
    'inventory_movements': await recent(db.inventoryMovements, (t) => t.updatedAt, (t) => t.deletedAt.isNull(), (r) => r.toJson()),
    'categories': await recent(db.categories, (t) => t.updatedAt, (t) => t.deletedAt.isNull(), (r) => r.toJson()),
    'pending_outbox': (await db.select(db.outbox).get()).map((o) => {
          'remote_table': o.remoteTable,
          'row_id': o.rowId,
          'attempts': o.attempts,
          'last_error': o.lastError,
        }).toList(),
  };
}
