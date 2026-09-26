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
