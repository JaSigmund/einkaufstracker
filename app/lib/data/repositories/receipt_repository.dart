import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/clock.dart';
import '../../domain/categorization/categorizer.dart';
import '../../domain/categorization/normalize_name.dart';
import '../../domain/receipt/parsed_receipt.dart';
import '../../domain/receipt/unit_price.dart';
import '../local/database.dart';
import '../sync/mappers.dart';
import 'inventory_repository.dart';
import 'product_repository.dart';
import 'shopping_list_repository.dart';
import '../../core/vienna_time.dart' show utcToViennaLocal;

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
/// Positionsart fuer Rabatte, die sich auf den ganzen Bon beziehen (Migration 0007).
const billDiscountKind = 'bill_discount';

class ReceiptRepository {
  ReceiptRepository(this._db,
      {required this.householdId, this.onChanged, this.productRepo, this.inventoryRepo, this.shoppingListRepo, Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Future<String> Function() householdId;
  final void Function()? onChanged;
  final Uuid _uuid;

  /// Erzeugen Bon-Vorschlaege im Inventar fuer Positionen lagerbarer Kategorien (Doku 06 §2 Punkt 1).
  /// Ohne diese beiden Abhaengigkeiten (z.B. in aelteren Tests) bleibt das Verhalten wie zuvor: kein Vorschlag.
  final ProductRepository? productRepo;
  final InventoryRepository? inventoryRepo;

  /// Hakt passende offene Einkaufslisten-Eintraege ab (Doku 06 §7). Optional wie die beiden oben, aus
  /// demselben Grund.
  final ShoppingListRepository? shoppingListRepo;

  String _storeId(String hid, String chain, String? branch) =>
      _uuid.v5(Namespace.url.value, 'einkaufstracker:store:$hid:${chain.toLowerCase()}:${branch ?? '-'}');

  String _receiptId(String hid, String externalId) =>
      _uuid.v5(Namespace.url.value, 'einkaufstracker:receipt:$hid:$externalId');

  String _itemId(String receiptId, int lineNo) => _uuid.v5(Namespace.url.value, 'einkaufstracker:item:$receiptId:$lineNo');

  String _aliasId(String hid, String key) => _uuid.v5(Namespace.url.value, 'einkaufstracker:alias:$hid:$key');

  /// Kalendertag des Kaufs in Wiener Ortszeit, als UTC-Mitternacht dieses Tages (Doku FR-07).
  DateTime _viennaDate(DateTime purchasedAtUtc) {
    final local = utcToViennaLocal(purchasedAtUtc);
    return DateTime.utc(local.year, local.month, local.day);
  }

  /// IDs der lagerbaren Kategorien des Haushalts (Doku FR-09), Grundlage fuer die Bon-Vorschlaege im Inventar.
  Future<Set<String>> _storableCategoryIds(String hid) async {
    final cats = await (_db.select(_db.categories)
          ..where((c) => c.householdId.equals(hid) & c.deletedAt.isNull() & c.isStorable.equals(true)))
        .get();
    return {for (final c in cats) c.id};
  }

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

  /// Bereits gespeicherter Bon zum selben Einkauf: gleiche Re-Nr, oder (ohne Re-Nr, z.B. Cloud-Lesung eines
  /// Fotos) gleiche Summe und Kaufzeit auf zwei Minuten genau. So wird ein Papierbon nicht doppelt erfasst,
  /// wenn derselbe Einkauf schon als digitaler Bon vorliegt.
  Future<Receipt?> findDuplicate(ParsedReceipt r) async {
    if (r.externalId != null) {
      final byId = await findByExternalId(r.externalId!);
      if (byId != null) return byId;
    }
    if (r.purchasedAtUtc == null || r.totalCents == null) return null;
    final hid = await householdId();
    final from = r.purchasedAtUtc!.subtract(const Duration(minutes: 2));
    final to = r.purchasedAtUtc!.add(const Duration(minutes: 2));
    final candidates = await (_db.select(_db.receipts)
          ..where((x) =>
              x.householdId.equals(hid) &
              x.deletedAt.isNull() &
              x.totalCents.equals(r.totalCents!) &
              x.purchasedAt.isBetweenValues(from, to)))
        .get();
    return candidates.firstOrNull;
  }

  /// Bereits geloeschter Bon zum selben Einkauf (gleiche Summe und Kaufzeit auf zwei Minuten genau), nur
  /// fuer Bons ohne Re-Nr relevant (Fehlerbericht "Zuordnung bei erneutem Bonscan nicht vorhanden",
  /// 2026-09-28): ein Bon mit Re-Nr bekommt ueber [_receiptId] ohnehin immer dieselbe ID und heilt sich beim
  /// erneuten Import von selbst (voller Upsert loescht `deletedAt`). Ein Foto-Bon ohne Re-Nr bekaeme sonst bei
  /// jedem Import eine neue Zufalls-ID, auch wenn es derselbe Bon ist, der zuvor geloescht wurde — bestaetigte
  /// Inventar-Eintraege blieben dann dauerhaft unverknuepft, und ein noch unbestaetigter Vorschlag wuerde
  /// doppelt angelegt. Wird hier ein Treffer gefunden, verwendet [saveParsed] dessen ID weiter: Positionen
  /// bekommen ueber [_itemId] dieselben IDs wie zuvor und heilen sich auf demselben Weg.
  Future<Receipt?> _findDeletedDuplicate(ParsedReceipt r, String hid) async {
    if (r.purchasedAtUtc == null || r.totalCents == null) return null;
    final from = r.purchasedAtUtc!.subtract(const Duration(minutes: 2));
    final to = r.purchasedAtUtc!.add(const Duration(minutes: 2));
    final candidates = await (_db.select(_db.receipts)
          ..where((x) =>
              x.householdId.equals(hid) &
              x.deletedAt.isNotNull() &
              x.totalCents.equals(r.totalCents!) &
              x.purchasedAt.isBetweenValues(from, to)))
        .get();
    return candidates.firstOrNull;
  }

  /// Nicht geloeschte, bestaetigte Bons, neueste zuerst.
  Stream<List<Receipt>> watchAll() => (_db.select(_db.receipts)
        ..where((r) => r.deletedAt.isNull() & r.status.equals('confirmed'))
        ..orderBy([(r) => OrderingTerm.desc(r.purchasedAt)]))
      .watch();

  Stream<Receipt?> watchReceipt(String id) => (_db.select(_db.receipts)..where((r) => r.id.equals(id))).watchSingleOrNull();

  Stream<List<Store>> watchStores() => (_db.select(_db.stores)..where((s) => s.deletedAt.isNull())).watch();

  /// Einmalige Momentaufnahmen von [watchAll]/[watchStores]/[watchAllItems] (Doku 07 §5 CSV-Export), ohne
  /// eine dauerhafte Abfrage offen zu halten.
  Future<List<Receipt>> allSnapshot() => (_db.select(_db.receipts)
        ..where((r) => r.deletedAt.isNull() & r.status.equals('confirmed'))
        ..orderBy([(r) => OrderingTerm.desc(r.purchasedAt)]))
      .get();

  Future<List<Store>> storesSnapshot() => (_db.select(_db.stores)..where((s) => s.deletedAt.isNull())).get();

  Stream<List<ReceiptItem>> watchItems(String receiptId) => (_db.select(_db.receiptItems)
        ..where((i) => i.receiptId.equals(receiptId) & i.deletedAt.isNull())
        ..orderBy([(i) => OrderingTerm.asc(i.lineNo)]))
      .watch();

  Stream<List<ReceiptFile>> watchFiles(String receiptId) => (_db.select(_db.receiptFiles)
        ..where((f) => f.receiptId.equals(receiptId) & f.deletedAt.isNull())
        ..orderBy([(f) => OrderingTerm.asc(f.pageNo)]))
      .watch();

  Future<List<ReceiptFile>> filesOf(String receiptId) => (_db.select(_db.receiptFiles)
        ..where((f) => f.receiptId.equals(receiptId) & f.deletedAt.isNull())
        ..orderBy([(f) => OrderingTerm.asc(f.pageNo)]))
      .get();

  /// Legt den Verweis auf eine Originaldatei an und stellt ihn in die Outbox.
  Future<void> putFile(ReceiptFile f) async {
    await _put('receipt_files', f.id, receiptFileToRemote(f),
        () => _db.into(_db.receiptFiles).insertOnConflictUpdate(f.toCompanion(false)));
    onChanged?.call();
  }

  /// Alle nicht geloeschten Positionen (fuer die Auswertung; Positionen geloeschter Bons filtert der Aufrufer
  /// ueber die Bonliste).
  Stream<List<ReceiptItem>> watchAllItems() =>
      (_db.select(_db.receiptItems)..where((i) => i.deletedAt.isNull())).watch();

  Future<List<ReceiptItem>> allItemsSnapshot() => (_db.select(_db.receiptItems)..where((i) => i.deletedAt.isNull())).get();

  /// Speichert einen gelesenen Bon als bestaetigt. Ein Bon mit derselben Re-Nr wird nicht doppelt angelegt.
  ///
  /// Bons, die nicht alle Pruefungen bestehen, werden mit `sumMismatch = true` gespeichert (der Nutzer hat
  /// sie in der Pruefansicht bewusst uebernommen). Ob das erlaubt ist, entscheidet die Oberflaeche.
  Future<ReceiptSaveResult> saveParsed(ParsedReceipt r, {String source = 'pdf_text'}) async {
    if (!r.isParsed || r.purchasedAtUtc == null || r.totalCents == null) {
      throw ArgumentError('Der Bon wurde nicht gelesen und kann nicht gespeichert werden.');
    }
    final hid = await householdId();
    final now = appClock.now().toUtc();
    final categorizer = await _buildCategorizer(hid);
    final storableIds = productRepo != null && inventoryRepo != null ? await _storableCategoryIds(hid) : const <String>{};
    final purchasedOn = _viennaDate(r.purchasedAtUtc!);

    final existing = await findDuplicate(r);
    if (existing != null) return ReceiptSaveResult(ReceiptSaveOutcome.duplicate, existing.id);

    final receiptId = r.externalId != null ? _receiptId(hid, r.externalId!) : (await _findDeletedDuplicate(r, hid))?.id ?? _uuid.v4();

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
        // Produkt-Zuordnung und Grundpreis (Doku 07 §3.1) gelten fuer JEDEN Artikel, nicht nur lagerbare
        // Kategorien: Preisvergleich/-verlauf sollen z.B. auch fuer Brot funktionieren, das nicht im
        // Inventar gefuehrt wird.
        Product? product;
        if (i.kind == ReceiptItemKind.article && productRepo != null) {
          product = await productRepo!.findOrCreateForReceiptItem(i.rawText, categoryId: suggestion.categoryId, baseUnit: i.quantityUnit);
        }
        final unitPriceNormCents = product == null
            ? null
            : computeUnitPriceNormCents(
                lineTotalCents: i.lineTotalCents,
                quantity: i.quantity,
                quantityUnit: i.quantityUnit,
                productBaseUnit: product.baseUnit,
                packSize: product.packSize,
              );

        await putItem(ReceiptItem(
          excluded: false,
          id: _itemId(receiptId, lineNo),
          householdId: hid,
          receiptId: receiptId,
          lineNo: lineNo,
          kind: i.kind.name,
          rawText: i.rawText,
          productId: product?.id,
          brand: product?.brand,
          quantity: i.quantity,
          quantityUnit: i.quantityUnit,
          unitPriceCents: i.unitPriceCents,
          lineTotalCents: i.lineTotalCents,
          unitPriceNormCents: unitPriceNormCents,
          taxCode: i.taxCode,
          categoryId: suggestion.categoryId,
          needsReview: i.kind == ReceiptItemKind.article && suggestion.categoryId == null,
          updatedAt: now,
        ));

        // Bon-Vorschlag im Inventar fuer lagerbare Kategorien (Doku 06 §2 Punkt 1): kein MHD, hoechstens
        // eine Schaetzung aus der Standardhaltbarkeit des Produkts.
        if (product != null && suggestion.categoryId != null && storableIds.contains(suggestion.categoryId)) {
          await inventoryRepo!.createSuggestionFromReceipt(
            productId: product.id,
            receiptItemId: _itemId(receiptId, lineNo),
            quantity: i.quantity,
            unit: i.quantityUnit,
            purchasedOn: purchasedOn,
            sealedShelfLifeDays: product.sealedShelfLifeDays,
            dateKind: product.defaultDateKind,
            location: product.defaultLocation,
          );
          // Schliesst den Kreis Liste -> Einkauf -> Bon (Doku 06 §7): offene, bereits bestaetigte
          // Eintraege desselben Produkts gelten damit als erledigt.
          await shoppingListRepo?.checkOffForProduct(product.id, receiptId: receiptId, paidCents: i.lineTotalCents);
        }
      }
      // Rabatte auf Bon-Ebene (z.B. jö Rabattsammler) als eigene Positionen ohne Steuerbuchstaben,
      // damit die Summe aller Positionen der Bon-Summe entspricht
      for (final d in r.bonDiscounts) {
        lineNo++;
        await putItem(ReceiptItem(
          excluded: false,
          id: _itemId(receiptId, lineNo),
          householdId: hid,
          receiptId: receiptId,
          lineNo: lineNo,
          kind: billDiscountKind,
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
    final now = appClock.now().toUtc();
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

  /// Markiert eine Bon-Position als "von jemand anderem bezahlt" (ADR-020 "Rechnungen teilen") oder hebt das
  /// wieder auf. Anders als [setItemCategory] wirkt das nur auf genau diese Position, nicht auf gleiche Artikel:
  /// wer diesmal fuer jemanden bezahlt hat, hat das nicht fuer jeden kuenftigen Kauf getan.
  ///
  /// Bei einem Artikel wandern Rabatte mit, die direkt darunter stehen (`kind == 'discount'`, sie beziehen sich
  /// wie in [categorizeMissing] auf den Artikel darueber): sonst wuerde der Rabatt eines ausgeschlossenen Artikels
  /// die eigene Ausgabe senken. Rabatte auf den ganzen Bon (`bill_discount`) bleiben unberuehrt, siehe ADR-020.
  /// Rueckgabe: Anzahl der geaenderten Positionen (Artikel plus mitgenommene Rabatte).
  Future<int> setItemExcluded(String itemId, bool excluded) async {
    final now = appClock.now().toUtc();
    var changed = 0;
    await _db.transaction(() async {
      final item = await (_db.select(_db.receiptItems)..where((i) => i.id.equals(itemId))).getSingle();
      if (item.kind == billDiscountKind) return;
      final affected = [item];
      if (item.kind == 'article') {
        final following = await (_db.select(_db.receiptItems)
              ..where((i) => i.receiptId.equals(item.receiptId) & i.deletedAt.isNull() & i.lineNo.isBiggerThanValue(item.lineNo))
              ..orderBy([(i) => OrderingTerm.asc(i.lineNo)]))
            .get();
        for (final next in following) {
          if (next.kind != 'discount') break;
          affected.add(next);
        }
      }
      for (final it in affected) {
        if (it.excluded == excluded) continue;
        final updated = it.copyWith(excluded: excluded, updatedAt: now);
        await _put('receipt_items', it.id, receiptItemToRemote(updated),
            () => _db.into(_db.receiptItems).insertOnConflictUpdate(updated.toCompanion(false)));
        changed++;
      }
    });
    if (changed > 0) onChanged?.call();
    return changed;
  }

  /// Ordnet alle noch unzugeordneten Positionen zu (Stichwortregeln und gelernte Zuordnungen), z.B. fuer Bons,
  /// die vor der Kategorisierung importiert wurden. Rabatte uebernehmen die Kategorie des Artikels darueber.
  /// Rueckgabe: Anzahl der geaenderten Positionen.
  Future<int> categorizeMissing() async {
    final hid = await householdId();
    final now = appClock.now().toUtc();
    final categorizer = await _buildCategorizer(hid);
    var changed = await _repairBillDiscounts(hid);
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
          if (category == null && i.kind != billDiscountKind) {
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

  /// Aeltere Bons haben Bon-Rabatte (jö Rabattsammler) als normalen Rabatt gespeichert, der dann per Backfill die
  /// Kategorie des Artikels darueber erbte (z.B. Getraenke). Bei digitalen Bons haben alle Artikel-Rabatte einen
  /// Steuerbuchstaben, ein Rabatt ohne ist daher ein Bon-Rabatt: Art korrigieren, Kategorie entfernen.
  Future<int> _repairBillDiscounts(String hid) async {
    final pdfReceipts = await (_db.select(_db.receipts)
          ..where((r) => r.householdId.equals(hid) & r.deletedAt.isNull() & r.source.equals('pdf_text')))
        .get();
    if (pdfReceipts.isEmpty) return 0;
    final legacy = await (_db.select(_db.receiptItems)
          ..where((i) =>
              i.receiptId.isIn(pdfReceipts.map((r) => r.id)) & i.kind.equals('discount') & i.taxCode.isNull() & i.deletedAt.isNull()))
        .get();
    final now = appClock.now().toUtc();
    for (final i in legacy) {
      final fixed = i.copyWith(kind: billDiscountKind, categoryId: const Value(null), needsReview: false, updatedAt: now);
      await _put('receipt_items', i.id, receiptItemToRemote(fixed),
          () => _db.into(_db.receiptItems).insertOnConflictUpdate(fixed.toCompanion(false)));
    }
    return legacy.length;
  }

  /// Loescht einen Bon samt Positionen (Soft-Delete, wird mit dem Server synchronisiert).
  Future<void> softDelete(String receiptId) async {
    final now = appClock.now().toUtc();
    await _db.transaction(() async {
      final r = await (_db.select(_db.receipts)..where((x) => x.id.equals(receiptId))).getSingleOrNull();
      if (r == null || r.deletedAt != null) return;
      final deleted = r.copyWith(deletedAt: Value(now), updatedAt: now);
      await _put('receipts', r.id, receiptToRemote(deleted),
          () => _db.into(_db.receipts).insertOnConflictUpdate(deleted.toCompanion(false)));
      final files = await (_db.select(_db.receiptFiles)..where((f) => f.receiptId.equals(receiptId) & f.deletedAt.isNull())).get();
      for (final f in files) {
        final df = f.copyWith(deletedAt: Value(now), updatedAt: now);
        await _put('receipt_files', f.id, receiptFileToRemote(df),
            () => _db.into(_db.receiptFiles).insertOnConflictUpdate(df.toCompanion(false)));
      }
      final items = await (_db.select(_db.receiptItems)..where((i) => i.receiptId.equals(receiptId) & i.deletedAt.isNull())).get();
      for (final i in items) {
        final di = i.copyWith(deletedAt: Value(now), updatedAt: now);
        await _put('receipt_items', i.id, receiptItemToRemote(di),
            () => _db.into(_db.receiptItems).insertOnConflictUpdate(di.toCompanion(false)));
      }
      // Noch unbestaetigte Inventar-Vorschlaege dieser Positionen verschwinden mit dem Bon, sonst entsteht
      // beim erneuten Import derselben Position ein doppelter Vorschlag (Fehlerbericht 2026-09-28).
      await inventoryRepo?.discardSuggestionsForReceiptItems(items.map((i) => i.id));
    });
    onChanged?.call();
  }

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
