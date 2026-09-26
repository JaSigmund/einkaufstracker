import 'package:drift/drift.dart';

import '../local/database.dart';

DateTime? _dt(Object? v) => v == null ? null : DateTime.parse(v as String).toUtc();

Map<String, dynamic> categoryToRemote(Category c) => {
      'id': c.id,
      'household_id': c.householdId,
      'parent_id': c.parentId,
      'name': c.name,
      'icon': c.icon,
      'sort_order': c.sortOrder,
      'is_storable': c.isStorable,
      'updated_at': c.updatedAt.toUtc().toIso8601String(),
      'deleted_at': c.deletedAt?.toUtc().toIso8601String(),
    };

CategoriesCompanion categoryFromRemote(Map<String, dynamic> j) => CategoriesCompanion(
      id: Value(j['id'] as String),
      householdId: Value(j['household_id'] as String),
      parentId: Value(j['parent_id'] as String?),
      name: Value(j['name'] as String),
      icon: Value(j['icon'] as String?),
      sortOrder: Value((j['sort_order'] as num?)?.toInt() ?? 0),
      isStorable: Value(j['is_storable'] as bool? ?? true),
      updatedAt: Value(_dt(j['updated_at'])!),
      deletedAt: Value(_dt(j['deleted_at'])),
    );

Map<String, dynamic> productToRemote(Product p) => {
      'id': p.id,
      'household_id': p.householdId,
      'name': p.name,
      'brand': p.brand,
      'category_id': p.categoryId,
      'base_unit': p.baseUnit,
      'pack_size': p.packSize,
      'updated_at': p.updatedAt.toUtc().toIso8601String(),
      'deleted_at': p.deletedAt?.toUtc().toIso8601String(),
    };

ProductsCompanion productFromRemote(Map<String, dynamic> j) => ProductsCompanion(
      id: Value(j['id'] as String),
      householdId: Value(j['household_id'] as String),
      name: Value(j['name'] as String),
      brand: Value(j['brand'] as String?),
      categoryId: Value(j['category_id'] as String?),
      baseUnit: Value(j['base_unit'] as String? ?? 'piece'),
      packSize: Value((j['pack_size'] as num?)?.toDouble()),
      updatedAt: Value(_dt(j['updated_at'])!),
      deletedAt: Value(_dt(j['deleted_at'])),
    );

Map<String, dynamic> storeToRemote(Store s) => {
      'id': s.id,
      'household_id': s.householdId,
      'chain': s.chain,
      'branch': s.branch,
      'updated_at': s.updatedAt.toUtc().toIso8601String(),
      'deleted_at': s.deletedAt?.toUtc().toIso8601String(),
    };

StoresCompanion storeFromRemote(Map<String, dynamic> j) => StoresCompanion(
      id: Value(j['id'] as String),
      householdId: Value(j['household_id'] as String),
      chain: Value(j['chain'] as String),
      branch: Value(j['branch'] as String?),
      updatedAt: Value(_dt(j['updated_at'])!),
      deletedAt: Value(_dt(j['deleted_at'])),
    );

Map<String, dynamic> receiptToRemote(Receipt r) => {
      'id': r.id,
      'household_id': r.householdId,
      'store_id': r.storeId,
      'purchased_at': r.purchasedAt.toUtc().toIso8601String(),
      'total_cents': r.totalCents,
      'status': r.status,
      'source': r.source,
      'external_id': r.externalId,
      'confidence': r.confidence,
      'sum_mismatch': r.sumMismatch,
      'updated_at': r.updatedAt.toUtc().toIso8601String(),
      'deleted_at': r.deletedAt?.toUtc().toIso8601String(),
    };

ReceiptsCompanion receiptFromRemote(Map<String, dynamic> j) => ReceiptsCompanion(
      id: Value(j['id'] as String),
      householdId: Value(j['household_id'] as String),
      storeId: Value(j['store_id'] as String?),
      purchasedAt: Value(_dt(j['purchased_at'])!),
      totalCents: Value((j['total_cents'] as num).toInt()),
      status: Value(j['status'] as String? ?? 'confirmed'),
      source: Value(j['source'] as String? ?? 'manual'),
      externalId: Value(j['external_id'] as String?),
      confidence: Value((j['confidence'] as num?)?.toDouble()),
      sumMismatch: Value(j['sum_mismatch'] as bool? ?? false),
      updatedAt: Value(_dt(j['updated_at'])!),
      deletedAt: Value(_dt(j['deleted_at'])),
    );

