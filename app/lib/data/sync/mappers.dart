import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/database.dart';

DateTime? _dt(Object? v) => v == null ? null : DateTime.parse(v as String).toUtc();

/// Postgres `date` (kein `timestamptz`): 'YYYY-MM-DD' ohne Zeitzone, als UTC-Mitternacht dieses Kalendertags.
DateTime? _date(Object? v) => v == null ? null : DateTime.parse('${v as String}T00:00:00Z');
String? _dateStr(DateTime? d) => d == null ? null : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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
      'sealed_shelf_life_days': p.sealedShelfLifeDays,
      'opened_shelf_life_days': p.openedShelfLifeDays,
      'default_date_kind': p.defaultDateKind,
      'default_location': p.defaultLocation,
      'restock': p.restock,
      'off_code': p.offCode,
      'nutrients_per_100': p.nutrientsPer100 == null ? null : jsonDecode(p.nutrientsPer100!),
      'nutrients_basis': p.nutrientsBasis,
      'nutrients_source': p.nutrientsSource,
      'unit_weight_g': p.unitWeightG,
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
      sealedShelfLifeDays: Value((j['sealed_shelf_life_days'] as num?)?.toInt()),
      openedShelfLifeDays: Value((j['opened_shelf_life_days'] as num?)?.toInt()),
      defaultDateKind: Value(j['default_date_kind'] as String? ?? 'best_before'),
      defaultLocation: Value(j['default_location'] as String? ?? 'pantry'),
      restock: Value(j['restock'] as bool? ?? false),
      offCode: Value(j['off_code'] as String?),
      nutrientsPer100: Value(j['nutrients_per_100'] == null ? null : jsonEncode(j['nutrients_per_100'])),
      nutrientsBasis: Value(j['nutrients_basis'] as String?),
      nutrientsSource: Value(j['nutrients_source'] as String?),
      unitWeightG: Value((j['unit_weight_g'] as num?)?.toDouble()),
      updatedAt: Value(_dt(j['updated_at'])!),
      deletedAt: Value(_dt(j['deleted_at'])),
    );

Map<String, dynamic> productBarcodeToRemote(ProductBarcode b) => {
      'household_id': b.householdId,
      'ean': b.ean,
      'product_id': b.productId,
      'updated_at': b.updatedAt.toUtc().toIso8601String(),
    };

