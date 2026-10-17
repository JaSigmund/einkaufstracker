import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/clock.dart';
import '../../domain/shopping_list/list_price_estimate.dart';
import '../local/database.dart';
import '../sync/mappers.dart';

/// Einkaufsliste (Doku 06 §6/§7, Lastenheft LH-SHO-01/02, Roadmap Phase 3). Jeder Haushalt hat eine Standardliste, angelegt beim ersten
/// Eintrag, und seit 1.14 auf Wunsch weitere (z.B. Drogerie, Baumarkt). Vorschlaege und Erinnerungen landen immer auf der
/// Standardliste. Eintraege sind entweder an ein Produkt gebunden oder frei getippt; automatische Vorschlaege (`isSuggestion = true`)
/// warten auf Bestaetigung, bevor sie wie ein normaler Eintrag zaehlen.
class ShoppingListRepository {
  ShoppingListRepository(this._db, {required this.householdId, this.onChanged, Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Future<String> Function() householdId;
  final void Function()? onChanged;
  final Uuid _uuid;
  Future<String>? _listIdFuture;

  Stream<List<ShoppingListItem>> watchItems() =>
      (_db.select(_db.shoppingListItems)..where((i) => i.deletedAt.isNull())).watch();

  Future<String> _defaultListId() => _listIdFuture ??= _loadOrCreateDefaultList();

  /// Die Standardliste (wird beim ersten Aufruf angelegt).
  Future<String> defaultListId() => _defaultListId();

  /// Alle nicht geloeschten Listen, die Standardliste zuerst, dann alphabetisch.
  Stream<List<ShoppingList>> watchLists() => (_db.select(_db.shoppingLists)..where((l) => l.deletedAt.isNull())).watch().map((rows) {
        final sorted = [...rows]..sort((a, b) {
            if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
        return sorted;
      });

  /// Legt eine weitere Liste an. Der Name darf nicht leer sein und nicht schon vergeben (ohne Gross-/Kleinschreibung): [ArgumentError].
  Future<ShoppingList> createList(String name) async {
    final label = _checkedName(name, await _lists());
    final hid = await householdId();
    await _defaultListId(); // die Standardliste gibt es immer vor weiteren
    final list = ShoppingList(id: _uuid.v4(), householdId: hid, name: label, isDefault: false, updatedAt: appClock.now().toUtc());
    await _putList(list);
    onChanged?.call();
    return list;
  }

  /// Benennt eine Liste um (auch die Standardliste). Gleiche Regeln wie bei [createList]; der eigene Name zaehlt nicht als vergeben.
  Future<void> renameList(String id, String name) async {
    final all = await _lists();
    final list = all.where((l) => l.id == id).firstOrNull;
    if (list == null) return;
    final label = _checkedName(name, [for (final l in all) if (l.id != id) l]);
    if (label == list.name) return;
    await _putList(list.copyWith(name: label, updatedAt: appClock.now().toUtc()));
    onChanged?.call();
  }

  /// Loescht eine weitere Liste (nicht die Standardliste). Ihre Eintraege gehen **nicht verloren**: sie wandern auf die Standardliste.
  Future<void> deleteList(String id) async {
    final all = await _lists();
    final list = all.where((l) => l.id == id).firstOrNull;
    if (list == null || list.isDefault) return;
    final defaultId = await _defaultListId();
    final now = appClock.now().toUtc();
    final items = await (_db.select(_db.shoppingListItems)..where((i) => i.listId.equals(id) & i.deletedAt.isNull())).get();
    await _db.transaction(() async {
      for (final i in items) {
        await _putItem(i.copyWith(listId: defaultId, updatedAt: now));
      }
      await _putList(list.copyWith(deletedAt: Value(now), updatedAt: now));
    });
    onChanged?.call();
  }

  /// Verschiebt einen Eintrag auf eine andere Liste (die Ziel-Liste muss es geben).
  Future<void> moveItem(String itemId, String listId) async {
    final target = (await _lists()).where((l) => l.id == listId).firstOrNull;
    if (target == null) throw ArgumentError('Die Liste gibt es nicht');
    final item = await _get(itemId);
    if (item.listId == listId) return;
    await _putItem(item.copyWith(listId: listId, updatedAt: appClock.now().toUtc()));
    onChanged?.call();
  }

  Future<List<ShoppingList>> _lists() => (_db.select(_db.shoppingLists)..where((l) => l.deletedAt.isNull())).get();

  static String _checkedName(String name, List<ShoppingList> others) {
    final label = name.trim();
    if (label.isEmpty) throw ArgumentError('Eine Liste braucht einen Namen');
    if (label.length > 40) throw ArgumentError('Der Name ist zu lang');
    if (others.any((l) => l.name.trim().toLowerCase() == label.toLowerCase())) throw ArgumentError('Eine Liste mit diesem Namen gibt es schon');
    return label;
  }

  Future<void> _putList(ShoppingList list) => _put('shopping_lists', list.id, shoppingListToRemote(list), () => _db.into(_db.shoppingLists).insertOnConflictUpdate(list.toCompanion(false)));

  Future<String> _loadOrCreateDefaultList() async {
    final hid = await householdId();
    final existing = await (_db.select(_db.shoppingLists)
          ..where((l) => l.householdId.equals(hid) & l.isDefault.equals(true) & l.deletedAt.isNull()))
        .getSingleOrNull();
    if (existing != null) return existing.id;
    final list = ShoppingList(id: _uuid.v4(), householdId: hid, name: 'Einkaufsliste', isDefault: true, updatedAt: appClock.now().toUtc());
    await _put('shopping_lists', list.id, shoppingListToRemote(list), () => _db.into(_db.shoppingLists).insertOnConflictUpdate(list.toCompanion(false)));
    return list.id;
  }

  /// Legt einen Eintrag manuell an (LH-SHO-01): entweder an ein Produkt gebunden oder frei getippt.
  Future<ShoppingListItem> addManual({String? productId, String? freeText, double quantity = 1, String unit = 'piece', String? listId}) async {
    assert(productId != null || freeText != null, 'Entweder productId oder freeText angeben');
    final hid = await householdId();
    // eine unbekannte oder geloeschte Liste faellt auf die Standardliste zurueck, statt den Eintrag zu verlieren
    final known = listId == null ? null : (await _lists()).where((l) => l.id == listId).firstOrNull;
    final targetId = known?.id ?? await _defaultListId();
    final item = ShoppingListItem(
      id: _uuid.v4(),
      householdId: hid,
      listId: targetId,
      productId: productId,
      freeText: freeText,
      quantity: quantity,
      unit: unit,
      checked: false,
      source: 'manual',
      isSuggestion: false,
      updatedAt: appClock.now().toUtc(),
    );
    await _putItem(item);
    onChanged?.call();
    return item;
  }

  /// Die unabgehakten Eintraege der Liste (Momentaufnahme), z.B. um Vorschlaege nicht doppelt anzulegen.
  Future<List<ShoppingListItem>> openItems() =>
      (_db.select(_db.shoppingListItems)..where((i) => i.deletedAt.isNull() & i.checked.equals(false))).get();

  /// Setzt mehrere Eintraege auf einmal auf die Liste (z.B. die fehlenden Zutaten einer Mahlzeit): je Eintrag Menge 1, was schon
  /// unabgehakt auf der Liste steht (gleiches Produkt, oder gleicher Freitext ohne Gross-/Kleinschreibung), wird nicht doppelt angelegt.
  /// Gibt die Zahl der neu angelegten Eintraege zurueck und stoesst den Sync nur einmal an.
  Future<int> addMany(Iterable<({String? productId, String? freeText, String unit})> entries) async {
    final open = await (_db.select(_db.shoppingListItems)..where((i) => i.deletedAt.isNull() & i.checked.equals(false))).get();
    final listedProducts = {for (final i in open) if (i.productId != null) i.productId!};
    final listedTexts = {for (final i in open) if (i.freeText != null) i.freeText!.trim().toLowerCase()};
    final hid = await householdId();
    final listId = await _defaultListId();
    var added = 0;
    for (final e in entries) {
      final id = e.productId;
      final text = e.freeText?.trim();
      if (id == null && (text == null || text.isEmpty)) continue;
      if (id != null ? !listedProducts.add(id) : !listedTexts.add(text!.toLowerCase())) continue;
      await _putItem(ShoppingListItem(
        id: _uuid.v4(),
        householdId: hid,
        listId: listId,
        productId: id,
        freeText: id == null ? text : null,
        quantity: 1,
        unit: e.unit,
        checked: false,
        source: 'manual',
        isSuggestion: false,
        updatedAt: appClock.now().toUtc(),
      ));
      added++;
    }
    if (added > 0) onChanged?.call();
    return added;
  }

  /// Abhaken/wieder aktivieren (LH-SHO-01).
  Future<void> setChecked(String id, bool checked) async {
    final item = await _get(id);
    await _putItem(item.copyWith(checked: checked, updatedAt: appClock.now().toUtc()));
    onChanged?.call();
  }

  /// Anzahl aendern (wie viele Packungen/Stueck gekauft werden sollen). Die Gesamtmenge ergibt sich daraus
  /// zusammen mit dem Inhalt des Produkts (`products.pack_size`), siehe `shopping_list_page.dart`.
  Future<void> setQuantity(String id, double quantity) async {
    final item = await _get(id);
    await _putItem(item.copyWith(quantity: quantity, updatedAt: appClock.now().toUtc()));
    onChanged?.call();
  }

  /// Bon-Import (Doku 06 §7): ein gekauftes Produkt hakt seine offenen, schon bestaetigten Eintraege
  /// automatisch ab. Unbestaetigte Vorschlaege (`isSuggestion = true`) bleiben unangetastet, die entscheidet
  /// der Nutzer weiterhin selbst. Schliesst den Kreis Liste -> Einkauf -> Bon -> Inventar -> Ablauf -> Liste.
  ///
  /// Mit [receiptId] und [paidCents] (Zeilensumme dieses Produkts auf dem Bon) wird zusaetzlich festgehalten, was die
  /// abgehakten Eintraege vor dem Einkauf gekostet haetten (zuletzt bezahlter Grundpreis VOR diesem Bon) und was sie
  /// tatsaechlich gekostet haben: Ist-Soll-Abgleich, siehe [comparisonFor].
  Future<void> checkOffForProduct(String productId, {String? receiptId, int? paidCents}) async {
    final open = await (_db.select(_db.shoppingListItems)
          ..where((i) => i.productId.equals(productId) & i.deletedAt.isNull() & i.checked.equals(false) & i.isSuggestion.equals(false)))
        .get();
    if (open.isEmpty) return;
    final now = appClock.now().toUtc();
    for (final item in open) {
      await _putItem(item.copyWith(checked: true, updatedAt: now));
    }
    if (receiptId != null && paidCents != null) await _recordComparison(open, productId, receiptId, paidCents);
    onChanged?.call();
  }

  static String _comparisonKey(String receiptId) => 'list_vs_actual:$receiptId';

  /// Der zuletzt bezahlte Grundpreis des Produkts aus einem Bon, der NICHT [excludeReceiptId] ist.
  Future<int?> _priorUnitPrice(String productId, String excludeReceiptId) async {
    final r = _db.receipts;
    final i = _db.receiptItems;
    final row = await (_db.select(i).join([innerJoin(r, r.id.equalsExp(i.receiptId))])
          ..where(i.productId.equals(productId) &
              i.receiptId.equals(excludeReceiptId).not() &
              i.unitPriceNormCents.isNotNull() &
              i.deletedAt.isNull() &
              r.deletedAt.isNull())
          ..orderBy([OrderingTerm.desc(r.purchasedAt)])
          ..limit(1))
        .getSingleOrNull();
    return row?.read(i.unitPriceNormCents);
  }

  Future<void> _recordComparison(List<ShoppingListItem> open, String productId, String receiptId, int paidCents) async {
    final product = await (_db.select(_db.products)..where((p) => p.id.equals(productId))).getSingleOrNull();
    final prior = await _priorUnitPrice(productId, receiptId);
    final estimate = estimateShoppingListTotal([
      for (final item in open) (quantity: item.quantity, packSize: product?.packSize, lastUnitPriceNormCents: prior),
    ]);
    // Ohne bekannten frueheren Preis gibt es nichts zu vergleichen: dieses Produkt zaehlt weder bei "geschaetzt" noch bei
    // "bezahlt", damit beide Seiten dieselben Artikel meinen.
    if (estimate.itemsWithPrice == 0) return;
    final known = await comparisonFor(receiptId);
    final total = (
      estimated: (known?.estimatedCents ?? 0) + estimate.totalCents,
      actual: (known?.actualCents ?? 0) + paidCents,
      items: (known?.items ?? 0) + estimate.itemsWithPrice,
    );
    await _db.setKv(_comparisonKey(receiptId), jsonEncode({'estimated': total.estimated, 'actual': total.actual, 'items': total.items}));
  }

  /// Ist-Soll-Abgleich eines Bons: was die dadurch abgehakten Listeneintraege vor dem Einkauf gekostet haetten und was
  /// auf dem Bon dafuer bezahlt wurde. `null`, wenn der Bon keine Listeneintraege mit bekanntem frueherem Preis abgehakt
  /// hat. Nur auf dem Geraet vorhanden, das den Bon gespeichert hat (nicht synchronisiert).
  Future<ListComparison?> comparisonFor(String receiptId) async {
    final raw = await _db.getKv(_comparisonKey(receiptId));
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return ListComparison(
        estimatedCents: (j['estimated'] as num).toInt(),
        actualCents: (j['actual'] as num).toInt(),
        items: (j['items'] as num).toInt(),
      );
    } on Object {
      return null;
    }
  }

  /// Loeschen (LH-SHO-01), auch fuer das Verwerfen eines Vorschlags.
  Future<void> delete(String id) async {
    final item = await _get(id);
    await _putItem(item.copyWith(deletedAt: Value(appClock.now().toUtc()), updatedAt: appClock.now().toUtc()));
    onChanged?.call();
  }

  /// Nimmt [delete] zurueck ("Rückgängig" nach dem Wischen, Codereview 2026-10-16, X2).
  Future<void> restore(String id) async {
    final item = await _get(id);
    if (item.deletedAt == null) return;
    await _putItem(item.copyWith(deletedAt: const Value(null), updatedAt: appClock.now().toUtc()));
    onChanged?.call();
  }

  /// Bestaetigt einen automatischen Vorschlag: zaehlt danach wie ein normaler Eintrag (Doku 06 §6).
  Future<void> confirmSuggestion(String id) async {
    final item = await _get(id);
    await _putItem(item.copyWith(isSuggestion: false, updatedAt: appClock.now().toUtc()));
    onChanged?.call();
  }

  /// Ein Produkt hat keinen aktiven Bestand mehr: schlaegt es vor, wenn es als Nachkaufprodukt markiert ist
  /// und nicht schon (unbestaetigt oder bestaetigt) auf der Liste steht (Doku 06 §6, Ausloeser "Leer").
  Future<void> suggestDepleted(String productId) async {
    final product = await (_db.select(_db.products)..where((p) => p.id.equals(productId))).getSingleOrNull();
    if (product == null || !product.restock) return;
    final already = await (_db.select(_db.shoppingListItems)
          ..where((i) => i.productId.equals(productId) & i.deletedAt.isNull() & i.checked.equals(false)))
        .get();
    if (already.isNotEmpty) return;
    final hid = await householdId();
    final listId = await _defaultListId();
    final item = ShoppingListItem(
      id: _uuid.v4(),
      householdId: hid,
      listId: listId,
      productId: productId,
      quantity: 1,
      unit: product.baseUnit,
      checked: false,
      source: 'depleted',
      isSuggestion: true,
      updatedAt: appClock.now().toUtc(),
    );
    await _putItem(item);
    onChanged?.call();
  }

  /// Aktion "Auf Liste setzen" aus einer Ablauf-Erinnerung (Doku 06 §5, Schritt 4): der Nutzer hat mit dem
  /// Antippen der Benachrichtigung schon bestaetigt, deshalb kein weiterer Vorschlag noetig, sondern gleich
  /// ein normaler Eintrag. Kein doppelter Eintrag, falls das Produkt schon unbestaetigt auf der Liste steht.
  Future<void> addFromExpiryReminder(String productId) async {
    final product = await (_db.select(_db.products)..where((p) => p.id.equals(productId))).getSingleOrNull();
    if (product == null) return;
    final already = await (_db.select(_db.shoppingListItems)
          ..where((i) => i.productId.equals(productId) & i.deletedAt.isNull() & i.checked.equals(false)))
        .get();
    if (already.isNotEmpty) return;
    final hid = await householdId();
    final listId = await _defaultListId();
    final item = ShoppingListItem(
      id: _uuid.v4(),
      householdId: hid,
      listId: listId,
      productId: productId,
      quantity: 1,
      unit: product.baseUnit,
      checked: false,
      source: 'expiring',
      isSuggestion: false,
      updatedAt: appClock.now().toUtc(),
    );
    await _putItem(item);
    onChanged?.call();
  }

  Future<ShoppingListItem> _get(String id) => (_db.select(_db.shoppingListItems)..where((i) => i.id.equals(id))).getSingle();

  Future<void> _putItem(ShoppingListItem item) => _put(
        'shopping_list_items',
        item.id,
        shoppingListItemToRemote(item),
        () => _db.into(_db.shoppingListItems).insertOnConflictUpdate(item.toCompanion(false)),
      );

  Future<void> _put(String remoteTable, String rowId, Map<String, dynamic> payload, Future<void> Function() writeLocal) async {
    await writeLocal();
    await _db.into(_db.outbox).insert(OutboxCompanion.insert(
          remoteTable: remoteTable,
          rowId: rowId,
          payload: jsonEncode(payload),
          createdAt: appClock.now().toUtc(),
        ));
  }
}

/// Ergebnis des Ist-Soll-Abgleichs fuer einen Bon (siehe [ShoppingListRepository.comparisonFor]).
class ListComparison {
  const ListComparison({required this.estimatedCents, required this.actualCents, required this.items});

  final int estimatedCents;
  final int actualCents;

  /// Anzahl abgehakter Listeneintraege, die in den Vergleich eingehen.
  final int items;

  EstimateVsActual get result => EstimateVsActual(estimatedCents: estimatedCents, actualCents: actualCents);
}
