import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/inventory/expiry.dart';
import '../../domain/nutrition/fefo_deduction.dart';
import '../local/database.dart';
import '../../domain/receipt/vienna_time.dart';
import '../sync/mappers.dart';

/// Kein aktiver Bestand mehr fuer dieses Produkt (fuer die Einkaufsliste-Vorschlaege in einer spaeteren PR).
class NoActiveStockException implements Exception {}

/// Ergebnis von [InventoryRepository.deductForMeal]: aus welchen Posten wie viel abgezogen wurde und was der
/// Bestand nicht decken konnte (`shortfall`, gilt als "nicht im Bestand", FR-11).
class MealDeduction {
  const MealDeduction({required this.allocations, required this.shortfall});
  final List<FefoAllocation> allocations;
  final double shortfall;

  /// Erster Posten, aus dem abgezogen wurde (fuer `meal_ingredients.inventory_item_id`), sonst `null`.
  String? get firstItemId => allocations.isEmpty ? null : allocations.first.inventoryItemId;
}

/// Der Bon, dem ein Inventar-Eintrag zugeordnet ist (siehe [InventoryRepository.receiptLinkFor]).
class ReceiptLink {
  const ReceiptLink(
      {required this.receiptId, required this.receiptItemId, required this.purchasedAt, this.storeChain, required this.rawText, this.lineTotalCents});
  final String receiptId;
  final String receiptItemId;
  final DateTime purchasedAt;
  final String? storeChain;
  final String rawText;
  final int? lineTotalCents;
}