ProductBarcodesCompanion productBarcodeFromRemote(Map<String, dynamic> j) => ProductBarcodesCompanion(
      householdId: Value(j['household_id'] as String),
      ean: Value(j['ean'] as String),
      productId: Value(j['product_id'] as String),
      updatedAt: Value(_dt(j['updated_at'])!),
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

Map<String, dynamic> inventoryItemToRemote(InventoryItem i) => {
      'id': i.id,
      'household_id': i.householdId,
      'product_id': i.productId,
      'receipt_item_id': i.receiptItemId,
      'ean': i.ean,
      'quantity': i.quantity,
      'unit': i.unit,
      'location': i.location,
      'purchased_on': _dateStr(i.purchasedOn),
      'best_before': _dateStr(i.bestBefore),
      'date_kind': i.dateKind,
      'opened_on': _dateStr(i.openedOn),
      'open_shelf_life_days': i.openShelfLifeDays,
      'status': i.status,
      'is_suggestion': i.isSuggestion,
      'closed_at': i.closedAt?.toUtc().toIso8601String(),
      'updated_at': i.updatedAt.toUtc().toIso8601String(),
      'deleted_at': i.deletedAt?.toUtc().toIso8601String(),
    };

InventoryItemsCompanion inventoryItemFromRemote(Map<String, dynamic> j) => InventoryItemsCompanion(
      id: Value(j['id'] as String),
      householdId: Value(j['household_id'] as String),
      productId: Value(j['product_id'] as String),
      receiptItemId: Value(j['receipt_item_id'] as String?),
      ean: Value(j['ean'] as String?),
      quantity: Value((j['quantity'] as num?)?.toDouble() ?? 1),
      unit: Value(j['unit'] as String? ?? 'piece'),
      location: Value(j['location'] as String? ?? 'pantry'),
      purchasedOn: Value(_date(j['purchased_on'])),
      bestBefore: Value(_date(j['best_before'])),
      dateKind: Value(j['date_kind'] as String? ?? 'best_before'),
      openedOn: Value(_date(j['opened_on'])),
      openShelfLifeDays: Value((j['open_shelf_life_days'] as num?)?.toInt()),
      status: Value(j['status'] as String? ?? 'sealed'),
      isSuggestion: Value(j['is_suggestion'] as bool? ?? false),
      closedAt: Value(_dt(j['closed_at'])),
      expiresOn: Value(_date(j['expires_on'])),
      updatedAt: Value(_dt(j['updated_at'])!),
      deletedAt: Value(_dt(j['deleted_at'])),
    );

Map<String, dynamic> inventoryMovementToRemote(InventoryMovement m) => {
      'id': m.id,
      'household_id': m.householdId,
      'inventory_item_id': m.inventoryItemId,
      'product_id': m.productId,
      'occurred_at': m.occurredAt.toUtc().toIso8601String(),
      'type': m.type,
      'quantity_delta': m.quantityDelta,
      'unit': m.unit,
      'note': m.note,
      'updated_at': m.updatedAt.toUtc().toIso8601String(),
      'deleted_at': m.deletedAt?.toUtc().toIso8601String(),
    };

InventoryMovementsCompanion inventoryMovementFromRemote(Map<String, dynamic> j) => InventoryMovementsCompanion(
      id: Value(j['id'] as String),
      householdId: Value(j['household_id'] as String),
      inventoryItemId: Value(j['inventory_item_id'] as String?),
      productId: Value(j['product_id'] as String),
      occurredAt: Value(_dt(j['occurred_at'])!),
      type: Value(j['type'] as String),
      quantityDelta: Value((j['quantity_delta'] as num).toDouble()),
      unit: Value(j['unit'] as String),
      note: Value(j['note'] as String?),
      updatedAt: Value(_dt(j['updated_at'])!),
      deletedAt: Value(_dt(j['deleted_at'])),
    );

Map<String, dynamic> productAliasToRemote(ProductAlias a) => {
      'id': a.id,
      'household_id': a.householdId,
      'store_id': a.storeId,
      'alias_text': a.aliasText,
      'product_id': a.productId,
      'hits': a.hits,
      'updated_at': a.updatedAt.toUtc().toIso8601String(),
      'deleted_at': a.deletedAt?.toUtc().toIso8601String(),
    };

ProductAliasesCompanion productAliasFromRemote(Map<String, dynamic> j) => ProductAliasesCompanion(
      id: Value(j['id'] as String),
      householdId: Value(j['household_id'] as String),
      storeId: Value(j['store_id'] as String?),
      aliasText: Value(j['alias_text'] as String),
      productId: Value(j['product_id'] as String),
      hits: Value((j['hits'] as num?)?.toInt() ?? 1),
      updatedAt: Value(_dt(j['updated_at'])!),
      deletedAt: Value(_dt(j['deleted_at'])),
    );

Map<String, dynamic> bugReportToRemote(BugReport b) => {
      'id': b.id,
      'household_id': b.householdId,
      'title': b.title,
      'description': b.description,
      'app_info': jsonDecode(b.appInfo),
      'data_snapshot': b.dataSnapshot == null ? null : jsonDecode(b.dataSnapshot!),
      // status/severity/resolution/fixed_in_version werden von der Entwicklung per SQL gesetzt, nicht vom
      // Client; sie werden trotzdem mitgeschickt, damit ein Upsert eine lokale Aenderung (z.B. Titel) nicht
      // versehentlich auf den Standardwert 'new' zuruecksetzt.
      'status': b.status,
      'severity': b.severity,
      'resolution': b.resolution,
      'fixed_in_version': b.fixedInVersion,
      'created_at': b.createdAt.toUtc().toIso8601String(),
      'updated_at': b.updatedAt.toUtc().toIso8601String(),
      'deleted_at': b.deletedAt?.toUtc().toIso8601String(),
    };

BugReportsCompanion bugReportFromRemote(Map<String, dynamic> j) => BugReportsCompanion(
      id: Value(j['id'] as String),
      householdId: Value(j['household_id'] as String),
      title: Value(j['title'] as String),
      description: Value(j['description'] as String?),
      appInfo: Value(jsonEncode(j['app_info'])),
      dataSnapshot: Value(j['data_snapshot'] == null ? null : jsonEncode(j['data_snapshot'])),
      status: Value(j['status'] as String? ?? 'new'),
      severity: Value(j['severity'] as String?),
      resolution: Value(j['resolution'] as String?),
      fixedInVersion: Value(j['fixed_in_version'] as String?),
      statusUpdatedAt: Value(_dt(j['status_updated_at'])),
      createdAt: Value(_dt(j['created_at'])!),
      updatedAt: Value(_dt(j['updated_at'])!),
      deletedAt: Value(_dt(j['deleted_at'])),
    );

Map<String, dynamic> shoppingListToRemote(ShoppingList l) => {
      'id': l.id,
      'household_id': l.householdId,
      'name': l.name,
      'is_default': l.isDefault,
      'updated_at': l.updatedAt.toUtc().toIso8601String(),
      'deleted_at': l.deletedAt?.toUtc().toIso8601String(),
    };

ShoppingListsCompanion shoppingListFromRemote(Map<String, dynamic> j) => ShoppingListsCompanion(
      id: Value(j['id'] as String),
      householdId: Value(j['household_id'] as String),
      name: Value(j['name'] as String? ?? 'Einkaufsliste'),
      isDefault: Value(j['is_default'] as bool? ?? true),
      updatedAt: Value(_dt(j['updated_at'])!),
      deletedAt: Value(_dt(j['deleted_at'])),
    );

Map<String, dynamic> shoppingListItemToRemote(ShoppingListItem i) => {
      'id': i.id,
      'household_id': i.householdId,
      'list_id': i.listId,
      'product_id': i.productId,
      'free_text': i.freeText,
      'quantity': i.quantity,
      'unit': i.unit,
      'checked': i.checked,
      'source': i.source,
      'is_suggestion': i.isSuggestion,
      'updated_at': i.updatedAt.toUtc().toIso8601String(),
      'deleted_at': i.deletedAt?.toUtc().toIso8601String(),
    };

ShoppingListItemsCompanion shoppingListItemFromRemote(Map<String, dynamic> j) => ShoppingListItemsCompanion(
      id: Value(j['id'] as String),
      householdId: Value(j['household_id'] as String),
      listId: Value(j['list_id'] as String),
      productId: Value(j['product_id'] as String?),
      freeText: Value(j['free_text'] as String?),
      quantity: Value((j['quantity'] as num?)?.toDouble() ?? 1),
      unit: Value(j['unit'] as String? ?? 'piece'),
      checked: Value(j['checked'] as bool? ?? false),
      source: Value(j['source'] as String? ?? 'manual'),
      isSuggestion: Value(j['is_suggestion'] as bool? ?? false),
      updatedAt: Value(_dt(j['updated_at'])!),
      deletedAt: Value(_dt(j['deleted_at'])),
    );
