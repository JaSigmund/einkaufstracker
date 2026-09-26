import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/receipt/parsed_receipt.dart';
import '../local/database.dart';
import '../sync/mappers.dart';

enum ReceiptSaveOutcome { saved, duplicate }

class ReceiptSaveResult {
  const ReceiptSaveResult(this.outcome, this.receiptId);
  final ReceiptSaveOutcome outcome;
  final String receiptId;
}

/// Bons speichern und lesen. Schreibt lokal und legt alle Aenderungen in derselben Transaktion in die
/// Outbox (offline-first, siehe Doku 03 §2.3).
///
/// **Deterministische IDs:** Filialen, Bons und Positionen bekommen ihre ID aus ihren Merkmalen
/// (UUID v5 aus Haushalt, Filiale bzw. Re-Nr, Zeilennummer). Importieren zwei Geraete denselben Bon,
/// entsteht dieselbe Zeile und kein Konflikt, und ein wieder importierter, zuvor geloeschter Bon
/// wird reaktiviert statt doppelt angelegt.
class ReceiptRepository {
  ReceiptRepository(this._db, {required this.householdId, this.onChanged, Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Future<String> Function() householdId;
  final void Function()? onChanged;
  final Uuid _uuid;

  String _storeId(String hid, String chain, String? branch) =>
      _uuid.v5(Namespace.url.value, 'einkaufstracker:store:$hid:${chain.toLowerCase()}:${branch ?? '-'}');

  String _receiptId(String hid, String externalId) =>
      _uuid.v5(Namespace.url.value, 'einkaufstracker:receipt:$hid:$externalId');

  String _itemId(String receiptId, int lineNo) => _uuid.v5(Namespace.url.value, 'einkaufstracker:item:$receiptId:$lineNo');

  /// Bereits gespeicherter (nicht geloeschter) Bon mit dieser Re-Nr, sonst null.
  Future<Receipt?> findByExternalId(String externalId) async {
    final hid = await householdId();
    return (_db.select(_db.receipts)
          ..where((x) => x.householdId.equals(hid) & x.externalId.equals(externalId) & x.deletedAt.isNull()))
        .getSingleOrNull();
  }

  /// Nicht geloeschte, bestaetigte Bons, neueste zuerst.
  Stream<List<Receipt>> watchAll() => (_db.select(_db.receipts)
        ..where((r) => r.deletedAt.isNull() & r.status.equals('confirmed'))
        ..orderBy([(r) => OrderingTerm.desc(r.purchasedAt)]))
      .watch();

  Stream<Receipt?> watchReceipt(String id) => (_db.select(_db.receipts)..where((r) => r.id.equals(id))).watchSingleOrNull();

  Stream<List<Store>> watchStores() => (_db.select(_db.stores)..where((s) => s.deletedAt.isNull())).watch();

  Stream<List<ReceiptItem>> watchItems(String receiptId) => (_db.select(_db.receiptItems)
        ..where((i) => i.receiptId.equals(receiptId) & i.deletedAt.isNull())
        ..orderBy([(i) => OrderingTerm.asc(i.lineNo)]))
      .watch();

  /// Speichert einen gelesenen Bon als bestaetigt. Ein Bon mit derselben Re-Nr wird nicht doppelt angelegt.
  ///
  /// Bons, die nicht alle Pruefungen bestehen, werden mit `sumMismatch = true` gespeichert (der Nutzer hat
  /// sie in der Pruefansicht bewusst uebernommen). Ob das erlaubt ist, entscheidet die Oberflaeche.
  Future<ReceiptSaveResult> saveParsed(ParsedReceipt r, {String source = 'pdf_text'}) async {
    if (!r.isParsed || r.purchasedAtUtc == null || r.totalCents == null) {
      throw ArgumentError('Der Bon wurde nicht gelesen und kann nicht gespeichert werden.');
    }
    final hid = await householdId();
    final now = DateTime.now().toUtc();
    final receiptId = r.externalId != null ? _receiptId(hid, r.externalId!) : _uuid.v4();

    if (r.externalId != null) {
      final existing = await (_db.select(_db.receipts)
            ..where((x) => x.householdId.equals(hid) & x.externalId.equals(r.externalId!) & x.deletedAt.isNull()))
          .getSingleOrNull();
      if (existing != null) return ReceiptSaveResult(ReceiptSaveOutcome.duplicate, existing.id);
    }

    await _db.transaction(() async {
      // Filiale finden oder anlegen
      final chain = r.chain ?? 'Unbekannt';
      final storeId = _storeId(hid, chain, r.branchCode);
      final store = await (_db.select(_db.stores)..where((s) => s.id.equals(storeId))).getSingleOrNull();
      if (store == null || store.deletedAt != null) {
        await _put(
          'stores',
          storeId,
          storeToRemote(Store(id: storeId, householdId: hid, chain: chain, branch: r.branchCode, updatedAt: now)),
          () => _db.into(_db.stores).insertOnConflictUpdate(
                Store(id: storeId, householdId: hid, chain: chain, branch: r.branchCode, updatedAt: now).toCompanion(false),
              ),
        );
      }

      final receipt = Receipt(
        id: receiptId,
        householdId: hid,
        storeId: storeId,
        purchasedAt: r.purchasedAtUtc!,
        totalCents: r.totalCents!,
        status: 'confirmed',
        source: source,
        externalId: r.externalId,
        confidence: r.checks!.allOk ? 1.0 : null,
        sumMismatch: !r.checks!.allOk,
        updatedAt: now,
      );
      await _put('receipts', receiptId, receiptToRemote(receipt),
          () => _db.into(_db.receipts).insertOnConflictUpdate(receipt.toCompanion(false)));

      var lineNo = 0;
      Future<void> putItem(ReceiptItem item) => _put('receipt_items', item.id, receiptItemToRemote(item),
          () => _db.into(_db.receiptItems).insertOnConflictUpdate(item.toCompanion(false)));

      for (final i in r.items) {
        lineNo++;
        await putItem(ReceiptItem(
          id: _itemId(receiptId, lineNo),
          householdId: hid,
          receiptId: receiptId,
          lineNo: lineNo,
          kind: i.kind.name,
          rawText: i.rawText,
          quantity: i.quantity,
          quantityUnit: i.quantityUnit,
          unitPriceCents: i.unitPriceCents,
          lineTotalCents: i.lineTotalCents,
          taxCode: i.taxCode,
          needsReview: false,
          updatedAt: now,
        ));
      }
      // Rabatte auf Bon-Ebene (z.B. jö Rabattsammler) als eigene Positionen ohne Steuerbuchstaben,
      // damit die Summe aller Positionen der Bon-Summe entspricht
      for (final d in r.bonDiscounts) {
        lineNo++;
        await putItem(ReceiptItem(
          id: _itemId(receiptId, lineNo),
          householdId: hid,
          receiptId: receiptId,
          lineNo: lineNo,
          kind: ReceiptItemKind.discount.name,
          rawText: d.percent == null ? d.name : '${d.name} ${d.percent}%',
          quantity: 1,
          quantityUnit: 'piece',
          lineTotalCents: d.cents,
          needsReview: false,
          updatedAt: now,
        ));
      }
    });

    onChanged?.call();
    return ReceiptSaveResult(ReceiptSaveOutcome.saved, receiptId);
  }

  /// Loescht einen Bon samt Positionen (Soft-Delete, wird mit dem Server synchronisiert).
  Future<void> softDelete(String receiptId) async {
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      final r = await (_db.select(_db.receipts)..where((x) => x.id.equals(receiptId))).getSingleOrNull();
      if (r == null || r.deletedAt != null) return;
      final deleted = r.copyWith(deletedAt: Value(now), updatedAt: now);
      await _put('receipts', r.id, receiptToRemote(deleted),
          () => _db.into(_db.receipts).insertOnConflictUpdate(deleted.toCompanion(false)));
      final items = await (_db.select(_db.receiptItems)..where((i) => i.receiptId.equals(receiptId) & i.deletedAt.isNull())).get();
      for (final i in items) {
        final di = i.copyWith(deletedAt: Value(now), updatedAt: now);
        await _put('receipt_items', i.id, receiptItemToRemote(di),
            () => _db.into(_db.receiptItems).insertOnConflictUpdate(di.toCompanion(false)));
      }
    });
    onChanged?.call();
  }

  Future<void> _put(String remoteTable, String rowId, Map<String, dynamic> payload, Future<void> Function() writeLocal) async {
    await writeLocal();
    await _db.into(_db.outbox).insert(OutboxCompanion.insert(
          remoteTable: remoteTable,
          rowId: rowId,
          payload: jsonEncode(payload),
          createdAt: DateTime.now().toUtc(),
        ));
  }
}