/// Inventar und Bestandsbewegungen (Doku 06). Jede Bestandsaenderung schreibt in derselben "Transaktion"
/// (lokal: drift-Transaktion, remote: zwei Outbox-Eintraege) auch eine Zeile ins Ledger (§9).
class InventoryRepository {
  InventoryRepository(this._db, {required this.householdId, this.onChanged, this.onDepleted, Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Future<String> Function() householdId;
  final void Function()? onChanged;

  /// Wird aufgerufen, wenn ein Produkt nach "Aufgebraucht"/"Weggeworfen" keinen aktiven Bestand mehr hat
  /// (Doku 06 §6, Ausloeser "Leer"): haengt die Einkaufsliste per Vorschlag ein, ohne dass InventoryRepository
  /// die Einkaufsliste selbst kennen muss.
  final Future<void> Function(String productId)? onDepleted;
  final Uuid _uuid;

  /// Aktiver Bestand (sealed/opened), nicht geloescht, nach Ablaufdatum sortiert (unbekannt zuletzt).
  Stream<List<InventoryItem>> watchActive() => (_db.select(_db.inventoryItems)
        ..where((i) => i.deletedAt.isNull() & i.status.isIn(['sealed', 'opened']) & i.isSuggestion.equals(false))
        ..orderBy([
          (i) => OrderingTerm.asc(i.expiresOn, nulls: NullsOrder.last),
          (i) => OrderingTerm.asc(i.purchasedOn),
        ]))
      .watch();

  /// Einmalige Momentaufnahme von [watchActive], ohne eine dauerhafte Abfrage offen zu halten (z.B. fuer die
  /// Ablauf-Erinnerungen, die nur gelegentlich neu geplant werden muessen).
  Future<List<InventoryItem>> activeSnapshot() => (_db.select(_db.inventoryItems)
        ..where((i) => i.deletedAt.isNull() & i.status.isIn(['sealed', 'opened']) & i.isSuggestion.equals(false)))
      .get();

  /// Bon-Vorschlaege, die noch nicht per Barcode bestaetigt wurden (Doku 06 §2, "Noch nicht gescannt").
  Stream<List<InventoryItem>> watchSuggestions() => (_db.select(_db.inventoryItems)
        ..where((i) => i.deletedAt.isNull() & i.isSuggestion.equals(true))
        ..orderBy([(i) => OrderingTerm.desc(i.purchasedOn)]))
      .watch();

  /// Einmalige Momentaufnahme von [watchSuggestions] (Fehlerbericht "keine Push-Benachrichtigung", 2026-09-28):
  /// auch ein noch unbestaetigter Bon-Vorschlag hat bereits ein geschaetztes Ablaufdatum und soll deshalb in
  /// die Ablauf-Erinnerungen einfliessen, nicht nur bestaetigter Bestand.
  Future<List<InventoryItem>> suggestionsSnapshot() =>
      (_db.select(_db.inventoryItems)..where((i) => i.deletedAt.isNull() & i.isSuggestion.equals(true))).get();

  /// Alle nicht geloeschten Bewegungen ab [since] (Grundlage der Verbrauchsbilanz, die rein clientseitig rechnet).
  Stream<List<InventoryMovement>> watchMovementsSince(DateTime since) => (_db.select(_db.inventoryMovements)
        ..where((m) => m.deletedAt.isNull() & m.occurredAt.isBiggerOrEqualValue(since)))
      .watch();

  Stream<List<InventoryMovement>> watchMovements(String productId) => (_db.select(_db.inventoryMovements)
        ..where((m) => m.productId.equals(productId) & m.deletedAt.isNull())
        ..orderBy([(m) => OrderingTerm.desc(m.occurredAt)]))
      .watch();

  /// Der Bon, aus dem ein Inventar-Eintrag als Vorschlag entstanden ist (Fehlerbericht "Bonzuordnung
  /// anzeigen", 2026-09-27). `null`, wenn der Eintrag nie einem Bon zugeordnet war (z.B. reiner Scan ohne
  /// vorherigen Bon-Vorschlag) — oder wenn der zugeordnete Bon inzwischen geloescht wurde: ein bestaetigter
  /// Inventar-Eintrag behaelt seine `receiptItemId` unabhaengig vom Schicksal des Bons (Gesamtkonzept
  /// Artikel<->Bon, 2026-09-28), ein geloeschter Bon soll dann aber nicht als "Geisterzuordnung" auftauchen.
  /// Wird derselbe Bon spaeter erneut importiert (z.B. digitaler Bon mit stabiler Re-Nr), heilt die Zuordnung
  /// von selbst wieder, weil die Bon-Position dieselbe ID zurueckbekommt.
  Future<ReceiptLink?> receiptLinkFor(String? receiptItemId) async {
    if (receiptItemId == null) return null;
    final row = await (_db.select(_db.receiptItems).join([
      innerJoin(_db.receipts, _db.receipts.id.equalsExp(_db.receiptItems.receiptId)),
      leftOuterJoin(_db.stores, _db.stores.id.equalsExp(_db.receipts.storeId)),
    ])
          ..where(_db.receiptItems.id.equals(receiptItemId) & _db.receiptItems.deletedAt.isNull() & _db.receipts.deletedAt.isNull()))
        .getSingleOrNull();
    if (row == null) return null;
    final item = row.readTable(_db.receiptItems);
    final receipt = row.readTable(_db.receipts);
    final store = row.readTableOrNull(_db.stores);
    return ReceiptLink(
      receiptId: receipt.id,
      receiptItemId: item.id,
      purchasedAt: receipt.purchasedAt,
      storeChain: store?.chain,
      rawText: item.rawText,
      lineTotalCents: item.lineTotalCents,
    );
  }

  /// Bon-Positionen desselben Produkts, die noch keinem Inventar-Eintrag zugeordnet sind: Kandidaten, um
  /// eine Bonzuordnung nachtraeglich zu setzen oder zu korrigieren (Fehlerbericht "Bonzuordnung anzeigen",
  /// erweitert 2026-09-28 um die Moeglichkeit, die Zuordnung auch wieder zu aendern).
  ///
  /// Als "schon zugeordnet" gelten nur **bestaetigte** Eintraege. Ein unbestaetigter Bon-Vorschlag traegt zwar
  /// ebenfalls eine `receiptItemId`, ist aber genau die Bon-Position, die der Nutzer einem bereits vorhandenen
  /// Bestand zuordnen will (Fehlerbericht "kein passender Bon bei Inventarartikel gefunden", 2026-10-01) -- sie
  /// auszublenden hiess, dass die Liste leer blieb, obwohl der passende Bon als Vorschlag direkt daneben lag.
  /// [setReceiptLink] nimmt den Vorschlag dann auf.
  Future<List<ReceiptLink>> candidateReceiptLinksFor(String productId, {int limit = 10}) async {
    final hid = await householdId();
    final linked = _db.selectOnly(_db.inventoryItems)
      ..addColumns([_db.inventoryItems.receiptItemId])
      ..where(_db.inventoryItems.receiptItemId.isNotNull() &
          _db.inventoryItems.deletedAt.isNull() &
          _db.inventoryItems.isSuggestion.equals(false));
    final linkedIds = (await linked.map((r) => r.read(_db.inventoryItems.receiptItemId)!).get()).toSet();

    final query = _db.select(_db.receiptItems).join([
      innerJoin(_db.receipts, _db.receipts.id.equalsExp(_db.receiptItems.receiptId)),
      leftOuterJoin(_db.stores, _db.stores.id.equalsExp(_db.receipts.storeId)),
    ])
      ..where(_db.receiptItems.householdId.equals(hid) & _db.receiptItems.productId.equals(productId) & _db.receiptItems.deletedAt.isNull())
      ..orderBy([OrderingTerm.desc(_db.receipts.purchasedAt)])
      ..limit(limit + linkedIds.length);
    final rows = await query.get();
    return rows
        .where((row) => !linkedIds.contains(row.readTable(_db.receiptItems).id))
        .take(limit)
        .map((row) {
          final item = row.readTable(_db.receiptItems);
          final receipt = row.readTable(_db.receipts);
          final store = row.readTableOrNull(_db.stores);
          return ReceiptLink(
            receiptId: receipt.id,
            receiptItemId: item.id,
            purchasedAt: receipt.purchasedAt,
            storeChain: store?.chain,
            rawText: item.rawText,
            lineTotalCents: item.lineTotalCents,
          );
        })
        .toList();
  }

  /// Setzt oder loest die Bonzuordnung eines Inventar-Eintrags nachtraeglich (Fehlerbericht "Bonzuordnung
  /// anzeigen"): `null` macht den Eintrag zu einem reinen Scan ohne Bon-Herkunft.
  ///
  /// Wird eine Bon-Position zugeordnet, auf die noch ein unbestaetigter Vorschlag zeigt, nimmt dieser Aufruf den
  /// Vorschlag auf: er und seine Kaufbuchung werden geloescht. Beides beschreibt denselben Einkauf wie der
  /// bestaetigte Eintrag (Vorschlag: Beleg per Bon, Eintrag: Beleg per Scan) -- bliebe der Vorschlag stehen,
  /// stuende die Ware doppelt im Bestand und im Ledger. Vorschlaege anderer Bon-Positionen bleiben unberuehrt.
  Future<void> setReceiptLink(String inventoryItemId, String? receiptItemId) async {
    final item = await _get(inventoryItemId);
    final now = DateTime.now().toUtc();
    if (receiptItemId != null) {
      final absorbed = await (_db.select(_db.inventoryItems)
            ..where((i) =>
                i.receiptItemId.equals(receiptItemId) &
                i.isSuggestion.equals(true) &
                i.deletedAt.isNull() &
                i.id.equals(inventoryItemId).not()))
          .get();
      for (final suggestion in absorbed) {
        await _putItem(suggestion.copyWith(deletedAt: Value(now), updatedAt: now));
        await _deleteMovementsOf(suggestion.id, now);
      }
    }
    await _putItem(item.copyWith(receiptItemId: Value(receiptItemId), updatedAt: now));
    onChanged?.call();
  }

  Future<void> _deleteMovementsOf(String inventoryItemId, DateTime now) async {
    final movements = await (_db.select(_db.inventoryMovements)
          ..where((m) => m.inventoryItemId.equals(inventoryItemId) & m.deletedAt.isNull()))
        .get();
    for (final m in movements) {
      final deleted = m.copyWith(deletedAt: Value(now), updatedAt: now);
      await _put('inventory_movements', m.id, inventoryMovementToRemote(deleted),
          () => _db.into(_db.inventoryMovements).insertOnConflictUpdate(deleted.toCompanion(false)));
    }
  }

  /// Legt einen Bon-Vorschlag an (Doku 06 §2 Punkt 1, §9 "Bon bestaetigt"): kein MHD, sondern hoechstens
  /// ein geschaetztes Ablaufdatum aus der Standardhaltbarkeit des Produkts. Bucht eine Kaufbewegung, weil der
  /// Bon selbst der Beleg ist (anders als beim Verfeinern per Scan, das keine neue Bewegung braucht).
  ///
  /// Idempotent ueber [receiptItemId] (Gesamtkonzept Artikel<->Bon, 2026-09-28): die ID des Eintrags wird
  /// deterministisch aus der Bon-Position abgeleitet, damit pro Position hoechstens ein Inventar-Eintrag
  /// existiert. Ein erneuter Aufruf fuer dieselbe Position (z.B. erneuter Import eines geloeschten Bons)
  /// erzeugt dadurch nie eine zweite Zeile, selbst wenn eine fruehere Aufraeumung ausgeblieben ist — die
  /// Korrektheit haengt nicht mehr davon ab, dass jede Loesch-Stelle im Code das sauber nachzieht. Wurde der
  /// Vorschlag inzwischen vom Nutzer bestaetigt (isSuggestion = false), bleibt er unangetastet: seine Menge,
  /// sein Lagerort und sein MHD sind bewusste Nutzerangaben, kein erneuter Bon-Import darf sie ueberschreiben
  /// oder den Eintrag zurueck zum Vorschlag machen.
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
    final id = _uuid.v5(Namespace.url.value, 'einkaufstracker:suggestion:$receiptItemId');
    final existing = await (_db.select(_db.inventoryItems)..where((i) => i.id.equals(id))).getSingleOrNull();
    if (existing != null && !existing.isSuggestion) return existing;

    final item = InventoryItem(
      id: id,
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
    if (existing == null) {
      await _addMovement(inventoryItemId: item.id, productId: productId, type: 'purchase', delta: quantity, unit: unit, now: purchasedOn);
    }
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
        quantity: quantity,
        unit: unit,
        bestBefore: Value(bestBefore),
        dateKind: dateKind,
        location: location,
        openShelfLifeDays: Value(openShelfLifeDays ?? refine.openShelfLifeDays),
        isSuggestion: false,
        expiresOn: Value(computeExpiresOn(bestBefore: bestBefore, openShelfLifeDays: openShelfLifeDays ?? refine.openShelfLifeDays)),
        updatedAt: DateTime.now().toUtc(),
      );
      await _putItem(updated);
      final delta = quantity - refine.quantity;
      if (delta != 0) {
        await _addMovement(inventoryItemId: updated.id, productId: productId, type: 'adjustment', delta: delta, unit: unit, now: now);
      }
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
    if (onDepleted != null) {
      final remaining = await (_db.select(_db.inventoryItems)
            ..where((i) =>
                i.productId.equals(item.productId) & i.deletedAt.isNull() & i.isSuggestion.equals(false) & i.status.isIn(['sealed', 'opened'])))
          .get();
      if (remaining.isEmpty) await onDepleted!(item.productId);
    }
    onChanged?.call();
  }

  /// Macht "Aufgebraucht"/"Weggeworfen" rueckgaengig, z.B. nach einem verwischten Wisch (Fehlerbericht
  /// "Rueckgaengigmachen von aufgebrauchten Artikeln", 2026-09-28): der Eintrag wird wieder aktiv (offen,
  /// falls er schon geoeffnet war, sonst versiegelt), die dadurch gebuchte Abgangsbewegung wird geloescht.
  Future<void> reopen(String id) async {
    final item = await _get(id);
    if (item.status != 'consumed' && item.status != 'discarded') return;
    final now = DateTime.now().toUtc();
    final updated = item.copyWith(status: item.openedOn != null ? 'opened' : 'sealed', closedAt: const Value(null), updatedAt: now);
    await _putItem(updated);
    final movement = await (_db.select(_db.inventoryMovements)
          ..where((m) => m.inventoryItemId.equals(id) & m.deletedAt.isNull() & (m.type.equals('consumed') | m.type.equals('discarded')))
          ..orderBy([(m) => OrderingTerm.desc(m.occurredAt)])
          ..limit(1))
        .getSingleOrNull();
    if (movement != null) {
      final deletedMovement = movement.copyWith(deletedAt: Value(now), updatedAt: now);
      await _put('inventory_movements', movement.id, inventoryMovementToRemote(deletedMovement),
          () => _db.into(_db.inventoryMovements).insertOnConflictUpdate(deletedMovement.toCompanion(false)));
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
  ///
  /// Stammt der Eintrag von einem Bon (receiptItemId gesetzt), wird er stattdessen wieder zum Bon-Vorschlag:
  /// die Kaufbewegung des Bons ist ja weiterhin belegt, nur die Barcode-Zuordnung und die dabei eingegebenen
  /// Werte werden zurueckgenommen (Fehlerbericht "Rueckgaengigmachen Bonartikel", 2026-09-28 - "soll wieder
  /// als Bonvorschlag auftauchen").
  Future<void> deleteItem(String id) async {
    final item = await _get(id);
    final now = DateTime.now().toUtc();
    if (item.receiptItemId != null) {
      final reverted = item.copyWith(
        isSuggestion: true,
        status: 'sealed',
        ean: const Value(null),
        openedOn: const Value(null),
        closedAt: const Value(null),
        // Codereview-Fund 2026-10-01: ohne das blieb das zuvor beim Oeffnen verkuerzte Ablaufdatum stehen
        // (z.B. Haltbarkeit-nach-Oeffnen-Tage ab einem jetzt wieder entfernten openedOn), obwohl der Eintrag
        // als ungeoeffnet gilt -- fuehrte zu einer verfruehten/falschen Ablauf-Erinnerung und einer roten
        // Ampel trotz noch weit entferntem MHD.
        expiresOn: Value(computeExpiresOn(bestBefore: item.bestBefore, openShelfLifeDays: item.openShelfLifeDays)),
        updatedAt: now,
      );
      await _putItem(reverted);
      onChanged?.call();
      return;
    }
    final updated = item.copyWith(deletedAt: Value(now), updatedAt: now);
    await _putItem(updated);
    await _deleteMovementsOf(id, now);
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

  /// Verwirft alle noch unbestaetigten Vorschlaege zu den angegebenen Bon-Positionen (Fehlerbericht
  /// "Bonartikel Vorschlag doppelt", 2026-09-28): wird ein Bon geloescht, sollen seine Vorschlaege nicht als
  /// Karteileiche liegen bleiben, sonst entsteht beim erneuten Import derselben Position ein Duplikat.
  /// Bereits bestaetigte Inventar-Eintraege (isSuggestion = false) bleiben unangetastet.
  Future<void> discardSuggestionsForReceiptItems(Iterable<String> receiptItemIds) async {
    final ids = receiptItemIds.toSet();
    if (ids.isEmpty) return;
    final items = await (_db.select(_db.inventoryItems)
          ..where((i) => i.receiptItemId.isIn(ids) & i.isSuggestion.equals(true) & i.deletedAt.isNull()))
        .get();
    if (items.isEmpty) return;
    final now = DateTime.now().toUtc();
    for (final item in items) {
      await _putItem(item.copyWith(deletedAt: Value(now), updatedAt: now));
    }
    onChanged?.call();
  }

  /// Bestaetigte (nicht mehr als Vorschlag markierte) Inventar-Eintraege, die einer dieser Bon-Positionen
  /// zugeordnet sind (Fehlerbericht "Bon löschen verwirft keine Zuordnung", 2026-09-28): Grundlage fuer die
  /// Rueckfrage beim Bon-Loeschen, ob die Zuordnung mit entfernt werden soll.
  Future<List<InventoryItem>> confirmedItemsLinkedTo(Iterable<String> receiptItemIds) async {
    final ids = receiptItemIds.toSet();
    if (ids.isEmpty) return const [];
    return (_db.select(_db.inventoryItems)
          ..where((i) => i.receiptItemId.isIn(ids) & i.isSuggestion.equals(false) & i.deletedAt.isNull()))
        .get();
  }

  /// Loest die Bonzuordnung aller bestaetigten Eintraege zu diesen Bon-Positionen (Rueckfrage beim Loeschen):
  /// der Bestand bleibt erhalten, verweist aber nicht mehr auf den (geloeschten) Bon.
  Future<void> clearReceiptLinksFor(Iterable<String> receiptItemIds) async {
    final items = await confirmedItemsLinkedTo(receiptItemIds);
    for (final item in items) {
      await setReceiptLink(item.id, null);
    }
  }

  /// Zieht [quantity] (in [unit], der Einheit des Produkts: `kg`, `l` oder `piece`) fuer eine Mahlzeit vom Bestand
  /// ab, aeltestes Ablaufdatum zuerst (FEFO, Doku 15 §3.4, FR-10). Jeder Abzug ist eine `meal`-Bewegung im Ledger
  /// mit Verweis auf die Mahlzeit (FR-12). Der Bestand wird nie negativ (FR-11): was nicht gedeckt ist, steht in
  /// [MealDeduction.shortfall] und wird nicht abgezogen.
  ///
  /// Wird ein Posten dabei nur angebrochen, gilt er als geoeffnet und bekommt die Haltbarkeit nach dem Oeffnen
  /// (FR-14, [openedShelfLifeDays] ist die Produktvorgabe); ein leerer Posten wird abgeschlossen. War es der letzte
  /// Bestand des Produkts, loest das wie bei "Aufgebraucht" [onDepleted] aus.
  ///
  /// Gehoert in die Transaktion des Aufrufers ([MealRepository]), schreibt aber selbst keine.
  Future<MealDeduction> deductForMeal({
    required String mealId,
    required String productId,
    required double quantity,
    required String unit,
    required DateTime eatenAt,
    int? openedShelfLifeDays,
  }) async {
    if (quantity <= 0) return const MealDeduction(allocations: [], shortfall: 0);
    final hid = await householdId();
    final active = await (_db.select(_db.inventoryItems)
          ..where((i) =>
              i.householdId.equals(hid) &
              i.productId.equals(productId) &
              i.deletedAt.isNull() &
              i.isSuggestion.equals(false) &
              i.status.isIn(['sealed', 'opened']) &
              i.unit.equals(unit)))
        .get();
    final byId = {for (final i in active) i.id: i};
    final result = allocateFefo(
      [for (final i in active) FefoCandidate(inventoryItemId: i.id, availableQuantity: i.quantity, expiresOn: i.expiresOn)],
      quantity,
    );

    final nowUtc = DateTime.now().toUtc();
    for (final a in result.allocations) {
      final item = byId[a.inventoryItemId]!;
      final remaining = _round3(item.quantity - a.quantity);
      if (remaining <= 0) {
        await _putItem(item.copyWith(quantity: 0, status: 'consumed', closedAt: Value(nowUtc), updatedAt: nowUtc));
      } else {
        await _putItem(item.copyWith(quantity: remaining, updatedAt: nowUtc));
        if (item.status == 'sealed') {
          await open(item.id, productDefaultOpenShelfLifeDays: openedShelfLifeDays, now: eatenAt);
        }
      }
      await _addMovement(
        inventoryItemId: item.id,
        productId: productId,
        type: 'meal',
        delta: -a.quantity,
        unit: unit,
        now: eatenAt,
        mealId: mealId,
      );
    }

    if (result.allocations.isNotEmpty && onDepleted != null) {
      final left = await (_db.select(_db.inventoryItems)
            ..where((i) =>
                i.productId.equals(productId) & i.deletedAt.isNull() & i.isSuggestion.equals(false) & i.status.isIn(['sealed', 'opened'])))
          .get();
      if (left.isEmpty) await onDepleted!(productId);
    }
    onChanged?.call();
    return MealDeduction(allocations: result.allocations, shortfall: _round3(result.shortfall));
  }

  /// Bucht den Abzug einer Mahlzeit per Gegenbuchung zurueck (Doku 15 §3.4, FR-12, LH-MEAL-04): fuer jeden Posten
  /// wird genau die noch offene Menge zurueckgebucht, als `adjustment` mit Verweis auf die Mahlzeit. Das Ledger
  /// bleibt dadurch append-only. Wiederholtes Aufrufen ist ungefaehrlich, denn zurueckgebucht wird nur, was
  /// netto noch abgezogen ist.
  ///
  /// Ein inzwischen geloeschter Posten kann nicht wiederhergestellt werden und wird uebersprungen. Ein durch den
  /// Abzug geleerter Posten ist danach wieder aktiv (`opened`, falls er je geoeffnet wurde, sonst `sealed`).
  /// Rueckgabe: Anzahl der zurueckgebuchten Posten.
  Future<int> restoreForMeal(String mealId, {DateTime? now}) async {
    final movements = await (_db.select(_db.inventoryMovements)
          ..where((m) => m.mealId.equals(mealId) & m.deletedAt.isNull() & m.inventoryItemId.isNotNull()))
        .get();
    final outstanding = <String, double>{};
    final sample = <String, InventoryMovement>{};
    for (final m in movements) {
      outstanding.update(m.inventoryItemId!, (v) => v - m.quantityDelta, ifAbsent: () => -m.quantityDelta);
      sample[m.inventoryItemId!] = m;
    }

    final nowUtc = now ?? DateTime.now().toUtc();
    var restored = 0;
    for (final entry in outstanding.entries) {
      final amount = _round3(entry.value);
      if (amount <= 0) continue;
      final item = await (_db.select(_db.inventoryItems)..where((i) => i.id.equals(entry.key))).getSingleOrNull();
      if (item == null || item.deletedAt != null) continue;
      final wasEmptied = item.status == 'consumed';
      final status = wasEmptied ? (item.openedOn != null ? 'opened' : 'sealed') : item.status;
      await _putItem(item.copyWith(
        quantity: _round3(item.quantity + amount),
        status: status,
        closedAt: wasEmptied ? const Value(null) : Value(item.closedAt),
        updatedAt: DateTime.now().toUtc(),
      ));
      await _addMovement(
        inventoryItemId: item.id,
        productId: item.productId,
        type: 'adjustment',
        delta: amount,
        unit: sample[entry.key]!.unit,
        now: nowUtc,
        mealId: mealId,
        note: 'Gegenbuchung zur Mahlzeit',
      );
      restored++;
    }
    if (restored > 0) onChanged?.call();
    return restored;
  }

  /// Rundet auf drei Nachkommastellen, wie `quantity_delta` in der Datenbank (numeric(10,3)): ohne das bliebe nach
  /// 1,0 - 0,15 - 0,85 ein Rest von 1e-17 stehen und der Posten wuerde nie als leer gelten.
  double _round3(double v) => (v * 1000).round() / 1000;

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
    String? mealId,
    String? note,
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
      note: note,
      mealId: mealId,
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
