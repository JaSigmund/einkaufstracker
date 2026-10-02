import 'package:drift/drift.dart' show Value;
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

DateTime _d(int y, int m, int d) => DateTime.utc(y, m, d);

void main() {
  late AppDatabase db;
  late String productId;

  setUp(() async {
    db = memoryDb();
    productId = (await productRepo(db).create(name: 'Vollmilch 1l', baseUnit: 'l', packSize: 1)).id;
  });
  tearDown(() => db.close());

  group('recordFromScan: neuer Bestand', () {
    test('legt einen versiegelten Eintrag an, Ablaufdatum aus MHD, Kaufbewegung im Ledger', () async {
      var changed = 0;
      final repo = inventoryRepo(db, onChanged: () => changed++);
      final item = await repo.recordFromScan(
        productId: productId,
        ean: '9008700000001',
        bestBefore: _d(2026, 10, 15),
        now: DateTime.utc(2026, 9, 27, 10),
      );
      expect(item.status, 'sealed');
      expect(item.isSuggestion, isFalse);
      expect(item.expiresOn, _d(2026, 10, 15));
      expect(item.purchasedOn, _d(2026, 9, 27));
      expect(changed, 1);

      final movements = await db.select(db.inventoryMovements).get();
      expect(movements, hasLength(1));
      expect((movements.single.type, movements.single.quantityDelta), ('purchase', 1.0));
      expect((await db.select(db.outbox).get()).map((o) => o.remoteTable), containsAll(['inventory_items', 'inventory_movements']));
    });

    test('ohne MHD und ohne Standardfrist bleibt der Ablauf unbekannt', () async {
      final item = await inventoryRepo(db).recordFromScan(productId: productId, ean: '1');
      expect(item.expiresOn, isNull);
    });

    test('Verbrauchsdatum wird uebernommen', () async {
      final item = await inventoryRepo(db).recordFromScan(productId: productId, ean: '1', bestBefore: _d(2026, 10, 1), dateKind: 'use_by');
      expect(item.dateKind, 'use_by');
    });
  });

  group('recordFromScan: verfeinert einen Bon-Vorschlag statt zu duplizieren (Doku 06 §2)', () {
    Future<String> makeSuggestion(DateTime purchasedOn) async {
      final id = 'sugg-${purchasedOn.toIso8601String()}';
      await db.into(db.inventoryItems).insert(InventoryItem(
            id: id,
            householdId: 'h1',
            productId: productId,
            quantity: 2,
            unit: 'piece',
            location: 'pantry',
            purchasedOn: purchasedOn,
            dateKind: 'best_before',
            status: 'sealed',
            isSuggestion: true,
            updatedAt: DateTime.utc(2026),
          ));
      return id;
    }

    test('Vorschlag der letzten 7 Tage wird verfeinert, kein zweiter Eintrag, keine zweite Kaufbewegung, Menge bleibt gleich', () async {
      final id = await makeSuggestion(_d(2026, 9, 25));
      final item = await inventoryRepo(db).recordFromScan(
        productId: productId,
        ean: '9008700000002',
        quantity: 2,
        bestBefore: _d(2026, 10, 10),
        location: 'fridge',
        now: DateTime.utc(2026, 9, 27),
      );
      expect(item.id, id);
      expect(item.isSuggestion, isFalse);
      expect(item.ean, '9008700000002');
      expect(item.location, 'fridge');
      expect(item.quantity, 2);
      expect(await db.select(db.inventoryItems).get(), hasLength(1));
      expect(await db.select(db.inventoryMovements).get(), isEmpty); // der Bon hat die Kaufbewegung schon erzeugt
    });

    test('beim Scan eingegebene Menge ueberschreibt die Menge des Bon-Vorschlags (Fehlerbericht "Bonartikel-Erkennung")', () async {
      final id = await makeSuggestion(_d(2026, 9, 25)); // Vorschlag hat Menge 2 aus dem Bon
      final item = await inventoryRepo(db).recordFromScan(
        productId: productId,
        ean: '9008700000002',
        quantity: 4, // Nutzer korrigiert beim Scan auf 4
        now: DateTime.utc(2026, 9, 27),
      );
      expect(item.id, id);
      expect(item.quantity, 4);
      final movements = await db.select(db.inventoryMovements).get();
      expect(movements, hasLength(1));
      expect(movements.single.type, 'adjustment');
      expect(movements.single.quantityDelta, 2); // 4 - 2
    });

    test('Vorschlag ist aelter als 7 Tage: neuer Eintrag statt Verfeinerung', () async {
      await makeSuggestion(_d(2026, 9, 1));
      await inventoryRepo(db).recordFromScan(productId: productId, ean: '1', now: DateTime.utc(2026, 9, 27));
      final items = await db.select(db.inventoryItems).get();
      expect(items, hasLength(2));
      expect(items.where((i) => i.isSuggestion), hasLength(1)); // der alte Vorschlag bleibt unangetastet
    });

    test('mehrere passende Vorschlaege: der juengste wird verfeinert', () async {
      await makeSuggestion(_d(2026, 9, 20));
      final newer = await makeSuggestion(_d(2026, 9, 26));
      final item = await inventoryRepo(db).recordFromScan(productId: productId, ean: '1', now: DateTime.utc(2026, 9, 27));
      expect(item.id, newer);
    });
  });

  group('open', () {
    test('setzt Oeffnungsdatum und uebernimmt die Standardfrist, wenn keine eigene gesetzt ist', () async {
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: productId, ean: '1', bestBefore: _d(2026, 10, 15), now: DateTime.utc(2026, 9, 27));
      await repo.open(item.id, productDefaultOpenShelfLifeDays: 3, now: DateTime.utc(2026, 9, 28));
      final updated = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
      expect(updated.status, 'opened');
      expect(updated.openedOn, _d(2026, 9, 28));
      expect(updated.openShelfLifeDays, 3);
      expect(updated.expiresOn, _d(2026, 10, 1)); // Oeffnungsfrist vor MHD
    });

    test('bereits geoeffnet oder aufgebraucht: kein Effekt', () async {
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: productId, ean: '1', now: DateTime.utc(2026, 9, 27));
      await repo.open(item.id);
      final afterFirst = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
      await repo.open(item.id, productDefaultOpenShelfLifeDays: 99);
      final afterSecond = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
      expect(afterSecond.openedOn, afterFirst.openedOn);
      expect(afterSecond.openShelfLifeDays, isNull);
    });
  });

  group('markConsumed / markDiscarded', () {
    test('schliesst den Eintrag und bucht die Restmenge negativ ins Ledger', () async {
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: productId, ean: '1', quantity: 3, now: DateTime.utc(2026, 9, 27));
      await repo.markConsumed(item.id, now: DateTime.utc(2026, 9, 28));
      final updated = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
      expect(updated.status, 'consumed');
      expect(updated.closedAt, isNotNull);
      final consumedMovement = (await db.select(db.inventoryMovements).get()).firstWhere((m) => m.type == 'consumed');
      expect(consumedMovement.quantityDelta, -3.0);
    });

    test('discarded verhaelt sich gleich, mit type discarded', () async {
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: productId, ean: '1', quantity: 1, now: DateTime.utc(2026, 9, 27));
      await repo.markDiscarded(item.id);
      final movement = (await db.select(db.inventoryMovements).get()).firstWhere((m) => m.type == 'discarded');
      expect(movement.quantityDelta, -1.0);
    });

    test('doppeltes Schliessen bucht nicht zweimal', () async {
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: productId, ean: '1', now: DateTime.utc(2026, 9, 27));
      await repo.markConsumed(item.id);
      await repo.markDiscarded(item.id); // schon konsumiert: kein Effekt
      final updated = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
      expect(updated.status, 'consumed');
      expect(await db.select(db.inventoryMovements).get(), hasLength(2)); // Kauf + ein Abgang
    });

    test('onDepleted feuert, wenn kein aktiver Bestand mehr uebrig ist (Einkaufsliste "Leer", Roadmap Phase 3)', () async {
      final depleted = <String>[];
      final repo = inventoryRepo(db, onDepleted: (id) async => depleted.add(id));
      final item = await repo.recordFromScan(productId: productId, ean: '1', now: DateTime.utc(2026, 9, 27));
      await repo.markConsumed(item.id);
      expect(depleted, [productId]);
    });

    test('onDepleted feuert nicht, solange noch aktiver Bestand desselben Produkts existiert', () async {
      final depleted = <String>[];
      final repo = inventoryRepo(db, onDepleted: (id) async => depleted.add(id));
      final a = await repo.recordFromScan(productId: productId, ean: '1', now: DateTime.utc(2026, 9, 27));
      await repo.recordFromScan(productId: productId, ean: '2', now: DateTime.utc(2026, 9, 27));
      await repo.markConsumed(a.id);
      expect(depleted, isEmpty);
    });
  });

  group('reopen', () {
    test('macht Aufgebraucht rueckgaengig, entfernt die Abgangsbewegung', () async {
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: productId, ean: '1', quantity: 2, now: DateTime.utc(2026, 9, 27));
      await repo.markConsumed(item.id);
      expect((await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle()).status, 'consumed');

      await repo.reopen(item.id);
      final row = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
      expect(row.status, 'sealed');
      expect(row.closedAt, isNull);
      expect(await (db.select(db.inventoryMovements)..where((m) => m.type.equals('consumed'))).get().then((l) => l.where((m) => m.deletedAt == null).toList()), isEmpty);
      final remaining = (await db.select(db.inventoryMovements).get()).where((m) => m.deletedAt == null).toList();
      expect(remaining, hasLength(1)); // der Kauf bleibt
    });

    test('war schon geoeffnet: kommt wieder auf opened zurueck, nicht sealed', () async {
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: productId, ean: '1', now: DateTime.utc(2026, 9, 27));
      await repo.open(item.id, now: DateTime.utc(2026, 9, 28));
      await repo.markDiscarded(item.id);
      await repo.reopen(item.id);
      expect((await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle()).status, 'opened');
    });

    test('aktiver Eintrag: kein Effekt', () async {
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: productId, ean: '1', now: DateTime.utc(2026, 9, 27));
      await repo.reopen(item.id); // war nie geschlossen
      expect((await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle()).status, 'sealed');
    });
  });

  group('deleteItem bei einem Bon-Artikel', () {
    test('wird wieder zum Vorschlag statt geloescht zu werden, die Kaufbewegung bleibt', () async {
      final repo = inventoryRepo(db);
      final suggestion = await repo.createSuggestionFromReceipt(
        productId: productId, receiptItemId: 'ri1', quantity: 1, unit: 'piece', purchasedOn: DateTime.utc(2026, 9, 20),
      );
      final refined = await repo.recordFromScan(productId: productId, ean: '1', bestBefore: DateTime.utc(2026, 10, 10), now: DateTime.utc(2026, 9, 21));
      expect(refined.id, suggestion.id); // verfeinert, kein zweiter Eintrag

      await repo.deleteItem(refined.id);
      final row = await (db.select(db.inventoryItems)..where((i) => i.id.equals(refined.id))).getSingle();
      expect(row.deletedAt, isNull); // nicht geloescht
      expect(row.isSuggestion, isTrue);
      expect(row.status, 'sealed');
      expect(row.ean, isNull);
      expect(await repo.watchSuggestions().first, hasLength(1));
      expect(await db.select(db.inventoryMovements).get(), hasLength(1)); // die Kaufbewegung des Bons bleibt
    });

    test('Codereview-Fund 2026-10-01: ein bereits geoeffneter Eintrag bekommt beim Zurueck-zum-Vorschlag wieder das volle (nicht das verkuerzte) Ablaufdatum', () async {
      final repo = inventoryRepo(db);
      await repo.createSuggestionFromReceipt(
        productId: productId, receiptItemId: 'ri1', quantity: 1, unit: 'piece', purchasedOn: DateTime.utc(2026, 9, 20),
      );
      final refined = await repo.recordFromScan(productId: productId, ean: '1', bestBefore: DateTime.utc(2026, 11, 1), now: DateTime.utc(2026, 9, 21));
      await repo.open(refined.id, productDefaultOpenShelfLifeDays: 3, now: DateTime.utc(2026, 10, 1));
      final opened = await (db.select(db.inventoryItems)..where((i) => i.id.equals(refined.id))).getSingle();
      expect(opened.expiresOn, DateTime.utc(2026, 10, 4)); // verkuerzt durch die 3 Tage nach Oeffnen

      await repo.deleteItem(refined.id);
      final reverted = await (db.select(db.inventoryItems)..where((i) => i.id.equals(refined.id))).getSingle();
      expect(reverted.openedOn, isNull);
      expect(reverted.expiresOn, DateTime.utc(2026, 11, 1)); // wieder das volle MHD, nicht mehr der 2026-10-04-Wert
    });
  });

  group('receiptLinkFor (Fehlerbericht "Bonzuordnung anzeigen")', () {
    test('liefert Bon-Datum, Haendler, Rohtext und Preis der Bon-Position', () async {
      await db.into(db.stores).insert(Store(id: 'store1', householdId: 'h1', chain: 'Billa', updatedAt: DateTime.utc(2026)));
      await db.into(db.receipts).insert(Receipt(
            id: 'r1',
            householdId: 'h1',
            storeId: 'store1',
            purchasedAt: _d(2026, 9, 20),
            totalCents: 500,
            status: 'confirmed',
            source: 'manual',
            sumMismatch: false,
            updatedAt: DateTime.utc(2026),
          ));
      await db.into(db.receiptItems).insert(ReceiptItem(
            id: 'ri1',
            householdId: 'h1',
            receiptId: 'r1',
            lineNo: 1,
            kind: 'article',
            rawText: 'DKIH PAPRIKA TRICOLORE',
            quantity: 1,
            quantityUnit: 'piece',
            lineTotalCents: 249,
            needsReview: false,
            updatedAt: DateTime.utc(2026),
          ));
      final repo = inventoryRepo(db);
      final suggestion = await repo.createSuggestionFromReceipt(
        productId: productId, receiptItemId: 'ri1', quantity: 1, unit: 'piece', purchasedOn: _d(2026, 9, 20),
      );

      final link = await repo.receiptLinkFor(suggestion.receiptItemId);
      expect(link, isNotNull);
      expect(link!.storeChain, 'Billa');
      expect(link.purchasedAt, _d(2026, 9, 20));
      expect(link.rawText, 'DKIH PAPRIKA TRICOLORE');
      expect(link.lineTotalCents, 249);
    });

    test('kein receiptItemId: null statt Fehler', () async {
      final link = await inventoryRepo(db).receiptLinkFor(null);
      expect(link, isNull);
    });

    test('geloeschter Bon: null statt einer Geisterzuordnung (Gesamtkonzept Artikel<->Bon, 2026-09-28)', () async {
      await db.into(db.receipts).insert(Receipt(
            id: 'r1', householdId: 'h1', purchasedAt: _d(2026, 9, 20), totalCents: 249, status: 'confirmed',
            source: 'manual', sumMismatch: false, updatedAt: DateTime.utc(2026),
          ));
      await db.into(db.receiptItems).insert(ReceiptItem(
            id: 'ri1', householdId: 'h1', receiptId: 'r1', lineNo: 1, kind: 'article', rawText: 'Paprika',
            quantity: 1, quantityUnit: 'piece', lineTotalCents: 249, needsReview: false, updatedAt: DateTime.utc(2026),
          ));
      // Ein bestaetigter (nicht bloss vorgeschlagener) Eintrag behaelt seine receiptItemId, wenn der Bon
      // geloescht wird — genau deshalb muss receiptLinkFor selbst den geloeschten Bon herausfiltern.
      final confirmed = await inventoryRepo(db).recordFromScan(productId: productId, ean: '1');
      await inventoryRepo(db).setReceiptLink(confirmed.id, 'ri1');
      expect(await inventoryRepo(db).receiptLinkFor('ri1'), isNotNull);

      await (db.update(db.receiptItems)..where((i) => i.id.equals('ri1'))).write(ReceiptItemsCompanion(deletedAt: Value(DateTime.now().toUtc())));
      await (db.update(db.receipts)..where((r) => r.id.equals('r1'))).write(ReceiptsCompanion(deletedAt: Value(DateTime.now().toUtc())));

      expect(await inventoryRepo(db).receiptLinkFor('ri1'), isNull);
    });
  });

  group('candidateReceiptLinksFor / setReceiptLink (Bonzuordnung aendern, 2026-09-28)', () {
    Future<void> makeReceiptItem(String id, String receiptId, {DateTime? purchasedAt}) async {
      await db.into(db.receipts).insertOnConflictUpdate(Receipt(
            id: receiptId,
            householdId: 'h1',
            purchasedAt: purchasedAt ?? _d(2026, 9, 20),
            totalCents: 500,
            status: 'confirmed',
            source: 'manual',
            sumMismatch: false,
            updatedAt: DateTime.utc(2026),
          ));
      await db.into(db.receiptItems).insert(ReceiptItem(
            id: id,
            householdId: 'h1',
            receiptId: receiptId,
            lineNo: 1,
            kind: 'article',
            rawText: 'Bon-Position $id',
            productId: productId,
            quantity: 1,
            quantityUnit: 'piece',
            lineTotalCents: 100,
            needsReview: false,
            updatedAt: DateTime.utc(2026),
          ));
    }

    test('zeigt nur Bon-Positionen ohne bestehende Zuordnung, neueste zuerst', () async {
      await makeReceiptItem('ri1', 'r1', purchasedAt: _d(2026, 9, 1));
      await makeReceiptItem('ri2', 'r2', purchasedAt: _d(2026, 9, 20));
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: productId, ean: '1', now: DateTime.utc(2026, 9, 27));
      await repo.setReceiptLink(item.id, 'ri1'); // ri1 ist damit "verlinkt", darf nicht als Kandidat auftauchen

      final candidates = await repo.candidateReceiptLinksFor(productId);
      expect(candidates.map((c) => c.receiptItemId), ['ri2']);
    });

    test('setReceiptLink verknuepft, setReceiptLink(null) loest wieder', () async {
      await makeReceiptItem('ri1', 'r1');
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: productId, ean: '1', now: DateTime.utc(2026, 9, 27));
      expect(item.receiptItemId, isNull);

      await repo.setReceiptLink(item.id, 'ri1');
      var row = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
      expect(row.receiptItemId, 'ri1');

      await repo.setReceiptLink(item.id, null);
      row = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
      expect(row.receiptItemId, isNull);
    });

    // Fehlerbericht "kein passender Bon bei Inventarartikel gefunden" (2026-10-01): ein Bon-Vorschlag IST
    // ein Inventar-Eintrag mit receiptItemId. Er hielt seine Bon-Position bisher fuer "schon verlinkt" und
    // blendete sie als Kandidat aus -- obwohl genau dieser Vorschlag der Grund war, den Bon zuordnen zu wollen.
    test('Kandidat trotz Vorschlag: bestehender, bestaetigter Eintrag ohne Bon sieht die Position des Vorschlags', () async {
      await makeReceiptItem('ri1', 'r1');
      final repo = inventoryRepo(db);
      // Bestaetigter Bestand ohne Bon (aelterer Scan), dann kommt ein Bon dazu und erzeugt einen Vorschlag.
      final confirmed = await repo.recordFromScan(productId: productId, ean: '1', now: DateTime.utc(2026, 9, 10));
      await repo.createSuggestionFromReceipt(
        productId: productId, receiptItemId: 'ri1', quantity: 1, unit: 'piece', purchasedOn: _d(2026, 9, 20),
      );

      final candidates = await repo.candidateReceiptLinksFor(productId);
      expect(candidates.map((c) => c.receiptItemId), ['ri1']);
      expect(confirmed.receiptItemId, isNull);
    });

    test('Zuordnen nimmt den Vorschlag auf: er verschwindet samt Kaufbuchung, nichts wird doppelt gezaehlt', () async {
      await makeReceiptItem('ri1', 'r1');
      final repo = inventoryRepo(db);
      final confirmed = await repo.recordFromScan(productId: productId, ean: '1', now: DateTime.utc(2026, 9, 10));
      final suggestion = await repo.createSuggestionFromReceipt(
        productId: productId, receiptItemId: 'ri1', quantity: 1, unit: 'piece', purchasedOn: _d(2026, 9, 20),
      );

      await repo.setReceiptLink(confirmed.id, 'ri1');

      final items = await (db.select(db.inventoryItems)..where((i) => i.deletedAt.isNull())).get();
      expect(items.map((i) => i.id), [confirmed.id], reason: 'nur der bestaetigte Eintrag bleibt aktiv');
      expect(items.single.receiptItemId, 'ri1');
      final suggestionRow = await (db.select(db.inventoryItems)..where((i) => i.id.equals(suggestion.id))).getSingle();
      expect(suggestionRow.deletedAt, isNotNull, reason: 'der Vorschlag ist aufgenommen (soft-deleted), nicht doppelt vorhanden');

      final activeMovements = await (db.select(db.inventoryMovements)..where((m) => m.deletedAt.isNull())).get();
      expect(activeMovements.map((m) => m.inventoryItemId).toSet(), {confirmed.id},
          reason: 'die Kaufbuchung des Vorschlags darf nicht zusaetzlich zum bestaetigten Eintrag zaehlen');
    });

    test('Zuordnen laesst Vorschlaege anderer Bon-Positionen unangetastet', () async {
      await makeReceiptItem('ri1', 'r1');
      await makeReceiptItem('ri2', 'r2');
      final repo = inventoryRepo(db);
      final confirmed = await repo.recordFromScan(productId: productId, ean: '1', now: DateTime.utc(2026, 9, 10));
      final other = await repo.createSuggestionFromReceipt(
        productId: productId, receiptItemId: 'ri2', quantity: 1, unit: 'piece', purchasedOn: _d(2026, 9, 20),
      );

      await repo.setReceiptLink(confirmed.id, 'ri1');

      final otherRow = await (db.select(db.inventoryItems)..where((i) => i.id.equals(other.id))).getSingle();
      expect(otherRow.deletedAt, isNull);
      expect(otherRow.isSuggestion, isTrue);
    });

    test('Zuordnung loesen (null) rettet keinen alten Vorschlag zurueck und aendert nichts am Bestand', () async {
      await makeReceiptItem('ri1', 'r1');
      final repo = inventoryRepo(db);
      final confirmed = await repo.recordFromScan(productId: productId, ean: '1', now: DateTime.utc(2026, 9, 10));
      await repo.setReceiptLink(confirmed.id, 'ri1');
      await repo.setReceiptLink(confirmed.id, null);

      final items = await (db.select(db.inventoryItems)..where((i) => i.deletedAt.isNull())).get();
      expect(items.map((i) => i.id), [confirmed.id]);
      expect(items.single.receiptItemId, isNull);
    });
  });

  group('updateDetails', () {
    test('aendert MHD, Datumsart und Lagerort, ohne Ledger-Bewegung', () async {
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: productId, ean: '1', bestBefore: _d(2026, 10, 1), now: DateTime.utc(2026, 9, 27));
      await repo.updateDetails(item.id, bestBefore: _d(2026, 10, 20), dateKind: 'use_by', location: 'fridge');
      final updated = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
      expect(updated.bestBefore, _d(2026, 10, 20));
      expect(updated.expiresOn, _d(2026, 10, 20));
      expect(updated.dateKind, 'use_by');
      expect(updated.location, 'fridge');
      expect(await db.select(db.inventoryMovements).get(), hasLength(1)); // nur der Kauf, keine neue Bewegung
    });

    test('MHD entfernen (clearBestBefore)', () async {
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: productId, ean: '1', bestBefore: _d(2026, 10, 1), now: DateTime.utc(2026, 9, 27));
      await repo.updateDetails(item.id, clearBestBefore: true);
      final updated = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
      expect(updated.bestBefore, isNull);
      expect(updated.expiresOn, isNull);
    });

    test('MHD-Aenderung wirkt sich auf einen bereits geoeffneten Eintrag aus (Oeffnungsfrist bleibt massgeblich)', () async {
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: productId, ean: '1', bestBefore: _d(2026, 10, 20), now: DateTime.utc(2026, 9, 27));
      await repo.open(item.id, productDefaultOpenShelfLifeDays: 3, now: DateTime.utc(2026, 9, 28));
      await repo.updateDetails(item.id, bestBefore: _d(2026, 9, 29)); // MHD jetzt vor der Oeffnungsfrist
      final updated = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
      expect(updated.expiresOn, _d(2026, 9, 29));
    });
  });

  group('adjustQuantity', () {
    test('bucht die Differenz als adjustment', () async {
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: productId, ean: '1', quantity: 5, now: DateTime.utc(2026, 9, 27));
      await repo.adjustQuantity(item.id, 3);
      final updated = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
      expect(updated.quantity, 3);
      final adj = (await db.select(db.inventoryMovements).get()).firstWhere((m) => m.type == 'adjustment');
      expect(adj.quantityDelta, -2.0);
    });

    test('gleiche Menge: keine Bewegung', () async {
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: productId, ean: '1', quantity: 5, now: DateTime.utc(2026, 9, 27));
      await repo.adjustQuantity(item.id, 5);
      expect(await db.select(db.inventoryMovements).get(), hasLength(1)); // nur der Kauf
    });
  });

  group('watchActive / watchSuggestions', () {
    test('Vorschlaege erscheinen nicht in watchActive, sortiert nach Ablauf', () async {
      final repo = inventoryRepo(db);
      final a = await repo.recordFromScan(productId: productId, ean: '1', bestBefore: _d(2026, 10, 20), now: DateTime.utc(2026, 9, 27));
      final b = await repo.recordFromScan(productId: productId, ean: '2', bestBefore: _d(2026, 10, 5), now: DateTime.utc(2026, 9, 27));
      await db.into(db.inventoryItems).insert(InventoryItem(
            id: 'sugg', householdId: 'h1', productId: productId, quantity: 1, unit: 'piece', location: 'pantry',
            purchasedOn: _d(2026, 9, 27), dateKind: 'best_before', status: 'sealed', isSuggestion: true, updatedAt: DateTime.utc(2026),
          ));
      final active = await repo.watchActive().first;
      expect(active.map((i) => i.id), [b.id, a.id]); // frueheres Ablaufdatum zuerst
      final suggestions = await repo.watchSuggestions().first;
      expect(suggestions.map((i) => i.id), ['sugg']);
    });

    test('geschlossene und geloeschte Eintraege erscheinen nicht', () async {
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: productId, ean: '1', now: DateTime.utc(2026, 9, 27));
      await repo.markConsumed(item.id);
      expect(await repo.watchActive().first, isEmpty);
    });
  });

  test('discardSuggestion loescht nur Vorschlaege', () async {
    final repo = inventoryRepo(db);
    await db.into(db.inventoryItems).insert(InventoryItem(
          id: 'sugg', householdId: 'h1', productId: productId, quantity: 1, unit: 'piece', location: 'pantry',
          purchasedOn: _d(2026, 9, 27), dateKind: 'best_before', status: 'sealed', isSuggestion: true, updatedAt: DateTime.utc(2026),
        ));
    await repo.discardSuggestion('sugg');
    expect((await (db.select(db.inventoryItems)..where((i) => i.id.equals('sugg'))).getSingle()).deletedAt, isNotNull);

    final real = await repo.recordFromScan(productId: productId, ean: '1', now: DateTime.utc(2026, 9, 27));
    await repo.discardSuggestion(real.id); // kein Vorschlag: kein Effekt
    expect((await (db.select(db.inventoryItems)..where((i) => i.id.equals(real.id))).getSingle()).deletedAt, isNull);
  });

  group('discardSuggestionsForReceiptItems (Fehlerbericht "Bonartikel Vorschlag doppelt", 2026-09-28)', () {
    test('verwirft nur unbestaetigte Vorschlaege der angegebenen Bon-Positionen', () async {
      final repo = inventoryRepo(db);
      final suggestion = await repo.createSuggestionFromReceipt(
        productId: productId, receiptItemId: 'ri1', quantity: 1, unit: 'piece', purchasedOn: _d(2026, 9, 20),
      );
      final other = await repo.createSuggestionFromReceipt(
        productId: productId, receiptItemId: 'ri2', quantity: 1, unit: 'piece', purchasedOn: _d(2026, 9, 20),
      );

      await repo.discardSuggestionsForReceiptItems(['ri1']);

      expect((await (db.select(db.inventoryItems)..where((i) => i.id.equals(suggestion.id))).getSingle()).deletedAt, isNotNull);
      expect((await (db.select(db.inventoryItems)..where((i) => i.id.equals(other.id))).getSingle()).deletedAt, isNull);
    });

    test('laesst bereits bestaetigte Inventar-Eintraege unangetastet', () async {
      final repo = inventoryRepo(db);
      final suggestion = await repo.createSuggestionFromReceipt(
        productId: productId, receiptItemId: 'ri1', quantity: 1, unit: 'piece', purchasedOn: _d(2026, 9, 20),
      );
      final confirmed = await repo.recordFromScan(productId: productId, ean: '1', now: DateTime.utc(2026, 9, 21));
      expect(confirmed.id, suggestion.id); // verfeinert die Vorlage, jetzt keine Vorschlag mehr

      await repo.discardSuggestionsForReceiptItems(['ri1']);
      expect((await (db.select(db.inventoryItems)..where((i) => i.id.equals(confirmed.id))).getSingle()).deletedAt, isNull);
    });

    test('leere Liste: kein Effekt', () async {
      await inventoryRepo(db).discardSuggestionsForReceiptItems(const []);
    });
  });

  group('createSuggestionFromReceipt ist idempotent ueber receiptItemId (Gesamtkonzept Artikel<->Bon, 2026-09-28)', () {
    test('zweiter Aufruf fuer dieselbe Bon-Position legt keinen zweiten Eintrag an', () async {
      final repo = inventoryRepo(db);
      final first = await repo.createSuggestionFromReceipt(
        productId: productId, receiptItemId: 'ri1', quantity: 1, unit: 'piece', purchasedOn: _d(2026, 9, 20),
      );
      final second = await repo.createSuggestionFromReceipt(
        productId: productId, receiptItemId: 'ri1', quantity: 1, unit: 'piece', purchasedOn: _d(2026, 9, 20),
      );

      expect(second.id, first.id);
      expect(await (db.select(db.inventoryItems)..where((i) => i.receiptItemId.equals('ri1'))).get(), hasLength(1));
      expect(await db.select(db.inventoryMovements).get(), hasLength(1)); // keine doppelte Kaufbewegung
    });

    test('reaktiviert einen zuvor verworfenen Vorschlag, statt eine zweite Zeile anzulegen '
        '(z.B. Bon geloescht und derselbe Bon erneut importiert)', () async {
      final repo = inventoryRepo(db);
      final first = await repo.createSuggestionFromReceipt(
        productId: productId, receiptItemId: 'ri1', quantity: 1, unit: 'piece', purchasedOn: _d(2026, 9, 20),
      );
      await repo.discardSuggestionsForReceiptItems(['ri1']);
      expect((await (db.select(db.inventoryItems)..where((i) => i.id.equals(first.id))).getSingle()).deletedAt, isNotNull);

      final again = await repo.createSuggestionFromReceipt(
        productId: productId, receiptItemId: 'ri1', quantity: 1, unit: 'piece', purchasedOn: _d(2026, 9, 20),
      );

      expect(again.id, first.id);
      final row = await (db.select(db.inventoryItems)..where((i) => i.id.equals(first.id))).getSingle();
      expect(row.deletedAt, isNull); // reaktiviert
      expect(await (db.select(db.inventoryItems)..where((i) => i.receiptItemId.equals('ri1'))).get(), hasLength(1));
    });

    test('bereits bestaetigter Eintrag bleibt unangetastet, auch bei erneutem Import derselben Position', () async {
      final repo = inventoryRepo(db);
      final suggestion = await repo.createSuggestionFromReceipt(
        productId: productId, receiptItemId: 'ri1', quantity: 1, unit: 'piece', purchasedOn: _d(2026, 9, 20),
      );
      final confirmed = await repo.recordFromScan(productId: productId, ean: '1', quantity: 3, location: 'fridge', now: DateTime.utc(2026, 9, 21));
      expect(confirmed.id, suggestion.id);
      final movementsBefore = await db.select(db.inventoryMovements).get();

      final again = await repo.createSuggestionFromReceipt(
        productId: productId, receiptItemId: 'ri1', quantity: 1, unit: 'piece', purchasedOn: _d(2026, 9, 20),
      );

      expect(again.id, confirmed.id);
      expect(again.isSuggestion, isFalse); // bleibt bestaetigt
      final row = await (db.select(db.inventoryItems)..where((i) => i.id.equals(confirmed.id))).getSingle();
      expect((row.quantity, row.location), (3.0, 'fridge')); // Nutzerangaben unveraendert
      expect(await db.select(db.inventoryMovements).get(), hasLength(movementsBefore.length)); // keine zusaetzliche Kaufbewegung
    });
  });

  group('confirmedItemsLinkedTo / clearReceiptLinksFor (Fehlerbericht "Bon löschen verwirft keine Zuordnung", 2026-09-28)', () {
    test('findet nur bestaetigte Eintraege der angegebenen Bon-Positionen, keine Vorschlaege', () async {
      final repo = inventoryRepo(db);
      final suggestion = await repo.createSuggestionFromReceipt(
        productId: productId, receiptItemId: 'ri1', quantity: 1, unit: 'piece', purchasedOn: _d(2026, 9, 20),
      );
      final other = await repo.createSuggestionFromReceipt(
        productId: productId, receiptItemId: 'ri2', quantity: 1, unit: 'piece', purchasedOn: _d(2026, 9, 20),
      );
      final confirmed = await repo.recordFromScan(productId: productId, ean: '1', now: DateTime.utc(2026, 9, 21));
      expect(confirmed.id, suggestion.id); // verfeinert ri1 zum bestaetigten Eintrag

      final linked = await repo.confirmedItemsLinkedTo(['ri1', 'ri2']);
      expect(linked.map((i) => i.id), [confirmed.id]);
      expect(other.isSuggestion, isTrue); // ri2 bleibt Vorschlag, taucht nicht auf
    });

    test('leere Liste: keine Treffer', () async {
      expect(await inventoryRepo(db).confirmedItemsLinkedTo(const []), isEmpty);
    });

    test('clearReceiptLinksFor loest die Zuordnung, der Bestand bleibt bestehen', () async {
      final repo = inventoryRepo(db);
      final suggestion = await repo.createSuggestionFromReceipt(
        productId: productId, receiptItemId: 'ri1', quantity: 1, unit: 'piece', purchasedOn: _d(2026, 9, 20),
      );
      final confirmed = await repo.recordFromScan(productId: productId, ean: '1', now: DateTime.utc(2026, 9, 21));
      expect(confirmed.id, suggestion.id);

      await repo.clearReceiptLinksFor(['ri1']);

      final row = await (db.select(db.inventoryItems)..where((i) => i.id.equals(confirmed.id))).getSingle();
      expect(row.receiptItemId, isNull);
      expect(row.deletedAt, isNull); // Bestand bleibt erhalten
    });
  });

  group('suggestionsSnapshot (Fehlerbericht "keine Push-Benachrichtigung", 2026-09-28)', () {
    test('liefert unbestaetigte Vorschlaege, keine bestaetigten oder geloeschten Eintraege', () async {
      final repo = inventoryRepo(db);
      final suggestion = await repo.createSuggestionFromReceipt(
        productId: productId, receiptItemId: 'ri1', quantity: 1, unit: 'piece', purchasedOn: _d(2026, 9, 20),
      );
      final confirmedProductId = (await productRepo(db).create(name: 'Anderes Produkt', baseUnit: 'piece')).id;
      await repo.recordFromScan(productId: confirmedProductId, ean: '1', now: DateTime.utc(2026, 9, 21));
      final discarded = await repo.createSuggestionFromReceipt(
        productId: productId, receiptItemId: 'ri2', quantity: 1, unit: 'piece', purchasedOn: _d(2026, 9, 20),
      );
      await repo.discardSuggestion(discarded.id);

      final snapshot = await repo.suggestionsSnapshot();
      expect(snapshot.map((i) => i.id), [suggestion.id]);
    });
  });

  group('deleteItem', () {
    test('loescht den Eintrag und seine Kaufbewegung, so als waere der Scan nie passiert', () async {
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: productId, ean: '1', quantity: 2, now: DateTime.utc(2026, 9, 27));
      expect(await db.select(db.inventoryMovements).get(), hasLength(1));

      await repo.deleteItem(item.id);
      final row = await (db.select(db.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
      expect(row.deletedAt, isNotNull);
      expect(await (db.select(db.inventoryMovements)..where((m) => m.deletedAt.isNull())).get(), isEmpty);
      expect(await repo.watchActive().first, isEmpty);
    });

    test('spaetere Bewegungen (z.B. eine Korrektur) werden ebenfalls entfernt', () async {
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: productId, ean: '1', quantity: 2, now: DateTime.utc(2026, 9, 27));
      await repo.adjustQuantity(item.id, 5);
      expect(await db.select(db.inventoryMovements).get(), hasLength(2));

      await repo.deleteItem(item.id);
      expect(await (db.select(db.inventoryMovements)..where((m) => m.deletedAt.isNull())).get(), isEmpty);
    });

    test('landet in der Outbox (Eintrag und Bewegung)', () async {
      final repo = inventoryRepo(db);
      final item = await repo.recordFromScan(productId: productId, ean: '1', now: DateTime.utc(2026, 9, 27));
      await db.delete(db.outbox).go();
      await repo.deleteItem(item.id);
      final tables = (await db.select(db.outbox).get()).map((o) => o.remoteTable).toSet();
      expect(tables, {'inventory_items', 'inventory_movements'});
    });
  });

  group('Sync', () {
    test('Inventareintrag und Bewegung kommen auf einem zweiten Geraet an', () async {
      final remote = FakeRemoteStore();
      final repo = inventoryRepo(db);
      await productRepo(db).linkBarcode('9008700000003', productId); // damit db2 dasselbe Produkt kennt
      await SyncEngine(db, remote).sync();
      final item = await repo.recordFromScan(productId: productId, ean: '9008700000003', bestBefore: _d(2026, 10, 10), now: DateTime.utc(2026, 9, 27));
      await SyncEngine(db, remote).sync();

      final db2 = memoryDb();
      addTearDown(db2.close);
      await SyncEngine(db2, remote).sync();
      final synced = await (db2.select(db2.inventoryItems)..where((i) => i.id.equals(item.id))).getSingle();
      expect(synced.expiresOn, _d(2026, 10, 10));
      expect(await db2.select(db2.inventoryMovements).get(), hasLength(1));
    });
  });
}
