import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/categorization/name_similarity.dart';
import '../../domain/categorization/normalize_name.dart';
import '../../domain/categorization/off_category_map.dart';
import '../../domain/inventory/shelf_life_rules.dart';
import '../local/database.dart';
import '../nutrition/bls_food_search.dart';
import '../products/off_client.dart';
import '../sync/mappers.dart';

/// Ergebnis eines Barcode-Scans: bekanntes Produkt, oder Lookup-Ergebnis fuer die manuelle Anlage.
class BarcodeLookupResult {
  const BarcodeLookupResult({this.product, this.offSuggestion});

  /// Bereits verknuepftes Produkt (lokale Zuordnung oder frueher schon einmal angelegt).
  final Product? product;

  /// Vorschlag von Open Food Facts, falls kein lokales Produkt gefunden wurde.
  final OffProduct? offSuggestion;

  bool get isKnown => product != null;
}

/// Produkte, Barcode-Zuordnung und der OFF-Lookup (Doku 06 §4). Schreibt immer lokal zuerst und stellt die
/// Aenderung in die Outbox (offline-first, wie die anderen Repositories).
class ProductRepository {
  ProductRepository(this._db, {required this.householdId, this.off, this.onChanged, Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Future<String> Function() householdId;

  /// Null = nur lokaler Cache, kein Netz-Lookup (z.B. in Tests).
  final OffClient? off;
  final void Function()? onChanged;
  final Uuid _uuid;

  Stream<List<Product>> watchAll() => (_db.select(_db.products)..where((p) => p.deletedAt.isNull())).watch();

  /// Einmalige Momentaufnahme von [watchAll], ohne eine dauerhafte Abfrage offen zu halten.
  Future<List<Product>> allSnapshot() => (_db.select(_db.products)..where((p) => p.deletedAt.isNull())).get();

  /// Gelernte Bon-Text-Zuordnungen dieses Produkts (ADR-010), damit sie sich nachtraeglich loesen lassen
  /// (Fehlerbericht "Alias ändern", 2026-09-27) statt fuer immer gebunden zu sein.
  Stream<List<ProductAlias>> watchAliasesFor(String productId) => (_db.select(_db.productAliases)
        ..where((a) => a.productId.equals(productId) & a.deletedAt.isNull())
        ..orderBy([(a) => OrderingTerm.desc(a.updatedAt)]))
      .watch();

  /// Loest eine gelernte Zuordnung: der Bon-Text wird beim naechsten Mal wieder als neues/anderes Produkt
  /// vorgeschlagen, statt automatisch an dieses Produkt gehaengt zu werden.
  Future<void> removeAlias(String aliasId) async {
    final alias = await (_db.select(_db.productAliases)..where((a) => a.id.equals(aliasId))).getSingle();
    final updated = alias.copyWith(deletedAt: Value(DateTime.now().toUtc()), updatedAt: DateTime.now().toUtc());
    await _put('product_aliases', updated.id, productAliasToRemote(updated), () => _db.into(_db.productAliases).insertOnConflictUpdate(updated.toCompanion(false)));
    onChanged?.call();
  }

  Future<Product?> byId(String id) => (_db.select(_db.products)..where((p) => p.id.equals(id))).getSingleOrNull();

  /// Produkte, deren Name den Suchtext enthaelt (fuer Autovervollstaendigung, Einkaufsliste).
  Future<List<Product>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final hid = await householdId();
    return (_db.select(_db.products)
          ..where((p) => p.householdId.equals(hid) & p.deletedAt.isNull() & p.name.lower().contains(q.toLowerCase()))
          ..orderBy([(p) => OrderingTerm.asc(p.name)])
          ..limit(20))
        .get();
  }

  /// Produkte ohne Barcode, zuletzt geaendert zuerst - typischerweise Bon-Vorschlaege, die noch nie gescannt
  /// wurden. Als Vorauswahl beim Verknuepfen eines unbekannten Barcodes (Fehlerbericht "Keine Bonzuordnung"/
  /// "Automatische Bonzuordnung", 2026-09-28), damit der Nutzer nicht zwingend selbst tippen muss.
  Future<List<Product>> recentUnlinked({int limit = 10}) async {
    final hid = await householdId();
    final linked = _db.selectOnly(_db.productBarcodes)
      ..addColumns([_db.productBarcodes.productId])
      ..where(_db.productBarcodes.householdId.equals(hid));
    final linkedIds = (await linked.map((r) => r.read(_db.productBarcodes.productId)!).get()).toSet();
    final all = await (_db.select(_db.products)
          ..where((p) => p.householdId.equals(hid) & p.deletedAt.isNull())
          ..orderBy([(p) => OrderingTerm.desc(p.updatedAt)])
          ..limit(limit + linkedIds.length))
        .get();
    return all.where((p) => !linkedIds.contains(p.id)).take(limit).toList();
  }

  /// Sucht den EAN zuerst lokal (schon einmal zugeordnet), dann bei Open Food Facts. Das lokale Produkt hat
  /// immer Vorrang, auch offline verfuegbar; OFF wird nur befragt, wenn nichts gefunden wurde.
  Future<BarcodeLookupResult> lookup(String ean) async {
    final hid = await householdId();
    final mapping = await (_db.select(_db.productBarcodes)..where((b) => b.householdId.equals(hid) & b.ean.equals(ean))).getSingleOrNull();
    if (mapping != null) {
      final p = await byId(mapping.productId);
      if (p != null && p.deletedAt == null) return BarcodeLookupResult(product: p);
    }
    final suggestion = off == null ? null : await off!.lookup(ean);
    if (suggestion != null) {
      final matched = await matchByLearnedName(suggestion.name);
      if (matched != null) {
        await linkBarcode(ean, matched.id);
        return BarcodeLookupResult(product: matched);
      }
    }
    return BarcodeLookupResult(offSuggestion: suggestion);
  }

  /// Bon-Position (Doku 06 §2, ADR-010): gelernter Alias -> vorhandenes Produkt, sonst neu angelegt und
  /// die Zuordnung gemerkt. Haendlerunabhaengig gelernt (storeId bleibt in der Zuordnung leer), damit
  /// derselbe Artikel bei jedem Haendler wiedererkannt wird.
  Future<Product> findOrCreateForReceiptItem(String rawText, {String? categoryId, String baseUnit = 'piece'}) async {
    final hid = await householdId();
    final key = normalizeItemName(rawText);
    final alias = await _activeAliasFor(hid, key);
    if (alias != null) {
      final p = await byId(alias.productId);
      if (p != null && p.deletedAt == null) return p;
    }

    // Kein exakter Treffer: ein einzelnes OCR-Leerzeichen oder ein Tippfehler darf trotzdem kein neues
    // Duplikat anlegen (ADR-023, Fehlerbericht "Faschiertes"/"Faschi ertes", 2026-10-01). Konservative,
    // laengenabhaengige Toleranz -- siehe name_similarity.dart.
    final fuzzyMatch = closestWithinTolerance(key, await _activeAliasKeys(hid));
    if (fuzzyMatch != null) {
      final fuzzyAlias = await _activeAliasFor(hid, fuzzyMatch);
      final p = fuzzyAlias == null ? null : await byId(fuzzyAlias.productId);
      if (p != null && p.deletedAt == null) {
        await _learnAlias(key, p.id, hid);
        return p;
      }
    }

    // Waegware (Obst, Gemuese, Kaese am Stueck ...) steht im Bon in kg: das gleich als Grundeinheit setzen,
    // statt bei "Stueck" zu bleiben (Fehlerbericht "Bonartikel bearbeiten", 2026-09-27).
    // Haltbarkeit nach dem Oeffnen, Lagerort und Datumsart aus den Startwerten der Roadmap-Phase 3
    // (Doku 06 §3.2) vorbelegen, damit nicht jedes Bon-Produkt erst manuell nachgepflegt werden muss.
    final shelfLife = suggestShelfLife(rawText);
    final product = await create(
      name: _cleanName(rawText),
      categoryId: categoryId,
      baseUnit: baseUnit,
      openedShelfLifeDays: shelfLife?.openedShelfLifeDays,
      defaultLocation: shelfLife?.location ?? 'pantry',
      defaultDateKind: shelfLife?.dateKind ?? 'best_before',
    );
    await _learnAlias(key, product.id, hid);
    return product;
  }

  /// Versucht, einen unbekannten Barcode automatisch einem bereits gelernten Produkt zuzuordnen: der
  /// Produktname von Open Food Facts wird wie ein Bon-Text normalisiert und gegen die gelernten Alias-
  /// Schluessel geprueft. Trifft das zu, wird der Barcode gleich mitverknuepft. So muss der Nutzer nicht
  /// immer manuell nach dem Bon-Vorschlag suchen (Fehlerbericht "Bonartikel bearbeiten", 2026-09-27).
  Future<Product?> matchByLearnedName(String offName) async {
    final hid = await householdId();
    final key = normalizeItemName(offName);
    if (key.isEmpty) return null;
    final alias = await (_db.select(_db.productAliases)
          ..where((a) => a.householdId.equals(hid) & a.aliasText.equals(key) & a.deletedAt.isNull()))
        .getSingleOrNull();
    if (alias == null) return null;
    final p = await byId(alias.productId);
    return (p != null && p.deletedAt == null) ? p : null;
  }

  /// Entfernt bekannte Bon-Praefixe ("IC", "1C" ...), behaelt sonst Gross-/Kleinschreibung wie gedruckt.
  static String _cleanName(String raw) {
    final t = raw.trim();
    final m = RegExp(r'^(ic|1c|io|i0|lc)\s+', caseSensitive: false).firstMatch(t);
    return (m == null ? t : t.substring(m.end)).trim();
  }

  /// Der aktive Alias zu [key] im Haushalt, falls vorhanden. `.get()` statt `.getSingleOrNull()`, damit ein
  /// bereits bestehendes Duplikat (z.B. aus einer Alt-Installation vor dem Codereview-Fix 2026-10-01, siehe
  /// `softDelete`) nicht den ganzen Bon-Import mit einem `StateError` abstuerzen laesst -- bei mehreren
  /// Treffern gewinnt der zuletzt aktualisierte, der Rest wird beim naechsten `softDelete` des betroffenen
  /// Produkts bereinigt.
  Future<ProductAlias?> _activeAliasFor(String hid, String key) async {
    final rows = await (_db.select(_db.productAliases)
          ..where((a) => a.householdId.equals(hid) & a.aliasText.equals(key) & a.deletedAt.isNull())
          ..orderBy([(a) => OrderingTerm.desc(a.updatedAt)]))
        .get();
    return rows.firstOrNull;
  }

  /// Alle aktiven, gelernten Alias-Schluessel des Haushalts (ADR-023: Vergleichsbasis fuer den
  /// Fuzzy-Match, bevor ein neues Produkt angelegt wird).
  Future<List<String>> _activeAliasKeys(String hid) => (_db.selectOnly(_db.productAliases)
        ..addColumns([_db.productAliases.aliasText])
        ..where(_db.productAliases.householdId.equals(hid) & _db.productAliases.deletedAt.isNull()))
      .map((r) => r.read(_db.productAliases.aliasText)!)
      .get();

  Future<void> _learnAlias(String key, String productId, String householdId) async {
    final a = ProductAlias(id: _uuid.v4(), householdId: householdId, aliasText: key, productId: productId, hits: 1, updatedAt: DateTime.now().toUtc());
    await _put('product_aliases', a.id, productAliasToRemote(a), () => _db.into(_db.productAliases).insertOnConflictUpdate(a.toCompanion(false)));
  }

  /// Legt ein neues Produkt an und verknuepft optional gleich den EAN (Barcode-Scan eines unbekannten Produkts).
  Future<Product> create({
    required String name,
    String? brand,
    String? categoryId,
    String baseUnit = 'piece',
    double? packSize,
    int? sealedShelfLifeDays,
    int? openedShelfLifeDays,
    String defaultDateKind = 'best_before',
    String defaultLocation = 'pantry',
    bool restock = false,
    String? offCode,
    Map<String, double>? nutrientsPer100,
    String? nutrientsBasis,
    // Codereview-Fund 2026-10-02 (Phase 7a): vorher wurde die Quelle immer stillschweigend als
    // 'off' angenommen, sobald Naehrwerte vorhanden waren -- das stimmt nicht mehr, sobald eine
    // zweite Quelle (BLS, Phase 7b) hinzukommt. Explizit statt geraten, Default haelt bestehende
    // Aufrufer (OFF-Scan) unveraendert.
    String? nutrientsSource,
    double? unitWeightG,
    String? ean,
  }) async {
    final n = name.trim();
    if (n.isEmpty) throw ArgumentError('Name darf nicht leer sein');
    if (nutrientsPer100 != null && nutrientsSource == null) {
      throw ArgumentError('nutrientsSource muss gesetzt sein, wenn nutrientsPer100 angegeben wird');
    }
    final hid = await householdId();
    final now = DateTime.now().toUtc();
    final product = Product(
      id: _uuid.v4(),
      householdId: hid,
      name: n,
      brand: brand?.trim().isEmpty == true ? null : brand?.trim(),
      categoryId: categoryId,
      baseUnit: baseUnit,
      packSize: packSize,
      sealedShelfLifeDays: sealedShelfLifeDays,
      openedShelfLifeDays: openedShelfLifeDays,
      defaultDateKind: defaultDateKind,
      defaultLocation: defaultLocation,
      restock: restock,
      offCode: offCode,
      nutrientsPer100: nutrientsPer100 == null ? null : jsonEncode(nutrientsPer100),
      nutrientsBasis: nutrientsBasis,
      nutrientsSource: nutrientsSource,
      unitWeightG: unitWeightG,
      updatedAt: now,
    );
    await _put('products', product.id, productToRemote(product), () => _db.into(_db.products).insertOnConflictUpdate(product.toCompanion(false)));
    if (ean != null) await linkBarcode(ean, product.id);
    onChanged?.call();
    return product;
  }

  Future<void> update(Product product) async {
    final updated = product.copyWith(updatedAt: DateTime.now().toUtc());
    await _put('products', updated.id, productToRemote(updated), () => _db.into(_db.products).insertOnConflictUpdate(updated.toCompanion(false)));
    onChanged?.call();
  }

  /// Merkt sich das Gewicht von 1 Stueck des Produkts in g (Phase N2): einmal angegeben, gilt es fuer jede Mahlzeit. `null` bei
  /// unbekanntem oder geloeschtem Produkt oder einem Gewicht ohne Sinn.
  Future<Product?> setUnitWeight(String productId, double grams) async {
    if (!(grams > 0) || grams > 5000) return null;
    final product = await byId(productId);
    if (product == null || product.deletedAt != null) return null;
    if (product.unitWeightG == grams) return product;
    final updated = product.copyWith(unitWeightG: Value(grams), updatedAt: DateTime.now().toUtc());
    await _put('products', updated.id, productToRemote(updated), () => _db.into(_db.products).insertOnConflictUpdate(updated.toCompanion(false)));
    onChanged?.call();
    return updated;
  }

  /// Verknuepft das Produkt mit einem Eintrag der Lebensmitteldatenbank (Phase N1, ADR-031): `bls_code` und das Profil je
  /// 100 g als Snapshot in `nutrients_per_100` (`nutrients_source = 'bls'`), damit die Mahlzeitenerfassung offline ohne Abfrage
  /// rechnet. Ein vorhandenes Profil (z.B. von Open Food Facts, packungsgenau) bleibt, ausser mit [overwrite].
  /// Liefert das geaenderte Produkt, `null` bei unbekanntem Produkt, vorhandenem Profil oder einem Eintrag ohne Naehrwerte.
  Future<Product?> setBlsProfile(String productId, BlsFood food, {bool overwrite = false}) async {
    final product = await byId(productId);
    if (product == null || product.deletedAt != null) return null;
    if (product.nutrientsPer100 != null && !overwrite) return null;
    final p = food.per100;
    final profile = <String, double>{
      if (p.kcal != null) 'kcal': p.kcal!,
      if (p.proteinG != null) 'protein_g': p.proteinG!,
      if (p.fatG != null) 'fat_g': p.fatG!,
      if (p.satFatG != null) 'sat_fat_g': p.satFatG!,
      if (p.carbsG != null) 'carbs_g': p.carbsG!,
      if (p.sugarG != null) 'sugar_g': p.sugarG!,
      if (p.fiberG != null) 'fiber_g': p.fiberG!,
      if (p.saltG != null) 'salt_g': p.saltG!,
    };
    if (profile.isEmpty) return null;
    final updated = product.copyWith(
      nutrientsPer100: Value(jsonEncode(profile)),
      nutrientsBasis: const Value('g'),
      nutrientsSource: const Value('bls'),
      blsCode: Value(food.code),
      updatedAt: DateTime.now().toUtc(),
    );
    await _put('products', updated.id, productToRemote(updated), () => _db.into(_db.products).insertOnConflictUpdate(updated.toCompanion(false)));
    onChanged?.call();
    return updated;
  }

  /// Loescht ein Produkt aus "Meine Produkte" (Fehlerbericht "Produkt löschen", 2026-09-28). Bestehende
  /// Bons, Inventar-Eintraege und Einkaufslisten-Positionen behalten ihre `product_id` und zeigen den Namen
  /// weiter an; nur Suche, Autovervollstaendigung und Barcode-Zuordnung ignorieren das Produkt danach.
  ///
  /// Loescht auch die gelernten Aliase mit (Codereview-Fund 2026-10-01): sonst bleibt ein aktiver Alias auf
  /// das geloeschte Produkt stehen, `findOrCreateForReceiptItem` legt beim naechsten Kauf desselben Artikels
  /// ein zweites Produkt mit demselben Alias-Text an, und ein dritter Kauf laesst die Alias-Abfrage zwei
  /// Treffer finden statt einem -- die lokale Tabelle hat (anders als die Server-Tabelle) keine Eindeutigkeits-
  /// Pruefung auf den Alias-Text, der ganze Bon-Import stuerzt dann ab.
  Future<void> softDelete(String id) async {
    final product = await byId(id);
    if (product == null) return;
    final now = DateTime.now().toUtc();
    // Codereview-Fund 2026-10-01: in einer Transaktion, damit ein Abbruch mittendrin (z.B. App-Kill) nicht
    // einen Teil der Aliase geloescht und den Rest (oder das Produkt selbst) aktiv zuruecklaesst.
    await _db.transaction(() async {
      final aliases = await (_db.select(_db.productAliases)
            ..where((a) => a.productId.equals(id) & a.deletedAt.isNull()))
          .get();
      for (final alias in aliases) {
        final deleted = alias.copyWith(deletedAt: Value(now), updatedAt: now);
        await _put('product_aliases', deleted.id, productAliasToRemote(deleted), () => _db.into(_db.productAliases).insertOnConflictUpdate(deleted.toCompanion(false)));
      }
      final updated = product.copyWith(deletedAt: Value(now), updatedAt: now);
      await _put('products', updated.id, productToRemote(updated), () => _db.into(_db.products).insertOnConflictUpdate(updated.toCompanion(false)));
    });
    onChanged?.call();
  }

  /// Fuehrt zwei Duplikate zusammen (Doku 07 §4.3): alle Bons, Inventar-Eintraege, Einkaufslisten-Positionen,
  /// Barcodes und gelernten Alias-Zuordnungen von [sourceId] werden auf [targetId] umgehaengt, danach wird
  /// [sourceId] geloescht wie bei [softDelete]. So bleibt die Kaufhistorie (und damit der Grundpreis-Verlauf,
  /// Doku 07 §3) unter einem einzigen Produkt vereint, statt auf zwei Eintraege verstreut zu sein.
  Future<void> mergeInto(String sourceId, String targetId) async {
    if (sourceId == targetId) return;
    final now = DateTime.now().toUtc();

    // Codereview-Fund 2026-10-01: eine einzige Transaktion ueber alle umgehaengten Tabellen plus das
    // abschliessende softDelete -- sonst koennte ein Abbruch mittendrin (z.B. App-Kill) manche Zeilen schon
    // auf das Zielprodukt umgehaengt und andere noch auf dem (dann weiterhin aktiven) Quellprodukt stehen
    // lassen, ein sichtbar inkonsistenter Zwischenzustand ohne einfachen Weg zurueck.
    await _db.transaction(() async {
      final receiptItems = await (_db.select(_db.receiptItems)..where((i) => i.productId.equals(sourceId))).get();
      for (final item in receiptItems) {
        final updated = item.copyWith(productId: Value(targetId), updatedAt: now);
        await _put('receipt_items', updated.id, receiptItemToRemote(updated), () => _db.into(_db.receiptItems).insertOnConflictUpdate(updated.toCompanion(false)));
      }

      final inventoryItems = await (_db.select(_db.inventoryItems)..where((i) => i.productId.equals(sourceId))).get();
      for (final item in inventoryItems) {
        final updated = item.copyWith(productId: targetId, updatedAt: now);
        await _put('inventory_items', updated.id, inventoryItemToRemote(updated), () => _db.into(_db.inventoryItems).insertOnConflictUpdate(updated.toCompanion(false)));
      }

      final listItems = await (_db.select(_db.shoppingListItems)..where((i) => i.productId.equals(sourceId))).get();
      for (final item in listItems) {
        final updated = item.copyWith(productId: Value(targetId), updatedAt: now);
        await _put('shopping_list_items', updated.id, shoppingListItemToRemote(updated), () => _db.into(_db.shoppingListItems).insertOnConflictUpdate(updated.toCompanion(false)));
      }

      final barcodes = await (_db.select(_db.productBarcodes)..where((b) => b.productId.equals(sourceId))).get();
      for (final b in barcodes) {
        final updated = b.copyWith(productId: targetId, updatedAt: now);
        await _put('product_barcodes', '${updated.householdId}:${updated.ean}', productBarcodeToRemote(updated),
            () => _db.into(_db.productBarcodes).insertOnConflictUpdate(updated.toCompanion(false)));
      }

      // Alias-Texte sind je Haushalt eindeutig gedacht (ADR-010): hat das Zielprodukt den Text schon, wird der
      // doppelte Alias geloescht statt eine zweite aktive Zeile fuer denselben Bon-Text anzulegen (das wuerde
      // findOrCreateForReceiptItem's getSingleOrNull() spaeter zum Absturz bringen).
      final aliases = await (_db.select(_db.productAliases)..where((a) => a.productId.equals(sourceId) & a.deletedAt.isNull())).get();
      for (final alias in aliases) {
        final clash = await (_db.select(_db.productAliases)
              ..where((a) =>
                  a.householdId.equals(alias.householdId) & a.aliasText.equals(alias.aliasText) & a.productId.equals(targetId) & a.deletedAt.isNull()))
            .getSingleOrNull();
        if (clash != null) {
          final deleted = alias.copyWith(deletedAt: Value(now), updatedAt: now);
          await _put('product_aliases', deleted.id, productAliasToRemote(deleted), () => _db.into(_db.productAliases).insertOnConflictUpdate(deleted.toCompanion(false)));
        } else {
          final updated = alias.copyWith(productId: targetId, updatedAt: now);
          await _put('product_aliases', updated.id, productAliasToRemote(updated), () => _db.into(_db.productAliases).insertOnConflictUpdate(updated.toCompanion(false)));
        }
      }

      await softDelete(sourceId);
    });
  }

  /// Verknuepft einen EAN dauerhaft mit einem Produkt (Doku 06 §4: "bleibt danach dauerhaft erhalten").
  Future<void> linkBarcode(String ean, String productId) async {
    final hid = await householdId();
    final b = ProductBarcode(householdId: hid, ean: ean, productId: productId, updatedAt: DateTime.now().toUtc());
    await _put('product_barcodes', '$hid:$ean', productBarcodeToRemote(b),
        () => _db.into(_db.productBarcodes).insertOnConflictUpdate(b.toCompanion(false)));
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

/// Grobe Kategorie-Vorbelegung fuer ein OFF-Ergebnis (Doku 06 §4). Der Nutzer kann sie aendern.
String? suggestCategoryId(OffProduct off, Map<String, String> categoryIdByName) {
  final name = categoryFromOffTags(off.categoryTags);
  return name == null ? null : categoryIdByName[name];
}
