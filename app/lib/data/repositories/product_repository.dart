import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/categorization/normalize_name.dart';
import '../../domain/categorization/off_category_map.dart';
import '../../domain/inventory/shelf_life_rules.dart';
import '../local/database.dart';
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
    final alias = await (_db.select(_db.productAliases)
          ..where((a) => a.householdId.equals(hid) & a.aliasText.equals(key) & a.deletedAt.isNull()))
        .getSingleOrNull();
    if (alias != null) {
      final p = await byId(alias.productId);
      if (p != null && p.deletedAt == null) return p;
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
    double? unitWeightG,
    String? ean,
  }) async {
    final n = name.trim();
    if (n.isEmpty) throw ArgumentError('Name darf nicht leer sein');
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
      nutrientsSource: nutrientsPer100 == null ? null : 'off',
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

  /// Loescht ein Produkt aus "Meine Produkte" (Fehlerbericht "Produkt löschen", 2026-09-28). Bestehende
  /// Bons, Inventar-Eintraege und Einkaufslisten-Positionen behalten ihre `product_id` und zeigen den Namen
  /// weiter an; nur Suche, Autovervollstaendigung und Barcode-Zuordnung ignorieren das Produkt danach.
  Future<void> softDelete(String id) async {
    final product = await byId(id);
    if (product == null) return;
    final updated = product.copyWith(deletedAt: Value(DateTime.now().toUtc()), updatedAt: DateTime.now().toUtc());
    await _put('products', updated.id, productToRemote(updated), () => _db.into(_db.products).insertOnConflictUpdate(updated.toCompanion(false)));
    onChanged?.call();
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
