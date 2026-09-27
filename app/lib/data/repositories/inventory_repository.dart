import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/inventory/expiry.dart';
import '../local/database.dart';
import '../../domain/receipt/vienna_time.dart';
import '../sync/mappers.dart';

/// Kein aktiver Bestand mehr fuer dieses Produkt (fuer die Einkaufsliste-Vorschlaege in einer spaeteren PR).
class NoActiveStockException implements Exception {}

/// Inventar und Bestandsbewegungen (Doku 06). Jede Bestandsaenderung schreibt in derselben "Transaktion"
/// (lokal: drift-Transaktion, remote: zwei Outbox-Eintraege) auch eine Zeile ins Ledger (§9).
class InventoryRepository {
  InventoryRepository(this._db, {required this.householdId, this.onChanged, Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Future<String> Function() householdId;
  final void Function()? onChanged;
  final Uuid _uuid;

  /// Aktiver Bestand (sealed/opened), nicht geloescht, nach Ablaufdatum sortiert (unbekannt zuletzt).
  Stream<List<InventoryItem>> watchActive() => (_db.select(_db.inventoryItems)
        ..where((i) => i.deletedAt.isNull() & i.status.isIn(['sealed', 'opened']) & i.isSuggestion.equals(false))
        ..orderBy([
          (i) => OrderingTerm.asc(i.expiresOn, nulls: NullsOrder.last),
          (i) => OrderingTerm.asc(i.purchasedOn),
        ]))
      .watch();

  /// Bon-Vorschlaege, die noch nicht per Barcode bestaetigt wurden (Doku 06 §2, "Noch nicht gescannt").
  Stream<List<InventoryItem>> watchSuggestions() => (_db.select(_db.inventoryItems)
        ..where((i) => i.deletedAt.isNull() & i.isSuggestion.equals(true))
        ..orderBy([(i) => OrderingTerm.desc(i.purchasedOn)]))
      .watch();

  Stream<List<InventoryMovement>> watchMovements(String productId) => (_db.select(_db.inventoryMovements)
        ..where((m) => m.productId.equals(productId) & m.deletedAt.isNull())
        ..orderBy([(m) => OrderingTerm.desc(m.occurredAt)]))
      .watch();

  /// Legt einen Bon-Vorschlag an (Doku 06 §2 Punkt 1, §9 "Bon bestaetigt"): kein MHD, sondern hoechstens
  /// ein geschaetztes Ablaufdatum aus der Standardhaltbarkeit des Produkts. Bucht eine Kaufbewegung, weil der
  /// Bon selbst der Beleg ist (anders als beim Verfeinern per Scan, das keine neue Bewegung braucht).
  Future<InventoryItem> createSuggestionFromReceipt({
    required String productId,
    required String receiptItemId,
    required double quantity,
    required String unit,
    required DateTime purchasedOn,
    int? sealedShelfLifeDays,
    String dateKind = 'best_before',
    String location = 'pantry',
  }) async {
    final hid = await householdId();
    final estimatedExpiry = sealedShelfLifeDays == null ? null : purchasedOn.add(Duration(days: sealedShelfLifeDays));
    final item = InventoryItem(
      id: _uuid.v4(),
      householdId: hid,
      productId: productId,
      receiptItemId: receiptItemId,
      quantity: quantity,
      unit: unit,
      location: location,
      purchasedOn: purchasedOn,
      bestBefore: estimatedExpiry,
      dateKind: dateKind,
      status: 'sealed',
      isSuggestion: true,
      expiresOn: estimatedExpiry,
      updatedAt: DateTime.now().toUtc(),
    );
    await _putItem(item);
    await _addMovement(inventoryItemId: item.id, productId: productId, type: 'purchase', delta: quantity, unit: unit, now: purchasedOn);
    return item;
  }

  /// Ein Bon-Vorschlag (isSuggestion, gleiches Produkt) aus den letzten 7 Tagen, der per Scan verfeinert werden
  /// kann, statt einen zweiten Eintrag anzulegen (Doku 06 §2, Punkt 2). Der juengste Vorschlag gewinnt.
  Future<InventoryItem?> findRefinableSuggestion(String productId, {DateTime? now}) async {
    final hid = await householdId();
    final today = _today(now);
    final cutoff = today.subtract(const Duration(days: 7));
    final candidates = await (_db.select(_db.inventoryItems)
          ..where((i) =>
              i.householdId.equals(hid) &
              i.productId.equals(productId) &
              i.isSuggestion.equals(true) &
              i.deletedAt.isNull() &
              i.purchasedOn.isBiggerOrEqualValue(cutoff))
          ..orderBy([(i) => OrderingTerm.desc(i.purchasedOn)]))
        .get();
    return candidates.firstOrNull;
  }

  /// Barcode-Scan eines Produkts (Doku 06 §3.5): verfeinert einen passenden Bon-Vorschlag, sonst legt es einen
  /// neuen, sofort bestaetigten Bestand an (mit Kaufbewegung, weil kein Bon dahintersteht).
  Future<InventoryItem> recordFromScan({
    required String productId,
    required String ean,
    double quantity = 1,
    String unit = 'piece',
    DateTime? bestBefore,
    String dateKind = 'best_before',
    String location = 'pantry',
    int? openShelfLifeDays,
    DateTime? now,
  }) async {
    final hid = await householdId();
    final today = _today(now);
    final refine = await findRefinableSuggestion(productId, now: now);
    final expiresOn = computeExpiresOn(bestBefore: bestBefore, openShelfLifeDays: openShelfLifeDays);

    if (refine != null) {
      final updated = refine.copyWith(
        ean: Value(ean),
        bestBefore: Value(bestBefore),
        dateKind: dateKind,
        location: location,
        openShelfLifeDays: Value(openShelfLifeDays ?? refine.openShelfLifeDays),
        isSuggestion: false,
        expiresOn: Value(computeExpiresOn(bestBefore: bestBefore, openShelfLifeDays: openShelfLifeDays ?? refine.openShelfLifeDays)),
        updatedAt: DateTime.now().toUtc(),
      );
      await _putItem(updated);
      onChanged?.call();
      return updated;
    }

    final item = InventoryItem(
      id: _uuid.v4(),
      householdId: hid,
      productId: productId,
      ean: ean,
      quantity: quantity,
      unit: unit,
      location: location,
      purchasedOn: today,
      bestBefore: bestBefore,
      dateKind: dateKind,
      openShelfLifeDays: openShelfLifeDays,
      status: 'sealed',
      isSuggestion: false,
      expiresOn: expiresOn,
      updatedAt: DateTime.now().toUtc(),
    );
    await _putItem(item);
    await _addMovement(inventoryItemId: item.id, productId: productId, type: 'purchase', delta: quantity, unit: unit, now: now);
    onChanged?.call();
    return item;
  }

  /// "Geoeffnet": setzt das Oeffnungsdatum und, falls noch keine eigene Frist hinterlegt ist, die
  /// Standardfrist des Produkts (Doku 06 §3.2).
  Future<void> open(String id, {int? productDefaultOpenShelfLifeDays, DateTime? now}) async {
    final item = await _get(id);
    if (item.status != 'sealed') return;
    final today = _today(now);
    final openDays = item.openShelfLifeDays ?? productDefaultOpenShelfLifeDays;
    final updated = item.copyWith(
      status: 'opened',
      openedOn: Value(today),
      openShelfLifeDays: Value(openDays),
      expiresOn: Value(computeExpiresOn(bestBefore: item.bestBefore, openedOn: today, openShelfLifeDays: openDays)),
      updatedAt: DateTime.now().toUtc(),
    );
    await _putItem(updated);
    onChanged?.call();
  }

  Future<void> markConsumed(String id, {DateTime? now}) => _close(id, 'consumed', now: now);
  Future<void> markDiscarded(String id, {DateTime? now}) => _close(id, 'discarded', now: now);

  Future<void> _close(String id, String status, {DateTime? now}) async {
    final item = await _get(id);
    if (item.status == 'consumed' || item.status == 'discarded') return;
    final nowUtc = DateTime.now().toUtc();
    final updated = item.copyWith(status: status, closedAt: Value(nowUtc), updatedAt: nowUtc);
    await _putItem(updated);
    if (item.quantity != 0) {
      await _addMovement(
        inventoryItemId: item.id,
        productId: item.productId,
        type: status,
        delta: -item.quantity,
        unit: item.unit,
        now: now,
      );
    }
    onChanged?.call();
  }

  /// Datum, Lagerort oder Art des Datums nachtraeglich korrigieren (z.B. beim Scan falsch abgelesenes MHD).
  /// Keine Ledger-Bewegung, weil sich dadurch die Bestandsmenge nicht aendert.
  Future<void> updateDetails(
    String id, {
    DateTime? bestBefore,
    bool clearBestBefore = false,
    String? dateKind,
    String? location,
  }) async {
    final item = await _get(id);
    final newBestBefore = clearBestBefore ? null : (bestBefore ?? item.bestBefore);
    final updated = item.copyWith(
      bestBefore: Value(newBestBefore),
      dateKind: dateKind ?? item.dateKind,
      location: location ?? item.location,
      expiresOn: Value(computeExpiresOn(bestBefore: newBestBefore, openedOn: item.openedOn, openShelfLifeDays: item.openShelfLifeDays)),
      updatedAt: DateTime.now().toUtc(),
    );
    await _putItem(updated);
    onChanged?.call();
  }

  /// Menge korrigieren (Inventur, Doku 06 §9: Bewegungsart `adjustment`, Vorzeichen ist die Differenz).
  Future<void> adjustQuantity(String id, double newQuantity, {DateTime? now}) async {
    final item = await _get(id);
    final delta = newQuantity - item.quantity;
    final updated = item.copyWith(quantity: newQuantity, updatedAt: DateTime.now().toUtc());
    await _putItem(updated);
    if (delta != 0) {
      await _addMovement(inventoryItemId: item.id, productId: item.productId, type: 'adjustment', delta: delta, unit: item.unit, now: now);
    }
    onChanged?.call();
  }

  /// Loescht einen faelschlich erfassten, bereits bestaetigten Eintrag rueckwirkend (Doku 06 kennt bisher nur
  /// "Vorschlag verwerfen"; das hier ist das Gegenstueck fuer Bestand, der schon gescannt wurde). Anders als
  /// "aufgebraucht"/"weggeworfen" (echte Ereignisse) wird auch die Kaufbewegung geloescht: es soll so aussehen,
  /// als waere der Scan nie passiert (Fehlerbericht "Rueckgaengig machen", 2026-09-27).
  Future<void> deleteItem(String id) async {
    final item = await _get(id);
    final now = DateTime.now().toUtc();
    final updated = item.copyWith(deletedAt: Value(now), updatedAt: now);
    await _putItem(updated);
    final movements = await (_db.select(_db.inventoryMovements)
          ..where((m) => m.inventoryItemId.equals(id) & m.deletedAt.isNull()))
        .get();
    for (final m in movements) {
      final deleted = m.copyWith(deletedAt: Value(now), updatedAt: now);
      await _put('inventory_movements', m.id, inventoryMovementToRemote(deleted),
          () => _db.into(_db.inventoryMovements).insertOnConflictUpdate(deleted.toCompanion(false)));
    }
    onChanged?.call();
  }

  /// Loescht einen Vorschlag, den der Nutzer nicht behalten will (Doku 06 §1: "Vorschlag --> verwerfen").
  Future<void> discardSuggestion(String id) async {
    final item = await _get(id);
    if (!item.isSuggestion) return;
    final updated = item.copyWith(deletedAt: Value(DateTime.now().toUtc()), updatedAt: DateTime.now().toUtc());
    await _putItem(updated);
    onChanged?.call();
  }

  Future<InventoryItem> _get(String id) => (_db.select(_db.inventoryItems)..where((i) => i.id.equals(id))).getSingle();

  Future<void> _putItem(InventoryItem item) =>
      _put('inventory_items', item.id, inventoryItemToRemote(item), () => _db.into(_db.inventoryItems).insertOnConflictUpdate(item.toCompanion(false)));

  Future<void> _addMovement({
    required String inventoryItemId,
    required String productId,
    required String type,
    required double delta,
    required String unit,
    DateTime? now,
  }) async {
    final hid = await householdId();
    final m = InventoryMovement(
      id: _uuid.v4(),
      householdId: hid,
      inventoryItemId: inventoryItemId,
      productId: productId,
      occurredAt: now ?? DateTime.now().toUtc(),
      type: type,
      quantityDelta: delta,
      unit: unit,
      updatedAt: DateTime.now().toUtc(),
    );
    await _put('inventory_movements', m.id, inventoryMovementToRemote(m),
        () => _db.into(_db.inventoryMovements).insertOnConflictUpdate(m.toCompanion(false)));
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

  /// Heutiges Kalenderdatum in Wiener Ortszeit (Doku FR-07), als UTC-Mitternacht dieses Tages gespeichert.
  DateTime _today(DateTime? now) {
    final local = utcToViennaLocal(now ?? DateTime.now().toUtc());
    return DateTime.utc(local.year, local.month, local.day);
  }
}