Map<String, dynamic> receiptItemToRemote(ReceiptItem i) => {
      'id': i.id,
      'household_id': i.householdId,
      'receipt_id': i.receiptId,
      'line_no': i.lineNo,
      'kind': i.kind,
      'raw_text': i.rawText,
      'product_id': i.productId,
      'category_id': i.categoryId,
      'quantity': i.quantity,
      'quantity_unit': i.quantityUnit,
      'unit_price_cents': i.unitPriceCents,
      'line_total_cents': i.lineTotalCents,
      'tax_code': i.taxCode,
      'needs_review': i.needsReview,
      'updated_at': i.updatedAt.toUtc().toIso8601String(),
      'deleted_at': i.deletedAt?.toUtc().toIso8601String(),
    };

ReceiptItemsCompanion receiptItemFromRemote(Map<String, dynamic> j) => ReceiptItemsCompanion(
      id: Value(j['id'] as String),
      householdId: Value(j['household_id'] as String),
      receiptId: Value(j['receipt_id'] as String),
      lineNo: Value((j['line_no'] as num).toInt()),
      kind: Value(j['kind'] as String? ?? 'article'),
      rawText: Value(j['raw_text'] as String),
      productId: Value(j['product_id'] as String?),
      categoryId: Value(j['category_id'] as String?),
      quantity: Value((j['quantity'] as num?)?.toDouble() ?? 1),
      quantityUnit: Value(j['quantity_unit'] as String? ?? 'piece'),
      unitPriceCents: Value((j['unit_price_cents'] as num?)?.toInt()),
      lineTotalCents: Value((j['line_total_cents'] as num).toInt()),
      taxCode: Value(j['tax_code'] as String?),
      needsReview: Value(j['needs_review'] as bool? ?? false),
      updatedAt: Value(_dt(j['updated_at'])!),
      deletedAt: Value(_dt(j['deleted_at'])),
    );

Map<String, dynamic> categoryAliasToRemote(CategoryAlias a) => {
      'id': a.id,
      'household_id': a.householdId,
      'alias_text': a.aliasText,
      'category_id': a.categoryId,
      'hits': a.hits,
      'updated_at': a.updatedAt.toUtc().toIso8601String(),
      'deleted_at': a.deletedAt?.toUtc().toIso8601String(),
    };

CategoryAliasesCompanion categoryAliasFromRemote(Map<String, dynamic> j) => CategoryAliasesCompanion(
      id: Value(j['id'] as String),
      householdId: Value(j['household_id'] as String),
      aliasText: Value(j['alias_text'] as String),
      categoryId: Value(j['category_id'] as String),
      hits: Value((j['hits'] as num?)?.toInt() ?? 1),
      updatedAt: Value(_dt(j['updated_at'])!),
      deletedAt: Value(_dt(j['deleted_at'])),
    );

Map<String, dynamic> receiptFileToRemote(ReceiptFile f) => {
      'id': f.id,
      'household_id': f.householdId,
      'receipt_id': f.receiptId,
      'kind': f.kind,
      'page_no': f.pageNo,
      'storage_path': f.storagePath,
      'size_bytes': f.sizeBytes,
      'updated_at': f.updatedAt.toUtc().toIso8601String(),
      'deleted_at': f.deletedAt?.toUtc().toIso8601String(),
    };

ReceiptFilesCompanion receiptFileFromRemote(Map<String, dynamic> j) => ReceiptFilesCompanion(
      id: Value(j['id'] as String),
      householdId: Value(j['household_id'] as String),
      receiptId: Value(j['receipt_id'] as String),
      kind: Value(j['kind'] as String),
      pageNo: Value((j['page_no'] as num?)?.toInt() ?? 1),
      storagePath: Value(j['storage_path'] as String),
      sizeBytes: Value((j['size_bytes'] as num?)?.toInt()),
      updatedAt: Value(_dt(j['updated_at'])!),
      deletedAt: Value(_dt(j['deleted_at'])),
    );
