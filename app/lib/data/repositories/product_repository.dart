import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/categorization/off_category_map.dart';
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
    return BarcodeLookupResult(offSuggestion: suggestion);
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
