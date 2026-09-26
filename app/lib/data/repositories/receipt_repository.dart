import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/categorization/categorizer.dart';
import '../../domain/categorization/normalize_name.dart';
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

  String _aliasId(String hid, String key) => _uuid.v5(Namespace.url.value, 'einkaufstracker:alias:$hid:$key');

  /// Kategorisierer aus den Kategorien und den gelernten Zuordnungen des Haushalts.
  Future<Categorizer> _buildCategorizer(String hid) async {
    final cats = await (_db.select(_db.categories)..where((c) => c.householdId.equals(hid) & c.deletedAt.isNull())).get();
    final ids = {for (final c in cats) c.id};
    final aliases = await (_db.select(_db.categoryAliases)..where((a) => a.householdId.equals(hid) & a.deletedAt.isNull())).get();
    return Categorizer(
      categoryIdByName: {for (final c in cats) c.name: c.id},
      // nur Zuordnungen auf noch vorhandene Kategorien
      aliasCategoryIdByKey: {for (final a in aliases.where((a) => ids.contains(a.categoryId))) a.aliasText: a.categoryId},
    );
  }

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
    final categorizer = await _buildCategorizer(hid);
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

      // Rabatte uebernehmen die Kategorie des Artikels darueber (Doku 02 FR-02), Pfand bekommt "Pfand"
      String? lastArticleCategory;
      for (final i in r.items) {
        lineNo++;
        final CategorySuggestion suggestion;
        switch (i.kind) {
          case ReceiptItemKind.deposit:
            suggestion = categorizer.categorize(i.rawText, isDeposit: true);
          case ReceiptItemKind.discount:
            suggestion = CategorySuggestion(lastArticleCategory, lastArticleCategory == null ? CategorySource.none : CategorySource.inherited);
          case ReceiptItemKind.article:
            suggestion = categorizer.categorize(i.rawText);
            lastArticleCategory = suggestion.categoryId;
        }
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
          categoryId: suggestion.categoryId,
          needsReview: i.kind == ReceiptItemKind.article && suggestion.categoryId == null,
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

  /// Der Nutzer ordnet eine Position einer Kategorie zu. Die App lernt daraus: Der normalisierte Name wird als
  /// Alias gemerkt, und alle Artikel mit demselben Namen (auch auf anderen Bons) bekommen dieselbe Kategorie.
  /// Rueckgabe: Anzahl der geaenderten Positionen.
  Future<int> setItemCategory(String itemId, String categoryId) async {
    final hid = await householdId();
    final now = DateTime.now().toUtc();
    var changed = 0;
    await _db.transaction(() async {
      final item = await (_db.select(_db.receiptItems)..where((i) => i.id.equals(itemId))).getSingle();
      final key = normalizeItemName(item.rawText);

      Future<void> assign(ReceiptItem it) async {
        final updated = it.copyWith(categoryId: Value(categoryId), needsReview: false, updatedAt: now);
        await _put('receipt_items', it.id, receiptItemToRemote(updated),
            () => _db.into(_db.receiptItems).insertOnConflictUpdate(updated.toCompanion(false)));
        changed++;
      }

      await assign(item);

      if (key.isNotEmpty && item.kind == 'article') {
        // Alias lernen (oder bestaetigen)
        final aliasId = _aliasId(hid, key);
        final existing = await (_db.select(_db.categoryAliases)..where((a) => a.id.equals(aliasId))).getSingleOrNull();
        final alias = CategoryAlias(
          id: aliasId,
          householdId: hid,
          aliasText: key,
          categoryId: categoryId,
          hits: (existing != null && existing.deletedAt == null && existing.categoryId == categoryId) ? existing.hits + 1 : 1,
          updatedAt: now,
        );
        await _put('category_aliases', aliasId, categoryAliasToRemote(alias),
            () => _db.into(_db.categoryAliases).insertOnConflictUpdate(alias.toCompanion(false)));

        // Gleiche Artikel auf anderen (oder demselben) Bons nachziehen
        final others = await (_db.select(_db.receiptItems)
              ..where((i) => i.householdId.equals(hid) & i.kind.equals('article') & i.deletedAt.isNull() & i.id.equals(itemId).not()))
            .get();
        for (final o in others) {
          if (normalizeItemName(o.rawText) == key && o.categoryId != categoryId) await assign(o);
        }
      }
    });
    onChanged?.call();
    return changed;
  }

  /// Ordnet alle noch unzugeordneten Positionen zu (Stichwortregeln und gelernte Zuordnungen), z.B. fuer Bons,
  /// die vor der Kategorisierung importiert wurden. Rabatte uebernehmen die Kategorie des Artikels darueber.
  /// Rueckgabe: Anzahl der geaenderten Positionen.
  Future<int> categorizeMissing() async {
    final hid = await householdId();
    final now = DateTime.now().toUtc();
    final categorizer = await _buildCategorizer(hid);
    var changed = 0;
    await _db.transaction(() async {
      final receipts = await (_db.select(_db.receipts)..where((r) => r.householdId.equals(hid) & r.deletedAt.isNull())).get();
      for (final r in receipts) {
        final items = await (_db.select(_db.receiptItems)
              ..where((i) => i.receiptId.equals(r.id) & i.deletedAt.isNull())
              ..orderBy([(i) => OrderingTerm.asc(i.lineNo)]))
            .get();
        String? lastArticleCategory;
        for (final i in items) {
          String? category = i.categoryId;
          if (category == null) {
            final CategorySuggestion s;
            switch (i.kind) {
              case 'deposit':
                s = categorizer.categorize(i.rawText, isDeposit: true);
              case 'discount':
                s = CategorySuggestion(lastArticleCategory, CategorySource.inherited);
              default:
                s = categorizer.categorize(i.rawText);
            }
            if (s.categoryId != null) {
              category = s.categoryId;
              final updated = i.copyWith(categoryId: Value(category), needsReview: false, updatedAt: now);
              await _put('receipt_items', i.id, receiptItemToRemote(updated),
                  () => _db.into(_db.receiptItems).insertOnConflictUpdate(updated.toCompanion(false)));
              changed++;
            }
          }
          if (i.kind == 'article') lastArticleCategory = category;
        }
      }
    });
    if (changed > 0) onChanged?.call();
    return changed;
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
