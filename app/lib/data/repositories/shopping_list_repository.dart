import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../local/database.dart';
import '../sync/mappers.dart';

/// Einkaufsliste (Doku 06 §6/§7, Lastenheft LH-SHO-01/02, Roadmap Phase 3). MVP: genau eine Standardliste
/// je Haushalt, angelegt beim ersten Eintrag. Eintraege sind entweder an ein Produkt gebunden oder frei
/// getippt; automatische Vorschlaege (`isSuggestion = true`) warten auf Bestaetigung, bevor sie wie ein
/// normaler Eintrag zaehlen.
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

  Future<String> _loadOrCreateDefaultList() async {
    final hid = await householdId();
    final existing = await (_db.select(_db.shoppingLists)
          ..where((l) => l.householdId.equals(hid) & l.isDefault.equals(true) & l.deletedAt.isNull()))
        .getSingleOrNull();
    if (existing != null) return existing.id;
    final list = ShoppingList(id: _uuid.v4(), householdId: hid, name: 'Einkaufsliste', isDefault: true, updatedAt: DateTime.now().toUtc());
    await _put('shopping_lists', list.id, shoppingListToRemote(list), () => _db.into(_db.shoppingLists).insertOnConflictUpdate(list.toCompanion(false)));
    return list.id;
  }

  /// Legt einen Eintrag manuell an (LH-SHO-01): entweder an ein Produkt gebunden oder frei getippt.
  Future<ShoppingListItem> addManual({String? productId, String? freeText, double quantity = 1, String unit = 'piece'}) async {
    assert(productId != null || freeText != null, 'Entweder productId oder freeText angeben');
    final hid = await householdId();
    final listId = await _defaultListId();
    final item = ShoppingListItem(
      id: _uuid.v4(),
      householdId: hid,
      listId: listId,
      productId: productId,
      freeText: freeText,
      quantity: quantity,
      unit: unit,
      checked: false,
      source: 'manual',
      isSuggestion: false,
      updatedAt: DateTime.now().toUtc(),
    );
    await _putItem(item);
    onChanged?.call();
    return item;
  }

  /// Abhaken/wieder aktivieren (LH-SHO-01).
  Future<void> setChecked(String id, bool checked) async {
    final item = await _get(id);
    await _putItem(item.copyWith(checked: checked, updatedAt: DateTime.now().toUtc()));
    onChanged?.call();
  }

  /// Anzahl aendern (wie viele Packungen/Stueck gekauft werden sollen). Die Gesamtmenge ergibt sich daraus
  /// zusammen mit dem Inhalt des Produkts (`products.pack_size`), siehe `shopping_list_page.dart`.
  Future<void> setQuantity(String id, double quantity) async {
    final item = await _get(id);
    await _putItem(item.copyWith(quantity: quantity, updatedAt: DateTime.now().toUtc()));
    onChanged?.call();
  }

  /// Bon-Import (Doku 06 §7): ein gekauftes Produkt hakt seine offenen, schon bestaetigten Eintraege
  /// automatisch ab. Unbestaetigte Vorschlaege (`isSuggestion = true`) bleiben unangetastet, die entscheidet
  /// der Nutzer weiterhin selbst. Schliesst den Kreis Liste -> Einkauf -> Bon -> Inventar -> Ablauf -> Liste.
  Future<void> checkOffForProduct(String productId) async {
    final open = await (_db.select(_db.shoppingListItems)
          ..where((i) => i.productId.equals(productId) & i.deletedAt.isNull() & i.checked.equals(false) & i.isSuggestion.equals(false)))
        .get();
    if (open.isEmpty) return;
    final now = DateTime.now().toUtc();
    for (final item in open) {
      await _putItem(item.copyWith(checked: true, updatedAt: now));
    }
    onChanged?.call();
  }

  /// Loeschen (LH-SHO-01), auch fuer das Verwerfen eines Vorschlags.
  Future<void> delete(String id) async {
    final item = await _get(id);
    await _putItem(item.copyWith(deletedAt: Value(DateTime.now().toUtc()), updatedAt: DateTime.now().toUtc()));
    onChanged?.call();
  }

  /// Bestaetigt einen automatischen Vorschlag: zaehlt danach wie ein normaler Eintrag (Doku 06 §6).
  Future<void> confirmSuggestion(String id) async {
    final item = await _get(id);
    await _putItem(item.copyWith(isSuggestion: false, updatedAt: DateTime.now().toUtc()));
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
      updatedAt: DateTime.now().toUtc(),
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
      updatedAt: DateTime.now().toUtc(),
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
          createdAt: DateTime.now().toUtc(),
        ));
  }
}
