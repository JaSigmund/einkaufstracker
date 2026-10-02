// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $CategoriesTable extends Categories
    with TableInfo<$CategoriesTable, Category> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _householdIdMeta = const VerificationMeta(
    'householdId',
  );
  @override
  late final GeneratedColumn<String> householdId = GeneratedColumn<String>(
    'household_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<String> icon = GeneratedColumn<String>(
    'icon',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isStorableMeta = const VerificationMeta(
    'isStorable',
  );
  @override
  late final GeneratedColumn<bool> isStorable = GeneratedColumn<bool>(
    'is_storable',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_storable" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    householdId,
    parentId,
    name,
    icon,
    sortOrder,
    isStorable,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<Category> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('household_id')) {
      context.handle(
        _householdIdMeta,
        householdId.isAcceptableOrUnknown(
          data['household_id']!,
          _householdIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_householdIdMeta);
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('icon')) {
      context.handle(
        _iconMeta,
        icon.isAcceptableOrUnknown(data['icon']!, _iconMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('is_storable')) {
      context.handle(
        _isStorableMeta,
        isStorable.isAcceptableOrUnknown(data['is_storable']!, _isStorableMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Category map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Category(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      householdId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}household_id'],
      )!,
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      icon: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon'],
      ),
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      isStorable: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_storable'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $CategoriesTable createAlias(String alias) {
    return $CategoriesTable(attachedDatabase, alias);
  }
}

class Category extends DataClass implements Insertable<Category> {
  final String id;
  final String householdId;
  final String? parentId;
  final String name;
  final String? icon;
  final int sortOrder;
  final bool isStorable;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const Category({
    required this.id,
    required this.householdId,
    this.parentId,
    required this.name,
    this.icon,
    required this.sortOrder,
    required this.isStorable,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['household_id'] = Variable<String>(householdId);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || icon != null) {
      map['icon'] = Variable<String>(icon);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    map['is_storable'] = Variable<bool>(isStorable);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  CategoriesCompanion toCompanion(bool nullToAbsent) {
    return CategoriesCompanion(
      id: Value(id),
      householdId: Value(householdId),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      name: Value(name),
      icon: icon == null && nullToAbsent ? const Value.absent() : Value(icon),
      sortOrder: Value(sortOrder),
      isStorable: Value(isStorable),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory Category.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Category(
      id: serializer.fromJson<String>(json['id']),
      householdId: serializer.fromJson<String>(json['householdId']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      name: serializer.fromJson<String>(json['name']),
      icon: serializer.fromJson<String?>(json['icon']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      isStorable: serializer.fromJson<bool>(json['isStorable']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'householdId': serializer.toJson<String>(householdId),
      'parentId': serializer.toJson<String?>(parentId),
      'name': serializer.toJson<String>(name),
      'icon': serializer.toJson<String?>(icon),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'isStorable': serializer.toJson<bool>(isStorable),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  Category copyWith({
    String? id,
    String? householdId,
    Value<String?> parentId = const Value.absent(),
    String? name,
    Value<String?> icon = const Value.absent(),
    int? sortOrder,
    bool? isStorable,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => Category(
    id: id ?? this.id,
    householdId: householdId ?? this.householdId,
    parentId: parentId.present ? parentId.value : this.parentId,
    name: name ?? this.name,
    icon: icon.present ? icon.value : this.icon,
    sortOrder: sortOrder ?? this.sortOrder,
    isStorable: isStorable ?? this.isStorable,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  Category copyWithCompanion(CategoriesCompanion data) {
    return Category(
      id: data.id.present ? data.id.value : this.id,
      householdId: data.householdId.present
          ? data.householdId.value
          : this.householdId,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      name: data.name.present ? data.name.value : this.name,
      icon: data.icon.present ? data.icon.value : this.icon,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      isStorable: data.isStorable.present
          ? data.isStorable.value
          : this.isStorable,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Category(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('parentId: $parentId, ')
          ..write('name: $name, ')
          ..write('icon: $icon, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('isStorable: $isStorable, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    householdId,
    parentId,
    name,
    icon,
    sortOrder,
    isStorable,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Category &&
          other.id == this.id &&
          other.householdId == this.householdId &&
          other.parentId == this.parentId &&
          other.name == this.name &&
          other.icon == this.icon &&
          other.sortOrder == this.sortOrder &&
          other.isStorable == this.isStorable &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class CategoriesCompanion extends UpdateCompanion<Category> {
  final Value<String> id;
  final Value<String> householdId;
  final Value<String?> parentId;
  final Value<String> name;
  final Value<String?> icon;
  final Value<int> sortOrder;
  final Value<bool> isStorable;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const CategoriesCompanion({
    this.id = const Value.absent(),
    this.householdId = const Value.absent(),
    this.parentId = const Value.absent(),
    this.name = const Value.absent(),
    this.icon = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.isStorable = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CategoriesCompanion.insert({
    required String id,
    required String householdId,
    this.parentId = const Value.absent(),
    required String name,
    this.icon = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.isStorable = const Value.absent(),
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       householdId = Value(householdId),
       name = Value(name),
       updatedAt = Value(updatedAt);
  static Insertable<Category> custom({
    Expression<String>? id,
    Expression<String>? householdId,
    Expression<String>? parentId,
    Expression<String>? name,
    Expression<String>? icon,
    Expression<int>? sortOrder,
    Expression<bool>? isStorable,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (householdId != null) 'household_id': householdId,
      if (parentId != null) 'parent_id': parentId,
      if (name != null) 'name': name,
      if (icon != null) 'icon': icon,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (isStorable != null) 'is_storable': isStorable,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CategoriesCompanion copyWith({
    Value<String>? id,
    Value<String>? householdId,
    Value<String?>? parentId,
    Value<String>? name,
    Value<String?>? icon,
    Value<int>? sortOrder,
    Value<bool>? isStorable,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return CategoriesCompanion(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      parentId: parentId ?? this.parentId,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      sortOrder: sortOrder ?? this.sortOrder,
      isStorable: isStorable ?? this.isStorable,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (householdId.present) {
      map['household_id'] = Variable<String>(householdId.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (icon.present) {
      map['icon'] = Variable<String>(icon.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (isStorable.present) {
      map['is_storable'] = Variable<bool>(isStorable.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoriesCompanion(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('parentId: $parentId, ')
          ..write('name: $name, ')
          ..write('icon: $icon, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('isStorable: $isStorable, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProductsTable extends Products with TableInfo<$ProductsTable, Product> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProductsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _householdIdMeta = const VerificationMeta(
    'householdId',
  );
  @override
  late final GeneratedColumn<String> householdId = GeneratedColumn<String>(
    'household_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _brandMeta = const VerificationMeta('brand');
  @override
  late final GeneratedColumn<String> brand = GeneratedColumn<String>(
    'brand',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _baseUnitMeta = const VerificationMeta(
    'baseUnit',
  );
  @override
  late final GeneratedColumn<String> baseUnit = GeneratedColumn<String>(
    'base_unit',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('piece'),
  );
  static const VerificationMeta _packSizeMeta = const VerificationMeta(
    'packSize',
  );
  @override
  late final GeneratedColumn<double> packSize = GeneratedColumn<double>(
    'pack_size',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sealedShelfLifeDaysMeta =
      const VerificationMeta('sealedShelfLifeDays');
  @override
  late final GeneratedColumn<int> sealedShelfLifeDays = GeneratedColumn<int>(
    'sealed_shelf_life_days',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _openedShelfLifeDaysMeta =
      const VerificationMeta('openedShelfLifeDays');
  @override
  late final GeneratedColumn<int> openedShelfLifeDays = GeneratedColumn<int>(
    'opened_shelf_life_days',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _defaultDateKindMeta = const VerificationMeta(
    'defaultDateKind',
  );
  @override
  late final GeneratedColumn<String> defaultDateKind = GeneratedColumn<String>(
    'default_date_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('best_before'),
  );
  static const VerificationMeta _defaultLocationMeta = const VerificationMeta(
    'defaultLocation',
  );
  @override
  late final GeneratedColumn<String> defaultLocation = GeneratedColumn<String>(
    'default_location',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pantry'),
  );
  static const VerificationMeta _restockMeta = const VerificationMeta(
    'restock',
  );
  @override
  late final GeneratedColumn<bool> restock = GeneratedColumn<bool>(
    'restock',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("restock" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _offCodeMeta = const VerificationMeta(
    'offCode',
  );
  @override
  late final GeneratedColumn<String> offCode = GeneratedColumn<String>(
    'off_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nutrientsPer100Meta = const VerificationMeta(
    'nutrientsPer100',
  );
  @override
  late final GeneratedColumn<String> nutrientsPer100 = GeneratedColumn<String>(
    'nutrients_per100',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nutrientsBasisMeta = const VerificationMeta(
    'nutrientsBasis',
  );
  @override
  late final GeneratedColumn<String> nutrientsBasis = GeneratedColumn<String>(
    'nutrients_basis',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nutrientsSourceMeta = const VerificationMeta(
    'nutrientsSource',
  );
  @override
  late final GeneratedColumn<String> nutrientsSource = GeneratedColumn<String>(
    'nutrients_source',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unitWeightGMeta = const VerificationMeta(
    'unitWeightG',
  );
  @override
  late final GeneratedColumn<double> unitWeightG = GeneratedColumn<double>(
    'unit_weight_g',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    householdId,
    name,
    brand,
    categoryId,
    baseUnit,
    packSize,
    sealedShelfLifeDays,
    openedShelfLifeDays,
    defaultDateKind,
    defaultLocation,
    restock,
    offCode,
    nutrientsPer100,
    nutrientsBasis,
    nutrientsSource,
    unitWeightG,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'products';
  @override
  VerificationContext validateIntegrity(
    Insertable<Product> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('household_id')) {
      context.handle(
        _householdIdMeta,
        householdId.isAcceptableOrUnknown(
          data['household_id']!,
          _householdIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_householdIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('brand')) {
      context.handle(
        _brandMeta,
        brand.isAcceptableOrUnknown(data['brand']!, _brandMeta),
      );
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('base_unit')) {
      context.handle(
        _baseUnitMeta,
        baseUnit.isAcceptableOrUnknown(data['base_unit']!, _baseUnitMeta),
      );
    }
    if (data.containsKey('pack_size')) {
      context.handle(
        _packSizeMeta,
        packSize.isAcceptableOrUnknown(data['pack_size']!, _packSizeMeta),
      );
    }
    if (data.containsKey('sealed_shelf_life_days')) {
      context.handle(
        _sealedShelfLifeDaysMeta,
        sealedShelfLifeDays.isAcceptableOrUnknown(
          data['sealed_shelf_life_days']!,
          _sealedShelfLifeDaysMeta,
        ),
      );
    }
    if (data.containsKey('opened_shelf_life_days')) {
      context.handle(
        _openedShelfLifeDaysMeta,
        openedShelfLifeDays.isAcceptableOrUnknown(
          data['opened_shelf_life_days']!,
          _openedShelfLifeDaysMeta,
        ),
      );
    }
    if (data.containsKey('default_date_kind')) {
      context.handle(
        _defaultDateKindMeta,
        defaultDateKind.isAcceptableOrUnknown(
          data['default_date_kind']!,
          _defaultDateKindMeta,
        ),
      );
    }
    if (data.containsKey('default_location')) {
      context.handle(
        _defaultLocationMeta,
        defaultLocation.isAcceptableOrUnknown(
          data['default_location']!,
          _defaultLocationMeta,
        ),
      );
    }
    if (data.containsKey('restock')) {
      context.handle(
        _restockMeta,
        restock.isAcceptableOrUnknown(data['restock']!, _restockMeta),
      );
    }
    if (data.containsKey('off_code')) {
      context.handle(
        _offCodeMeta,
        offCode.isAcceptableOrUnknown(data['off_code']!, _offCodeMeta),
      );
    }
    if (data.containsKey('nutrients_per100')) {
      context.handle(
        _nutrientsPer100Meta,
        nutrientsPer100.isAcceptableOrUnknown(
          data['nutrients_per100']!,
          _nutrientsPer100Meta,
        ),
      );
    }
    if (data.containsKey('nutrients_basis')) {
      context.handle(
        _nutrientsBasisMeta,
        nutrientsBasis.isAcceptableOrUnknown(
          data['nutrients_basis']!,
          _nutrientsBasisMeta,
        ),
      );
    }
    if (data.containsKey('nutrients_source')) {
      context.handle(
        _nutrientsSourceMeta,
        nutrientsSource.isAcceptableOrUnknown(
          data['nutrients_source']!,
          _nutrientsSourceMeta,
        ),
      );
    }
    if (data.containsKey('unit_weight_g')) {
      context.handle(
        _unitWeightGMeta,
        unitWeightG.isAcceptableOrUnknown(
          data['unit_weight_g']!,
          _unitWeightGMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Product map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Product(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      householdId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}household_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      brand: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}brand'],
      ),
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      ),
      baseUnit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_unit'],
      )!,
      packSize: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}pack_size'],
      ),
      sealedShelfLifeDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sealed_shelf_life_days'],
      ),
      openedShelfLifeDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}opened_shelf_life_days'],
      ),
      defaultDateKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}default_date_kind'],
      )!,
      defaultLocation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}default_location'],
      )!,
      restock: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}restock'],
      )!,
      offCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}off_code'],
      ),
      nutrientsPer100: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nutrients_per100'],
      ),
      nutrientsBasis: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nutrients_basis'],
      ),
      nutrientsSource: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nutrients_source'],
      ),
      unitWeightG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}unit_weight_g'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $ProductsTable createAlias(String alias) {
    return $ProductsTable(attachedDatabase, alias);
  }
}

class Product extends DataClass implements Insertable<Product> {
  final String id;
  final String householdId;
  final String name;
  final String? brand;
  final String? categoryId;

  /// 'kg' | 'l' | 'piece'
  final String baseUnit;
  final double? packSize;

  /// Standardhaltbarkeit ab Kauf (Tage), falls kein MHD bekannt ist.
  final int? sealedShelfLifeDays;

  /// Standardhaltbarkeit nach dem Oeffnen (Tage).
  final int? openedShelfLifeDays;

  /// 'best_before' | 'use_by'
  final String defaultDateKind;

  /// 'fridge' | 'freezer' | 'pantry' | 'other'
  final String defaultLocation;

  /// Nachkaufprodukt: Vorschlag fuer die Einkaufsliste, wenn der letzte Bestand ausgeht (Phase 3).
  final bool restock;
  final String? offCode;

  /// Naehrwerte je 100 g/ml als JSON (Phase 7): {kcal, protein_g, fat_g, sat_fat_g, carbs_g, sugar_g, fiber_g, salt_g}
  final String? nutrientsPer100;

  /// 'g' | 'ml', nur gesetzt wenn nutrientsPer100 gesetzt ist.
  final String? nutrientsBasis;

  /// 'off' | 'usda' | 'manual' | 'llm_estimate'
  final String? nutrientsSource;

  /// Gewicht eines Stuecks in Gramm (z.B. Paprika ~150), fuer die Umrechnung Stueck <-> Gewicht.
  final double? unitWeightG;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const Product({
    required this.id,
    required this.householdId,
    required this.name,
    this.brand,
    this.categoryId,
    required this.baseUnit,
    this.packSize,
    this.sealedShelfLifeDays,
    this.openedShelfLifeDays,
    required this.defaultDateKind,
    required this.defaultLocation,
    required this.restock,
    this.offCode,
    this.nutrientsPer100,
    this.nutrientsBasis,
    this.nutrientsSource,
    this.unitWeightG,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['household_id'] = Variable<String>(householdId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || brand != null) {
      map['brand'] = Variable<String>(brand);
    }
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    map['base_unit'] = Variable<String>(baseUnit);
    if (!nullToAbsent || packSize != null) {
      map['pack_size'] = Variable<double>(packSize);
    }
    if (!nullToAbsent || sealedShelfLifeDays != null) {
      map['sealed_shelf_life_days'] = Variable<int>(sealedShelfLifeDays);
    }
    if (!nullToAbsent || openedShelfLifeDays != null) {
      map['opened_shelf_life_days'] = Variable<int>(openedShelfLifeDays);
    }
    map['default_date_kind'] = Variable<String>(defaultDateKind);
    map['default_location'] = Variable<String>(defaultLocation);
    map['restock'] = Variable<bool>(restock);
    if (!nullToAbsent || offCode != null) {
      map['off_code'] = Variable<String>(offCode);
    }
    if (!nullToAbsent || nutrientsPer100 != null) {
      map['nutrients_per100'] = Variable<String>(nutrientsPer100);
    }
    if (!nullToAbsent || nutrientsBasis != null) {
      map['nutrients_basis'] = Variable<String>(nutrientsBasis);
    }
    if (!nullToAbsent || nutrientsSource != null) {
      map['nutrients_source'] = Variable<String>(nutrientsSource);
    }
    if (!nullToAbsent || unitWeightG != null) {
      map['unit_weight_g'] = Variable<double>(unitWeightG);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  ProductsCompanion toCompanion(bool nullToAbsent) {
    return ProductsCompanion(
      id: Value(id),
      householdId: Value(householdId),
      name: Value(name),
      brand: brand == null && nullToAbsent
          ? const Value.absent()
          : Value(brand),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      baseUnit: Value(baseUnit),
      packSize: packSize == null && nullToAbsent
          ? const Value.absent()
          : Value(packSize),
      sealedShelfLifeDays: sealedShelfLifeDays == null && nullToAbsent
          ? const Value.absent()
          : Value(sealedShelfLifeDays),
      openedShelfLifeDays: openedShelfLifeDays == null && nullToAbsent
          ? const Value.absent()
          : Value(openedShelfLifeDays),
      defaultDateKind: Value(defaultDateKind),
      defaultLocation: Value(defaultLocation),
      restock: Value(restock),
      offCode: offCode == null && nullToAbsent
          ? const Value.absent()
          : Value(offCode),
      nutrientsPer100: nutrientsPer100 == null && nullToAbsent
          ? const Value.absent()
          : Value(nutrientsPer100),
      nutrientsBasis: nutrientsBasis == null && nullToAbsent
          ? const Value.absent()
          : Value(nutrientsBasis),
      nutrientsSource: nutrientsSource == null && nullToAbsent
          ? const Value.absent()
          : Value(nutrientsSource),
      unitWeightG: unitWeightG == null && nullToAbsent
          ? const Value.absent()
          : Value(unitWeightG),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory Product.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Product(
      id: serializer.fromJson<String>(json['id']),
      householdId: serializer.fromJson<String>(json['householdId']),
      name: serializer.fromJson<String>(json['name']),
      brand: serializer.fromJson<String?>(json['brand']),
      categoryId: serializer.fromJson<String?>(json['categoryId']),
      baseUnit: serializer.fromJson<String>(json['baseUnit']),
      packSize: serializer.fromJson<double?>(json['packSize']),
      sealedShelfLifeDays: serializer.fromJson<int?>(
        json['sealedShelfLifeDays'],
      ),
      openedShelfLifeDays: serializer.fromJson<int?>(
        json['openedShelfLifeDays'],
      ),
      defaultDateKind: serializer.fromJson<String>(json['defaultDateKind']),
      defaultLocation: serializer.fromJson<String>(json['defaultLocation']),
      restock: serializer.fromJson<bool>(json['restock']),
      offCode: serializer.fromJson<String?>(json['offCode']),
      nutrientsPer100: serializer.fromJson<String?>(json['nutrientsPer100']),
      nutrientsBasis: serializer.fromJson<String?>(json['nutrientsBasis']),
      nutrientsSource: serializer.fromJson<String?>(json['nutrientsSource']),
      unitWeightG: serializer.fromJson<double?>(json['unitWeightG']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'householdId': serializer.toJson<String>(householdId),
      'name': serializer.toJson<String>(name),
      'brand': serializer.toJson<String?>(brand),
      'categoryId': serializer.toJson<String?>(categoryId),
      'baseUnit': serializer.toJson<String>(baseUnit),
      'packSize': serializer.toJson<double?>(packSize),
      'sealedShelfLifeDays': serializer.toJson<int?>(sealedShelfLifeDays),
      'openedShelfLifeDays': serializer.toJson<int?>(openedShelfLifeDays),
      'defaultDateKind': serializer.toJson<String>(defaultDateKind),
      'defaultLocation': serializer.toJson<String>(defaultLocation),
      'restock': serializer.toJson<bool>(restock),
      'offCode': serializer.toJson<String?>(offCode),
      'nutrientsPer100': serializer.toJson<String?>(nutrientsPer100),
      'nutrientsBasis': serializer.toJson<String?>(nutrientsBasis),
      'nutrientsSource': serializer.toJson<String?>(nutrientsSource),
      'unitWeightG': serializer.toJson<double?>(unitWeightG),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  Product copyWith({
    String? id,
    String? householdId,
    String? name,
    Value<String?> brand = const Value.absent(),
    Value<String?> categoryId = const Value.absent(),
    String? baseUnit,
    Value<double?> packSize = const Value.absent(),
    Value<int?> sealedShelfLifeDays = const Value.absent(),
    Value<int?> openedShelfLifeDays = const Value.absent(),
    String? defaultDateKind,
    String? defaultLocation,
    bool? restock,
    Value<String?> offCode = const Value.absent(),
    Value<String?> nutrientsPer100 = const Value.absent(),
    Value<String?> nutrientsBasis = const Value.absent(),
    Value<String?> nutrientsSource = const Value.absent(),
    Value<double?> unitWeightG = const Value.absent(),
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => Product(
    id: id ?? this.id,
    householdId: householdId ?? this.householdId,
    name: name ?? this.name,
    brand: brand.present ? brand.value : this.brand,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    baseUnit: baseUnit ?? this.baseUnit,
    packSize: packSize.present ? packSize.value : this.packSize,
    sealedShelfLifeDays: sealedShelfLifeDays.present
        ? sealedShelfLifeDays.value
        : this.sealedShelfLifeDays,
    openedShelfLifeDays: openedShelfLifeDays.present
        ? openedShelfLifeDays.value
        : this.openedShelfLifeDays,
    defaultDateKind: defaultDateKind ?? this.defaultDateKind,
    defaultLocation: defaultLocation ?? this.defaultLocation,
    restock: restock ?? this.restock,
    offCode: offCode.present ? offCode.value : this.offCode,
    nutrientsPer100: nutrientsPer100.present
        ? nutrientsPer100.value
        : this.nutrientsPer100,
    nutrientsBasis: nutrientsBasis.present
        ? nutrientsBasis.value
        : this.nutrientsBasis,
    nutrientsSource: nutrientsSource.present
        ? nutrientsSource.value
        : this.nutrientsSource,
    unitWeightG: unitWeightG.present ? unitWeightG.value : this.unitWeightG,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  Product copyWithCompanion(ProductsCompanion data) {
    return Product(
      id: data.id.present ? data.id.value : this.id,
      householdId: data.householdId.present
          ? data.householdId.value
          : this.householdId,
      name: data.name.present ? data.name.value : this.name,
      brand: data.brand.present ? data.brand.value : this.brand,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      baseUnit: data.baseUnit.present ? data.baseUnit.value : this.baseUnit,
      packSize: data.packSize.present ? data.packSize.value : this.packSize,
      sealedShelfLifeDays: data.sealedShelfLifeDays.present
          ? data.sealedShelfLifeDays.value
          : this.sealedShelfLifeDays,
      openedShelfLifeDays: data.openedShelfLifeDays.present
          ? data.openedShelfLifeDays.value
          : this.openedShelfLifeDays,
      defaultDateKind: data.defaultDateKind.present
          ? data.defaultDateKind.value
          : this.defaultDateKind,
      defaultLocation: data.defaultLocation.present
          ? data.defaultLocation.value
          : this.defaultLocation,
      restock: data.restock.present ? data.restock.value : this.restock,
      offCode: data.offCode.present ? data.offCode.value : this.offCode,
      nutrientsPer100: data.nutrientsPer100.present
          ? data.nutrientsPer100.value
          : this.nutrientsPer100,
      nutrientsBasis: data.nutrientsBasis.present
          ? data.nutrientsBasis.value
          : this.nutrientsBasis,
      nutrientsSource: data.nutrientsSource.present
          ? data.nutrientsSource.value
          : this.nutrientsSource,
      unitWeightG: data.unitWeightG.present
          ? data.unitWeightG.value
          : this.unitWeightG,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Product(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('name: $name, ')
          ..write('brand: $brand, ')
          ..write('categoryId: $categoryId, ')
          ..write('baseUnit: $baseUnit, ')
          ..write('packSize: $packSize, ')
          ..write('sealedShelfLifeDays: $sealedShelfLifeDays, ')
          ..write('openedShelfLifeDays: $openedShelfLifeDays, ')
          ..write('defaultDateKind: $defaultDateKind, ')
          ..write('defaultLocation: $defaultLocation, ')
          ..write('restock: $restock, ')
          ..write('offCode: $offCode, ')
          ..write('nutrientsPer100: $nutrientsPer100, ')
          ..write('nutrientsBasis: $nutrientsBasis, ')
          ..write('nutrientsSource: $nutrientsSource, ')
          ..write('unitWeightG: $unitWeightG, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    householdId,
    name,
    brand,
    categoryId,
    baseUnit,
    packSize,
    sealedShelfLifeDays,
    openedShelfLifeDays,
    defaultDateKind,
    defaultLocation,
    restock,
    offCode,
    nutrientsPer100,
    nutrientsBasis,
    nutrientsSource,
    unitWeightG,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Product &&
          other.id == this.id &&
          other.householdId == this.householdId &&
          other.name == this.name &&
          other.brand == this.brand &&
          other.categoryId == this.categoryId &&
          other.baseUnit == this.baseUnit &&
          other.packSize == this.packSize &&
          other.sealedShelfLifeDays == this.sealedShelfLifeDays &&
          other.openedShelfLifeDays == this.openedShelfLifeDays &&
          other.defaultDateKind == this.defaultDateKind &&
          other.defaultLocation == this.defaultLocation &&
          other.restock == this.restock &&
          other.offCode == this.offCode &&
          other.nutrientsPer100 == this.nutrientsPer100 &&
          other.nutrientsBasis == this.nutrientsBasis &&
          other.nutrientsSource == this.nutrientsSource &&
          other.unitWeightG == this.unitWeightG &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class ProductsCompanion extends UpdateCompanion<Product> {
  final Value<String> id;
  final Value<String> householdId;
  final Value<String> name;
  final Value<String?> brand;
  final Value<String?> categoryId;
  final Value<String> baseUnit;
  final Value<double?> packSize;
  final Value<int?> sealedShelfLifeDays;
  final Value<int?> openedShelfLifeDays;
  final Value<String> defaultDateKind;
  final Value<String> defaultLocation;
  final Value<bool> restock;
  final Value<String?> offCode;
  final Value<String?> nutrientsPer100;
  final Value<String?> nutrientsBasis;
  final Value<String?> nutrientsSource;
  final Value<double?> unitWeightG;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const ProductsCompanion({
    this.id = const Value.absent(),
    this.householdId = const Value.absent(),
    this.name = const Value.absent(),
    this.brand = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.baseUnit = const Value.absent(),
    this.packSize = const Value.absent(),
    this.sealedShelfLifeDays = const Value.absent(),
    this.openedShelfLifeDays = const Value.absent(),
    this.defaultDateKind = const Value.absent(),
    this.defaultLocation = const Value.absent(),
    this.restock = const Value.absent(),
    this.offCode = const Value.absent(),
    this.nutrientsPer100 = const Value.absent(),
    this.nutrientsBasis = const Value.absent(),
    this.nutrientsSource = const Value.absent(),
    this.unitWeightG = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProductsCompanion.insert({
    required String id,
    required String householdId,
    required String name,
    this.brand = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.baseUnit = const Value.absent(),
    this.packSize = const Value.absent(),
    this.sealedShelfLifeDays = const Value.absent(),
    this.openedShelfLifeDays = const Value.absent(),
    this.defaultDateKind = const Value.absent(),
    this.defaultLocation = const Value.absent(),
    this.restock = const Value.absent(),
    this.offCode = const Value.absent(),
    this.nutrientsPer100 = const Value.absent(),
    this.nutrientsBasis = const Value.absent(),
    this.nutrientsSource = const Value.absent(),
    this.unitWeightG = const Value.absent(),
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       householdId = Value(householdId),
       name = Value(name),
       updatedAt = Value(updatedAt);
  static Insertable<Product> custom({
    Expression<String>? id,
    Expression<String>? householdId,
    Expression<String>? name,
    Expression<String>? brand,
    Expression<String>? categoryId,
    Expression<String>? baseUnit,
    Expression<double>? packSize,
    Expression<int>? sealedShelfLifeDays,
    Expression<int>? openedShelfLifeDays,
    Expression<String>? defaultDateKind,
    Expression<String>? defaultLocation,
    Expression<bool>? restock,
    Expression<String>? offCode,
    Expression<String>? nutrientsPer100,
    Expression<String>? nutrientsBasis,
    Expression<String>? nutrientsSource,
    Expression<double>? unitWeightG,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (householdId != null) 'household_id': householdId,
      if (name != null) 'name': name,
      if (brand != null) 'brand': brand,
      if (categoryId != null) 'category_id': categoryId,
      if (baseUnit != null) 'base_unit': baseUnit,
      if (packSize != null) 'pack_size': packSize,
      if (sealedShelfLifeDays != null)
        'sealed_shelf_life_days': sealedShelfLifeDays,
      if (openedShelfLifeDays != null)
        'opened_shelf_life_days': openedShelfLifeDays,
      if (defaultDateKind != null) 'default_date_kind': defaultDateKind,
      if (defaultLocation != null) 'default_location': defaultLocation,
      if (restock != null) 'restock': restock,
      if (offCode != null) 'off_code': offCode,
      if (nutrientsPer100 != null) 'nutrients_per100': nutrientsPer100,
      if (nutrientsBasis != null) 'nutrients_basis': nutrientsBasis,
      if (nutrientsSource != null) 'nutrients_source': nutrientsSource,
      if (unitWeightG != null) 'unit_weight_g': unitWeightG,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProductsCompanion copyWith({
    Value<String>? id,
    Value<String>? householdId,
    Value<String>? name,
    Value<String?>? brand,
    Value<String?>? categoryId,
    Value<String>? baseUnit,
    Value<double?>? packSize,
    Value<int?>? sealedShelfLifeDays,
    Value<int?>? openedShelfLifeDays,
    Value<String>? defaultDateKind,
    Value<String>? defaultLocation,
    Value<bool>? restock,
    Value<String?>? offCode,
    Value<String?>? nutrientsPer100,
    Value<String?>? nutrientsBasis,
    Value<String?>? nutrientsSource,
    Value<double?>? unitWeightG,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return ProductsCompanion(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      categoryId: categoryId ?? this.categoryId,
      baseUnit: baseUnit ?? this.baseUnit,
      packSize: packSize ?? this.packSize,
      sealedShelfLifeDays: sealedShelfLifeDays ?? this.sealedShelfLifeDays,
      openedShelfLifeDays: openedShelfLifeDays ?? this.openedShelfLifeDays,
      defaultDateKind: defaultDateKind ?? this.defaultDateKind,
      defaultLocation: defaultLocation ?? this.defaultLocation,
      restock: restock ?? this.restock,
      offCode: offCode ?? this.offCode,
      nutrientsPer100: nutrientsPer100 ?? this.nutrientsPer100,
      nutrientsBasis: nutrientsBasis ?? this.nutrientsBasis,
      nutrientsSource: nutrientsSource ?? this.nutrientsSource,
      unitWeightG: unitWeightG ?? this.unitWeightG,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (householdId.present) {
      map['household_id'] = Variable<String>(householdId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (brand.present) {
      map['brand'] = Variable<String>(brand.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (baseUnit.present) {
      map['base_unit'] = Variable<String>(baseUnit.value);
    }
    if (packSize.present) {
      map['pack_size'] = Variable<double>(packSize.value);
    }
    if (sealedShelfLifeDays.present) {
      map['sealed_shelf_life_days'] = Variable<int>(sealedShelfLifeDays.value);
    }
    if (openedShelfLifeDays.present) {
      map['opened_shelf_life_days'] = Variable<int>(openedShelfLifeDays.value);
    }
    if (defaultDateKind.present) {
      map['default_date_kind'] = Variable<String>(defaultDateKind.value);
    }
    if (defaultLocation.present) {
      map['default_location'] = Variable<String>(defaultLocation.value);
    }
    if (restock.present) {
      map['restock'] = Variable<bool>(restock.value);
    }
    if (offCode.present) {
      map['off_code'] = Variable<String>(offCode.value);
    }
    if (nutrientsPer100.present) {
      map['nutrients_per100'] = Variable<String>(nutrientsPer100.value);
    }
    if (nutrientsBasis.present) {
      map['nutrients_basis'] = Variable<String>(nutrientsBasis.value);
    }
    if (nutrientsSource.present) {
      map['nutrients_source'] = Variable<String>(nutrientsSource.value);
    }
    if (unitWeightG.present) {
      map['unit_weight_g'] = Variable<double>(unitWeightG.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProductsCompanion(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('name: $name, ')
          ..write('brand: $brand, ')
          ..write('categoryId: $categoryId, ')
          ..write('baseUnit: $baseUnit, ')
          ..write('packSize: $packSize, ')
          ..write('sealedShelfLifeDays: $sealedShelfLifeDays, ')
          ..write('openedShelfLifeDays: $openedShelfLifeDays, ')
          ..write('defaultDateKind: $defaultDateKind, ')
          ..write('defaultLocation: $defaultLocation, ')
          ..write('restock: $restock, ')
          ..write('offCode: $offCode, ')
          ..write('nutrientsPer100: $nutrientsPer100, ')
          ..write('nutrientsBasis: $nutrientsBasis, ')
          ..write('nutrientsSource: $nutrientsSource, ')
          ..write('unitWeightG: $unitWeightG, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProductBarcodesTable extends ProductBarcodes
    with TableInfo<$ProductBarcodesTable, ProductBarcode> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProductBarcodesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _householdIdMeta = const VerificationMeta(
    'householdId',
  );
  @override
  late final GeneratedColumn<String> householdId = GeneratedColumn<String>(
    'household_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eanMeta = const VerificationMeta('ean');
  @override
  late final GeneratedColumn<String> ean = GeneratedColumn<String>(
    'ean',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _productIdMeta = const VerificationMeta(
    'productId',
  );
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
    'product_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    householdId,
    ean,
    productId,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'product_barcodes';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProductBarcode> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('household_id')) {
      context.handle(
        _householdIdMeta,
        householdId.isAcceptableOrUnknown(
          data['household_id']!,
          _householdIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_householdIdMeta);
    }
    if (data.containsKey('ean')) {
      context.handle(
        _eanMeta,
        ean.isAcceptableOrUnknown(data['ean']!, _eanMeta),
      );
    } else if (isInserting) {
      context.missing(_eanMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(
        _productIdMeta,
        productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta),
      );
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {householdId, ean};
  @override
  ProductBarcode map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProductBarcode(
      householdId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}household_id'],
      )!,
      ean: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ean'],
      )!,
      productId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}product_id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ProductBarcodesTable createAlias(String alias) {
    return $ProductBarcodesTable(attachedDatabase, alias);
  }
}

class ProductBarcode extends DataClass implements Insertable<ProductBarcode> {
  final String householdId;
  final String ean;
  final String productId;
  final DateTime updatedAt;
  const ProductBarcode({
    required this.householdId,
    required this.ean,
    required this.productId,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['household_id'] = Variable<String>(householdId);
    map['ean'] = Variable<String>(ean);
    map['product_id'] = Variable<String>(productId);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ProductBarcodesCompanion toCompanion(bool nullToAbsent) {
    return ProductBarcodesCompanion(
      householdId: Value(householdId),
      ean: Value(ean),
      productId: Value(productId),
      updatedAt: Value(updatedAt),
    );
  }

  factory ProductBarcode.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProductBarcode(
      householdId: serializer.fromJson<String>(json['householdId']),
      ean: serializer.fromJson<String>(json['ean']),
      productId: serializer.fromJson<String>(json['productId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'householdId': serializer.toJson<String>(householdId),
      'ean': serializer.toJson<String>(ean),
      'productId': serializer.toJson<String>(productId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ProductBarcode copyWith({
    String? householdId,
    String? ean,
    String? productId,
    DateTime? updatedAt,
  }) => ProductBarcode(
    householdId: householdId ?? this.householdId,
    ean: ean ?? this.ean,
    productId: productId ?? this.productId,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ProductBarcode copyWithCompanion(ProductBarcodesCompanion data) {
    return ProductBarcode(
      householdId: data.householdId.present
          ? data.householdId.value
          : this.householdId,
      ean: data.ean.present ? data.ean.value : this.ean,
      productId: data.productId.present ? data.productId.value : this.productId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProductBarcode(')
          ..write('householdId: $householdId, ')
          ..write('ean: $ean, ')
          ..write('productId: $productId, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(householdId, ean, productId, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProductBarcode &&
          other.householdId == this.householdId &&
          other.ean == this.ean &&
          other.productId == this.productId &&
          other.updatedAt == this.updatedAt);
}

class ProductBarcodesCompanion extends UpdateCompanion<ProductBarcode> {
  final Value<String> householdId;
  final Value<String> ean;
  final Value<String> productId;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ProductBarcodesCompanion({
    this.householdId = const Value.absent(),
    this.ean = const Value.absent(),
    this.productId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProductBarcodesCompanion.insert({
    required String householdId,
    required String ean,
    required String productId,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : householdId = Value(householdId),
       ean = Value(ean),
       productId = Value(productId),
       updatedAt = Value(updatedAt);
  static Insertable<ProductBarcode> custom({
    Expression<String>? householdId,
    Expression<String>? ean,
    Expression<String>? productId,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (householdId != null) 'household_id': householdId,
      if (ean != null) 'ean': ean,
      if (productId != null) 'product_id': productId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProductBarcodesCompanion copyWith({
    Value<String>? householdId,
    Value<String>? ean,
    Value<String>? productId,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ProductBarcodesCompanion(
      householdId: householdId ?? this.householdId,
      ean: ean ?? this.ean,
      productId: productId ?? this.productId,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (householdId.present) {
      map['household_id'] = Variable<String>(householdId.value);
    }
    if (ean.present) {
      map['ean'] = Variable<String>(ean.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProductBarcodesCompanion(')
          ..write('householdId: $householdId, ')
          ..write('ean: $ean, ')
          ..write('productId: $productId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProductAliasesTable extends ProductAliases
    with TableInfo<$ProductAliasesTable, ProductAlias> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProductAliasesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _householdIdMeta = const VerificationMeta(
    'householdId',
  );
  @override
  late final GeneratedColumn<String> householdId = GeneratedColumn<String>(
    'household_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _storeIdMeta = const VerificationMeta(
    'storeId',
  );
  @override
  late final GeneratedColumn<String> storeId = GeneratedColumn<String>(
    'store_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _aliasTextMeta = const VerificationMeta(
    'aliasText',
  );
  @override
  late final GeneratedColumn<String> aliasText = GeneratedColumn<String>(
    'alias_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _productIdMeta = const VerificationMeta(
    'productId',
  );
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
    'product_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hitsMeta = const VerificationMeta('hits');
  @override
  late final GeneratedColumn<int> hits = GeneratedColumn<int>(
    'hits',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    householdId,
    storeId,
    aliasText,
    productId,
    hits,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'product_aliases';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProductAlias> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('household_id')) {
      context.handle(
        _householdIdMeta,
        householdId.isAcceptableOrUnknown(
          data['household_id']!,
          _householdIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_householdIdMeta);
    }
    if (data.containsKey('store_id')) {
      context.handle(
        _storeIdMeta,
        storeId.isAcceptableOrUnknown(data['store_id']!, _storeIdMeta),
      );
    }
    if (data.containsKey('alias_text')) {
      context.handle(
        _aliasTextMeta,
        aliasText.isAcceptableOrUnknown(data['alias_text']!, _aliasTextMeta),
      );
    } else if (isInserting) {
      context.missing(_aliasTextMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(
        _productIdMeta,
        productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta),
      );
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('hits')) {
      context.handle(
        _hitsMeta,
        hits.isAcceptableOrUnknown(data['hits']!, _hitsMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProductAlias map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProductAlias(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      householdId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}household_id'],
      )!,
      storeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}store_id'],
      ),
      aliasText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}alias_text'],
      )!,
      productId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}product_id'],
      )!,
      hits: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}hits'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $ProductAliasesTable createAlias(String alias) {
    return $ProductAliasesTable(attachedDatabase, alias);
  }
}

class ProductAlias extends DataClass implements Insertable<ProductAlias> {
  final String id;
  final String householdId;
  final String? storeId;
  final String aliasText;
  final String productId;
  final int hits;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const ProductAlias({
    required this.id,
    required this.householdId,
    this.storeId,
    required this.aliasText,
    required this.productId,
    required this.hits,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['household_id'] = Variable<String>(householdId);
    if (!nullToAbsent || storeId != null) {
      map['store_id'] = Variable<String>(storeId);
    }
    map['alias_text'] = Variable<String>(aliasText);
    map['product_id'] = Variable<String>(productId);
    map['hits'] = Variable<int>(hits);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  ProductAliasesCompanion toCompanion(bool nullToAbsent) {
    return ProductAliasesCompanion(
      id: Value(id),
      householdId: Value(householdId),
      storeId: storeId == null && nullToAbsent
          ? const Value.absent()
          : Value(storeId),
      aliasText: Value(aliasText),
      productId: Value(productId),
      hits: Value(hits),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory ProductAlias.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProductAlias(
      id: serializer.fromJson<String>(json['id']),
      householdId: serializer.fromJson<String>(json['householdId']),
      storeId: serializer.fromJson<String?>(json['storeId']),
      aliasText: serializer.fromJson<String>(json['aliasText']),
      productId: serializer.fromJson<String>(json['productId']),
      hits: serializer.fromJson<int>(json['hits']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'householdId': serializer.toJson<String>(householdId),
      'storeId': serializer.toJson<String?>(storeId),
      'aliasText': serializer.toJson<String>(aliasText),
      'productId': serializer.toJson<String>(productId),
      'hits': serializer.toJson<int>(hits),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  ProductAlias copyWith({
    String? id,
    String? householdId,
    Value<String?> storeId = const Value.absent(),
    String? aliasText,
    String? productId,
    int? hits,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => ProductAlias(
    id: id ?? this.id,
    householdId: householdId ?? this.householdId,
    storeId: storeId.present ? storeId.value : this.storeId,
    aliasText: aliasText ?? this.aliasText,
    productId: productId ?? this.productId,
    hits: hits ?? this.hits,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  ProductAlias copyWithCompanion(ProductAliasesCompanion data) {
    return ProductAlias(
      id: data.id.present ? data.id.value : this.id,
      householdId: data.householdId.present
          ? data.householdId.value
          : this.householdId,
      storeId: data.storeId.present ? data.storeId.value : this.storeId,
      aliasText: data.aliasText.present ? data.aliasText.value : this.aliasText,
      productId: data.productId.present ? data.productId.value : this.productId,
      hits: data.hits.present ? data.hits.value : this.hits,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProductAlias(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('storeId: $storeId, ')
          ..write('aliasText: $aliasText, ')
          ..write('productId: $productId, ')
          ..write('hits: $hits, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    householdId,
    storeId,
    aliasText,
    productId,
    hits,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProductAlias &&
          other.id == this.id &&
          other.householdId == this.householdId &&
          other.storeId == this.storeId &&
          other.aliasText == this.aliasText &&
          other.productId == this.productId &&
          other.hits == this.hits &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class ProductAliasesCompanion extends UpdateCompanion<ProductAlias> {
  final Value<String> id;
  final Value<String> householdId;
  final Value<String?> storeId;
  final Value<String> aliasText;
  final Value<String> productId;
  final Value<int> hits;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const ProductAliasesCompanion({
    this.id = const Value.absent(),
    this.householdId = const Value.absent(),
    this.storeId = const Value.absent(),
    this.aliasText = const Value.absent(),
    this.productId = const Value.absent(),
    this.hits = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProductAliasesCompanion.insert({
    required String id,
    required String householdId,
    this.storeId = const Value.absent(),
    required String aliasText,
    required String productId,
    this.hits = const Value.absent(),
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       householdId = Value(householdId),
       aliasText = Value(aliasText),
       productId = Value(productId),
       updatedAt = Value(updatedAt);
  static Insertable<ProductAlias> custom({
    Expression<String>? id,
    Expression<String>? householdId,
    Expression<String>? storeId,
    Expression<String>? aliasText,
    Expression<String>? productId,
    Expression<int>? hits,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (householdId != null) 'household_id': householdId,
      if (storeId != null) 'store_id': storeId,
      if (aliasText != null) 'alias_text': aliasText,
      if (productId != null) 'product_id': productId,
      if (hits != null) 'hits': hits,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProductAliasesCompanion copyWith({
    Value<String>? id,
    Value<String>? householdId,
    Value<String?>? storeId,
    Value<String>? aliasText,
    Value<String>? productId,
    Value<int>? hits,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return ProductAliasesCompanion(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      storeId: storeId ?? this.storeId,
      aliasText: aliasText ?? this.aliasText,
      productId: productId ?? this.productId,
      hits: hits ?? this.hits,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (householdId.present) {
      map['household_id'] = Variable<String>(householdId.value);
    }
    if (storeId.present) {
      map['store_id'] = Variable<String>(storeId.value);
    }
    if (aliasText.present) {
      map['alias_text'] = Variable<String>(aliasText.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (hits.present) {
      map['hits'] = Variable<int>(hits.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProductAliasesCompanion(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('storeId: $storeId, ')
          ..write('aliasText: $aliasText, ')
          ..write('productId: $productId, ')
          ..write('hits: $hits, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StoresTable extends Stores with TableInfo<$StoresTable, Store> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StoresTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _householdIdMeta = const VerificationMeta(
    'householdId',
  );
  @override
  late final GeneratedColumn<String> householdId = GeneratedColumn<String>(
    'household_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chainMeta = const VerificationMeta('chain');
  @override
  late final GeneratedColumn<String> chain = GeneratedColumn<String>(
    'chain',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchMeta = const VerificationMeta('branch');
  @override
  late final GeneratedColumn<String> branch = GeneratedColumn<String>(
    'branch',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    householdId,
    chain,
    branch,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stores';
  @override
  VerificationContext validateIntegrity(
    Insertable<Store> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('household_id')) {
      context.handle(
        _householdIdMeta,
        householdId.isAcceptableOrUnknown(
          data['household_id']!,
          _householdIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_householdIdMeta);
    }
    if (data.containsKey('chain')) {
      context.handle(
        _chainMeta,
        chain.isAcceptableOrUnknown(data['chain']!, _chainMeta),
      );
    } else if (isInserting) {
      context.missing(_chainMeta);
    }
    if (data.containsKey('branch')) {
      context.handle(
        _branchMeta,
        branch.isAcceptableOrUnknown(data['branch']!, _branchMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Store map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Store(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      householdId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}household_id'],
      )!,
      chain: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chain'],
      )!,
      branch: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $StoresTable createAlias(String alias) {
    return $StoresTable(attachedDatabase, alias);
  }
}

class Store extends DataClass implements Insertable<Store> {
  final String id;
  final String householdId;
  final String chain;

  /// Filialkennung, z.B. "0643"
  final String? branch;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const Store({
    required this.id,
    required this.householdId,
    required this.chain,
    this.branch,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['household_id'] = Variable<String>(householdId);
    map['chain'] = Variable<String>(chain);
    if (!nullToAbsent || branch != null) {
      map['branch'] = Variable<String>(branch);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  StoresCompanion toCompanion(bool nullToAbsent) {
    return StoresCompanion(
      id: Value(id),
      householdId: Value(householdId),
      chain: Value(chain),
      branch: branch == null && nullToAbsent
          ? const Value.absent()
          : Value(branch),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory Store.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Store(
      id: serializer.fromJson<String>(json['id']),
      householdId: serializer.fromJson<String>(json['householdId']),
      chain: serializer.fromJson<String>(json['chain']),
      branch: serializer.fromJson<String?>(json['branch']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'householdId': serializer.toJson<String>(householdId),
      'chain': serializer.toJson<String>(chain),
      'branch': serializer.toJson<String?>(branch),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  Store copyWith({
    String? id,
    String? householdId,
    String? chain,
    Value<String?> branch = const Value.absent(),
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => Store(
    id: id ?? this.id,
    householdId: householdId ?? this.householdId,
    chain: chain ?? this.chain,
    branch: branch.present ? branch.value : this.branch,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  Store copyWithCompanion(StoresCompanion data) {
    return Store(
      id: data.id.present ? data.id.value : this.id,
      householdId: data.householdId.present
          ? data.householdId.value
          : this.householdId,
      chain: data.chain.present ? data.chain.value : this.chain,
      branch: data.branch.present ? data.branch.value : this.branch,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Store(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('chain: $chain, ')
          ..write('branch: $branch, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, householdId, chain, branch, updatedAt, deletedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Store &&
          other.id == this.id &&
          other.householdId == this.householdId &&
          other.chain == this.chain &&
          other.branch == this.branch &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class StoresCompanion extends UpdateCompanion<Store> {
  final Value<String> id;
  final Value<String> householdId;
  final Value<String> chain;
  final Value<String?> branch;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const StoresCompanion({
    this.id = const Value.absent(),
    this.householdId = const Value.absent(),
    this.chain = const Value.absent(),
    this.branch = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StoresCompanion.insert({
    required String id,
    required String householdId,
    required String chain,
    this.branch = const Value.absent(),
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       householdId = Value(householdId),
       chain = Value(chain),
       updatedAt = Value(updatedAt);
  static Insertable<Store> custom({
    Expression<String>? id,
    Expression<String>? householdId,
    Expression<String>? chain,
    Expression<String>? branch,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (householdId != null) 'household_id': householdId,
      if (chain != null) 'chain': chain,
      if (branch != null) 'branch': branch,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StoresCompanion copyWith({
    Value<String>? id,
    Value<String>? householdId,
    Value<String>? chain,
    Value<String?>? branch,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return StoresCompanion(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      chain: chain ?? this.chain,
      branch: branch ?? this.branch,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (householdId.present) {
      map['household_id'] = Variable<String>(householdId.value);
    }
    if (chain.present) {
      map['chain'] = Variable<String>(chain.value);
    }
    if (branch.present) {
      map['branch'] = Variable<String>(branch.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoresCompanion(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('chain: $chain, ')
          ..write('branch: $branch, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReceiptsTable extends Receipts with TableInfo<$ReceiptsTable, Receipt> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReceiptsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _householdIdMeta = const VerificationMeta(
    'householdId',
  );
  @override
  late final GeneratedColumn<String> householdId = GeneratedColumn<String>(
    'household_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _storeIdMeta = const VerificationMeta(
    'storeId',
  );
  @override
  late final GeneratedColumn<String> storeId = GeneratedColumn<String>(
    'store_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _purchasedAtMeta = const VerificationMeta(
    'purchasedAt',
  );
  @override
  late final GeneratedColumn<DateTime> purchasedAt = GeneratedColumn<DateTime>(
    'purchased_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _totalCentsMeta = const VerificationMeta(
    'totalCents',
  );
  @override
  late final GeneratedColumn<int> totalCents = GeneratedColumn<int>(
    'total_cents',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('confirmed'),
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('manual'),
  );
  static const VerificationMeta _externalIdMeta = const VerificationMeta(
    'externalId',
  );
  @override
  late final GeneratedColumn<String> externalId = GeneratedColumn<String>(
    'external_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _confidenceMeta = const VerificationMeta(
    'confidence',
  );
  @override
  late final GeneratedColumn<double> confidence = GeneratedColumn<double>(
    'confidence',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sumMismatchMeta = const VerificationMeta(
    'sumMismatch',
  );
  @override
  late final GeneratedColumn<bool> sumMismatch = GeneratedColumn<bool>(
    'sum_mismatch',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("sum_mismatch" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    householdId,
    storeId,
    purchasedAt,
    totalCents,
    status,
    source,
    externalId,
    confidence,
    sumMismatch,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'receipts';
  @override
  VerificationContext validateIntegrity(
    Insertable<Receipt> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('household_id')) {
      context.handle(
        _householdIdMeta,
        householdId.isAcceptableOrUnknown(
          data['household_id']!,
          _householdIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_householdIdMeta);
    }
    if (data.containsKey('store_id')) {
      context.handle(
        _storeIdMeta,
        storeId.isAcceptableOrUnknown(data['store_id']!, _storeIdMeta),
      );
    }
    if (data.containsKey('purchased_at')) {
      context.handle(
        _purchasedAtMeta,
        purchasedAt.isAcceptableOrUnknown(
          data['purchased_at']!,
          _purchasedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_purchasedAtMeta);
    }
    if (data.containsKey('total_cents')) {
      context.handle(
        _totalCentsMeta,
        totalCents.isAcceptableOrUnknown(data['total_cents']!, _totalCentsMeta),
      );
    } else if (isInserting) {
      context.missing(_totalCentsMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('external_id')) {
      context.handle(
        _externalIdMeta,
        externalId.isAcceptableOrUnknown(data['external_id']!, _externalIdMeta),
      );
    }
    if (data.containsKey('confidence')) {
      context.handle(
        _confidenceMeta,
        confidence.isAcceptableOrUnknown(data['confidence']!, _confidenceMeta),
      );
    }
    if (data.containsKey('sum_mismatch')) {
      context.handle(
        _sumMismatchMeta,
        sumMismatch.isAcceptableOrUnknown(
          data['sum_mismatch']!,
          _sumMismatchMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Receipt map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Receipt(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      householdId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}household_id'],
      )!,
      storeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}store_id'],
      ),
      purchasedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}purchased_at'],
      )!,
      totalCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_cents'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      externalId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}external_id'],
      ),
      confidence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}confidence'],
      ),
      sumMismatch: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}sum_mismatch'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $ReceiptsTable createAlias(String alias) {
    return $ReceiptsTable(attachedDatabase, alias);
  }
}

class Receipt extends DataClass implements Insertable<Receipt> {
  final String id;
  final String householdId;
  final String? storeId;
  final DateTime purchasedAt;
  final int totalCents;

  /// 'draft' | 'confirmed' | 'pending'
  final String status;

  /// 'pdf_text' | 'on_device' | 'llm' | 'manual'
  final String source;

  /// Eindeutige Kennung des Kaufs (bei Billa die Re-Nr), Grundlage der Duplikaterkennung.
  final String? externalId;
  final double? confidence;
  final bool sumMismatch;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const Receipt({
    required this.id,
    required this.householdId,
    this.storeId,
    required this.purchasedAt,
    required this.totalCents,
    required this.status,
    required this.source,
    this.externalId,
    this.confidence,
    required this.sumMismatch,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['household_id'] = Variable<String>(householdId);
    if (!nullToAbsent || storeId != null) {
      map['store_id'] = Variable<String>(storeId);
    }
    map['purchased_at'] = Variable<DateTime>(purchasedAt);
    map['total_cents'] = Variable<int>(totalCents);
    map['status'] = Variable<String>(status);
    map['source'] = Variable<String>(source);
    if (!nullToAbsent || externalId != null) {
      map['external_id'] = Variable<String>(externalId);
    }
    if (!nullToAbsent || confidence != null) {
      map['confidence'] = Variable<double>(confidence);
    }
    map['sum_mismatch'] = Variable<bool>(sumMismatch);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  ReceiptsCompanion toCompanion(bool nullToAbsent) {
    return ReceiptsCompanion(
      id: Value(id),
      householdId: Value(householdId),
      storeId: storeId == null && nullToAbsent
          ? const Value.absent()
          : Value(storeId),
      purchasedAt: Value(purchasedAt),
      totalCents: Value(totalCents),
      status: Value(status),
      source: Value(source),
      externalId: externalId == null && nullToAbsent
          ? const Value.absent()
          : Value(externalId),
      confidence: confidence == null && nullToAbsent
          ? const Value.absent()
          : Value(confidence),
      sumMismatch: Value(sumMismatch),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory Receipt.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Receipt(
      id: serializer.fromJson<String>(json['id']),
      householdId: serializer.fromJson<String>(json['householdId']),
      storeId: serializer.fromJson<String?>(json['storeId']),
      purchasedAt: serializer.fromJson<DateTime>(json['purchasedAt']),
      totalCents: serializer.fromJson<int>(json['totalCents']),
      status: serializer.fromJson<String>(json['status']),
      source: serializer.fromJson<String>(json['source']),
      externalId: serializer.fromJson<String?>(json['externalId']),
      confidence: serializer.fromJson<double?>(json['confidence']),
      sumMismatch: serializer.fromJson<bool>(json['sumMismatch']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'householdId': serializer.toJson<String>(householdId),
      'storeId': serializer.toJson<String?>(storeId),
      'purchasedAt': serializer.toJson<DateTime>(purchasedAt),
      'totalCents': serializer.toJson<int>(totalCents),
      'status': serializer.toJson<String>(status),
      'source': serializer.toJson<String>(source),
      'externalId': serializer.toJson<String?>(externalId),
      'confidence': serializer.toJson<double?>(confidence),
      'sumMismatch': serializer.toJson<bool>(sumMismatch),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  Receipt copyWith({
    String? id,
    String? householdId,
    Value<String?> storeId = const Value.absent(),
    DateTime? purchasedAt,
    int? totalCents,
    String? status,
    String? source,
    Value<String?> externalId = const Value.absent(),
    Value<double?> confidence = const Value.absent(),
    bool? sumMismatch,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => Receipt(
    id: id ?? this.id,
    householdId: householdId ?? this.householdId,
    storeId: storeId.present ? storeId.value : this.storeId,
    purchasedAt: purchasedAt ?? this.purchasedAt,
    totalCents: totalCents ?? this.totalCents,
    status: status ?? this.status,
    source: source ?? this.source,
    externalId: externalId.present ? externalId.value : this.externalId,
    confidence: confidence.present ? confidence.value : this.confidence,
    sumMismatch: sumMismatch ?? this.sumMismatch,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  Receipt copyWithCompanion(ReceiptsCompanion data) {
    return Receipt(
      id: data.id.present ? data.id.value : this.id,
      householdId: data.householdId.present
          ? data.householdId.value
          : this.householdId,
      storeId: data.storeId.present ? data.storeId.value : this.storeId,
      purchasedAt: data.purchasedAt.present
          ? data.purchasedAt.value
          : this.purchasedAt,
      totalCents: data.totalCents.present
          ? data.totalCents.value
          : this.totalCents,
      status: data.status.present ? data.status.value : this.status,
      source: data.source.present ? data.source.value : this.source,
      externalId: data.externalId.present
          ? data.externalId.value
          : this.externalId,
      confidence: data.confidence.present
          ? data.confidence.value
          : this.confidence,
      sumMismatch: data.sumMismatch.present
          ? data.sumMismatch.value
          : this.sumMismatch,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Receipt(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('storeId: $storeId, ')
          ..write('purchasedAt: $purchasedAt, ')
          ..write('totalCents: $totalCents, ')
          ..write('status: $status, ')
          ..write('source: $source, ')
          ..write('externalId: $externalId, ')
          ..write('confidence: $confidence, ')
          ..write('sumMismatch: $sumMismatch, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    householdId,
    storeId,
    purchasedAt,
    totalCents,
    status,
    source,
    externalId,
    confidence,
    sumMismatch,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Receipt &&
          other.id == this.id &&
          other.householdId == this.householdId &&
          other.storeId == this.storeId &&
          other.purchasedAt == this.purchasedAt &&
          other.totalCents == this.totalCents &&
          other.status == this.status &&
          other.source == this.source &&
          other.externalId == this.externalId &&
          other.confidence == this.confidence &&
          other.sumMismatch == this.sumMismatch &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class ReceiptsCompanion extends UpdateCompanion<Receipt> {
  final Value<String> id;
  final Value<String> householdId;
  final Value<String?> storeId;
  final Value<DateTime> purchasedAt;
  final Value<int> totalCents;
  final Value<String> status;
  final Value<String> source;
  final Value<String?> externalId;
  final Value<double?> confidence;
  final Value<bool> sumMismatch;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const ReceiptsCompanion({
    this.id = const Value.absent(),
    this.householdId = const Value.absent(),
    this.storeId = const Value.absent(),
    this.purchasedAt = const Value.absent(),
    this.totalCents = const Value.absent(),
    this.status = const Value.absent(),
    this.source = const Value.absent(),
    this.externalId = const Value.absent(),
    this.confidence = const Value.absent(),
    this.sumMismatch = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReceiptsCompanion.insert({
    required String id,
    required String householdId,
    this.storeId = const Value.absent(),
    required DateTime purchasedAt,
    required int totalCents,
    this.status = const Value.absent(),
    this.source = const Value.absent(),
    this.externalId = const Value.absent(),
    this.confidence = const Value.absent(),
    this.sumMismatch = const Value.absent(),
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       householdId = Value(householdId),
       purchasedAt = Value(purchasedAt),
       totalCents = Value(totalCents),
       updatedAt = Value(updatedAt);
  static Insertable<Receipt> custom({
    Expression<String>? id,
    Expression<String>? householdId,
    Expression<String>? storeId,
    Expression<DateTime>? purchasedAt,
    Expression<int>? totalCents,
    Expression<String>? status,
    Expression<String>? source,
    Expression<String>? externalId,
    Expression<double>? confidence,
    Expression<bool>? sumMismatch,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (householdId != null) 'household_id': householdId,
      if (storeId != null) 'store_id': storeId,
      if (purchasedAt != null) 'purchased_at': purchasedAt,
      if (totalCents != null) 'total_cents': totalCents,
      if (status != null) 'status': status,
      if (source != null) 'source': source,
      if (externalId != null) 'external_id': externalId,
      if (confidence != null) 'confidence': confidence,
      if (sumMismatch != null) 'sum_mismatch': sumMismatch,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReceiptsCompanion copyWith({
    Value<String>? id,
    Value<String>? householdId,
    Value<String?>? storeId,
    Value<DateTime>? purchasedAt,
    Value<int>? totalCents,
    Value<String>? status,
    Value<String>? source,
    Value<String?>? externalId,
    Value<double?>? confidence,
    Value<bool>? sumMismatch,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return ReceiptsCompanion(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      storeId: storeId ?? this.storeId,
      purchasedAt: purchasedAt ?? this.purchasedAt,
      totalCents: totalCents ?? this.totalCents,
      status: status ?? this.status,
      source: source ?? this.source,
      externalId: externalId ?? this.externalId,
      confidence: confidence ?? this.confidence,
      sumMismatch: sumMismatch ?? this.sumMismatch,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (householdId.present) {
      map['household_id'] = Variable<String>(householdId.value);
    }
    if (storeId.present) {
      map['store_id'] = Variable<String>(storeId.value);
    }
    if (purchasedAt.present) {
      map['purchased_at'] = Variable<DateTime>(purchasedAt.value);
    }
    if (totalCents.present) {
      map['total_cents'] = Variable<int>(totalCents.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (externalId.present) {
      map['external_id'] = Variable<String>(externalId.value);
    }
    if (confidence.present) {
      map['confidence'] = Variable<double>(confidence.value);
    }
    if (sumMismatch.present) {
      map['sum_mismatch'] = Variable<bool>(sumMismatch.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReceiptsCompanion(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('storeId: $storeId, ')
          ..write('purchasedAt: $purchasedAt, ')
          ..write('totalCents: $totalCents, ')
          ..write('status: $status, ')
          ..write('source: $source, ')
          ..write('externalId: $externalId, ')
          ..write('confidence: $confidence, ')
          ..write('sumMismatch: $sumMismatch, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReceiptItemsTable extends ReceiptItems
    with TableInfo<$ReceiptItemsTable, ReceiptItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReceiptItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _householdIdMeta = const VerificationMeta(
    'householdId',
  );
  @override
  late final GeneratedColumn<String> householdId = GeneratedColumn<String>(
    'household_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _receiptIdMeta = const VerificationMeta(
    'receiptId',
  );
  @override
  late final GeneratedColumn<String> receiptId = GeneratedColumn<String>(
    'receipt_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lineNoMeta = const VerificationMeta('lineNo');
  @override
  late final GeneratedColumn<int> lineNo = GeneratedColumn<int>(
    'line_no',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('article'),
  );
  static const VerificationMeta _rawTextMeta = const VerificationMeta(
    'rawText',
  );
  @override
  late final GeneratedColumn<String> rawText = GeneratedColumn<String>(
    'raw_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _productIdMeta = const VerificationMeta(
    'productId',
  );
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
    'product_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _brandMeta = const VerificationMeta('brand');
  @override
  late final GeneratedColumn<String> brand = GeneratedColumn<String>(
    'brand',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _quantityMeta = const VerificationMeta(
    'quantity',
  );
  @override
  late final GeneratedColumn<double> quantity = GeneratedColumn<double>(
    'quantity',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _quantityUnitMeta = const VerificationMeta(
    'quantityUnit',
  );
  @override
  late final GeneratedColumn<String> quantityUnit = GeneratedColumn<String>(
    'quantity_unit',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('piece'),
  );
  static const VerificationMeta _unitPriceCentsMeta = const VerificationMeta(
    'unitPriceCents',
  );
  @override
  late final GeneratedColumn<int> unitPriceCents = GeneratedColumn<int>(
    'unit_price_cents',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lineTotalCentsMeta = const VerificationMeta(
    'lineTotalCents',
  );
  @override
  late final GeneratedColumn<int> lineTotalCents = GeneratedColumn<int>(
    'line_total_cents',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _unitPriceNormCentsMeta =
      const VerificationMeta('unitPriceNormCents');
  @override
  late final GeneratedColumn<int> unitPriceNormCents = GeneratedColumn<int>(
    'unit_price_norm_cents',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _taxCodeMeta = const VerificationMeta(
    'taxCode',
  );
  @override
  late final GeneratedColumn<String> taxCode = GeneratedColumn<String>(
    'tax_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _needsReviewMeta = const VerificationMeta(
    'needsReview',
  );
  @override
  late final GeneratedColumn<bool> needsReview = GeneratedColumn<bool>(
    'needs_review',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("needs_review" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _excludedMeta = const VerificationMeta(
    'excluded',
  );
  @override
  late final GeneratedColumn<bool> excluded = GeneratedColumn<bool>(
    'excluded',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("excluded" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    householdId,
    receiptId,
    lineNo,
    kind,
    rawText,
    productId,
    categoryId,
    brand,
    quantity,
    quantityUnit,
    unitPriceCents,
    lineTotalCents,
    unitPriceNormCents,
    taxCode,
    needsReview,
    excluded,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'receipt_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReceiptItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('household_id')) {
      context.handle(
        _householdIdMeta,
        householdId.isAcceptableOrUnknown(
          data['household_id']!,
          _householdIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_householdIdMeta);
    }
    if (data.containsKey('receipt_id')) {
      context.handle(
        _receiptIdMeta,
        receiptId.isAcceptableOrUnknown(data['receipt_id']!, _receiptIdMeta),
      );
    } else if (isInserting) {
      context.missing(_receiptIdMeta);
    }
    if (data.containsKey('line_no')) {
      context.handle(
        _lineNoMeta,
        lineNo.isAcceptableOrUnknown(data['line_no']!, _lineNoMeta),
      );
    } else if (isInserting) {
      context.missing(_lineNoMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    }
    if (data.containsKey('raw_text')) {
      context.handle(
        _rawTextMeta,
        rawText.isAcceptableOrUnknown(data['raw_text']!, _rawTextMeta),
      );
    } else if (isInserting) {
      context.missing(_rawTextMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(
        _productIdMeta,
        productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta),
      );
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('brand')) {
      context.handle(
        _brandMeta,
        brand.isAcceptableOrUnknown(data['brand']!, _brandMeta),
      );
    }
    if (data.containsKey('quantity')) {
      context.handle(
        _quantityMeta,
        quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta),
      );
    }
    if (data.containsKey('quantity_unit')) {
      context.handle(
        _quantityUnitMeta,
        quantityUnit.isAcceptableOrUnknown(
          data['quantity_unit']!,
          _quantityUnitMeta,
        ),
      );
    }
    if (data.containsKey('unit_price_cents')) {
      context.handle(
        _unitPriceCentsMeta,
        unitPriceCents.isAcceptableOrUnknown(
          data['unit_price_cents']!,
          _unitPriceCentsMeta,
        ),
      );
    }
    if (data.containsKey('line_total_cents')) {
      context.handle(
        _lineTotalCentsMeta,
        lineTotalCents.isAcceptableOrUnknown(
          data['line_total_cents']!,
          _lineTotalCentsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lineTotalCentsMeta);
    }
    if (data.containsKey('unit_price_norm_cents')) {
      context.handle(
        _unitPriceNormCentsMeta,
        unitPriceNormCents.isAcceptableOrUnknown(
          data['unit_price_norm_cents']!,
          _unitPriceNormCentsMeta,
        ),
      );
    }
    if (data.containsKey('tax_code')) {
      context.handle(
        _taxCodeMeta,
        taxCode.isAcceptableOrUnknown(data['tax_code']!, _taxCodeMeta),
      );
    }
    if (data.containsKey('needs_review')) {
      context.handle(
        _needsReviewMeta,
        needsReview.isAcceptableOrUnknown(
          data['needs_review']!,
          _needsReviewMeta,
        ),
      );
    }
    if (data.containsKey('excluded')) {
      context.handle(
        _excludedMeta,
        excluded.isAcceptableOrUnknown(data['excluded']!, _excludedMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ReceiptItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReceiptItem(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      householdId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}household_id'],
      )!,
      receiptId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}receipt_id'],
      )!,
      lineNo: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}line_no'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      rawText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_text'],
      )!,
      productId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}product_id'],
      ),
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      ),
      brand: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}brand'],
      ),
      quantity: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}quantity'],
      )!,
      quantityUnit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}quantity_unit'],
      )!,
      unitPriceCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unit_price_cents'],
      ),
      lineTotalCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}line_total_cents'],
      )!,
      unitPriceNormCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unit_price_norm_cents'],
      ),
      taxCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tax_code'],
      ),
      needsReview: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}needs_review'],
      )!,
      excluded: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}excluded'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $ReceiptItemsTable createAlias(String alias) {
    return $ReceiptItemsTable(attachedDatabase, alias);
  }
}

class ReceiptItem extends DataClass implements Insertable<ReceiptItem> {
  final String id;
  final String householdId;
  final String receiptId;
  final int lineNo;

  /// 'article' | 'deposit' | 'discount'
  final String kind;
  final String rawText;
  final String? productId;
  final String? categoryId;
  final String? brand;
  final double quantity;

  /// 'piece' | 'kg' | 'l'
  final String quantityUnit;
  final int? unitPriceCents;
  final int lineTotalCents;

  /// Grundpreis je Basiseinheit des Produkts, in Cent (Doku 07 §3.1). `null`, wenn nicht berechenbar
  /// (kein Produkt zugeordnet oder Packware ohne bekannten Packungsinhalt).
  final int? unitPriceNormCents;
  final String? taxCode;
  final bool needsReview;

  /// Von jemand anderem bezahlt (ADR-020 "Rechnungen teilen"): zaehlt nicht zur eigenen Auswertung,
  /// bleibt aber auf dem Bon sichtbar und wandert normal ins Inventar.
  final bool excluded;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const ReceiptItem({
    required this.id,
    required this.householdId,
    required this.receiptId,
    required this.lineNo,
    required this.kind,
    required this.rawText,
    this.productId,
    this.categoryId,
    this.brand,
    required this.quantity,
    required this.quantityUnit,
    this.unitPriceCents,
    required this.lineTotalCents,
    this.unitPriceNormCents,
    this.taxCode,
    required this.needsReview,
    required this.excluded,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['household_id'] = Variable<String>(householdId);
    map['receipt_id'] = Variable<String>(receiptId);
    map['line_no'] = Variable<int>(lineNo);
    map['kind'] = Variable<String>(kind);
    map['raw_text'] = Variable<String>(rawText);
    if (!nullToAbsent || productId != null) {
      map['product_id'] = Variable<String>(productId);
    }
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    if (!nullToAbsent || brand != null) {
      map['brand'] = Variable<String>(brand);
    }
    map['quantity'] = Variable<double>(quantity);
    map['quantity_unit'] = Variable<String>(quantityUnit);
    if (!nullToAbsent || unitPriceCents != null) {
      map['unit_price_cents'] = Variable<int>(unitPriceCents);
    }
    map['line_total_cents'] = Variable<int>(lineTotalCents);
    if (!nullToAbsent || unitPriceNormCents != null) {
      map['unit_price_norm_cents'] = Variable<int>(unitPriceNormCents);
    }
    if (!nullToAbsent || taxCode != null) {
      map['tax_code'] = Variable<String>(taxCode);
    }
    map['needs_review'] = Variable<bool>(needsReview);
    map['excluded'] = Variable<bool>(excluded);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  ReceiptItemsCompanion toCompanion(bool nullToAbsent) {
    return ReceiptItemsCompanion(
      id: Value(id),
      householdId: Value(householdId),
      receiptId: Value(receiptId),
      lineNo: Value(lineNo),
      kind: Value(kind),
      rawText: Value(rawText),
      productId: productId == null && nullToAbsent
          ? const Value.absent()
          : Value(productId),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      brand: brand == null && nullToAbsent
          ? const Value.absent()
          : Value(brand),
      quantity: Value(quantity),
      quantityUnit: Value(quantityUnit),
      unitPriceCents: unitPriceCents == null && nullToAbsent
          ? const Value.absent()
          : Value(unitPriceCents),
      lineTotalCents: Value(lineTotalCents),
      unitPriceNormCents: unitPriceNormCents == null && nullToAbsent
          ? const Value.absent()
          : Value(unitPriceNormCents),
      taxCode: taxCode == null && nullToAbsent
          ? const Value.absent()
          : Value(taxCode),
      needsReview: Value(needsReview),
      excluded: Value(excluded),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory ReceiptItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReceiptItem(
      id: serializer.fromJson<String>(json['id']),
      householdId: serializer.fromJson<String>(json['householdId']),
      receiptId: serializer.fromJson<String>(json['receiptId']),
      lineNo: serializer.fromJson<int>(json['lineNo']),
      kind: serializer.fromJson<String>(json['kind']),
      rawText: serializer.fromJson<String>(json['rawText']),
      productId: serializer.fromJson<String?>(json['productId']),
      categoryId: serializer.fromJson<String?>(json['categoryId']),
      brand: serializer.fromJson<String?>(json['brand']),
      quantity: serializer.fromJson<double>(json['quantity']),
      quantityUnit: serializer.fromJson<String>(json['quantityUnit']),
      unitPriceCents: serializer.fromJson<int?>(json['unitPriceCents']),
      lineTotalCents: serializer.fromJson<int>(json['lineTotalCents']),
      unitPriceNormCents: serializer.fromJson<int?>(json['unitPriceNormCents']),
      taxCode: serializer.fromJson<String?>(json['taxCode']),
      needsReview: serializer.fromJson<bool>(json['needsReview']),
      excluded: serializer.fromJson<bool>(json['excluded']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'householdId': serializer.toJson<String>(householdId),
      'receiptId': serializer.toJson<String>(receiptId),
      'lineNo': serializer.toJson<int>(lineNo),
      'kind': serializer.toJson<String>(kind),
      'rawText': serializer.toJson<String>(rawText),
      'productId': serializer.toJson<String?>(productId),
      'categoryId': serializer.toJson<String?>(categoryId),
      'brand': serializer.toJson<String?>(brand),
      'quantity': serializer.toJson<double>(quantity),
      'quantityUnit': serializer.toJson<String>(quantityUnit),
      'unitPriceCents': serializer.toJson<int?>(unitPriceCents),
      'lineTotalCents': serializer.toJson<int>(lineTotalCents),
      'unitPriceNormCents': serializer.toJson<int?>(unitPriceNormCents),
      'taxCode': serializer.toJson<String?>(taxCode),
      'needsReview': serializer.toJson<bool>(needsReview),
      'excluded': serializer.toJson<bool>(excluded),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  ReceiptItem copyWith({
    String? id,
    String? householdId,
    String? receiptId,
    int? lineNo,
    String? kind,
    String? rawText,
    Value<String?> productId = const Value.absent(),
    Value<String?> categoryId = const Value.absent(),
    Value<String?> brand = const Value.absent(),
    double? quantity,
    String? quantityUnit,
    Value<int?> unitPriceCents = const Value.absent(),
    int? lineTotalCents,
    Value<int?> unitPriceNormCents = const Value.absent(),
    Value<String?> taxCode = const Value.absent(),
    bool? needsReview,
    bool? excluded,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => ReceiptItem(
    id: id ?? this.id,
    householdId: householdId ?? this.householdId,
    receiptId: receiptId ?? this.receiptId,
    lineNo: lineNo ?? this.lineNo,
    kind: kind ?? this.kind,
    rawText: rawText ?? this.rawText,
    productId: productId.present ? productId.value : this.productId,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    brand: brand.present ? brand.value : this.brand,
    quantity: quantity ?? this.quantity,
    quantityUnit: quantityUnit ?? this.quantityUnit,
    unitPriceCents: unitPriceCents.present
        ? unitPriceCents.value
        : this.unitPriceCents,
    lineTotalCents: lineTotalCents ?? this.lineTotalCents,
    unitPriceNormCents: unitPriceNormCents.present
        ? unitPriceNormCents.value
        : this.unitPriceNormCents,
    taxCode: taxCode.present ? taxCode.value : this.taxCode,
    needsReview: needsReview ?? this.needsReview,
    excluded: excluded ?? this.excluded,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  ReceiptItem copyWithCompanion(ReceiptItemsCompanion data) {
    return ReceiptItem(
      id: data.id.present ? data.id.value : this.id,
      householdId: data.householdId.present
          ? data.householdId.value
          : this.householdId,
      receiptId: data.receiptId.present ? data.receiptId.value : this.receiptId,
      lineNo: data.lineNo.present ? data.lineNo.value : this.lineNo,
      kind: data.kind.present ? data.kind.value : this.kind,
      rawText: data.rawText.present ? data.rawText.value : this.rawText,
      productId: data.productId.present ? data.productId.value : this.productId,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      brand: data.brand.present ? data.brand.value : this.brand,
      quantity: data.quantity.present ? data.quantity.value : this.quantity,
      quantityUnit: data.quantityUnit.present
          ? data.quantityUnit.value
          : this.quantityUnit,
      unitPriceCents: data.unitPriceCents.present
          ? data.unitPriceCents.value
          : this.unitPriceCents,
      lineTotalCents: data.lineTotalCents.present
          ? data.lineTotalCents.value
          : this.lineTotalCents,
      unitPriceNormCents: data.unitPriceNormCents.present
          ? data.unitPriceNormCents.value
          : this.unitPriceNormCents,
      taxCode: data.taxCode.present ? data.taxCode.value : this.taxCode,
      needsReview: data.needsReview.present
          ? data.needsReview.value
          : this.needsReview,
      excluded: data.excluded.present ? data.excluded.value : this.excluded,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReceiptItem(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('receiptId: $receiptId, ')
          ..write('lineNo: $lineNo, ')
          ..write('kind: $kind, ')
          ..write('rawText: $rawText, ')
          ..write('productId: $productId, ')
          ..write('categoryId: $categoryId, ')
          ..write('brand: $brand, ')
          ..write('quantity: $quantity, ')
          ..write('quantityUnit: $quantityUnit, ')
          ..write('unitPriceCents: $unitPriceCents, ')
          ..write('lineTotalCents: $lineTotalCents, ')
          ..write('unitPriceNormCents: $unitPriceNormCents, ')
          ..write('taxCode: $taxCode, ')
          ..write('needsReview: $needsReview, ')
          ..write('excluded: $excluded, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    householdId,
    receiptId,
    lineNo,
    kind,
    rawText,
    productId,
    categoryId,
    brand,
    quantity,
    quantityUnit,
    unitPriceCents,
    lineTotalCents,
    unitPriceNormCents,
    taxCode,
    needsReview,
    excluded,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReceiptItem &&
          other.id == this.id &&
          other.householdId == this.householdId &&
          other.receiptId == this.receiptId &&
          other.lineNo == this.lineNo &&
          other.kind == this.kind &&
          other.rawText == this.rawText &&
          other.productId == this.productId &&
          other.categoryId == this.categoryId &&
          other.brand == this.brand &&
          other.quantity == this.quantity &&
          other.quantityUnit == this.quantityUnit &&
          other.unitPriceCents == this.unitPriceCents &&
          other.lineTotalCents == this.lineTotalCents &&
          other.unitPriceNormCents == this.unitPriceNormCents &&
          other.taxCode == this.taxCode &&
          other.needsReview == this.needsReview &&
          other.excluded == this.excluded &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class ReceiptItemsCompanion extends UpdateCompanion<ReceiptItem> {
  final Value<String> id;
  final Value<String> householdId;
  final Value<String> receiptId;
  final Value<int> lineNo;
  final Value<String> kind;
  final Value<String> rawText;
  final Value<String?> productId;
  final Value<String?> categoryId;
  final Value<String?> brand;
  final Value<double> quantity;
  final Value<String> quantityUnit;
  final Value<int?> unitPriceCents;
  final Value<int> lineTotalCents;
  final Value<int?> unitPriceNormCents;
  final Value<String?> taxCode;
  final Value<bool> needsReview;
  final Value<bool> excluded;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const ReceiptItemsCompanion({
    this.id = const Value.absent(),
    this.householdId = const Value.absent(),
    this.receiptId = const Value.absent(),
    this.lineNo = const Value.absent(),
    this.kind = const Value.absent(),
    this.rawText = const Value.absent(),
    this.productId = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.brand = const Value.absent(),
    this.quantity = const Value.absent(),
    this.quantityUnit = const Value.absent(),
    this.unitPriceCents = const Value.absent(),
    this.lineTotalCents = const Value.absent(),
    this.unitPriceNormCents = const Value.absent(),
    this.taxCode = const Value.absent(),
    this.needsReview = const Value.absent(),
    this.excluded = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReceiptItemsCompanion.insert({
    required String id,
    required String householdId,
    required String receiptId,
    required int lineNo,
    this.kind = const Value.absent(),
    required String rawText,
    this.productId = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.brand = const Value.absent(),
    this.quantity = const Value.absent(),
    this.quantityUnit = const Value.absent(),
    this.unitPriceCents = const Value.absent(),
    required int lineTotalCents,
    this.unitPriceNormCents = const Value.absent(),
    this.taxCode = const Value.absent(),
    this.needsReview = const Value.absent(),
    this.excluded = const Value.absent(),
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       householdId = Value(householdId),
       receiptId = Value(receiptId),
       lineNo = Value(lineNo),
       rawText = Value(rawText),
       lineTotalCents = Value(lineTotalCents),
       updatedAt = Value(updatedAt);
  static Insertable<ReceiptItem> custom({
    Expression<String>? id,
    Expression<String>? householdId,
    Expression<String>? receiptId,
    Expression<int>? lineNo,
    Expression<String>? kind,
    Expression<String>? rawText,
    Expression<String>? productId,
    Expression<String>? categoryId,
    Expression<String>? brand,
    Expression<double>? quantity,
    Expression<String>? quantityUnit,
    Expression<int>? unitPriceCents,
    Expression<int>? lineTotalCents,
    Expression<int>? unitPriceNormCents,
    Expression<String>? taxCode,
    Expression<bool>? needsReview,
    Expression<bool>? excluded,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (householdId != null) 'household_id': householdId,
      if (receiptId != null) 'receipt_id': receiptId,
      if (lineNo != null) 'line_no': lineNo,
      if (kind != null) 'kind': kind,
      if (rawText != null) 'raw_text': rawText,
      if (productId != null) 'product_id': productId,
      if (categoryId != null) 'category_id': categoryId,
      if (brand != null) 'brand': brand,
      if (quantity != null) 'quantity': quantity,
      if (quantityUnit != null) 'quantity_unit': quantityUnit,
      if (unitPriceCents != null) 'unit_price_cents': unitPriceCents,
      if (lineTotalCents != null) 'line_total_cents': lineTotalCents,
      if (unitPriceNormCents != null)
        'unit_price_norm_cents': unitPriceNormCents,
      if (taxCode != null) 'tax_code': taxCode,
      if (needsReview != null) 'needs_review': needsReview,
      if (excluded != null) 'excluded': excluded,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReceiptItemsCompanion copyWith({
    Value<String>? id,
    Value<String>? householdId,
    Value<String>? receiptId,
    Value<int>? lineNo,
    Value<String>? kind,
    Value<String>? rawText,
    Value<String?>? productId,
    Value<String?>? categoryId,
    Value<String?>? brand,
    Value<double>? quantity,
    Value<String>? quantityUnit,
    Value<int?>? unitPriceCents,
    Value<int>? lineTotalCents,
    Value<int?>? unitPriceNormCents,
    Value<String?>? taxCode,
    Value<bool>? needsReview,
    Value<bool>? excluded,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return ReceiptItemsCompanion(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      receiptId: receiptId ?? this.receiptId,
      lineNo: lineNo ?? this.lineNo,
      kind: kind ?? this.kind,
      rawText: rawText ?? this.rawText,
      productId: productId ?? this.productId,
      categoryId: categoryId ?? this.categoryId,
      brand: brand ?? this.brand,
      quantity: quantity ?? this.quantity,
      quantityUnit: quantityUnit ?? this.quantityUnit,
      unitPriceCents: unitPriceCents ?? this.unitPriceCents,
      lineTotalCents: lineTotalCents ?? this.lineTotalCents,
      unitPriceNormCents: unitPriceNormCents ?? this.unitPriceNormCents,
      taxCode: taxCode ?? this.taxCode,
      needsReview: needsReview ?? this.needsReview,
      excluded: excluded ?? this.excluded,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (householdId.present) {
      map['household_id'] = Variable<String>(householdId.value);
    }
    if (receiptId.present) {
      map['receipt_id'] = Variable<String>(receiptId.value);
    }
    if (lineNo.present) {
      map['line_no'] = Variable<int>(lineNo.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (rawText.present) {
      map['raw_text'] = Variable<String>(rawText.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (brand.present) {
      map['brand'] = Variable<String>(brand.value);
    }
    if (quantity.present) {
      map['quantity'] = Variable<double>(quantity.value);
    }
    if (quantityUnit.present) {
      map['quantity_unit'] = Variable<String>(quantityUnit.value);
    }
    if (unitPriceCents.present) {
      map['unit_price_cents'] = Variable<int>(unitPriceCents.value);
    }
    if (lineTotalCents.present) {
      map['line_total_cents'] = Variable<int>(lineTotalCents.value);
    }
    if (unitPriceNormCents.present) {
      map['unit_price_norm_cents'] = Variable<int>(unitPriceNormCents.value);
    }
    if (taxCode.present) {
      map['tax_code'] = Variable<String>(taxCode.value);
    }
    if (needsReview.present) {
      map['needs_review'] = Variable<bool>(needsReview.value);
    }
    if (excluded.present) {
      map['excluded'] = Variable<bool>(excluded.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReceiptItemsCompanion(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('receiptId: $receiptId, ')
          ..write('lineNo: $lineNo, ')
          ..write('kind: $kind, ')
          ..write('rawText: $rawText, ')
          ..write('productId: $productId, ')
          ..write('categoryId: $categoryId, ')
          ..write('brand: $brand, ')
          ..write('quantity: $quantity, ')
          ..write('quantityUnit: $quantityUnit, ')
          ..write('unitPriceCents: $unitPriceCents, ')
          ..write('lineTotalCents: $lineTotalCents, ')
          ..write('unitPriceNormCents: $unitPriceNormCents, ')
          ..write('taxCode: $taxCode, ')
          ..write('needsReview: $needsReview, ')
          ..write('excluded: $excluded, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CategoryAliasesTable extends CategoryAliases
    with TableInfo<$CategoryAliasesTable, CategoryAlias> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoryAliasesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _householdIdMeta = const VerificationMeta(
    'householdId',
  );
  @override
  late final GeneratedColumn<String> householdId = GeneratedColumn<String>(
    'household_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _aliasTextMeta = const VerificationMeta(
    'aliasText',
  );
  @override
  late final GeneratedColumn<String> aliasText = GeneratedColumn<String>(
    'alias_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hitsMeta = const VerificationMeta('hits');
  @override
  late final GeneratedColumn<int> hits = GeneratedColumn<int>(
    'hits',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    householdId,
    aliasText,
    categoryId,
    hits,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'category_aliases';
  @override
  VerificationContext validateIntegrity(
    Insertable<CategoryAlias> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('household_id')) {
      context.handle(
        _householdIdMeta,
        householdId.isAcceptableOrUnknown(
          data['household_id']!,
          _householdIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_householdIdMeta);
    }
    if (data.containsKey('alias_text')) {
      context.handle(
        _aliasTextMeta,
        aliasText.isAcceptableOrUnknown(data['alias_text']!, _aliasTextMeta),
      );
    } else if (isInserting) {
      context.missing(_aliasTextMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryIdMeta);
    }
    if (data.containsKey('hits')) {
      context.handle(
        _hitsMeta,
        hits.isAcceptableOrUnknown(data['hits']!, _hitsMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CategoryAlias map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CategoryAlias(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      householdId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}household_id'],
      )!,
      aliasText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}alias_text'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      )!,
      hits: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}hits'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $CategoryAliasesTable createAlias(String alias) {
    return $CategoryAliasesTable(attachedDatabase, alias);
  }
}

class CategoryAlias extends DataClass implements Insertable<CategoryAlias> {
  final String id;
  final String householdId;

  /// Ergebnis von normalizeItemName, z.B. "dkih paprika tricolore".
  final String aliasText;
  final String categoryId;
  final int hits;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const CategoryAlias({
    required this.id,
    required this.householdId,
    required this.aliasText,
    required this.categoryId,
    required this.hits,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['household_id'] = Variable<String>(householdId);
    map['alias_text'] = Variable<String>(aliasText);
    map['category_id'] = Variable<String>(categoryId);
    map['hits'] = Variable<int>(hits);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  CategoryAliasesCompanion toCompanion(bool nullToAbsent) {
    return CategoryAliasesCompanion(
      id: Value(id),
      householdId: Value(householdId),
      aliasText: Value(aliasText),
      categoryId: Value(categoryId),
      hits: Value(hits),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory CategoryAlias.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CategoryAlias(
      id: serializer.fromJson<String>(json['id']),
      householdId: serializer.fromJson<String>(json['householdId']),
      aliasText: serializer.fromJson<String>(json['aliasText']),
      categoryId: serializer.fromJson<String>(json['categoryId']),
      hits: serializer.fromJson<int>(json['hits']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'householdId': serializer.toJson<String>(householdId),
      'aliasText': serializer.toJson<String>(aliasText),
      'categoryId': serializer.toJson<String>(categoryId),
      'hits': serializer.toJson<int>(hits),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  CategoryAlias copyWith({
    String? id,
    String? householdId,
    String? aliasText,
    String? categoryId,
    int? hits,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => CategoryAlias(
    id: id ?? this.id,
    householdId: householdId ?? this.householdId,
    aliasText: aliasText ?? this.aliasText,
    categoryId: categoryId ?? this.categoryId,
    hits: hits ?? this.hits,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  CategoryAlias copyWithCompanion(CategoryAliasesCompanion data) {
    return CategoryAlias(
      id: data.id.present ? data.id.value : this.id,
      householdId: data.householdId.present
          ? data.householdId.value
          : this.householdId,
      aliasText: data.aliasText.present ? data.aliasText.value : this.aliasText,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      hits: data.hits.present ? data.hits.value : this.hits,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CategoryAlias(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('aliasText: $aliasText, ')
          ..write('categoryId: $categoryId, ')
          ..write('hits: $hits, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    householdId,
    aliasText,
    categoryId,
    hits,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CategoryAlias &&
          other.id == this.id &&
          other.householdId == this.householdId &&
          other.aliasText == this.aliasText &&
          other.categoryId == this.categoryId &&
          other.hits == this.hits &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class CategoryAliasesCompanion extends UpdateCompanion<CategoryAlias> {
  final Value<String> id;
  final Value<String> householdId;
  final Value<String> aliasText;
  final Value<String> categoryId;
  final Value<int> hits;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const CategoryAliasesCompanion({
    this.id = const Value.absent(),
    this.householdId = const Value.absent(),
    this.aliasText = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.hits = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CategoryAliasesCompanion.insert({
    required String id,
    required String householdId,
    required String aliasText,
    required String categoryId,
    this.hits = const Value.absent(),
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       householdId = Value(householdId),
       aliasText = Value(aliasText),
       categoryId = Value(categoryId),
       updatedAt = Value(updatedAt);
  static Insertable<CategoryAlias> custom({
    Expression<String>? id,
    Expression<String>? householdId,
    Expression<String>? aliasText,
    Expression<String>? categoryId,
    Expression<int>? hits,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (householdId != null) 'household_id': householdId,
      if (aliasText != null) 'alias_text': aliasText,
      if (categoryId != null) 'category_id': categoryId,
      if (hits != null) 'hits': hits,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CategoryAliasesCompanion copyWith({
    Value<String>? id,
    Value<String>? householdId,
    Value<String>? aliasText,
    Value<String>? categoryId,
    Value<int>? hits,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return CategoryAliasesCompanion(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      aliasText: aliasText ?? this.aliasText,
      categoryId: categoryId ?? this.categoryId,
      hits: hits ?? this.hits,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (householdId.present) {
      map['household_id'] = Variable<String>(householdId.value);
    }
    if (aliasText.present) {
      map['alias_text'] = Variable<String>(aliasText.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (hits.present) {
      map['hits'] = Variable<int>(hits.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoryAliasesCompanion(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('aliasText: $aliasText, ')
          ..write('categoryId: $categoryId, ')
          ..write('hits: $hits, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReceiptFilesTable extends ReceiptFiles
    with TableInfo<$ReceiptFilesTable, ReceiptFile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReceiptFilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _householdIdMeta = const VerificationMeta(
    'householdId',
  );
  @override
  late final GeneratedColumn<String> householdId = GeneratedColumn<String>(
    'household_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _receiptIdMeta = const VerificationMeta(
    'receiptId',
  );
  @override
  late final GeneratedColumn<String> receiptId = GeneratedColumn<String>(
    'receipt_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pageNoMeta = const VerificationMeta('pageNo');
  @override
  late final GeneratedColumn<int> pageNo = GeneratedColumn<int>(
    'page_no',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _storagePathMeta = const VerificationMeta(
    'storagePath',
  );
  @override
  late final GeneratedColumn<String> storagePath = GeneratedColumn<String>(
    'storage_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    householdId,
    receiptId,
    kind,
    pageNo,
    storagePath,
    sizeBytes,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'receipt_files';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReceiptFile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('household_id')) {
      context.handle(
        _householdIdMeta,
        householdId.isAcceptableOrUnknown(
          data['household_id']!,
          _householdIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_householdIdMeta);
    }
    if (data.containsKey('receipt_id')) {
      context.handle(
        _receiptIdMeta,
        receiptId.isAcceptableOrUnknown(data['receipt_id']!, _receiptIdMeta),
      );
    } else if (isInserting) {
      context.missing(_receiptIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('page_no')) {
      context.handle(
        _pageNoMeta,
        pageNo.isAcceptableOrUnknown(data['page_no']!, _pageNoMeta),
      );
    }
    if (data.containsKey('storage_path')) {
      context.handle(
        _storagePathMeta,
        storagePath.isAcceptableOrUnknown(
          data['storage_path']!,
          _storagePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_storagePathMeta);
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ReceiptFile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReceiptFile(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      householdId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}household_id'],
      )!,
      receiptId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}receipt_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      pageNo: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page_no'],
      )!,
      storagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}storage_path'],
      )!,
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $ReceiptFilesTable createAlias(String alias) {
    return $ReceiptFilesTable(attachedDatabase, alias);
  }
}

class ReceiptFile extends DataClass implements Insertable<ReceiptFile> {
  final String id;
  final String householdId;
  final String receiptId;

  /// 'pdf' | 'image'
  final String kind;
  final int pageNo;

  /// Pfad im Bucket: {household_id}/{receipt_id}/{file_id}.{ext}
  final String storagePath;
  final int? sizeBytes;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const ReceiptFile({
    required this.id,
    required this.householdId,
    required this.receiptId,
    required this.kind,
    required this.pageNo,
    required this.storagePath,
    this.sizeBytes,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['household_id'] = Variable<String>(householdId);
    map['receipt_id'] = Variable<String>(receiptId);
    map['kind'] = Variable<String>(kind);
    map['page_no'] = Variable<int>(pageNo);
    map['storage_path'] = Variable<String>(storagePath);
    if (!nullToAbsent || sizeBytes != null) {
      map['size_bytes'] = Variable<int>(sizeBytes);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  ReceiptFilesCompanion toCompanion(bool nullToAbsent) {
    return ReceiptFilesCompanion(
      id: Value(id),
      householdId: Value(householdId),
      receiptId: Value(receiptId),
      kind: Value(kind),
      pageNo: Value(pageNo),
      storagePath: Value(storagePath),
      sizeBytes: sizeBytes == null && nullToAbsent
          ? const Value.absent()
          : Value(sizeBytes),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory ReceiptFile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReceiptFile(
      id: serializer.fromJson<String>(json['id']),
      householdId: serializer.fromJson<String>(json['householdId']),
      receiptId: serializer.fromJson<String>(json['receiptId']),
      kind: serializer.fromJson<String>(json['kind']),
      pageNo: serializer.fromJson<int>(json['pageNo']),
      storagePath: serializer.fromJson<String>(json['storagePath']),
      sizeBytes: serializer.fromJson<int?>(json['sizeBytes']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'householdId': serializer.toJson<String>(householdId),
      'receiptId': serializer.toJson<String>(receiptId),
      'kind': serializer.toJson<String>(kind),
      'pageNo': serializer.toJson<int>(pageNo),
      'storagePath': serializer.toJson<String>(storagePath),
      'sizeBytes': serializer.toJson<int?>(sizeBytes),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  ReceiptFile copyWith({
    String? id,
    String? householdId,
    String? receiptId,
    String? kind,
    int? pageNo,
    String? storagePath,
    Value<int?> sizeBytes = const Value.absent(),
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => ReceiptFile(
    id: id ?? this.id,
    householdId: householdId ?? this.householdId,
    receiptId: receiptId ?? this.receiptId,
    kind: kind ?? this.kind,
    pageNo: pageNo ?? this.pageNo,
    storagePath: storagePath ?? this.storagePath,
    sizeBytes: sizeBytes.present ? sizeBytes.value : this.sizeBytes,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  ReceiptFile copyWithCompanion(ReceiptFilesCompanion data) {
    return ReceiptFile(
      id: data.id.present ? data.id.value : this.id,
      householdId: data.householdId.present
          ? data.householdId.value
          : this.householdId,
      receiptId: data.receiptId.present ? data.receiptId.value : this.receiptId,
      kind: data.kind.present ? data.kind.value : this.kind,
      pageNo: data.pageNo.present ? data.pageNo.value : this.pageNo,
      storagePath: data.storagePath.present
          ? data.storagePath.value
          : this.storagePath,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReceiptFile(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('receiptId: $receiptId, ')
          ..write('kind: $kind, ')
          ..write('pageNo: $pageNo, ')
          ..write('storagePath: $storagePath, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    householdId,
    receiptId,
    kind,
    pageNo,
    storagePath,
    sizeBytes,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReceiptFile &&
          other.id == this.id &&
          other.householdId == this.householdId &&
          other.receiptId == this.receiptId &&
          other.kind == this.kind &&
          other.pageNo == this.pageNo &&
          other.storagePath == this.storagePath &&
          other.sizeBytes == this.sizeBytes &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class ReceiptFilesCompanion extends UpdateCompanion<ReceiptFile> {
  final Value<String> id;
  final Value<String> householdId;
  final Value<String> receiptId;
  final Value<String> kind;
  final Value<int> pageNo;
  final Value<String> storagePath;
  final Value<int?> sizeBytes;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const ReceiptFilesCompanion({
    this.id = const Value.absent(),
    this.householdId = const Value.absent(),
    this.receiptId = const Value.absent(),
    this.kind = const Value.absent(),
    this.pageNo = const Value.absent(),
    this.storagePath = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReceiptFilesCompanion.insert({
    required String id,
    required String householdId,
    required String receiptId,
    required String kind,
    this.pageNo = const Value.absent(),
    required String storagePath,
    this.sizeBytes = const Value.absent(),
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       householdId = Value(householdId),
       receiptId = Value(receiptId),
       kind = Value(kind),
       storagePath = Value(storagePath),
       updatedAt = Value(updatedAt);
  static Insertable<ReceiptFile> custom({
    Expression<String>? id,
    Expression<String>? householdId,
    Expression<String>? receiptId,
    Expression<String>? kind,
    Expression<int>? pageNo,
    Expression<String>? storagePath,
    Expression<int>? sizeBytes,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (householdId != null) 'household_id': householdId,
      if (receiptId != null) 'receipt_id': receiptId,
      if (kind != null) 'kind': kind,
      if (pageNo != null) 'page_no': pageNo,
      if (storagePath != null) 'storage_path': storagePath,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReceiptFilesCompanion copyWith({
    Value<String>? id,
    Value<String>? householdId,
    Value<String>? receiptId,
    Value<String>? kind,
    Value<int>? pageNo,
    Value<String>? storagePath,
    Value<int?>? sizeBytes,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return ReceiptFilesCompanion(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      receiptId: receiptId ?? this.receiptId,
      kind: kind ?? this.kind,
      pageNo: pageNo ?? this.pageNo,
      storagePath: storagePath ?? this.storagePath,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (householdId.present) {
      map['household_id'] = Variable<String>(householdId.value);
    }
    if (receiptId.present) {
      map['receipt_id'] = Variable<String>(receiptId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (pageNo.present) {
      map['page_no'] = Variable<int>(pageNo.value);
    }
    if (storagePath.present) {
      map['storage_path'] = Variable<String>(storagePath.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReceiptFilesCompanion(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('receiptId: $receiptId, ')
          ..write('kind: $kind, ')
          ..write('pageNo: $pageNo, ')
          ..write('storagePath: $storagePath, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $InventoryItemsTable extends InventoryItems
    with TableInfo<$InventoryItemsTable, InventoryItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InventoryItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _householdIdMeta = const VerificationMeta(
    'householdId',
  );
  @override
  late final GeneratedColumn<String> householdId = GeneratedColumn<String>(
    'household_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _productIdMeta = const VerificationMeta(
    'productId',
  );
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
    'product_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _receiptItemIdMeta = const VerificationMeta(
    'receiptItemId',
  );
  @override
  late final GeneratedColumn<String> receiptItemId = GeneratedColumn<String>(
    'receipt_item_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _eanMeta = const VerificationMeta('ean');
  @override
  late final GeneratedColumn<String> ean = GeneratedColumn<String>(
    'ean',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _quantityMeta = const VerificationMeta(
    'quantity',
  );
  @override
  late final GeneratedColumn<double> quantity = GeneratedColumn<double>(
    'quantity',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _unitMeta = const VerificationMeta('unit');
  @override
  late final GeneratedColumn<String> unit = GeneratedColumn<String>(
    'unit',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('piece'),
  );
  static const VerificationMeta _locationMeta = const VerificationMeta(
    'location',
  );
  @override
  late final GeneratedColumn<String> location = GeneratedColumn<String>(
    'location',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pantry'),
  );
  static const VerificationMeta _purchasedOnMeta = const VerificationMeta(
    'purchasedOn',
  );
  @override
  late final GeneratedColumn<DateTime> purchasedOn = GeneratedColumn<DateTime>(
    'purchased_on',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bestBeforeMeta = const VerificationMeta(
    'bestBefore',
  );
  @override
  late final GeneratedColumn<DateTime> bestBefore = GeneratedColumn<DateTime>(
    'best_before',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dateKindMeta = const VerificationMeta(
    'dateKind',
  );
  @override
  late final GeneratedColumn<String> dateKind = GeneratedColumn<String>(
    'date_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('best_before'),
  );
  static const VerificationMeta _openedOnMeta = const VerificationMeta(
    'openedOn',
  );
  @override
  late final GeneratedColumn<DateTime> openedOn = GeneratedColumn<DateTime>(
    'opened_on',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _openShelfLifeDaysMeta = const VerificationMeta(
    'openShelfLifeDays',
  );
  @override
  late final GeneratedColumn<int> openShelfLifeDays = GeneratedColumn<int>(
    'open_shelf_life_days',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('sealed'),
  );
  static const VerificationMeta _isSuggestionMeta = const VerificationMeta(
    'isSuggestion',
  );
  @override
  late final GeneratedColumn<bool> isSuggestion = GeneratedColumn<bool>(
    'is_suggestion',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_suggestion" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _closedAtMeta = const VerificationMeta(
    'closedAt',
  );
  @override
  late final GeneratedColumn<DateTime> closedAt = GeneratedColumn<DateTime>(
    'closed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _expiresOnMeta = const VerificationMeta(
    'expiresOn',
  );
  @override
  late final GeneratedColumn<DateTime> expiresOn = GeneratedColumn<DateTime>(
    'expires_on',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    householdId,
    productId,
    receiptItemId,
    ean,
    quantity,
    unit,
    location,
    purchasedOn,
    bestBefore,
    dateKind,
    openedOn,
    openShelfLifeDays,
    status,
    isSuggestion,
    closedAt,
    expiresOn,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'inventory_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<InventoryItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('household_id')) {
      context.handle(
        _householdIdMeta,
        householdId.isAcceptableOrUnknown(
          data['household_id']!,
          _householdIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_householdIdMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(
        _productIdMeta,
        productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta),
      );
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('receipt_item_id')) {
      context.handle(
        _receiptItemIdMeta,
        receiptItemId.isAcceptableOrUnknown(
          data['receipt_item_id']!,
          _receiptItemIdMeta,
        ),
      );
    }
    if (data.containsKey('ean')) {
      context.handle(
        _eanMeta,
        ean.isAcceptableOrUnknown(data['ean']!, _eanMeta),
      );
    }
    if (data.containsKey('quantity')) {
      context.handle(
        _quantityMeta,
        quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta),
      );
    }
    if (data.containsKey('unit')) {
      context.handle(
        _unitMeta,
        unit.isAcceptableOrUnknown(data['unit']!, _unitMeta),
      );
    }
    if (data.containsKey('location')) {
      context.handle(
        _locationMeta,
        location.isAcceptableOrUnknown(data['location']!, _locationMeta),
      );
    }
    if (data.containsKey('purchased_on')) {
      context.handle(
        _purchasedOnMeta,
        purchasedOn.isAcceptableOrUnknown(
          data['purchased_on']!,
          _purchasedOnMeta,
        ),
      );
    }
    if (data.containsKey('best_before')) {
      context.handle(
        _bestBeforeMeta,
        bestBefore.isAcceptableOrUnknown(data['best_before']!, _bestBeforeMeta),
      );
    }
    if (data.containsKey('date_kind')) {
      context.handle(
        _dateKindMeta,
        dateKind.isAcceptableOrUnknown(data['date_kind']!, _dateKindMeta),
      );
    }
    if (data.containsKey('opened_on')) {
      context.handle(
        _openedOnMeta,
        openedOn.isAcceptableOrUnknown(data['opened_on']!, _openedOnMeta),
      );
    }
    if (data.containsKey('open_shelf_life_days')) {
      context.handle(
        _openShelfLifeDaysMeta,
        openShelfLifeDays.isAcceptableOrUnknown(
          data['open_shelf_life_days']!,
          _openShelfLifeDaysMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('is_suggestion')) {
      context.handle(
        _isSuggestionMeta,
        isSuggestion.isAcceptableOrUnknown(
          data['is_suggestion']!,
          _isSuggestionMeta,
        ),
      );
    }
    if (data.containsKey('closed_at')) {
      context.handle(
        _closedAtMeta,
        closedAt.isAcceptableOrUnknown(data['closed_at']!, _closedAtMeta),
      );
    }
    if (data.containsKey('expires_on')) {
      context.handle(
        _expiresOnMeta,
        expiresOn.isAcceptableOrUnknown(data['expires_on']!, _expiresOnMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  InventoryItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InventoryItem(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      householdId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}household_id'],
      )!,
      productId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}product_id'],
      )!,
      receiptItemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}receipt_item_id'],
      ),
      ean: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ean'],
      ),
      quantity: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}quantity'],
      )!,
      unit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unit'],
      )!,
      location: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location'],
      )!,
      purchasedOn: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}purchased_on'],
      ),
      bestBefore: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}best_before'],
      ),
      dateKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date_kind'],
      )!,
      openedOn: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}opened_on'],
      ),
      openShelfLifeDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}open_shelf_life_days'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      isSuggestion: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_suggestion'],
      )!,
      closedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}closed_at'],
      ),
      expiresOn: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}expires_on'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $InventoryItemsTable createAlias(String alias) {
    return $InventoryItemsTable(attachedDatabase, alias);
  }
}

class InventoryItem extends DataClass implements Insertable<InventoryItem> {
  final String id;
  final String householdId;
  final String productId;

  /// Bon-Position, aus der dieser Eintrag als Vorschlag entstanden ist (Doku 06 §2).
  final String? receiptItemId;
  final String? ean;
  final double quantity;

  /// 'piece' | 'kg' | 'l'
  final String unit;

  /// 'fridge' | 'freezer' | 'pantry' | 'other'
  final String location;
  final DateTime? purchasedOn;
  final DateTime? bestBefore;

  /// 'best_before' | 'use_by'
  final String dateKind;
  final DateTime? openedOn;
  final int? openShelfLifeDays;

  /// 'sealed' | 'opened' | 'consumed' | 'discarded'
  final String status;

  /// Aus einem Bon vorgeschlagen, noch nicht per Barcode bestaetigt (Doku 06 §2, INV-08).
  final bool isSuggestion;
  final DateTime? closedAt;

  /// Fruehestes aus bestBefore und openedOn+openShelfLifeDays (siehe computeExpiresOn), vom Server berechnet
  /// und hier gespiegelt; fuer optimistische lokale Anzeige vor dem naechsten Sync selbst gesetzt.
  final DateTime? expiresOn;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const InventoryItem({
    required this.id,
    required this.householdId,
    required this.productId,
    this.receiptItemId,
    this.ean,
    required this.quantity,
    required this.unit,
    required this.location,
    this.purchasedOn,
    this.bestBefore,
    required this.dateKind,
    this.openedOn,
    this.openShelfLifeDays,
    required this.status,
    required this.isSuggestion,
    this.closedAt,
    this.expiresOn,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['household_id'] = Variable<String>(householdId);
    map['product_id'] = Variable<String>(productId);
    if (!nullToAbsent || receiptItemId != null) {
      map['receipt_item_id'] = Variable<String>(receiptItemId);
    }
    if (!nullToAbsent || ean != null) {
      map['ean'] = Variable<String>(ean);
    }
    map['quantity'] = Variable<double>(quantity);
    map['unit'] = Variable<String>(unit);
    map['location'] = Variable<String>(location);
    if (!nullToAbsent || purchasedOn != null) {
      map['purchased_on'] = Variable<DateTime>(purchasedOn);
    }
    if (!nullToAbsent || bestBefore != null) {
      map['best_before'] = Variable<DateTime>(bestBefore);
    }
    map['date_kind'] = Variable<String>(dateKind);
    if (!nullToAbsent || openedOn != null) {
      map['opened_on'] = Variable<DateTime>(openedOn);
    }
    if (!nullToAbsent || openShelfLifeDays != null) {
      map['open_shelf_life_days'] = Variable<int>(openShelfLifeDays);
    }
    map['status'] = Variable<String>(status);
    map['is_suggestion'] = Variable<bool>(isSuggestion);
    if (!nullToAbsent || closedAt != null) {
      map['closed_at'] = Variable<DateTime>(closedAt);
    }
    if (!nullToAbsent || expiresOn != null) {
      map['expires_on'] = Variable<DateTime>(expiresOn);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  InventoryItemsCompanion toCompanion(bool nullToAbsent) {
    return InventoryItemsCompanion(
      id: Value(id),
      householdId: Value(householdId),
      productId: Value(productId),
      receiptItemId: receiptItemId == null && nullToAbsent
          ? const Value.absent()
          : Value(receiptItemId),
      ean: ean == null && nullToAbsent ? const Value.absent() : Value(ean),
      quantity: Value(quantity),
      unit: Value(unit),
      location: Value(location),
      purchasedOn: purchasedOn == null && nullToAbsent
          ? const Value.absent()
          : Value(purchasedOn),
      bestBefore: bestBefore == null && nullToAbsent
          ? const Value.absent()
          : Value(bestBefore),
      dateKind: Value(dateKind),
      openedOn: openedOn == null && nullToAbsent
          ? const Value.absent()
          : Value(openedOn),
      openShelfLifeDays: openShelfLifeDays == null && nullToAbsent
          ? const Value.absent()
          : Value(openShelfLifeDays),
      status: Value(status),
      isSuggestion: Value(isSuggestion),
      closedAt: closedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(closedAt),
      expiresOn: expiresOn == null && nullToAbsent
          ? const Value.absent()
          : Value(expiresOn),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory InventoryItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InventoryItem(
      id: serializer.fromJson<String>(json['id']),
      householdId: serializer.fromJson<String>(json['householdId']),
      productId: serializer.fromJson<String>(json['productId']),
      receiptItemId: serializer.fromJson<String?>(json['receiptItemId']),
      ean: serializer.fromJson<String?>(json['ean']),
      quantity: serializer.fromJson<double>(json['quantity']),
      unit: serializer.fromJson<String>(json['unit']),
      location: serializer.fromJson<String>(json['location']),
      purchasedOn: serializer.fromJson<DateTime?>(json['purchasedOn']),
      bestBefore: serializer.fromJson<DateTime?>(json['bestBefore']),
      dateKind: serializer.fromJson<String>(json['dateKind']),
      openedOn: serializer.fromJson<DateTime?>(json['openedOn']),
      openShelfLifeDays: serializer.fromJson<int?>(json['openShelfLifeDays']),
      status: serializer.fromJson<String>(json['status']),
      isSuggestion: serializer.fromJson<bool>(json['isSuggestion']),
      closedAt: serializer.fromJson<DateTime?>(json['closedAt']),
      expiresOn: serializer.fromJson<DateTime?>(json['expiresOn']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'householdId': serializer.toJson<String>(householdId),
      'productId': serializer.toJson<String>(productId),
      'receiptItemId': serializer.toJson<String?>(receiptItemId),
      'ean': serializer.toJson<String?>(ean),
      'quantity': serializer.toJson<double>(quantity),
      'unit': serializer.toJson<String>(unit),
      'location': serializer.toJson<String>(location),
      'purchasedOn': serializer.toJson<DateTime?>(purchasedOn),
      'bestBefore': serializer.toJson<DateTime?>(bestBefore),
      'dateKind': serializer.toJson<String>(dateKind),
      'openedOn': serializer.toJson<DateTime?>(openedOn),
      'openShelfLifeDays': serializer.toJson<int?>(openShelfLifeDays),
      'status': serializer.toJson<String>(status),
      'isSuggestion': serializer.toJson<bool>(isSuggestion),
      'closedAt': serializer.toJson<DateTime?>(closedAt),
      'expiresOn': serializer.toJson<DateTime?>(expiresOn),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  InventoryItem copyWith({
    String? id,
    String? householdId,
    String? productId,
    Value<String?> receiptItemId = const Value.absent(),
    Value<String?> ean = const Value.absent(),
    double? quantity,
    String? unit,
    String? location,
    Value<DateTime?> purchasedOn = const Value.absent(),
    Value<DateTime?> bestBefore = const Value.absent(),
    String? dateKind,
    Value<DateTime?> openedOn = const Value.absent(),
    Value<int?> openShelfLifeDays = const Value.absent(),
    String? status,
    bool? isSuggestion,
    Value<DateTime?> closedAt = const Value.absent(),
    Value<DateTime?> expiresOn = const Value.absent(),
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => InventoryItem(
    id: id ?? this.id,
    householdId: householdId ?? this.householdId,
    productId: productId ?? this.productId,
    receiptItemId: receiptItemId.present
        ? receiptItemId.value
        : this.receiptItemId,
    ean: ean.present ? ean.value : this.ean,
    quantity: quantity ?? this.quantity,
    unit: unit ?? this.unit,
    location: location ?? this.location,
    purchasedOn: purchasedOn.present ? purchasedOn.value : this.purchasedOn,
    bestBefore: bestBefore.present ? bestBefore.value : this.bestBefore,
    dateKind: dateKind ?? this.dateKind,
    openedOn: openedOn.present ? openedOn.value : this.openedOn,
    openShelfLifeDays: openShelfLifeDays.present
        ? openShelfLifeDays.value
        : this.openShelfLifeDays,
    status: status ?? this.status,
    isSuggestion: isSuggestion ?? this.isSuggestion,
    closedAt: closedAt.present ? closedAt.value : this.closedAt,
    expiresOn: expiresOn.present ? expiresOn.value : this.expiresOn,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  InventoryItem copyWithCompanion(InventoryItemsCompanion data) {
    return InventoryItem(
      id: data.id.present ? data.id.value : this.id,
      householdId: data.householdId.present
          ? data.householdId.value
          : this.householdId,
      productId: data.productId.present ? data.productId.value : this.productId,
      receiptItemId: data.receiptItemId.present
          ? data.receiptItemId.value
          : this.receiptItemId,
      ean: data.ean.present ? data.ean.value : this.ean,
      quantity: data.quantity.present ? data.quantity.value : this.quantity,
      unit: data.unit.present ? data.unit.value : this.unit,
      location: data.location.present ? data.location.value : this.location,
      purchasedOn: data.purchasedOn.present
          ? data.purchasedOn.value
          : this.purchasedOn,
      bestBefore: data.bestBefore.present
          ? data.bestBefore.value
          : this.bestBefore,
      dateKind: data.dateKind.present ? data.dateKind.value : this.dateKind,
      openedOn: data.openedOn.present ? data.openedOn.value : this.openedOn,
      openShelfLifeDays: data.openShelfLifeDays.present
          ? data.openShelfLifeDays.value
          : this.openShelfLifeDays,
      status: data.status.present ? data.status.value : this.status,
      isSuggestion: data.isSuggestion.present
          ? data.isSuggestion.value
          : this.isSuggestion,
      closedAt: data.closedAt.present ? data.closedAt.value : this.closedAt,
      expiresOn: data.expiresOn.present ? data.expiresOn.value : this.expiresOn,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InventoryItem(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('productId: $productId, ')
          ..write('receiptItemId: $receiptItemId, ')
          ..write('ean: $ean, ')
          ..write('quantity: $quantity, ')
          ..write('unit: $unit, ')
          ..write('location: $location, ')
          ..write('purchasedOn: $purchasedOn, ')
          ..write('bestBefore: $bestBefore, ')
          ..write('dateKind: $dateKind, ')
          ..write('openedOn: $openedOn, ')
          ..write('openShelfLifeDays: $openShelfLifeDays, ')
          ..write('status: $status, ')
          ..write('isSuggestion: $isSuggestion, ')
          ..write('closedAt: $closedAt, ')
          ..write('expiresOn: $expiresOn, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    householdId,
    productId,
    receiptItemId,
    ean,
    quantity,
    unit,
    location,
    purchasedOn,
    bestBefore,
    dateKind,
    openedOn,
    openShelfLifeDays,
    status,
    isSuggestion,
    closedAt,
    expiresOn,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InventoryItem &&
          other.id == this.id &&
          other.householdId == this.householdId &&
          other.productId == this.productId &&
          other.receiptItemId == this.receiptItemId &&
          other.ean == this.ean &&
          other.quantity == this.quantity &&
          other.unit == this.unit &&
          other.location == this.location &&
          other.purchasedOn == this.purchasedOn &&
          other.bestBefore == this.bestBefore &&
          other.dateKind == this.dateKind &&
          other.openedOn == this.openedOn &&
          other.openShelfLifeDays == this.openShelfLifeDays &&
          other.status == this.status &&
          other.isSuggestion == this.isSuggestion &&
          other.closedAt == this.closedAt &&
          other.expiresOn == this.expiresOn &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class InventoryItemsCompanion extends UpdateCompanion<InventoryItem> {
  final Value<String> id;
  final Value<String> householdId;
  final Value<String> productId;
  final Value<String?> receiptItemId;
  final Value<String?> ean;
  final Value<double> quantity;
  final Value<String> unit;
  final Value<String> location;
  final Value<DateTime?> purchasedOn;
  final Value<DateTime?> bestBefore;
  final Value<String> dateKind;
  final Value<DateTime?> openedOn;
  final Value<int?> openShelfLifeDays;
  final Value<String> status;
  final Value<bool> isSuggestion;
  final Value<DateTime?> closedAt;
  final Value<DateTime?> expiresOn;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const InventoryItemsCompanion({
    this.id = const Value.absent(),
    this.householdId = const Value.absent(),
    this.productId = const Value.absent(),
    this.receiptItemId = const Value.absent(),
    this.ean = const Value.absent(),
    this.quantity = const Value.absent(),
    this.unit = const Value.absent(),
    this.location = const Value.absent(),
    this.purchasedOn = const Value.absent(),
    this.bestBefore = const Value.absent(),
    this.dateKind = const Value.absent(),
    this.openedOn = const Value.absent(),
    this.openShelfLifeDays = const Value.absent(),
    this.status = const Value.absent(),
    this.isSuggestion = const Value.absent(),
    this.closedAt = const Value.absent(),
    this.expiresOn = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InventoryItemsCompanion.insert({
    required String id,
    required String householdId,
    required String productId,
    this.receiptItemId = const Value.absent(),
    this.ean = const Value.absent(),
    this.quantity = const Value.absent(),
    this.unit = const Value.absent(),
    this.location = const Value.absent(),
    this.purchasedOn = const Value.absent(),
    this.bestBefore = const Value.absent(),
    this.dateKind = const Value.absent(),
    this.openedOn = const Value.absent(),
    this.openShelfLifeDays = const Value.absent(),
    this.status = const Value.absent(),
    this.isSuggestion = const Value.absent(),
    this.closedAt = const Value.absent(),
    this.expiresOn = const Value.absent(),
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       householdId = Value(householdId),
       productId = Value(productId),
       updatedAt = Value(updatedAt);
  static Insertable<InventoryItem> custom({
    Expression<String>? id,
    Expression<String>? householdId,
    Expression<String>? productId,
    Expression<String>? receiptItemId,
    Expression<String>? ean,
    Expression<double>? quantity,
    Expression<String>? unit,
    Expression<String>? location,
    Expression<DateTime>? purchasedOn,
    Expression<DateTime>? bestBefore,
    Expression<String>? dateKind,
    Expression<DateTime>? openedOn,
    Expression<int>? openShelfLifeDays,
    Expression<String>? status,
    Expression<bool>? isSuggestion,
    Expression<DateTime>? closedAt,
    Expression<DateTime>? expiresOn,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (householdId != null) 'household_id': householdId,
      if (productId != null) 'product_id': productId,
      if (receiptItemId != null) 'receipt_item_id': receiptItemId,
      if (ean != null) 'ean': ean,
      if (quantity != null) 'quantity': quantity,
      if (unit != null) 'unit': unit,
      if (location != null) 'location': location,
      if (purchasedOn != null) 'purchased_on': purchasedOn,
      if (bestBefore != null) 'best_before': bestBefore,
      if (dateKind != null) 'date_kind': dateKind,
      if (openedOn != null) 'opened_on': openedOn,
      if (openShelfLifeDays != null) 'open_shelf_life_days': openShelfLifeDays,
      if (status != null) 'status': status,
      if (isSuggestion != null) 'is_suggestion': isSuggestion,
      if (closedAt != null) 'closed_at': closedAt,
      if (expiresOn != null) 'expires_on': expiresOn,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InventoryItemsCompanion copyWith({
    Value<String>? id,
    Value<String>? householdId,
    Value<String>? productId,
    Value<String?>? receiptItemId,
    Value<String?>? ean,
    Value<double>? quantity,
    Value<String>? unit,
    Value<String>? location,
    Value<DateTime?>? purchasedOn,
    Value<DateTime?>? bestBefore,
    Value<String>? dateKind,
    Value<DateTime?>? openedOn,
    Value<int?>? openShelfLifeDays,
    Value<String>? status,
    Value<bool>? isSuggestion,
    Value<DateTime?>? closedAt,
    Value<DateTime?>? expiresOn,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return InventoryItemsCompanion(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      productId: productId ?? this.productId,
      receiptItemId: receiptItemId ?? this.receiptItemId,
      ean: ean ?? this.ean,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      location: location ?? this.location,
      purchasedOn: purchasedOn ?? this.purchasedOn,
      bestBefore: bestBefore ?? this.bestBefore,
      dateKind: dateKind ?? this.dateKind,
      openedOn: openedOn ?? this.openedOn,
      openShelfLifeDays: openShelfLifeDays ?? this.openShelfLifeDays,
      status: status ?? this.status,
      isSuggestion: isSuggestion ?? this.isSuggestion,
      closedAt: closedAt ?? this.closedAt,
      expiresOn: expiresOn ?? this.expiresOn,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (householdId.present) {
      map['household_id'] = Variable<String>(householdId.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (receiptItemId.present) {
      map['receipt_item_id'] = Variable<String>(receiptItemId.value);
    }
    if (ean.present) {
      map['ean'] = Variable<String>(ean.value);
    }
    if (quantity.present) {
      map['quantity'] = Variable<double>(quantity.value);
    }
    if (unit.present) {
      map['unit'] = Variable<String>(unit.value);
    }
    if (location.present) {
      map['location'] = Variable<String>(location.value);
    }
    if (purchasedOn.present) {
      map['purchased_on'] = Variable<DateTime>(purchasedOn.value);
    }
    if (bestBefore.present) {
      map['best_before'] = Variable<DateTime>(bestBefore.value);
    }
    if (dateKind.present) {
      map['date_kind'] = Variable<String>(dateKind.value);
    }
    if (openedOn.present) {
      map['opened_on'] = Variable<DateTime>(openedOn.value);
    }
    if (openShelfLifeDays.present) {
      map['open_shelf_life_days'] = Variable<int>(openShelfLifeDays.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (isSuggestion.present) {
      map['is_suggestion'] = Variable<bool>(isSuggestion.value);
    }
    if (closedAt.present) {
      map['closed_at'] = Variable<DateTime>(closedAt.value);
    }
    if (expiresOn.present) {
      map['expires_on'] = Variable<DateTime>(expiresOn.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InventoryItemsCompanion(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('productId: $productId, ')
          ..write('receiptItemId: $receiptItemId, ')
          ..write('ean: $ean, ')
          ..write('quantity: $quantity, ')
          ..write('unit: $unit, ')
          ..write('location: $location, ')
          ..write('purchasedOn: $purchasedOn, ')
          ..write('bestBefore: $bestBefore, ')
          ..write('dateKind: $dateKind, ')
          ..write('openedOn: $openedOn, ')
          ..write('openShelfLifeDays: $openShelfLifeDays, ')
          ..write('status: $status, ')
          ..write('isSuggestion: $isSuggestion, ')
          ..write('closedAt: $closedAt, ')
          ..write('expiresOn: $expiresOn, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $InventoryMovementsTable extends InventoryMovements
    with TableInfo<$InventoryMovementsTable, InventoryMovement> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InventoryMovementsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _householdIdMeta = const VerificationMeta(
    'householdId',
  );
  @override
  late final GeneratedColumn<String> householdId = GeneratedColumn<String>(
    'household_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _inventoryItemIdMeta = const VerificationMeta(
    'inventoryItemId',
  );
  @override
  late final GeneratedColumn<String> inventoryItemId = GeneratedColumn<String>(
    'inventory_item_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _productIdMeta = const VerificationMeta(
    'productId',
  );
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
    'product_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _occurredAtMeta = const VerificationMeta(
    'occurredAt',
  );
  @override
  late final GeneratedColumn<DateTime> occurredAt = GeneratedColumn<DateTime>(
    'occurred_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _quantityDeltaMeta = const VerificationMeta(
    'quantityDelta',
  );
  @override
  late final GeneratedColumn<double> quantityDelta = GeneratedColumn<double>(
    'quantity_delta',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _unitMeta = const VerificationMeta('unit');
  @override
  late final GeneratedColumn<String> unit = GeneratedColumn<String>(
    'unit',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mealIdMeta = const VerificationMeta('mealId');
  @override
  late final GeneratedColumn<String> mealId = GeneratedColumn<String>(
    'meal_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    householdId,
    inventoryItemId,
    productId,
    occurredAt,
    type,
    quantityDelta,
    unit,
    note,
    mealId,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'inventory_movements';
  @override
  VerificationContext validateIntegrity(
    Insertable<InventoryMovement> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('household_id')) {
      context.handle(
        _householdIdMeta,
        householdId.isAcceptableOrUnknown(
          data['household_id']!,
          _householdIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_householdIdMeta);
    }
    if (data.containsKey('inventory_item_id')) {
      context.handle(
        _inventoryItemIdMeta,
        inventoryItemId.isAcceptableOrUnknown(
          data['inventory_item_id']!,
          _inventoryItemIdMeta,
        ),
      );
    }
    if (data.containsKey('product_id')) {
      context.handle(
        _productIdMeta,
        productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta),
      );
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('occurred_at')) {
      context.handle(
        _occurredAtMeta,
        occurredAt.isAcceptableOrUnknown(data['occurred_at']!, _occurredAtMeta),
      );
    } else if (isInserting) {
      context.missing(_occurredAtMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('quantity_delta')) {
      context.handle(
        _quantityDeltaMeta,
        quantityDelta.isAcceptableOrUnknown(
          data['quantity_delta']!,
          _quantityDeltaMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_quantityDeltaMeta);
    }
    if (data.containsKey('unit')) {
      context.handle(
        _unitMeta,
        unit.isAcceptableOrUnknown(data['unit']!, _unitMeta),
      );
    } else if (isInserting) {
      context.missing(_unitMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('meal_id')) {
      context.handle(
        _mealIdMeta,
        mealId.isAcceptableOrUnknown(data['meal_id']!, _mealIdMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  InventoryMovement map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InventoryMovement(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      householdId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}household_id'],
      )!,
      inventoryItemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}inventory_item_id'],
      ),
      productId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}product_id'],
      )!,
      occurredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}occurred_at'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      quantityDelta: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}quantity_delta'],
      )!,
      unit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unit'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      mealId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}meal_id'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $InventoryMovementsTable createAlias(String alias) {
    return $InventoryMovementsTable(attachedDatabase, alias);
  }
}

class InventoryMovement extends DataClass
    implements Insertable<InventoryMovement> {
  final String id;
  final String householdId;
  final String? inventoryItemId;
  final String productId;
  final DateTime occurredAt;

  /// 'purchase' | 'consumed' | 'meal' | 'discarded' | 'adjustment'
  final String type;

  /// Vorzeichen: Zugang +, Abgang -.
  final double quantityDelta;

  /// 'piece' | 'kg' | 'l'
  final String unit;
  final String? note;

  /// Mahlzeit, die diese Bewegung ausgeloest hat (Abzug oder Gegenbuchung, Doku 15 §3.4, FR-12).
  final String? mealId;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const InventoryMovement({
    required this.id,
    required this.householdId,
    this.inventoryItemId,
    required this.productId,
    required this.occurredAt,
    required this.type,
    required this.quantityDelta,
    required this.unit,
    this.note,
    this.mealId,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['household_id'] = Variable<String>(householdId);
    if (!nullToAbsent || inventoryItemId != null) {
      map['inventory_item_id'] = Variable<String>(inventoryItemId);
    }
    map['product_id'] = Variable<String>(productId);
    map['occurred_at'] = Variable<DateTime>(occurredAt);
    map['type'] = Variable<String>(type);
    map['quantity_delta'] = Variable<double>(quantityDelta);
    map['unit'] = Variable<String>(unit);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    if (!nullToAbsent || mealId != null) {
      map['meal_id'] = Variable<String>(mealId);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  InventoryMovementsCompanion toCompanion(bool nullToAbsent) {
    return InventoryMovementsCompanion(
      id: Value(id),
      householdId: Value(householdId),
      inventoryItemId: inventoryItemId == null && nullToAbsent
          ? const Value.absent()
          : Value(inventoryItemId),
      productId: Value(productId),
      occurredAt: Value(occurredAt),
      type: Value(type),
      quantityDelta: Value(quantityDelta),
      unit: Value(unit),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      mealId: mealId == null && nullToAbsent
          ? const Value.absent()
          : Value(mealId),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory InventoryMovement.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InventoryMovement(
      id: serializer.fromJson<String>(json['id']),
      householdId: serializer.fromJson<String>(json['householdId']),
      inventoryItemId: serializer.fromJson<String?>(json['inventoryItemId']),
      productId: serializer.fromJson<String>(json['productId']),
      occurredAt: serializer.fromJson<DateTime>(json['occurredAt']),
      type: serializer.fromJson<String>(json['type']),
      quantityDelta: serializer.fromJson<double>(json['quantityDelta']),
      unit: serializer.fromJson<String>(json['unit']),
      note: serializer.fromJson<String?>(json['note']),
      mealId: serializer.fromJson<String?>(json['mealId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'householdId': serializer.toJson<String>(householdId),
      'inventoryItemId': serializer.toJson<String?>(inventoryItemId),
      'productId': serializer.toJson<String>(productId),
      'occurredAt': serializer.toJson<DateTime>(occurredAt),
      'type': serializer.toJson<String>(type),
      'quantityDelta': serializer.toJson<double>(quantityDelta),
      'unit': serializer.toJson<String>(unit),
      'note': serializer.toJson<String?>(note),
      'mealId': serializer.toJson<String?>(mealId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  InventoryMovement copyWith({
    String? id,
    String? householdId,
    Value<String?> inventoryItemId = const Value.absent(),
    String? productId,
    DateTime? occurredAt,
    String? type,
    double? quantityDelta,
    String? unit,
    Value<String?> note = const Value.absent(),
    Value<String?> mealId = const Value.absent(),
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => InventoryMovement(
    id: id ?? this.id,
    householdId: householdId ?? this.householdId,
    inventoryItemId: inventoryItemId.present
        ? inventoryItemId.value
        : this.inventoryItemId,
    productId: productId ?? this.productId,
    occurredAt: occurredAt ?? this.occurredAt,
    type: type ?? this.type,
    quantityDelta: quantityDelta ?? this.quantityDelta,
    unit: unit ?? this.unit,
    note: note.present ? note.value : this.note,
    mealId: mealId.present ? mealId.value : this.mealId,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  InventoryMovement copyWithCompanion(InventoryMovementsCompanion data) {
    return InventoryMovement(
      id: data.id.present ? data.id.value : this.id,
      householdId: data.householdId.present
          ? data.householdId.value
          : this.householdId,
      inventoryItemId: data.inventoryItemId.present
          ? data.inventoryItemId.value
          : this.inventoryItemId,
      productId: data.productId.present ? data.productId.value : this.productId,
      occurredAt: data.occurredAt.present
          ? data.occurredAt.value
          : this.occurredAt,
      type: data.type.present ? data.type.value : this.type,
      quantityDelta: data.quantityDelta.present
          ? data.quantityDelta.value
          : this.quantityDelta,
      unit: data.unit.present ? data.unit.value : this.unit,
      note: data.note.present ? data.note.value : this.note,
      mealId: data.mealId.present ? data.mealId.value : this.mealId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InventoryMovement(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('inventoryItemId: $inventoryItemId, ')
          ..write('productId: $productId, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('type: $type, ')
          ..write('quantityDelta: $quantityDelta, ')
          ..write('unit: $unit, ')
          ..write('note: $note, ')
          ..write('mealId: $mealId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    householdId,
    inventoryItemId,
    productId,
    occurredAt,
    type,
    quantityDelta,
    unit,
    note,
    mealId,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InventoryMovement &&
          other.id == this.id &&
          other.householdId == this.householdId &&
          other.inventoryItemId == this.inventoryItemId &&
          other.productId == this.productId &&
          other.occurredAt == this.occurredAt &&
          other.type == this.type &&
          other.quantityDelta == this.quantityDelta &&
          other.unit == this.unit &&
          other.note == this.note &&
          other.mealId == this.mealId &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class InventoryMovementsCompanion extends UpdateCompanion<InventoryMovement> {
  final Value<String> id;
  final Value<String> householdId;
  final Value<String?> inventoryItemId;
  final Value<String> productId;
  final Value<DateTime> occurredAt;
  final Value<String> type;
  final Value<double> quantityDelta;
  final Value<String> unit;
  final Value<String?> note;
  final Value<String?> mealId;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const InventoryMovementsCompanion({
    this.id = const Value.absent(),
    this.householdId = const Value.absent(),
    this.inventoryItemId = const Value.absent(),
    this.productId = const Value.absent(),
    this.occurredAt = const Value.absent(),
    this.type = const Value.absent(),
    this.quantityDelta = const Value.absent(),
    this.unit = const Value.absent(),
    this.note = const Value.absent(),
    this.mealId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InventoryMovementsCompanion.insert({
    required String id,
    required String householdId,
    this.inventoryItemId = const Value.absent(),
    required String productId,
    required DateTime occurredAt,
    required String type,
    required double quantityDelta,
    required String unit,
    this.note = const Value.absent(),
    this.mealId = const Value.absent(),
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       householdId = Value(householdId),
       productId = Value(productId),
       occurredAt = Value(occurredAt),
       type = Value(type),
       quantityDelta = Value(quantityDelta),
       unit = Value(unit),
       updatedAt = Value(updatedAt);
  static Insertable<InventoryMovement> custom({
    Expression<String>? id,
    Expression<String>? householdId,
    Expression<String>? inventoryItemId,
    Expression<String>? productId,
    Expression<DateTime>? occurredAt,
    Expression<String>? type,
    Expression<double>? quantityDelta,
    Expression<String>? unit,
    Expression<String>? note,
    Expression<String>? mealId,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (householdId != null) 'household_id': householdId,
      if (inventoryItemId != null) 'inventory_item_id': inventoryItemId,
      if (productId != null) 'product_id': productId,
      if (occurredAt != null) 'occurred_at': occurredAt,
      if (type != null) 'type': type,
      if (quantityDelta != null) 'quantity_delta': quantityDelta,
      if (unit != null) 'unit': unit,
      if (note != null) 'note': note,
      if (mealId != null) 'meal_id': mealId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InventoryMovementsCompanion copyWith({
    Value<String>? id,
    Value<String>? householdId,
    Value<String?>? inventoryItemId,
    Value<String>? productId,
    Value<DateTime>? occurredAt,
    Value<String>? type,
    Value<double>? quantityDelta,
    Value<String>? unit,
    Value<String?>? note,
    Value<String?>? mealId,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return InventoryMovementsCompanion(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      inventoryItemId: inventoryItemId ?? this.inventoryItemId,
      productId: productId ?? this.productId,
      occurredAt: occurredAt ?? this.occurredAt,
      type: type ?? this.type,
      quantityDelta: quantityDelta ?? this.quantityDelta,
      unit: unit ?? this.unit,
      note: note ?? this.note,
      mealId: mealId ?? this.mealId,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (householdId.present) {
      map['household_id'] = Variable<String>(householdId.value);
    }
    if (inventoryItemId.present) {
      map['inventory_item_id'] = Variable<String>(inventoryItemId.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (occurredAt.present) {
      map['occurred_at'] = Variable<DateTime>(occurredAt.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (quantityDelta.present) {
      map['quantity_delta'] = Variable<double>(quantityDelta.value);
    }
    if (unit.present) {
      map['unit'] = Variable<String>(unit.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (mealId.present) {
      map['meal_id'] = Variable<String>(mealId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InventoryMovementsCompanion(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('inventoryItemId: $inventoryItemId, ')
          ..write('productId: $productId, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('type: $type, ')
          ..write('quantityDelta: $quantityDelta, ')
          ..write('unit: $unit, ')
          ..write('note: $note, ')
          ..write('mealId: $mealId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MealsTable extends Meals with TableInfo<$MealsTable, Meal> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MealsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _householdIdMeta = const VerificationMeta(
    'householdId',
  );
  @override
  late final GeneratedColumn<String> householdId = GeneratedColumn<String>(
    'household_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eatenAtMeta = const VerificationMeta(
    'eatenAt',
  );
  @override
  late final GeneratedColumn<DateTime> eatenAt = GeneratedColumn<DateTime>(
    'eaten_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mealTypeMeta = const VerificationMeta(
    'mealType',
  );
  @override
  late final GeneratedColumn<String> mealType = GeneratedColumn<String>(
    'meal_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('lunch'),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _photoPathMeta = const VerificationMeta(
    'photoPath',
  );
  @override
  late final GeneratedColumn<String> photoPath = GeneratedColumn<String>(
    'photo_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _recipeIdMeta = const VerificationMeta(
    'recipeId',
  );
  @override
  late final GeneratedColumn<String> recipeId = GeneratedColumn<String>(
    'recipe_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _servingsEatenMeta = const VerificationMeta(
    'servingsEaten',
  );
  @override
  late final GeneratedColumn<double> servingsEaten = GeneratedColumn<double>(
    'servings_eaten',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _servingsMadeMeta = const VerificationMeta(
    'servingsMade',
  );
  @override
  late final GeneratedColumn<double> servingsMade = GeneratedColumn<double>(
    'servings_made',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('manual'),
  );
  static const VerificationMeta _isEstimateMeta = const VerificationMeta(
    'isEstimate',
  );
  @override
  late final GeneratedColumn<bool> isEstimate = GeneratedColumn<bool>(
    'is_estimate',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_estimate" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    householdId,
    eatenAt,
    mealType,
    title,
    note,
    photoPath,
    recipeId,
    servingsEaten,
    servingsMade,
    source,
    isEstimate,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'meals';
  @override
  VerificationContext validateIntegrity(
    Insertable<Meal> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('household_id')) {
      context.handle(
        _householdIdMeta,
        householdId.isAcceptableOrUnknown(
          data['household_id']!,
          _householdIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_householdIdMeta);
    }
    if (data.containsKey('eaten_at')) {
      context.handle(
        _eatenAtMeta,
        eatenAt.isAcceptableOrUnknown(data['eaten_at']!, _eatenAtMeta),
      );
    } else if (isInserting) {
      context.missing(_eatenAtMeta);
    }
    if (data.containsKey('meal_type')) {
      context.handle(
        _mealTypeMeta,
        mealType.isAcceptableOrUnknown(data['meal_type']!, _mealTypeMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('photo_path')) {
      context.handle(
        _photoPathMeta,
        photoPath.isAcceptableOrUnknown(data['photo_path']!, _photoPathMeta),
      );
    }
    if (data.containsKey('recipe_id')) {
      context.handle(
        _recipeIdMeta,
        recipeId.isAcceptableOrUnknown(data['recipe_id']!, _recipeIdMeta),
      );
    }
    if (data.containsKey('servings_eaten')) {
      context.handle(
        _servingsEatenMeta,
        servingsEaten.isAcceptableOrUnknown(
          data['servings_eaten']!,
          _servingsEatenMeta,
        ),
      );
    }
    if (data.containsKey('servings_made')) {
      context.handle(
        _servingsMadeMeta,
        servingsMade.isAcceptableOrUnknown(
          data['servings_made']!,
          _servingsMadeMeta,
        ),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('is_estimate')) {
      context.handle(
        _isEstimateMeta,
        isEstimate.isAcceptableOrUnknown(data['is_estimate']!, _isEstimateMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Meal map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Meal(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      householdId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}household_id'],
      )!,
      eatenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}eaten_at'],
      )!,
      mealType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}meal_type'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      photoPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}photo_path'],
      ),
      recipeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recipe_id'],
      ),
      servingsEaten: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}servings_eaten'],
      )!,
      servingsMade: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}servings_made'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      isEstimate: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_estimate'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $MealsTable createAlias(String alias) {
    return $MealsTable(attachedDatabase, alias);
  }
}

class Meal extends DataClass implements Insertable<Meal> {
  final String id;
  final String householdId;
  final DateTime eatenAt;

  /// 'breakfast' | 'lunch' | 'dinner' | 'snack' | 'drink'
  final String mealType;
  final String title;
  final String? note;

  /// Storage-Pfad im Bucket `meals` (`{household_id}/{meal_id}.jpg`), sobald das Foto hochgeladen ist.
  final String? photoPath;
  final String? recipeId;

  /// Anteil, der von der Person selbst gegessen wurde, und insgesamt zubereitete Portionen (FR-13).
  final double servingsEaten;
  final double servingsMade;

  /// 'manual' | 'photo_ai' | 'recipe'
  final String source;

  /// Zutaten nur geschaetzt (z.B. Restaurant), in allen Auswertungen erkennbar (FR-17).
  final bool isEstimate;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const Meal({
    required this.id,
    required this.householdId,
    required this.eatenAt,
    required this.mealType,
    required this.title,
    this.note,
    this.photoPath,
    this.recipeId,
    required this.servingsEaten,
    required this.servingsMade,
    required this.source,
    required this.isEstimate,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['household_id'] = Variable<String>(householdId);
    map['eaten_at'] = Variable<DateTime>(eatenAt);
    map['meal_type'] = Variable<String>(mealType);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    if (!nullToAbsent || photoPath != null) {
      map['photo_path'] = Variable<String>(photoPath);
    }
    if (!nullToAbsent || recipeId != null) {
      map['recipe_id'] = Variable<String>(recipeId);
    }
    map['servings_eaten'] = Variable<double>(servingsEaten);
    map['servings_made'] = Variable<double>(servingsMade);
    map['source'] = Variable<String>(source);
    map['is_estimate'] = Variable<bool>(isEstimate);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  MealsCompanion toCompanion(bool nullToAbsent) {
    return MealsCompanion(
      id: Value(id),
      householdId: Value(householdId),
      eatenAt: Value(eatenAt),
      mealType: Value(mealType),
      title: Value(title),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      photoPath: photoPath == null && nullToAbsent
          ? const Value.absent()
          : Value(photoPath),
      recipeId: recipeId == null && nullToAbsent
          ? const Value.absent()
          : Value(recipeId),
      servingsEaten: Value(servingsEaten),
      servingsMade: Value(servingsMade),
      source: Value(source),
      isEstimate: Value(isEstimate),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory Meal.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Meal(
      id: serializer.fromJson<String>(json['id']),
      householdId: serializer.fromJson<String>(json['householdId']),
      eatenAt: serializer.fromJson<DateTime>(json['eatenAt']),
      mealType: serializer.fromJson<String>(json['mealType']),
      title: serializer.fromJson<String>(json['title']),
      note: serializer.fromJson<String?>(json['note']),
      photoPath: serializer.fromJson<String?>(json['photoPath']),
      recipeId: serializer.fromJson<String?>(json['recipeId']),
      servingsEaten: serializer.fromJson<double>(json['servingsEaten']),
      servingsMade: serializer.fromJson<double>(json['servingsMade']),
      source: serializer.fromJson<String>(json['source']),
      isEstimate: serializer.fromJson<bool>(json['isEstimate']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'householdId': serializer.toJson<String>(householdId),
      'eatenAt': serializer.toJson<DateTime>(eatenAt),
      'mealType': serializer.toJson<String>(mealType),
      'title': serializer.toJson<String>(title),
      'note': serializer.toJson<String?>(note),
      'photoPath': serializer.toJson<String?>(photoPath),
      'recipeId': serializer.toJson<String?>(recipeId),
      'servingsEaten': serializer.toJson<double>(servingsEaten),
      'servingsMade': serializer.toJson<double>(servingsMade),
      'source': serializer.toJson<String>(source),
      'isEstimate': serializer.toJson<bool>(isEstimate),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  Meal copyWith({
    String? id,
    String? householdId,
    DateTime? eatenAt,
    String? mealType,
    String? title,
    Value<String?> note = const Value.absent(),
    Value<String?> photoPath = const Value.absent(),
    Value<String?> recipeId = const Value.absent(),
    double? servingsEaten,
    double? servingsMade,
    String? source,
    bool? isEstimate,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => Meal(
    id: id ?? this.id,
    householdId: householdId ?? this.householdId,
    eatenAt: eatenAt ?? this.eatenAt,
    mealType: mealType ?? this.mealType,
    title: title ?? this.title,
    note: note.present ? note.value : this.note,
    photoPath: photoPath.present ? photoPath.value : this.photoPath,
    recipeId: recipeId.present ? recipeId.value : this.recipeId,
    servingsEaten: servingsEaten ?? this.servingsEaten,
    servingsMade: servingsMade ?? this.servingsMade,
    source: source ?? this.source,
    isEstimate: isEstimate ?? this.isEstimate,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  Meal copyWithCompanion(MealsCompanion data) {
    return Meal(
      id: data.id.present ? data.id.value : this.id,
      householdId: data.householdId.present
          ? data.householdId.value
          : this.householdId,
      eatenAt: data.eatenAt.present ? data.eatenAt.value : this.eatenAt,
      mealType: data.mealType.present ? data.mealType.value : this.mealType,
      title: data.title.present ? data.title.value : this.title,
      note: data.note.present ? data.note.value : this.note,
      photoPath: data.photoPath.present ? data.photoPath.value : this.photoPath,
      recipeId: data.recipeId.present ? data.recipeId.value : this.recipeId,
      servingsEaten: data.servingsEaten.present
          ? data.servingsEaten.value
          : this.servingsEaten,
      servingsMade: data.servingsMade.present
          ? data.servingsMade.value
          : this.servingsMade,
      source: data.source.present ? data.source.value : this.source,
      isEstimate: data.isEstimate.present
          ? data.isEstimate.value
          : this.isEstimate,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Meal(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('eatenAt: $eatenAt, ')
          ..write('mealType: $mealType, ')
          ..write('title: $title, ')
          ..write('note: $note, ')
          ..write('photoPath: $photoPath, ')
          ..write('recipeId: $recipeId, ')
          ..write('servingsEaten: $servingsEaten, ')
          ..write('servingsMade: $servingsMade, ')
          ..write('source: $source, ')
          ..write('isEstimate: $isEstimate, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    householdId,
    eatenAt,
    mealType,
    title,
    note,
    photoPath,
    recipeId,
    servingsEaten,
    servingsMade,
    source,
    isEstimate,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Meal &&
          other.id == this.id &&
          other.householdId == this.householdId &&
          other.eatenAt == this.eatenAt &&
          other.mealType == this.mealType &&
          other.title == this.title &&
          other.note == this.note &&
          other.photoPath == this.photoPath &&
          other.recipeId == this.recipeId &&
          other.servingsEaten == this.servingsEaten &&
          other.servingsMade == this.servingsMade &&
          other.source == this.source &&
          other.isEstimate == this.isEstimate &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class MealsCompanion extends UpdateCompanion<Meal> {
  final Value<String> id;
  final Value<String> householdId;
  final Value<DateTime> eatenAt;
  final Value<String> mealType;
  final Value<String> title;
  final Value<String?> note;
  final Value<String?> photoPath;
  final Value<String?> recipeId;
  final Value<double> servingsEaten;
  final Value<double> servingsMade;
  final Value<String> source;
  final Value<bool> isEstimate;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const MealsCompanion({
    this.id = const Value.absent(),
    this.householdId = const Value.absent(),
    this.eatenAt = const Value.absent(),
    this.mealType = const Value.absent(),
    this.title = const Value.absent(),
    this.note = const Value.absent(),
    this.photoPath = const Value.absent(),
    this.recipeId = const Value.absent(),
    this.servingsEaten = const Value.absent(),
    this.servingsMade = const Value.absent(),
    this.source = const Value.absent(),
    this.isEstimate = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MealsCompanion.insert({
    required String id,
    required String householdId,
    required DateTime eatenAt,
    this.mealType = const Value.absent(),
    required String title,
    this.note = const Value.absent(),
    this.photoPath = const Value.absent(),
    this.recipeId = const Value.absent(),
    this.servingsEaten = const Value.absent(),
    this.servingsMade = const Value.absent(),
    this.source = const Value.absent(),
    this.isEstimate = const Value.absent(),
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       householdId = Value(householdId),
       eatenAt = Value(eatenAt),
       title = Value(title),
       updatedAt = Value(updatedAt);
  static Insertable<Meal> custom({
    Expression<String>? id,
    Expression<String>? householdId,
    Expression<DateTime>? eatenAt,
    Expression<String>? mealType,
    Expression<String>? title,
    Expression<String>? note,
    Expression<String>? photoPath,
    Expression<String>? recipeId,
    Expression<double>? servingsEaten,
    Expression<double>? servingsMade,
    Expression<String>? source,
    Expression<bool>? isEstimate,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (householdId != null) 'household_id': householdId,
      if (eatenAt != null) 'eaten_at': eatenAt,
      if (mealType != null) 'meal_type': mealType,
      if (title != null) 'title': title,
      if (note != null) 'note': note,
      if (photoPath != null) 'photo_path': photoPath,
      if (recipeId != null) 'recipe_id': recipeId,
      if (servingsEaten != null) 'servings_eaten': servingsEaten,
      if (servingsMade != null) 'servings_made': servingsMade,
      if (source != null) 'source': source,
      if (isEstimate != null) 'is_estimate': isEstimate,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MealsCompanion copyWith({
    Value<String>? id,
    Value<String>? householdId,
    Value<DateTime>? eatenAt,
    Value<String>? mealType,
    Value<String>? title,
    Value<String?>? note,
    Value<String?>? photoPath,
    Value<String?>? recipeId,
    Value<double>? servingsEaten,
    Value<double>? servingsMade,
    Value<String>? source,
    Value<bool>? isEstimate,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return MealsCompanion(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      eatenAt: eatenAt ?? this.eatenAt,
      mealType: mealType ?? this.mealType,
      title: title ?? this.title,
      note: note ?? this.note,
      photoPath: photoPath ?? this.photoPath,
      recipeId: recipeId ?? this.recipeId,
      servingsEaten: servingsEaten ?? this.servingsEaten,
      servingsMade: servingsMade ?? this.servingsMade,
      source: source ?? this.source,
      isEstimate: isEstimate ?? this.isEstimate,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (householdId.present) {
      map['household_id'] = Variable<String>(householdId.value);
    }
    if (eatenAt.present) {
      map['eaten_at'] = Variable<DateTime>(eatenAt.value);
    }
    if (mealType.present) {
      map['meal_type'] = Variable<String>(mealType.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (photoPath.present) {
      map['photo_path'] = Variable<String>(photoPath.value);
    }
    if (recipeId.present) {
      map['recipe_id'] = Variable<String>(recipeId.value);
    }
    if (servingsEaten.present) {
      map['servings_eaten'] = Variable<double>(servingsEaten.value);
    }
    if (servingsMade.present) {
      map['servings_made'] = Variable<double>(servingsMade.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (isEstimate.present) {
      map['is_estimate'] = Variable<bool>(isEstimate.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MealsCompanion(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('eatenAt: $eatenAt, ')
          ..write('mealType: $mealType, ')
          ..write('title: $title, ')
          ..write('note: $note, ')
          ..write('photoPath: $photoPath, ')
          ..write('recipeId: $recipeId, ')
          ..write('servingsEaten: $servingsEaten, ')
          ..write('servingsMade: $servingsMade, ')
          ..write('source: $source, ')
          ..write('isEstimate: $isEstimate, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MealIngredientsTable extends MealIngredients
    with TableInfo<$MealIngredientsTable, MealIngredient> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MealIngredientsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _householdIdMeta = const VerificationMeta(
    'householdId',
  );
  @override
  late final GeneratedColumn<String> householdId = GeneratedColumn<String>(
    'household_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mealIdMeta = const VerificationMeta('mealId');
  @override
  late final GeneratedColumn<String> mealId = GeneratedColumn<String>(
    'meal_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _productIdMeta = const VerificationMeta(
    'productId',
  );
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
    'product_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _inventoryItemIdMeta = const VerificationMeta(
    'inventoryItemId',
  );
  @override
  late final GeneratedColumn<String> inventoryItemId = GeneratedColumn<String>(
    'inventory_item_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _freeTextMeta = const VerificationMeta(
    'freeText',
  );
  @override
  late final GeneratedColumn<String> freeText = GeneratedColumn<String>(
    'free_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _quantityMeta = const VerificationMeta(
    'quantity',
  );
  @override
  late final GeneratedColumn<double> quantity = GeneratedColumn<double>(
    'quantity',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _unitMeta = const VerificationMeta('unit');
  @override
  late final GeneratedColumn<String> unit = GeneratedColumn<String>(
    'unit',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountGMeta = const VerificationMeta(
    'amountG',
  );
  @override
  late final GeneratedColumn<double> amountG = GeneratedColumn<double>(
    'amount_g',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('manual'),
  );
  static const VerificationMeta _confidenceMeta = const VerificationMeta(
    'confidence',
  );
  @override
  late final GeneratedColumn<double> confidence = GeneratedColumn<double>(
    'confidence',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _kcalMeta = const VerificationMeta('kcal');
  @override
  late final GeneratedColumn<double> kcal = GeneratedColumn<double>(
    'kcal',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _proteinGMeta = const VerificationMeta(
    'proteinG',
  );
  @override
  late final GeneratedColumn<double> proteinG = GeneratedColumn<double>(
    'protein_g',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fatGMeta = const VerificationMeta('fatG');
  @override
  late final GeneratedColumn<double> fatG = GeneratedColumn<double>(
    'fat_g',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _carbsGMeta = const VerificationMeta('carbsG');
  @override
  late final GeneratedColumn<double> carbsG = GeneratedColumn<double>(
    'carbs_g',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sugarGMeta = const VerificationMeta('sugarG');
  @override
  late final GeneratedColumn<double> sugarG = GeneratedColumn<double>(
    'sugar_g',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fiberGMeta = const VerificationMeta('fiberG');
  @override
  late final GeneratedColumn<double> fiberG = GeneratedColumn<double>(
    'fiber_g',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _saltGMeta = const VerificationMeta('saltG');
  @override
  late final GeneratedColumn<double> saltG = GeneratedColumn<double>(
    'salt_g',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    householdId,
    mealId,
    productId,
    inventoryItemId,
    freeText,
    quantity,
    unit,
    amountG,
    source,
    confidence,
    kcal,
    proteinG,
    fatG,
    carbsG,
    sugarG,
    fiberG,
    saltG,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'meal_ingredients';
  @override
  VerificationContext validateIntegrity(
    Insertable<MealIngredient> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('household_id')) {
      context.handle(
        _householdIdMeta,
        householdId.isAcceptableOrUnknown(
          data['household_id']!,
          _householdIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_householdIdMeta);
    }
    if (data.containsKey('meal_id')) {
      context.handle(
        _mealIdMeta,
        mealId.isAcceptableOrUnknown(data['meal_id']!, _mealIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mealIdMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(
        _productIdMeta,
        productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta),
      );
    }
    if (data.containsKey('inventory_item_id')) {
      context.handle(
        _inventoryItemIdMeta,
        inventoryItemId.isAcceptableOrUnknown(
          data['inventory_item_id']!,
          _inventoryItemIdMeta,
        ),
      );
    }
    if (data.containsKey('free_text')) {
      context.handle(
        _freeTextMeta,
        freeText.isAcceptableOrUnknown(data['free_text']!, _freeTextMeta),
      );
    }
    if (data.containsKey('quantity')) {
      context.handle(
        _quantityMeta,
        quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta),
      );
    } else if (isInserting) {
      context.missing(_quantityMeta);
    }
    if (data.containsKey('unit')) {
      context.handle(
        _unitMeta,
        unit.isAcceptableOrUnknown(data['unit']!, _unitMeta),
      );
    } else if (isInserting) {
      context.missing(_unitMeta);
    }
    if (data.containsKey('amount_g')) {
      context.handle(
        _amountGMeta,
        amountG.isAcceptableOrUnknown(data['amount_g']!, _amountGMeta),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('confidence')) {
      context.handle(
        _confidenceMeta,
        confidence.isAcceptableOrUnknown(data['confidence']!, _confidenceMeta),
      );
    }
    if (data.containsKey('kcal')) {
      context.handle(
        _kcalMeta,
        kcal.isAcceptableOrUnknown(data['kcal']!, _kcalMeta),
      );
    }
    if (data.containsKey('protein_g')) {
      context.handle(
        _proteinGMeta,
        proteinG.isAcceptableOrUnknown(data['protein_g']!, _proteinGMeta),
      );
    }
    if (data.containsKey('fat_g')) {
      context.handle(
        _fatGMeta,
        fatG.isAcceptableOrUnknown(data['fat_g']!, _fatGMeta),
      );
    }
    if (data.containsKey('carbs_g')) {
      context.handle(
        _carbsGMeta,
        carbsG.isAcceptableOrUnknown(data['carbs_g']!, _carbsGMeta),
      );
    }
    if (data.containsKey('sugar_g')) {
      context.handle(
        _sugarGMeta,
        sugarG.isAcceptableOrUnknown(data['sugar_g']!, _sugarGMeta),
      );
    }
    if (data.containsKey('fiber_g')) {
      context.handle(
        _fiberGMeta,
        fiberG.isAcceptableOrUnknown(data['fiber_g']!, _fiberGMeta),
      );
    }
    if (data.containsKey('salt_g')) {
      context.handle(
        _saltGMeta,
        saltG.isAcceptableOrUnknown(data['salt_g']!, _saltGMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MealIngredient map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MealIngredient(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      householdId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}household_id'],
      )!,
      mealId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}meal_id'],
      )!,
      productId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}product_id'],
      ),
      inventoryItemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}inventory_item_id'],
      ),
      freeText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}free_text'],
      ),
      quantity: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}quantity'],
      )!,
      unit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unit'],
      )!,
      amountG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}amount_g'],
      ),
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      confidence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}confidence'],
      ),
      kcal: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}kcal'],
      ),
      proteinG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}protein_g'],
      ),
      fatG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}fat_g'],
      ),
      carbsG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}carbs_g'],
      ),
      sugarG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}sugar_g'],
      ),
      fiberG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}fiber_g'],
      ),
      saltG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}salt_g'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $MealIngredientsTable createAlias(String alias) {
    return $MealIngredientsTable(attachedDatabase, alias);
  }
}

class MealIngredient extends DataClass implements Insertable<MealIngredient> {
  final String id;
  final String householdId;
  final String mealId;
  final String? productId;

  /// Erster Inventar-Posten, aus dem abgezogen wurde (die Aufteilung auf mehrere Posten steht im Ledger).
  final String? inventoryItemId;
  final String? freeText;

  /// Erfasste Menge in einer der Datenbank-Einheiten `kg` | `l` | `piece`.
  final double quantity;
  final String unit;

  /// Menge in g bzw. ml, Basis der Naehrwertrechnung; `null`, wenn nicht bestimmbar.
  final double? amountG;

  /// 'inventory' | 'photo_ai' | 'recipe' | 'manual' | 'estimate'
  final String source;
  final double? confidence;
  final double? kcal;
  final double? proteinG;
  final double? fatG;
  final double? carbsG;
  final double? sugarG;
  final double? fiberG;
  final double? saltG;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const MealIngredient({
    required this.id,
    required this.householdId,
    required this.mealId,
    this.productId,
    this.inventoryItemId,
    this.freeText,
    required this.quantity,
    required this.unit,
    this.amountG,
    required this.source,
    this.confidence,
    this.kcal,
    this.proteinG,
    this.fatG,
    this.carbsG,
    this.sugarG,
    this.fiberG,
    this.saltG,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['household_id'] = Variable<String>(householdId);
    map['meal_id'] = Variable<String>(mealId);
    if (!nullToAbsent || productId != null) {
      map['product_id'] = Variable<String>(productId);
    }
    if (!nullToAbsent || inventoryItemId != null) {
      map['inventory_item_id'] = Variable<String>(inventoryItemId);
    }
    if (!nullToAbsent || freeText != null) {
      map['free_text'] = Variable<String>(freeText);
    }
    map['quantity'] = Variable<double>(quantity);
    map['unit'] = Variable<String>(unit);
    if (!nullToAbsent || amountG != null) {
      map['amount_g'] = Variable<double>(amountG);
    }
    map['source'] = Variable<String>(source);
    if (!nullToAbsent || confidence != null) {
      map['confidence'] = Variable<double>(confidence);
    }
    if (!nullToAbsent || kcal != null) {
      map['kcal'] = Variable<double>(kcal);
    }
    if (!nullToAbsent || proteinG != null) {
      map['protein_g'] = Variable<double>(proteinG);
    }
    if (!nullToAbsent || fatG != null) {
      map['fat_g'] = Variable<double>(fatG);
    }
    if (!nullToAbsent || carbsG != null) {
      map['carbs_g'] = Variable<double>(carbsG);
    }
    if (!nullToAbsent || sugarG != null) {
      map['sugar_g'] = Variable<double>(sugarG);
    }
    if (!nullToAbsent || fiberG != null) {
      map['fiber_g'] = Variable<double>(fiberG);
    }
    if (!nullToAbsent || saltG != null) {
      map['salt_g'] = Variable<double>(saltG);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  MealIngredientsCompanion toCompanion(bool nullToAbsent) {
    return MealIngredientsCompanion(
      id: Value(id),
      householdId: Value(householdId),
      mealId: Value(mealId),
      productId: productId == null && nullToAbsent
          ? const Value.absent()
          : Value(productId),
      inventoryItemId: inventoryItemId == null && nullToAbsent
          ? const Value.absent()
          : Value(inventoryItemId),
      freeText: freeText == null && nullToAbsent
          ? const Value.absent()
          : Value(freeText),
      quantity: Value(quantity),
      unit: Value(unit),
      amountG: amountG == null && nullToAbsent
          ? const Value.absent()
          : Value(amountG),
      source: Value(source),
      confidence: confidence == null && nullToAbsent
          ? const Value.absent()
          : Value(confidence),
      kcal: kcal == null && nullToAbsent ? const Value.absent() : Value(kcal),
      proteinG: proteinG == null && nullToAbsent
          ? const Value.absent()
          : Value(proteinG),
      fatG: fatG == null && nullToAbsent ? const Value.absent() : Value(fatG),
      carbsG: carbsG == null && nullToAbsent
          ? const Value.absent()
          : Value(carbsG),
      sugarG: sugarG == null && nullToAbsent
          ? const Value.absent()
          : Value(sugarG),
      fiberG: fiberG == null && nullToAbsent
          ? const Value.absent()
          : Value(fiberG),
      saltG: saltG == null && nullToAbsent
          ? const Value.absent()
          : Value(saltG),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory MealIngredient.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MealIngredient(
      id: serializer.fromJson<String>(json['id']),
      householdId: serializer.fromJson<String>(json['householdId']),
      mealId: serializer.fromJson<String>(json['mealId']),
      productId: serializer.fromJson<String?>(json['productId']),
      inventoryItemId: serializer.fromJson<String?>(json['inventoryItemId']),
      freeText: serializer.fromJson<String?>(json['freeText']),
      quantity: serializer.fromJson<double>(json['quantity']),
      unit: serializer.fromJson<String>(json['unit']),
      amountG: serializer.fromJson<double?>(json['amountG']),
      source: serializer.fromJson<String>(json['source']),
      confidence: serializer.fromJson<double?>(json['confidence']),
      kcal: serializer.fromJson<double?>(json['kcal']),
      proteinG: serializer.fromJson<double?>(json['proteinG']),
      fatG: serializer.fromJson<double?>(json['fatG']),
      carbsG: serializer.fromJson<double?>(json['carbsG']),
      sugarG: serializer.fromJson<double?>(json['sugarG']),
      fiberG: serializer.fromJson<double?>(json['fiberG']),
      saltG: serializer.fromJson<double?>(json['saltG']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'householdId': serializer.toJson<String>(householdId),
      'mealId': serializer.toJson<String>(mealId),
      'productId': serializer.toJson<String?>(productId),
      'inventoryItemId': serializer.toJson<String?>(inventoryItemId),
      'freeText': serializer.toJson<String?>(freeText),
      'quantity': serializer.toJson<double>(quantity),
      'unit': serializer.toJson<String>(unit),
      'amountG': serializer.toJson<double?>(amountG),
      'source': serializer.toJson<String>(source),
      'confidence': serializer.toJson<double?>(confidence),
      'kcal': serializer.toJson<double?>(kcal),
      'proteinG': serializer.toJson<double?>(proteinG),
      'fatG': serializer.toJson<double?>(fatG),
      'carbsG': serializer.toJson<double?>(carbsG),
      'sugarG': serializer.toJson<double?>(sugarG),
      'fiberG': serializer.toJson<double?>(fiberG),
      'saltG': serializer.toJson<double?>(saltG),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  MealIngredient copyWith({
    String? id,
    String? householdId,
    String? mealId,
    Value<String?> productId = const Value.absent(),
    Value<String?> inventoryItemId = const Value.absent(),
    Value<String?> freeText = const Value.absent(),
    double? quantity,
    String? unit,
    Value<double?> amountG = const Value.absent(),
    String? source,
    Value<double?> confidence = const Value.absent(),
    Value<double?> kcal = const Value.absent(),
    Value<double?> proteinG = const Value.absent(),
    Value<double?> fatG = const Value.absent(),
    Value<double?> carbsG = const Value.absent(),
    Value<double?> sugarG = const Value.absent(),
    Value<double?> fiberG = const Value.absent(),
    Value<double?> saltG = const Value.absent(),
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => MealIngredient(
    id: id ?? this.id,
    householdId: householdId ?? this.householdId,
    mealId: mealId ?? this.mealId,
    productId: productId.present ? productId.value : this.productId,
    inventoryItemId: inventoryItemId.present
        ? inventoryItemId.value
        : this.inventoryItemId,
    freeText: freeText.present ? freeText.value : this.freeText,
    quantity: quantity ?? this.quantity,
    unit: unit ?? this.unit,
    amountG: amountG.present ? amountG.value : this.amountG,
    source: source ?? this.source,
    confidence: confidence.present ? confidence.value : this.confidence,
    kcal: kcal.present ? kcal.value : this.kcal,
    proteinG: proteinG.present ? proteinG.value : this.proteinG,
    fatG: fatG.present ? fatG.value : this.fatG,
    carbsG: carbsG.present ? carbsG.value : this.carbsG,
    sugarG: sugarG.present ? sugarG.value : this.sugarG,
    fiberG: fiberG.present ? fiberG.value : this.fiberG,
    saltG: saltG.present ? saltG.value : this.saltG,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  MealIngredient copyWithCompanion(MealIngredientsCompanion data) {
    return MealIngredient(
      id: data.id.present ? data.id.value : this.id,
      householdId: data.householdId.present
          ? data.householdId.value
          : this.householdId,
      mealId: data.mealId.present ? data.mealId.value : this.mealId,
      productId: data.productId.present ? data.productId.value : this.productId,
      inventoryItemId: data.inventoryItemId.present
          ? data.inventoryItemId.value
          : this.inventoryItemId,
      freeText: data.freeText.present ? data.freeText.value : this.freeText,
      quantity: data.quantity.present ? data.quantity.value : this.quantity,
      unit: data.unit.present ? data.unit.value : this.unit,
      amountG: data.amountG.present ? data.amountG.value : this.amountG,
      source: data.source.present ? data.source.value : this.source,
      confidence: data.confidence.present
          ? data.confidence.value
          : this.confidence,
      kcal: data.kcal.present ? data.kcal.value : this.kcal,
      proteinG: data.proteinG.present ? data.proteinG.value : this.proteinG,
      fatG: data.fatG.present ? data.fatG.value : this.fatG,
      carbsG: data.carbsG.present ? data.carbsG.value : this.carbsG,
      sugarG: data.sugarG.present ? data.sugarG.value : this.sugarG,
      fiberG: data.fiberG.present ? data.fiberG.value : this.fiberG,
      saltG: data.saltG.present ? data.saltG.value : this.saltG,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MealIngredient(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('mealId: $mealId, ')
          ..write('productId: $productId, ')
          ..write('inventoryItemId: $inventoryItemId, ')
          ..write('freeText: $freeText, ')
          ..write('quantity: $quantity, ')
          ..write('unit: $unit, ')
          ..write('amountG: $amountG, ')
          ..write('source: $source, ')
          ..write('confidence: $confidence, ')
          ..write('kcal: $kcal, ')
          ..write('proteinG: $proteinG, ')
          ..write('fatG: $fatG, ')
          ..write('carbsG: $carbsG, ')
          ..write('sugarG: $sugarG, ')
          ..write('fiberG: $fiberG, ')
          ..write('saltG: $saltG, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    householdId,
    mealId,
    productId,
    inventoryItemId,
    freeText,
    quantity,
    unit,
    amountG,
    source,
    confidence,
    kcal,
    proteinG,
    fatG,
    carbsG,
    sugarG,
    fiberG,
    saltG,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MealIngredient &&
          other.id == this.id &&
          other.householdId == this.householdId &&
          other.mealId == this.mealId &&
          other.productId == this.productId &&
          other.inventoryItemId == this.inventoryItemId &&
          other.freeText == this.freeText &&
          other.quantity == this.quantity &&
          other.unit == this.unit &&
          other.amountG == this.amountG &&
          other.source == this.source &&
          other.confidence == this.confidence &&
          other.kcal == this.kcal &&
          other.proteinG == this.proteinG &&
          other.fatG == this.fatG &&
          other.carbsG == this.carbsG &&
          other.sugarG == this.sugarG &&
          other.fiberG == this.fiberG &&
          other.saltG == this.saltG &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class MealIngredientsCompanion extends UpdateCompanion<MealIngredient> {
  final Value<String> id;
  final Value<String> householdId;
  final Value<String> mealId;
  final Value<String?> productId;
  final Value<String?> inventoryItemId;
  final Value<String?> freeText;
  final Value<double> quantity;
  final Value<String> unit;
  final Value<double?> amountG;
  final Value<String> source;
  final Value<double?> confidence;
  final Value<double?> kcal;
  final Value<double?> proteinG;
  final Value<double?> fatG;
  final Value<double?> carbsG;
  final Value<double?> sugarG;
  final Value<double?> fiberG;
  final Value<double?> saltG;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const MealIngredientsCompanion({
    this.id = const Value.absent(),
    this.householdId = const Value.absent(),
    this.mealId = const Value.absent(),
    this.productId = const Value.absent(),
    this.inventoryItemId = const Value.absent(),
    this.freeText = const Value.absent(),
    this.quantity = const Value.absent(),
    this.unit = const Value.absent(),
    this.amountG = const Value.absent(),
    this.source = const Value.absent(),
    this.confidence = const Value.absent(),
    this.kcal = const Value.absent(),
    this.proteinG = const Value.absent(),
    this.fatG = const Value.absent(),
    this.carbsG = const Value.absent(),
    this.sugarG = const Value.absent(),
    this.fiberG = const Value.absent(),
    this.saltG = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MealIngredientsCompanion.insert({
    required String id,
    required String householdId,
    required String mealId,
    this.productId = const Value.absent(),
    this.inventoryItemId = const Value.absent(),
    this.freeText = const Value.absent(),
    required double quantity,
    required String unit,
    this.amountG = const Value.absent(),
    this.source = const Value.absent(),
    this.confidence = const Value.absent(),
    this.kcal = const Value.absent(),
    this.proteinG = const Value.absent(),
    this.fatG = const Value.absent(),
    this.carbsG = const Value.absent(),
    this.sugarG = const Value.absent(),
    this.fiberG = const Value.absent(),
    this.saltG = const Value.absent(),
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       householdId = Value(householdId),
       mealId = Value(mealId),
       quantity = Value(quantity),
       unit = Value(unit),
       updatedAt = Value(updatedAt);
  static Insertable<MealIngredient> custom({
    Expression<String>? id,
    Expression<String>? householdId,
    Expression<String>? mealId,
    Expression<String>? productId,
    Expression<String>? inventoryItemId,
    Expression<String>? freeText,
    Expression<double>? quantity,
    Expression<String>? unit,
    Expression<double>? amountG,
    Expression<String>? source,
    Expression<double>? confidence,
    Expression<double>? kcal,
    Expression<double>? proteinG,
    Expression<double>? fatG,
    Expression<double>? carbsG,
    Expression<double>? sugarG,
    Expression<double>? fiberG,
    Expression<double>? saltG,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (householdId != null) 'household_id': householdId,
      if (mealId != null) 'meal_id': mealId,
      if (productId != null) 'product_id': productId,
      if (inventoryItemId != null) 'inventory_item_id': inventoryItemId,
      if (freeText != null) 'free_text': freeText,
      if (quantity != null) 'quantity': quantity,
      if (unit != null) 'unit': unit,
      if (amountG != null) 'amount_g': amountG,
      if (source != null) 'source': source,
      if (confidence != null) 'confidence': confidence,
      if (kcal != null) 'kcal': kcal,
      if (proteinG != null) 'protein_g': proteinG,
      if (fatG != null) 'fat_g': fatG,
      if (carbsG != null) 'carbs_g': carbsG,
      if (sugarG != null) 'sugar_g': sugarG,
      if (fiberG != null) 'fiber_g': fiberG,
      if (saltG != null) 'salt_g': saltG,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MealIngredientsCompanion copyWith({
    Value<String>? id,
    Value<String>? householdId,
    Value<String>? mealId,
    Value<String?>? productId,
    Value<String?>? inventoryItemId,
    Value<String?>? freeText,
    Value<double>? quantity,
    Value<String>? unit,
    Value<double?>? amountG,
    Value<String>? source,
    Value<double?>? confidence,
    Value<double?>? kcal,
    Value<double?>? proteinG,
    Value<double?>? fatG,
    Value<double?>? carbsG,
    Value<double?>? sugarG,
    Value<double?>? fiberG,
    Value<double?>? saltG,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return MealIngredientsCompanion(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      mealId: mealId ?? this.mealId,
      productId: productId ?? this.productId,
      inventoryItemId: inventoryItemId ?? this.inventoryItemId,
      freeText: freeText ?? this.freeText,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      amountG: amountG ?? this.amountG,
      source: source ?? this.source,
      confidence: confidence ?? this.confidence,
      kcal: kcal ?? this.kcal,
      proteinG: proteinG ?? this.proteinG,
      fatG: fatG ?? this.fatG,
      carbsG: carbsG ?? this.carbsG,
      sugarG: sugarG ?? this.sugarG,
      fiberG: fiberG ?? this.fiberG,
      saltG: saltG ?? this.saltG,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (householdId.present) {
      map['household_id'] = Variable<String>(householdId.value);
    }
    if (mealId.present) {
      map['meal_id'] = Variable<String>(mealId.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (inventoryItemId.present) {
      map['inventory_item_id'] = Variable<String>(inventoryItemId.value);
    }
    if (freeText.present) {
      map['free_text'] = Variable<String>(freeText.value);
    }
    if (quantity.present) {
      map['quantity'] = Variable<double>(quantity.value);
    }
    if (unit.present) {
      map['unit'] = Variable<String>(unit.value);
    }
    if (amountG.present) {
      map['amount_g'] = Variable<double>(amountG.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (confidence.present) {
      map['confidence'] = Variable<double>(confidence.value);
    }
    if (kcal.present) {
      map['kcal'] = Variable<double>(kcal.value);
    }
    if (proteinG.present) {
      map['protein_g'] = Variable<double>(proteinG.value);
    }
    if (fatG.present) {
      map['fat_g'] = Variable<double>(fatG.value);
    }
    if (carbsG.present) {
      map['carbs_g'] = Variable<double>(carbsG.value);
    }
    if (sugarG.present) {
      map['sugar_g'] = Variable<double>(sugarG.value);
    }
    if (fiberG.present) {
      map['fiber_g'] = Variable<double>(fiberG.value);
    }
    if (saltG.present) {
      map['salt_g'] = Variable<double>(saltG.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MealIngredientsCompanion(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('mealId: $mealId, ')
          ..write('productId: $productId, ')
          ..write('inventoryItemId: $inventoryItemId, ')
          ..write('freeText: $freeText, ')
          ..write('quantity: $quantity, ')
          ..write('unit: $unit, ')
          ..write('amountG: $amountG, ')
          ..write('source: $source, ')
          ..write('confidence: $confidence, ')
          ..write('kcal: $kcal, ')
          ..write('proteinG: $proteinG, ')
          ..write('fatG: $fatG, ')
          ..write('carbsG: $carbsG, ')
          ..write('sugarG: $sugarG, ')
          ..write('fiberG: $fiberG, ')
          ..write('saltG: $saltG, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BugReportsTable extends BugReports
    with TableInfo<$BugReportsTable, BugReport> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BugReportsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _householdIdMeta = const VerificationMeta(
    'householdId',
  );
  @override
  late final GeneratedColumn<String> householdId = GeneratedColumn<String>(
    'household_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('bug'),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _appInfoMeta = const VerificationMeta(
    'appInfo',
  );
  @override
  late final GeneratedColumn<String> appInfo = GeneratedColumn<String>(
    'app_info',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dataSnapshotMeta = const VerificationMeta(
    'dataSnapshot',
  );
  @override
  late final GeneratedColumn<String> dataSnapshot = GeneratedColumn<String>(
    'data_snapshot',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('new'),
  );
  static const VerificationMeta _severityMeta = const VerificationMeta(
    'severity',
  );
  @override
  late final GeneratedColumn<String> severity = GeneratedColumn<String>(
    'severity',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _resolutionMeta = const VerificationMeta(
    'resolution',
  );
  @override
  late final GeneratedColumn<String> resolution = GeneratedColumn<String>(
    'resolution',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fixedInVersionMeta = const VerificationMeta(
    'fixedInVersion',
  );
  @override
  late final GeneratedColumn<String> fixedInVersion = GeneratedColumn<String>(
    'fixed_in_version',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusUpdatedAtMeta = const VerificationMeta(
    'statusUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> statusUpdatedAt =
      GeneratedColumn<DateTime>(
        'status_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    householdId,
    kind,
    title,
    description,
    appInfo,
    dataSnapshot,
    status,
    severity,
    resolution,
    fixedInVersion,
    statusUpdatedAt,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'bug_reports';
  @override
  VerificationContext validateIntegrity(
    Insertable<BugReport> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('household_id')) {
      context.handle(
        _householdIdMeta,
        householdId.isAcceptableOrUnknown(
          data['household_id']!,
          _householdIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_householdIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('app_info')) {
      context.handle(
        _appInfoMeta,
        appInfo.isAcceptableOrUnknown(data['app_info']!, _appInfoMeta),
      );
    } else if (isInserting) {
      context.missing(_appInfoMeta);
    }
    if (data.containsKey('data_snapshot')) {
      context.handle(
        _dataSnapshotMeta,
        dataSnapshot.isAcceptableOrUnknown(
          data['data_snapshot']!,
          _dataSnapshotMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('severity')) {
      context.handle(
        _severityMeta,
        severity.isAcceptableOrUnknown(data['severity']!, _severityMeta),
      );
    }
    if (data.containsKey('resolution')) {
      context.handle(
        _resolutionMeta,
        resolution.isAcceptableOrUnknown(data['resolution']!, _resolutionMeta),
      );
    }
    if (data.containsKey('fixed_in_version')) {
      context.handle(
        _fixedInVersionMeta,
        fixedInVersion.isAcceptableOrUnknown(
          data['fixed_in_version']!,
          _fixedInVersionMeta,
        ),
      );
    }
    if (data.containsKey('status_updated_at')) {
      context.handle(
        _statusUpdatedAtMeta,
        statusUpdatedAt.isAcceptableOrUnknown(
          data['status_updated_at']!,
          _statusUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BugReport map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BugReport(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      householdId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}household_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      appInfo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}app_info'],
      )!,
      dataSnapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data_snapshot'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      severity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}severity'],
      ),
      resolution: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resolution'],
      ),
      fixedInVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fixed_in_version'],
      ),
      statusUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}status_updated_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $BugReportsTable createAlias(String alias) {
    return $BugReportsTable(attachedDatabase, alias);
  }
}

class BugReport extends DataClass implements Insertable<BugReport> {
  final String id;
  final String householdId;

  /// 'bug' | 'feature'
  final String kind;
  final String title;
  final String? description;
  final String appInfo;
  final String? dataSnapshot;

  /// 'new' | 'confirmed' | 'in_progress' | 'fixed' | 'verified' | 'wont_fix' | 'duplicate'
  final String status;

  /// 'low' | 'medium' | 'high' | 'critical', von der Entwicklung gesetzt.
  final String? severity;
  final String? resolution;
  final String? fixedInVersion;
  final DateTime? statusUpdatedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const BugReport({
    required this.id,
    required this.householdId,
    required this.kind,
    required this.title,
    this.description,
    required this.appInfo,
    this.dataSnapshot,
    required this.status,
    this.severity,
    this.resolution,
    this.fixedInVersion,
    this.statusUpdatedAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['household_id'] = Variable<String>(householdId);
    map['kind'] = Variable<String>(kind);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['app_info'] = Variable<String>(appInfo);
    if (!nullToAbsent || dataSnapshot != null) {
      map['data_snapshot'] = Variable<String>(dataSnapshot);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || severity != null) {
      map['severity'] = Variable<String>(severity);
    }
    if (!nullToAbsent || resolution != null) {
      map['resolution'] = Variable<String>(resolution);
    }
    if (!nullToAbsent || fixedInVersion != null) {
      map['fixed_in_version'] = Variable<String>(fixedInVersion);
    }
    if (!nullToAbsent || statusUpdatedAt != null) {
      map['status_updated_at'] = Variable<DateTime>(statusUpdatedAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  BugReportsCompanion toCompanion(bool nullToAbsent) {
    return BugReportsCompanion(
      id: Value(id),
      householdId: Value(householdId),
      kind: Value(kind),
      title: Value(title),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      appInfo: Value(appInfo),
      dataSnapshot: dataSnapshot == null && nullToAbsent
          ? const Value.absent()
          : Value(dataSnapshot),
      status: Value(status),
      severity: severity == null && nullToAbsent
          ? const Value.absent()
          : Value(severity),
      resolution: resolution == null && nullToAbsent
          ? const Value.absent()
          : Value(resolution),
      fixedInVersion: fixedInVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(fixedInVersion),
      statusUpdatedAt: statusUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(statusUpdatedAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory BugReport.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BugReport(
      id: serializer.fromJson<String>(json['id']),
      householdId: serializer.fromJson<String>(json['householdId']),
      kind: serializer.fromJson<String>(json['kind']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String?>(json['description']),
      appInfo: serializer.fromJson<String>(json['appInfo']),
      dataSnapshot: serializer.fromJson<String?>(json['dataSnapshot']),
      status: serializer.fromJson<String>(json['status']),
      severity: serializer.fromJson<String?>(json['severity']),
      resolution: serializer.fromJson<String?>(json['resolution']),
      fixedInVersion: serializer.fromJson<String?>(json['fixedInVersion']),
      statusUpdatedAt: serializer.fromJson<DateTime?>(json['statusUpdatedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'householdId': serializer.toJson<String>(householdId),
      'kind': serializer.toJson<String>(kind),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String?>(description),
      'appInfo': serializer.toJson<String>(appInfo),
      'dataSnapshot': serializer.toJson<String?>(dataSnapshot),
      'status': serializer.toJson<String>(status),
      'severity': serializer.toJson<String?>(severity),
      'resolution': serializer.toJson<String?>(resolution),
      'fixedInVersion': serializer.toJson<String?>(fixedInVersion),
      'statusUpdatedAt': serializer.toJson<DateTime?>(statusUpdatedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  BugReport copyWith({
    String? id,
    String? householdId,
    String? kind,
    String? title,
    Value<String?> description = const Value.absent(),
    String? appInfo,
    Value<String?> dataSnapshot = const Value.absent(),
    String? status,
    Value<String?> severity = const Value.absent(),
    Value<String?> resolution = const Value.absent(),
    Value<String?> fixedInVersion = const Value.absent(),
    Value<DateTime?> statusUpdatedAt = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => BugReport(
    id: id ?? this.id,
    householdId: householdId ?? this.householdId,
    kind: kind ?? this.kind,
    title: title ?? this.title,
    description: description.present ? description.value : this.description,
    appInfo: appInfo ?? this.appInfo,
    dataSnapshot: dataSnapshot.present ? dataSnapshot.value : this.dataSnapshot,
    status: status ?? this.status,
    severity: severity.present ? severity.value : this.severity,
    resolution: resolution.present ? resolution.value : this.resolution,
    fixedInVersion: fixedInVersion.present
        ? fixedInVersion.value
        : this.fixedInVersion,
    statusUpdatedAt: statusUpdatedAt.present
        ? statusUpdatedAt.value
        : this.statusUpdatedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  BugReport copyWithCompanion(BugReportsCompanion data) {
    return BugReport(
      id: data.id.present ? data.id.value : this.id,
      householdId: data.householdId.present
          ? data.householdId.value
          : this.householdId,
      kind: data.kind.present ? data.kind.value : this.kind,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
      appInfo: data.appInfo.present ? data.appInfo.value : this.appInfo,
      dataSnapshot: data.dataSnapshot.present
          ? data.dataSnapshot.value
          : this.dataSnapshot,
      status: data.status.present ? data.status.value : this.status,
      severity: data.severity.present ? data.severity.value : this.severity,
      resolution: data.resolution.present
          ? data.resolution.value
          : this.resolution,
      fixedInVersion: data.fixedInVersion.present
          ? data.fixedInVersion.value
          : this.fixedInVersion,
      statusUpdatedAt: data.statusUpdatedAt.present
          ? data.statusUpdatedAt.value
          : this.statusUpdatedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BugReport(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('kind: $kind, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('appInfo: $appInfo, ')
          ..write('dataSnapshot: $dataSnapshot, ')
          ..write('status: $status, ')
          ..write('severity: $severity, ')
          ..write('resolution: $resolution, ')
          ..write('fixedInVersion: $fixedInVersion, ')
          ..write('statusUpdatedAt: $statusUpdatedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    householdId,
    kind,
    title,
    description,
    appInfo,
    dataSnapshot,
    status,
    severity,
    resolution,
    fixedInVersion,
    statusUpdatedAt,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BugReport &&
          other.id == this.id &&
          other.householdId == this.householdId &&
          other.kind == this.kind &&
          other.title == this.title &&
          other.description == this.description &&
          other.appInfo == this.appInfo &&
          other.dataSnapshot == this.dataSnapshot &&
          other.status == this.status &&
          other.severity == this.severity &&
          other.resolution == this.resolution &&
          other.fixedInVersion == this.fixedInVersion &&
          other.statusUpdatedAt == this.statusUpdatedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class BugReportsCompanion extends UpdateCompanion<BugReport> {
  final Value<String> id;
  final Value<String> householdId;
  final Value<String> kind;
  final Value<String> title;
  final Value<String?> description;
  final Value<String> appInfo;
  final Value<String?> dataSnapshot;
  final Value<String> status;
  final Value<String?> severity;
  final Value<String?> resolution;
  final Value<String?> fixedInVersion;
  final Value<DateTime?> statusUpdatedAt;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const BugReportsCompanion({
    this.id = const Value.absent(),
    this.householdId = const Value.absent(),
    this.kind = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.appInfo = const Value.absent(),
    this.dataSnapshot = const Value.absent(),
    this.status = const Value.absent(),
    this.severity = const Value.absent(),
    this.resolution = const Value.absent(),
    this.fixedInVersion = const Value.absent(),
    this.statusUpdatedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BugReportsCompanion.insert({
    required String id,
    required String householdId,
    this.kind = const Value.absent(),
    required String title,
    this.description = const Value.absent(),
    required String appInfo,
    this.dataSnapshot = const Value.absent(),
    this.status = const Value.absent(),
    this.severity = const Value.absent(),
    this.resolution = const Value.absent(),
    this.fixedInVersion = const Value.absent(),
    this.statusUpdatedAt = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       householdId = Value(householdId),
       title = Value(title),
       appInfo = Value(appInfo),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<BugReport> custom({
    Expression<String>? id,
    Expression<String>? householdId,
    Expression<String>? kind,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? appInfo,
    Expression<String>? dataSnapshot,
    Expression<String>? status,
    Expression<String>? severity,
    Expression<String>? resolution,
    Expression<String>? fixedInVersion,
    Expression<DateTime>? statusUpdatedAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (householdId != null) 'household_id': householdId,
      if (kind != null) 'kind': kind,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (appInfo != null) 'app_info': appInfo,
      if (dataSnapshot != null) 'data_snapshot': dataSnapshot,
      if (status != null) 'status': status,
      if (severity != null) 'severity': severity,
      if (resolution != null) 'resolution': resolution,
      if (fixedInVersion != null) 'fixed_in_version': fixedInVersion,
      if (statusUpdatedAt != null) 'status_updated_at': statusUpdatedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BugReportsCompanion copyWith({
    Value<String>? id,
    Value<String>? householdId,
    Value<String>? kind,
    Value<String>? title,
    Value<String?>? description,
    Value<String>? appInfo,
    Value<String?>? dataSnapshot,
    Value<String>? status,
    Value<String?>? severity,
    Value<String?>? resolution,
    Value<String?>? fixedInVersion,
    Value<DateTime?>? statusUpdatedAt,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return BugReportsCompanion(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      description: description ?? this.description,
      appInfo: appInfo ?? this.appInfo,
      dataSnapshot: dataSnapshot ?? this.dataSnapshot,
      status: status ?? this.status,
      severity: severity ?? this.severity,
      resolution: resolution ?? this.resolution,
      fixedInVersion: fixedInVersion ?? this.fixedInVersion,
      statusUpdatedAt: statusUpdatedAt ?? this.statusUpdatedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (householdId.present) {
      map['household_id'] = Variable<String>(householdId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (appInfo.present) {
      map['app_info'] = Variable<String>(appInfo.value);
    }
    if (dataSnapshot.present) {
      map['data_snapshot'] = Variable<String>(dataSnapshot.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (severity.present) {
      map['severity'] = Variable<String>(severity.value);
    }
    if (resolution.present) {
      map['resolution'] = Variable<String>(resolution.value);
    }
    if (fixedInVersion.present) {
      map['fixed_in_version'] = Variable<String>(fixedInVersion.value);
    }
    if (statusUpdatedAt.present) {
      map['status_updated_at'] = Variable<DateTime>(statusUpdatedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BugReportsCompanion(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('kind: $kind, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('appInfo: $appInfo, ')
          ..write('dataSnapshot: $dataSnapshot, ')
          ..write('status: $status, ')
          ..write('severity: $severity, ')
          ..write('resolution: $resolution, ')
          ..write('fixedInVersion: $fixedInVersion, ')
          ..write('statusUpdatedAt: $statusUpdatedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ShoppingListsTable extends ShoppingLists
    with TableInfo<$ShoppingListsTable, ShoppingList> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ShoppingListsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _householdIdMeta = const VerificationMeta(
    'householdId',
  );
  @override
  late final GeneratedColumn<String> householdId = GeneratedColumn<String>(
    'household_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('Einkaufsliste'),
  );
  static const VerificationMeta _isDefaultMeta = const VerificationMeta(
    'isDefault',
  );
  @override
  late final GeneratedColumn<bool> isDefault = GeneratedColumn<bool>(
    'is_default',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_default" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    householdId,
    name,
    isDefault,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'shopping_lists';
  @override
  VerificationContext validateIntegrity(
    Insertable<ShoppingList> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('household_id')) {
      context.handle(
        _householdIdMeta,
        householdId.isAcceptableOrUnknown(
          data['household_id']!,
          _householdIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_householdIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('is_default')) {
      context.handle(
        _isDefaultMeta,
        isDefault.isAcceptableOrUnknown(data['is_default']!, _isDefaultMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ShoppingList map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ShoppingList(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      householdId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}household_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      isDefault: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_default'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $ShoppingListsTable createAlias(String alias) {
    return $ShoppingListsTable(attachedDatabase, alias);
  }
}

class ShoppingList extends DataClass implements Insertable<ShoppingList> {
  final String id;
  final String householdId;
  final String name;
  final bool isDefault;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const ShoppingList({
    required this.id,
    required this.householdId,
    required this.name,
    required this.isDefault,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['household_id'] = Variable<String>(householdId);
    map['name'] = Variable<String>(name);
    map['is_default'] = Variable<bool>(isDefault);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  ShoppingListsCompanion toCompanion(bool nullToAbsent) {
    return ShoppingListsCompanion(
      id: Value(id),
      householdId: Value(householdId),
      name: Value(name),
      isDefault: Value(isDefault),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory ShoppingList.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ShoppingList(
      id: serializer.fromJson<String>(json['id']),
      householdId: serializer.fromJson<String>(json['householdId']),
      name: serializer.fromJson<String>(json['name']),
      isDefault: serializer.fromJson<bool>(json['isDefault']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'householdId': serializer.toJson<String>(householdId),
      'name': serializer.toJson<String>(name),
      'isDefault': serializer.toJson<bool>(isDefault),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  ShoppingList copyWith({
    String? id,
    String? householdId,
    String? name,
    bool? isDefault,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => ShoppingList(
    id: id ?? this.id,
    householdId: householdId ?? this.householdId,
    name: name ?? this.name,
    isDefault: isDefault ?? this.isDefault,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  ShoppingList copyWithCompanion(ShoppingListsCompanion data) {
    return ShoppingList(
      id: data.id.present ? data.id.value : this.id,
      householdId: data.householdId.present
          ? data.householdId.value
          : this.householdId,
      name: data.name.present ? data.name.value : this.name,
      isDefault: data.isDefault.present ? data.isDefault.value : this.isDefault,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ShoppingList(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('name: $name, ')
          ..write('isDefault: $isDefault, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, householdId, name, isDefault, updatedAt, deletedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ShoppingList &&
          other.id == this.id &&
          other.householdId == this.householdId &&
          other.name == this.name &&
          other.isDefault == this.isDefault &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class ShoppingListsCompanion extends UpdateCompanion<ShoppingList> {
  final Value<String> id;
  final Value<String> householdId;
  final Value<String> name;
  final Value<bool> isDefault;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const ShoppingListsCompanion({
    this.id = const Value.absent(),
    this.householdId = const Value.absent(),
    this.name = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ShoppingListsCompanion.insert({
    required String id,
    required String householdId,
    this.name = const Value.absent(),
    this.isDefault = const Value.absent(),
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       householdId = Value(householdId),
       updatedAt = Value(updatedAt);
  static Insertable<ShoppingList> custom({
    Expression<String>? id,
    Expression<String>? householdId,
    Expression<String>? name,
    Expression<bool>? isDefault,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (householdId != null) 'household_id': householdId,
      if (name != null) 'name': name,
      if (isDefault != null) 'is_default': isDefault,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ShoppingListsCompanion copyWith({
    Value<String>? id,
    Value<String>? householdId,
    Value<String>? name,
    Value<bool>? isDefault,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return ShoppingListsCompanion(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      name: name ?? this.name,
      isDefault: isDefault ?? this.isDefault,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (householdId.present) {
      map['household_id'] = Variable<String>(householdId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (isDefault.present) {
      map['is_default'] = Variable<bool>(isDefault.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ShoppingListsCompanion(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('name: $name, ')
          ..write('isDefault: $isDefault, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ShoppingListItemsTable extends ShoppingListItems
    with TableInfo<$ShoppingListItemsTable, ShoppingListItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ShoppingListItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _householdIdMeta = const VerificationMeta(
    'householdId',
  );
  @override
  late final GeneratedColumn<String> householdId = GeneratedColumn<String>(
    'household_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _listIdMeta = const VerificationMeta('listId');
  @override
  late final GeneratedColumn<String> listId = GeneratedColumn<String>(
    'list_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _productIdMeta = const VerificationMeta(
    'productId',
  );
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
    'product_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _freeTextMeta = const VerificationMeta(
    'freeText',
  );
  @override
  late final GeneratedColumn<String> freeText = GeneratedColumn<String>(
    'free_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _quantityMeta = const VerificationMeta(
    'quantity',
  );
  @override
  late final GeneratedColumn<double> quantity = GeneratedColumn<double>(
    'quantity',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _unitMeta = const VerificationMeta('unit');
  @override
  late final GeneratedColumn<String> unit = GeneratedColumn<String>(
    'unit',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('piece'),
  );
  static const VerificationMeta _checkedMeta = const VerificationMeta(
    'checked',
  );
  @override
  late final GeneratedColumn<bool> checked = GeneratedColumn<bool>(
    'checked',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("checked" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('manual'),
  );
  static const VerificationMeta _isSuggestionMeta = const VerificationMeta(
    'isSuggestion',
  );
  @override
  late final GeneratedColumn<bool> isSuggestion = GeneratedColumn<bool>(
    'is_suggestion',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_suggestion" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    householdId,
    listId,
    productId,
    freeText,
    quantity,
    unit,
    checked,
    source,
    isSuggestion,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'shopping_list_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<ShoppingListItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('household_id')) {
      context.handle(
        _householdIdMeta,
        householdId.isAcceptableOrUnknown(
          data['household_id']!,
          _householdIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_householdIdMeta);
    }
    if (data.containsKey('list_id')) {
      context.handle(
        _listIdMeta,
        listId.isAcceptableOrUnknown(data['list_id']!, _listIdMeta),
      );
    } else if (isInserting) {
      context.missing(_listIdMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(
        _productIdMeta,
        productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta),
      );
    }
    if (data.containsKey('free_text')) {
      context.handle(
        _freeTextMeta,
        freeText.isAcceptableOrUnknown(data['free_text']!, _freeTextMeta),
      );
    }
    if (data.containsKey('quantity')) {
      context.handle(
        _quantityMeta,
        quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta),
      );
    }
    if (data.containsKey('unit')) {
      context.handle(
        _unitMeta,
        unit.isAcceptableOrUnknown(data['unit']!, _unitMeta),
      );
    }
    if (data.containsKey('checked')) {
      context.handle(
        _checkedMeta,
        checked.isAcceptableOrUnknown(data['checked']!, _checkedMeta),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('is_suggestion')) {
      context.handle(
        _isSuggestionMeta,
        isSuggestion.isAcceptableOrUnknown(
          data['is_suggestion']!,
          _isSuggestionMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ShoppingListItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ShoppingListItem(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      householdId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}household_id'],
      )!,
      listId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}list_id'],
      )!,
      productId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}product_id'],
      ),
      freeText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}free_text'],
      ),
      quantity: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}quantity'],
      )!,
      unit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unit'],
      )!,
      checked: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}checked'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      isSuggestion: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_suggestion'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $ShoppingListItemsTable createAlias(String alias) {
    return $ShoppingListItemsTable(attachedDatabase, alias);
  }
}

class ShoppingListItem extends DataClass
    implements Insertable<ShoppingListItem> {
  final String id;
  final String householdId;
  final String listId;
  final String? productId;
  final String? freeText;
  final double quantity;

  /// 'piece' | 'kg' | 'l'
  final String unit;
  final bool checked;

  /// 'manual' | 'expiring' | 'depleted' | 'recurring' | 'scan'
  final String source;
  final bool isSuggestion;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const ShoppingListItem({
    required this.id,
    required this.householdId,
    required this.listId,
    this.productId,
    this.freeText,
    required this.quantity,
    required this.unit,
    required this.checked,
    required this.source,
    required this.isSuggestion,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['household_id'] = Variable<String>(householdId);
    map['list_id'] = Variable<String>(listId);
    if (!nullToAbsent || productId != null) {
      map['product_id'] = Variable<String>(productId);
    }
    if (!nullToAbsent || freeText != null) {
      map['free_text'] = Variable<String>(freeText);
    }
    map['quantity'] = Variable<double>(quantity);
    map['unit'] = Variable<String>(unit);
    map['checked'] = Variable<bool>(checked);
    map['source'] = Variable<String>(source);
    map['is_suggestion'] = Variable<bool>(isSuggestion);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  ShoppingListItemsCompanion toCompanion(bool nullToAbsent) {
    return ShoppingListItemsCompanion(
      id: Value(id),
      householdId: Value(householdId),
      listId: Value(listId),
      productId: productId == null && nullToAbsent
          ? const Value.absent()
          : Value(productId),
      freeText: freeText == null && nullToAbsent
          ? const Value.absent()
          : Value(freeText),
      quantity: Value(quantity),
      unit: Value(unit),
      checked: Value(checked),
      source: Value(source),
      isSuggestion: Value(isSuggestion),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory ShoppingListItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ShoppingListItem(
      id: serializer.fromJson<String>(json['id']),
      householdId: serializer.fromJson<String>(json['householdId']),
      listId: serializer.fromJson<String>(json['listId']),
      productId: serializer.fromJson<String?>(json['productId']),
      freeText: serializer.fromJson<String?>(json['freeText']),
      quantity: serializer.fromJson<double>(json['quantity']),
      unit: serializer.fromJson<String>(json['unit']),
      checked: serializer.fromJson<bool>(json['checked']),
      source: serializer.fromJson<String>(json['source']),
      isSuggestion: serializer.fromJson<bool>(json['isSuggestion']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'householdId': serializer.toJson<String>(householdId),
      'listId': serializer.toJson<String>(listId),
      'productId': serializer.toJson<String?>(productId),
      'freeText': serializer.toJson<String?>(freeText),
      'quantity': serializer.toJson<double>(quantity),
      'unit': serializer.toJson<String>(unit),
      'checked': serializer.toJson<bool>(checked),
      'source': serializer.toJson<String>(source),
      'isSuggestion': serializer.toJson<bool>(isSuggestion),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  ShoppingListItem copyWith({
    String? id,
    String? householdId,
    String? listId,
    Value<String?> productId = const Value.absent(),
    Value<String?> freeText = const Value.absent(),
    double? quantity,
    String? unit,
    bool? checked,
    String? source,
    bool? isSuggestion,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => ShoppingListItem(
    id: id ?? this.id,
    householdId: householdId ?? this.householdId,
    listId: listId ?? this.listId,
    productId: productId.present ? productId.value : this.productId,
    freeText: freeText.present ? freeText.value : this.freeText,
    quantity: quantity ?? this.quantity,
    unit: unit ?? this.unit,
    checked: checked ?? this.checked,
    source: source ?? this.source,
    isSuggestion: isSuggestion ?? this.isSuggestion,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  ShoppingListItem copyWithCompanion(ShoppingListItemsCompanion data) {
    return ShoppingListItem(
      id: data.id.present ? data.id.value : this.id,
      householdId: data.householdId.present
          ? data.householdId.value
          : this.householdId,
      listId: data.listId.present ? data.listId.value : this.listId,
      productId: data.productId.present ? data.productId.value : this.productId,
      freeText: data.freeText.present ? data.freeText.value : this.freeText,
      quantity: data.quantity.present ? data.quantity.value : this.quantity,
      unit: data.unit.present ? data.unit.value : this.unit,
      checked: data.checked.present ? data.checked.value : this.checked,
      source: data.source.present ? data.source.value : this.source,
      isSuggestion: data.isSuggestion.present
          ? data.isSuggestion.value
          : this.isSuggestion,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ShoppingListItem(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('listId: $listId, ')
          ..write('productId: $productId, ')
          ..write('freeText: $freeText, ')
          ..write('quantity: $quantity, ')
          ..write('unit: $unit, ')
          ..write('checked: $checked, ')
          ..write('source: $source, ')
          ..write('isSuggestion: $isSuggestion, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    householdId,
    listId,
    productId,
    freeText,
    quantity,
    unit,
    checked,
    source,
    isSuggestion,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ShoppingListItem &&
          other.id == this.id &&
          other.householdId == this.householdId &&
          other.listId == this.listId &&
          other.productId == this.productId &&
          other.freeText == this.freeText &&
          other.quantity == this.quantity &&
          other.unit == this.unit &&
          other.checked == this.checked &&
          other.source == this.source &&
          other.isSuggestion == this.isSuggestion &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class ShoppingListItemsCompanion extends UpdateCompanion<ShoppingListItem> {
  final Value<String> id;
  final Value<String> householdId;
  final Value<String> listId;
  final Value<String?> productId;
  final Value<String?> freeText;
  final Value<double> quantity;
  final Value<String> unit;
  final Value<bool> checked;
  final Value<String> source;
  final Value<bool> isSuggestion;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const ShoppingListItemsCompanion({
    this.id = const Value.absent(),
    this.householdId = const Value.absent(),
    this.listId = const Value.absent(),
    this.productId = const Value.absent(),
    this.freeText = const Value.absent(),
    this.quantity = const Value.absent(),
    this.unit = const Value.absent(),
    this.checked = const Value.absent(),
    this.source = const Value.absent(),
    this.isSuggestion = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ShoppingListItemsCompanion.insert({
    required String id,
    required String householdId,
    required String listId,
    this.productId = const Value.absent(),
    this.freeText = const Value.absent(),
    this.quantity = const Value.absent(),
    this.unit = const Value.absent(),
    this.checked = const Value.absent(),
    this.source = const Value.absent(),
    this.isSuggestion = const Value.absent(),
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       householdId = Value(householdId),
       listId = Value(listId),
       updatedAt = Value(updatedAt);
  static Insertable<ShoppingListItem> custom({
    Expression<String>? id,
    Expression<String>? householdId,
    Expression<String>? listId,
    Expression<String>? productId,
    Expression<String>? freeText,
    Expression<double>? quantity,
    Expression<String>? unit,
    Expression<bool>? checked,
    Expression<String>? source,
    Expression<bool>? isSuggestion,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (householdId != null) 'household_id': householdId,
      if (listId != null) 'list_id': listId,
      if (productId != null) 'product_id': productId,
      if (freeText != null) 'free_text': freeText,
      if (quantity != null) 'quantity': quantity,
      if (unit != null) 'unit': unit,
      if (checked != null) 'checked': checked,
      if (source != null) 'source': source,
      if (isSuggestion != null) 'is_suggestion': isSuggestion,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ShoppingListItemsCompanion copyWith({
    Value<String>? id,
    Value<String>? householdId,
    Value<String>? listId,
    Value<String?>? productId,
    Value<String?>? freeText,
    Value<double>? quantity,
    Value<String>? unit,
    Value<bool>? checked,
    Value<String>? source,
    Value<bool>? isSuggestion,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return ShoppingListItemsCompanion(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      listId: listId ?? this.listId,
      productId: productId ?? this.productId,
      freeText: freeText ?? this.freeText,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      checked: checked ?? this.checked,
      source: source ?? this.source,
      isSuggestion: isSuggestion ?? this.isSuggestion,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (householdId.present) {
      map['household_id'] = Variable<String>(householdId.value);
    }
    if (listId.present) {
      map['list_id'] = Variable<String>(listId.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (freeText.present) {
      map['free_text'] = Variable<String>(freeText.value);
    }
    if (quantity.present) {
      map['quantity'] = Variable<double>(quantity.value);
    }
    if (unit.present) {
      map['unit'] = Variable<String>(unit.value);
    }
    if (checked.present) {
      map['checked'] = Variable<bool>(checked.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (isSuggestion.present) {
      map['is_suggestion'] = Variable<bool>(isSuggestion.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ShoppingListItemsCompanion(')
          ..write('id: $id, ')
          ..write('householdId: $householdId, ')
          ..write('listId: $listId, ')
          ..write('productId: $productId, ')
          ..write('freeText: $freeText, ')
          ..write('quantity: $quantity, ')
          ..write('unit: $unit, ')
          ..write('checked: $checked, ')
          ..write('source: $source, ')
          ..write('isSuggestion: $isSuggestion, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxTable extends Outbox with TableInfo<$OutboxTable, OutboxEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _remoteTableMeta = const VerificationMeta(
    'remoteTable',
  );
  @override
  late final GeneratedColumn<String> remoteTable = GeneratedColumn<String>(
    'remote_table',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rowIdMeta = const VerificationMeta('rowId');
  @override
  late final GeneratedColumn<String> rowId = GeneratedColumn<String>(
    'row_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    remoteTable,
    rowId,
    payload,
    createdAt,
    attempts,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('remote_table')) {
      context.handle(
        _remoteTableMeta,
        remoteTable.isAcceptableOrUnknown(
          data['remote_table']!,
          _remoteTableMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_remoteTableMeta);
    }
    if (data.containsKey('row_id')) {
      context.handle(
        _rowIdMeta,
        rowId.isAcceptableOrUnknown(data['row_id']!, _rowIdMeta),
      );
    } else if (isInserting) {
      context.missing(_rowIdMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OutboxEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      remoteTable: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_table'],
      )!,
      rowId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}row_id'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
    );
  }

  @override
  $OutboxTable createAlias(String alias) {
    return $OutboxTable(attachedDatabase, alias);
  }
}

class OutboxEntry extends DataClass implements Insertable<OutboxEntry> {
  final int id;

  /// Name der Zieltabelle auf dem Server (z.B. 'categories').
  final String remoteTable;
  final String rowId;

  /// JSON der Zeile im Server-Format (snake_case).
  final String payload;
  final DateTime createdAt;
  final int attempts;
  final String? lastError;
  const OutboxEntry({
    required this.id,
    required this.remoteTable,
    required this.rowId,
    required this.payload,
    required this.createdAt,
    required this.attempts,
    this.lastError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['remote_table'] = Variable<String>(remoteTable);
    map['row_id'] = Variable<String>(rowId);
    map['payload'] = Variable<String>(payload);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  OutboxCompanion toCompanion(bool nullToAbsent) {
    return OutboxCompanion(
      id: Value(id),
      remoteTable: Value(remoteTable),
      rowId: Value(rowId),
      payload: Value(payload),
      createdAt: Value(createdAt),
      attempts: Value(attempts),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory OutboxEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxEntry(
      id: serializer.fromJson<int>(json['id']),
      remoteTable: serializer.fromJson<String>(json['remoteTable']),
      rowId: serializer.fromJson<String>(json['rowId']),
      payload: serializer.fromJson<String>(json['payload']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      attempts: serializer.fromJson<int>(json['attempts']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'remoteTable': serializer.toJson<String>(remoteTable),
      'rowId': serializer.toJson<String>(rowId),
      'payload': serializer.toJson<String>(payload),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'attempts': serializer.toJson<int>(attempts),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  OutboxEntry copyWith({
    int? id,
    String? remoteTable,
    String? rowId,
    String? payload,
    DateTime? createdAt,
    int? attempts,
    Value<String?> lastError = const Value.absent(),
  }) => OutboxEntry(
    id: id ?? this.id,
    remoteTable: remoteTable ?? this.remoteTable,
    rowId: rowId ?? this.rowId,
    payload: payload ?? this.payload,
    createdAt: createdAt ?? this.createdAt,
    attempts: attempts ?? this.attempts,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  OutboxEntry copyWithCompanion(OutboxCompanion data) {
    return OutboxEntry(
      id: data.id.present ? data.id.value : this.id,
      remoteTable: data.remoteTable.present
          ? data.remoteTable.value
          : this.remoteTable,
      rowId: data.rowId.present ? data.rowId.value : this.rowId,
      payload: data.payload.present ? data.payload.value : this.payload,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxEntry(')
          ..write('id: $id, ')
          ..write('remoteTable: $remoteTable, ')
          ..write('rowId: $rowId, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    remoteTable,
    rowId,
    payload,
    createdAt,
    attempts,
    lastError,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxEntry &&
          other.id == this.id &&
          other.remoteTable == this.remoteTable &&
          other.rowId == this.rowId &&
          other.payload == this.payload &&
          other.createdAt == this.createdAt &&
          other.attempts == this.attempts &&
          other.lastError == this.lastError);
}

class OutboxCompanion extends UpdateCompanion<OutboxEntry> {
  final Value<int> id;
  final Value<String> remoteTable;
  final Value<String> rowId;
  final Value<String> payload;
  final Value<DateTime> createdAt;
  final Value<int> attempts;
  final Value<String?> lastError;
  const OutboxCompanion({
    this.id = const Value.absent(),
    this.remoteTable = const Value.absent(),
    this.rowId = const Value.absent(),
    this.payload = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
  });
  OutboxCompanion.insert({
    this.id = const Value.absent(),
    required String remoteTable,
    required String rowId,
    required String payload,
    required DateTime createdAt,
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
  }) : remoteTable = Value(remoteTable),
       rowId = Value(rowId),
       payload = Value(payload),
       createdAt = Value(createdAt);
  static Insertable<OutboxEntry> custom({
    Expression<int>? id,
    Expression<String>? remoteTable,
    Expression<String>? rowId,
    Expression<String>? payload,
    Expression<DateTime>? createdAt,
    Expression<int>? attempts,
    Expression<String>? lastError,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (remoteTable != null) 'remote_table': remoteTable,
      if (rowId != null) 'row_id': rowId,
      if (payload != null) 'payload': payload,
      if (createdAt != null) 'created_at': createdAt,
      if (attempts != null) 'attempts': attempts,
      if (lastError != null) 'last_error': lastError,
    });
  }

  OutboxCompanion copyWith({
    Value<int>? id,
    Value<String>? remoteTable,
    Value<String>? rowId,
    Value<String>? payload,
    Value<DateTime>? createdAt,
    Value<int>? attempts,
    Value<String?>? lastError,
  }) {
    return OutboxCompanion(
      id: id ?? this.id,
      remoteTable: remoteTable ?? this.remoteTable,
      rowId: rowId ?? this.rowId,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (remoteTable.present) {
      map['remote_table'] = Variable<String>(remoteTable.value);
    }
    if (rowId.present) {
      map['row_id'] = Variable<String>(rowId.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxCompanion(')
          ..write('id: $id, ')
          ..write('remoteTable: $remoteTable, ')
          ..write('rowId: $rowId, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }
}

class $SyncStatesTable extends SyncStates
    with TableInfo<$SyncStatesTable, SyncStateEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _remoteTableMeta = const VerificationMeta(
    'remoteTable',
  );
  @override
  late final GeneratedColumn<String> remoteTable = GeneratedColumn<String>(
    'remote_table',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastPulledAtMeta = const VerificationMeta(
    'lastPulledAt',
  );
  @override
  late final GeneratedColumn<String> lastPulledAt = GeneratedColumn<String>(
    'last_pulled_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [remoteTable, lastPulledAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncStateEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('remote_table')) {
      context.handle(
        _remoteTableMeta,
        remoteTable.isAcceptableOrUnknown(
          data['remote_table']!,
          _remoteTableMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_remoteTableMeta);
    }
    if (data.containsKey('last_pulled_at')) {
      context.handle(
        _lastPulledAtMeta,
        lastPulledAt.isAcceptableOrUnknown(
          data['last_pulled_at']!,
          _lastPulledAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {remoteTable};
  @override
  SyncStateEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncStateEntry(
      remoteTable: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_table'],
      )!,
      lastPulledAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_pulled_at'],
      ),
    );
  }

  @override
  $SyncStatesTable createAlias(String alias) {
    return $SyncStatesTable(attachedDatabase, alias);
  }
}

class SyncStateEntry extends DataClass implements Insertable<SyncStateEntry> {
  final String remoteTable;
  final String? lastPulledAt;
  const SyncStateEntry({required this.remoteTable, this.lastPulledAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['remote_table'] = Variable<String>(remoteTable);
    if (!nullToAbsent || lastPulledAt != null) {
      map['last_pulled_at'] = Variable<String>(lastPulledAt);
    }
    return map;
  }

  SyncStatesCompanion toCompanion(bool nullToAbsent) {
    return SyncStatesCompanion(
      remoteTable: Value(remoteTable),
      lastPulledAt: lastPulledAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPulledAt),
    );
  }

  factory SyncStateEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncStateEntry(
      remoteTable: serializer.fromJson<String>(json['remoteTable']),
      lastPulledAt: serializer.fromJson<String?>(json['lastPulledAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'remoteTable': serializer.toJson<String>(remoteTable),
      'lastPulledAt': serializer.toJson<String?>(lastPulledAt),
    };
  }

  SyncStateEntry copyWith({
    String? remoteTable,
    Value<String?> lastPulledAt = const Value.absent(),
  }) => SyncStateEntry(
    remoteTable: remoteTable ?? this.remoteTable,
    lastPulledAt: lastPulledAt.present ? lastPulledAt.value : this.lastPulledAt,
  );
  SyncStateEntry copyWithCompanion(SyncStatesCompanion data) {
    return SyncStateEntry(
      remoteTable: data.remoteTable.present
          ? data.remoteTable.value
          : this.remoteTable,
      lastPulledAt: data.lastPulledAt.present
          ? data.lastPulledAt.value
          : this.lastPulledAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateEntry(')
          ..write('remoteTable: $remoteTable, ')
          ..write('lastPulledAt: $lastPulledAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(remoteTable, lastPulledAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncStateEntry &&
          other.remoteTable == this.remoteTable &&
          other.lastPulledAt == this.lastPulledAt);
}

class SyncStatesCompanion extends UpdateCompanion<SyncStateEntry> {
  final Value<String> remoteTable;
  final Value<String?> lastPulledAt;
  final Value<int> rowid;
  const SyncStatesCompanion({
    this.remoteTable = const Value.absent(),
    this.lastPulledAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncStatesCompanion.insert({
    required String remoteTable,
    this.lastPulledAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : remoteTable = Value(remoteTable);
  static Insertable<SyncStateEntry> custom({
    Expression<String>? remoteTable,
    Expression<String>? lastPulledAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (remoteTable != null) 'remote_table': remoteTable,
      if (lastPulledAt != null) 'last_pulled_at': lastPulledAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncStatesCompanion copyWith({
    Value<String>? remoteTable,
    Value<String?>? lastPulledAt,
    Value<int>? rowid,
  }) {
    return SyncStatesCompanion(
      remoteTable: remoteTable ?? this.remoteTable,
      lastPulledAt: lastPulledAt ?? this.lastPulledAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (remoteTable.present) {
      map['remote_table'] = Variable<String>(remoteTable.value);
    }
    if (lastPulledAt.present) {
      map['last_pulled_at'] = Variable<String>(lastPulledAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncStatesCompanion(')
          ..write('remoteTable: $remoteTable, ')
          ..write('lastPulledAt: $lastPulledAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $KeyValuesTable extends KeyValues
    with TableInfo<$KeyValuesTable, KeyValueEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KeyValuesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'key_values';
  @override
  VerificationContext validateIntegrity(
    Insertable<KeyValueEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  KeyValueEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KeyValueEntry(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $KeyValuesTable createAlias(String alias) {
    return $KeyValuesTable(attachedDatabase, alias);
  }
}

class KeyValueEntry extends DataClass implements Insertable<KeyValueEntry> {
  final String key;
  final String value;
  const KeyValueEntry({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  KeyValuesCompanion toCompanion(bool nullToAbsent) {
    return KeyValuesCompanion(key: Value(key), value: Value(value));
  }

  factory KeyValueEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KeyValueEntry(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  KeyValueEntry copyWith({String? key, String? value}) =>
      KeyValueEntry(key: key ?? this.key, value: value ?? this.value);
  KeyValueEntry copyWithCompanion(KeyValuesCompanion data) {
    return KeyValueEntry(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KeyValueEntry(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KeyValueEntry &&
          other.key == this.key &&
          other.value == this.value);
}

class KeyValuesCompanion extends UpdateCompanion<KeyValueEntry> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const KeyValuesCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KeyValuesCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<KeyValueEntry> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  KeyValuesCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return KeyValuesCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KeyValuesCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CategoriesTable categories = $CategoriesTable(this);
  late final $ProductsTable products = $ProductsTable(this);
  late final $ProductBarcodesTable productBarcodes = $ProductBarcodesTable(
    this,
  );
  late final $ProductAliasesTable productAliases = $ProductAliasesTable(this);
  late final $StoresTable stores = $StoresTable(this);
  late final $ReceiptsTable receipts = $ReceiptsTable(this);
  late final $ReceiptItemsTable receiptItems = $ReceiptItemsTable(this);
  late final $CategoryAliasesTable categoryAliases = $CategoryAliasesTable(
    this,
  );
  late final $ReceiptFilesTable receiptFiles = $ReceiptFilesTable(this);
  late final $InventoryItemsTable inventoryItems = $InventoryItemsTable(this);
  late final $InventoryMovementsTable inventoryMovements =
      $InventoryMovementsTable(this);
  late final $MealsTable meals = $MealsTable(this);
  late final $MealIngredientsTable mealIngredients = $MealIngredientsTable(
    this,
  );
  late final $BugReportsTable bugReports = $BugReportsTable(this);
  late final $ShoppingListsTable shoppingLists = $ShoppingListsTable(this);
  late final $ShoppingListItemsTable shoppingListItems =
      $ShoppingListItemsTable(this);
  late final $OutboxTable outbox = $OutboxTable(this);
  late final $SyncStatesTable syncStates = $SyncStatesTable(this);
  late final $KeyValuesTable keyValues = $KeyValuesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    categories,
    products,
    productBarcodes,
    productAliases,
    stores,
    receipts,
    receiptItems,
    categoryAliases,
    receiptFiles,
    inventoryItems,
    inventoryMovements,
    meals,
    mealIngredients,
    bugReports,
    shoppingLists,
    shoppingListItems,
    outbox,
    syncStates,
    keyValues,
  ];
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);
}

typedef $$CategoriesTableCreateCompanionBuilder = CategoriesCompanion Function({
  required String id,
  required String householdId,
  Value<String?> parentId,
  required String name,
  Value<String?> icon,
  Value<int> sortOrder,
  Value<bool> isStorable,
  required DateTime updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});
typedef $$CategoriesTableUpdateCompanionBuilder = CategoriesCompanion Function({
  Value<String> id,
  Value<String> householdId,
  Value<String?> parentId,
  Value<String> name,
  Value<String?> icon,
  Value<int> sortOrder,
  Value<bool> isStorable,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});

class $$CategoriesTableFilterComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isStorable => $composableBuilder(
    column: $table.isStorable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CategoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isStorable => $composableBuilder(
    column: $table.isStorable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CategoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get icon =>
      $composableBuilder(column: $table.icon, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<bool> get isStorable => $composableBuilder(
    column: $table.isStorable,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$CategoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CategoriesTable,
          Category,
          $$CategoriesTableFilterComposer,
          $$CategoriesTableOrderingComposer,
          $$CategoriesTableAnnotationComposer,
          $$CategoriesTableCreateCompanionBuilder,
          $$CategoriesTableUpdateCompanionBuilder,
          (Category, BaseReferences<_$AppDatabase, $CategoriesTable, Category>),
          Category,
          PrefetchHooks Function()
        > {
  $$CategoriesTableTableManager(_$AppDatabase db, $CategoriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> householdId = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> icon = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<bool> isStorable = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion(
                id: id,
                householdId: householdId,
                parentId: parentId,
                name: name,
                icon: icon,
                sortOrder: sortOrder,
                isStorable: isStorable,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String householdId,
                Value<String?> parentId = const Value.absent(),
                required String name,
                Value<String?> icon = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<bool> isStorable = const Value.absent(),
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion.insert(
                id: id,
                householdId: householdId,
                parentId: parentId,
                name: name,
                icon: icon,
                sortOrder: sortOrder,
                isStorable: isStorable,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CategoriesTable, Category>(table),
                  BaseReferences<_$AppDatabase, $CategoriesTable, Category>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CategoriesTable,
      Category,
      $$CategoriesTableFilterComposer,
      $$CategoriesTableOrderingComposer,
      $$CategoriesTableAnnotationComposer,
      $$CategoriesTableCreateCompanionBuilder,
      $$CategoriesTableUpdateCompanionBuilder,
      (Category, BaseReferences<_$AppDatabase, $CategoriesTable, Category>),
      Category,
      PrefetchHooks Function()
    >;
typedef $$ProductsTableCreateCompanionBuilder = ProductsCompanion Function({
  required String id,
  required String householdId,
  required String name,
  Value<String?> brand,
  Value<String?> categoryId,
  Value<String> baseUnit,
  Value<double?> packSize,
  Value<int?> sealedShelfLifeDays,
  Value<int?> openedShelfLifeDays,
  Value<String> defaultDateKind,
  Value<String> defaultLocation,
  Value<bool> restock,
  Value<String?> offCode,
  Value<String?> nutrientsPer100,
  Value<String?> nutrientsBasis,
  Value<String?> nutrientsSource,
  Value<double?> unitWeightG,
  required DateTime updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});
typedef $$ProductsTableUpdateCompanionBuilder = ProductsCompanion Function({
  Value<String> id,
  Value<String> householdId,
  Value<String> name,
  Value<String?> brand,
  Value<String?> categoryId,
  Value<String> baseUnit,
  Value<double?> packSize,
  Value<int?> sealedShelfLifeDays,
  Value<int?> openedShelfLifeDays,
  Value<String> defaultDateKind,
  Value<String> defaultLocation,
  Value<bool> restock,
  Value<String?> offCode,
  Value<String?> nutrientsPer100,
  Value<String?> nutrientsBasis,
  Value<String?> nutrientsSource,
  Value<double?> unitWeightG,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});

class $$ProductsTableFilterComposer
    extends Composer<_$AppDatabase, $ProductsTable> {
  $$ProductsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get brand => $composableBuilder(
    column: $table.brand,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baseUnit => $composableBuilder(
    column: $table.baseUnit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get packSize => $composableBuilder(
    column: $table.packSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sealedShelfLifeDays => $composableBuilder(
    column: $table.sealedShelfLifeDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get openedShelfLifeDays => $composableBuilder(
    column: $table.openedShelfLifeDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get defaultDateKind => $composableBuilder(
    column: $table.defaultDateKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get defaultLocation => $composableBuilder(
    column: $table.defaultLocation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get restock => $composableBuilder(
    column: $table.restock,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get offCode => $composableBuilder(
    column: $table.offCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nutrientsPer100 => $composableBuilder(
    column: $table.nutrientsPer100,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nutrientsBasis => $composableBuilder(
    column: $table.nutrientsBasis,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nutrientsSource => $composableBuilder(
    column: $table.nutrientsSource,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get unitWeightG => $composableBuilder(
    column: $table.unitWeightG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProductsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProductsTable> {
  $$ProductsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get brand => $composableBuilder(
    column: $table.brand,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseUnit => $composableBuilder(
    column: $table.baseUnit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get packSize => $composableBuilder(
    column: $table.packSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sealedShelfLifeDays => $composableBuilder(
    column: $table.sealedShelfLifeDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get openedShelfLifeDays => $composableBuilder(
    column: $table.openedShelfLifeDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get defaultDateKind => $composableBuilder(
    column: $table.defaultDateKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get defaultLocation => $composableBuilder(
    column: $table.defaultLocation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get restock => $composableBuilder(
    column: $table.restock,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get offCode => $composableBuilder(
    column: $table.offCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nutrientsPer100 => $composableBuilder(
    column: $table.nutrientsPer100,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nutrientsBasis => $composableBuilder(
    column: $table.nutrientsBasis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nutrientsSource => $composableBuilder(
    column: $table.nutrientsSource,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get unitWeightG => $composableBuilder(
    column: $table.unitWeightG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProductsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProductsTable> {
  $$ProductsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get brand =>
      $composableBuilder(column: $table.brand, builder: (column) => column);

  GeneratedColumn<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get baseUnit =>
      $composableBuilder(column: $table.baseUnit, builder: (column) => column);

  GeneratedColumn<double> get packSize =>
      $composableBuilder(column: $table.packSize, builder: (column) => column);

  GeneratedColumn<int> get sealedShelfLifeDays => $composableBuilder(
    column: $table.sealedShelfLifeDays,
    builder: (column) => column,
  );

  GeneratedColumn<int> get openedShelfLifeDays => $composableBuilder(
    column: $table.openedShelfLifeDays,
    builder: (column) => column,
  );

  GeneratedColumn<String> get defaultDateKind => $composableBuilder(
    column: $table.defaultDateKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get defaultLocation => $composableBuilder(
    column: $table.defaultLocation,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get restock =>
      $composableBuilder(column: $table.restock, builder: (column) => column);

  GeneratedColumn<String> get offCode =>
      $composableBuilder(column: $table.offCode, builder: (column) => column);

  GeneratedColumn<String> get nutrientsPer100 => $composableBuilder(
    column: $table.nutrientsPer100,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nutrientsBasis => $composableBuilder(
    column: $table.nutrientsBasis,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nutrientsSource => $composableBuilder(
    column: $table.nutrientsSource,
    builder: (column) => column,
  );

  GeneratedColumn<double> get unitWeightG => $composableBuilder(
    column: $table.unitWeightG,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$ProductsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProductsTable,
          Product,
          $$ProductsTableFilterComposer,
          $$ProductsTableOrderingComposer,
          $$ProductsTableAnnotationComposer,
          $$ProductsTableCreateCompanionBuilder,
          $$ProductsTableUpdateCompanionBuilder,
          (Product, BaseReferences<_$AppDatabase, $ProductsTable, Product>),
          Product,
          PrefetchHooks Function()
        > {
  $$ProductsTableTableManager(_$AppDatabase db, $ProductsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProductsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProductsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProductsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> householdId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> brand = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<String> baseUnit = const Value.absent(),
                Value<double?> packSize = const Value.absent(),
                Value<int?> sealedShelfLifeDays = const Value.absent(),
                Value<int?> openedShelfLifeDays = const Value.absent(),
                Value<String> defaultDateKind = const Value.absent(),
                Value<String> defaultLocation = const Value.absent(),
                Value<bool> restock = const Value.absent(),
                Value<String?> offCode = const Value.absent(),
                Value<String?> nutrientsPer100 = const Value.absent(),
                Value<String?> nutrientsBasis = const Value.absent(),
                Value<String?> nutrientsSource = const Value.absent(),
                Value<double?> unitWeightG = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProductsCompanion(
                id: id,
                householdId: householdId,
                name: name,
                brand: brand,
                categoryId: categoryId,
                baseUnit: baseUnit,
                packSize: packSize,
                sealedShelfLifeDays: sealedShelfLifeDays,
                openedShelfLifeDays: openedShelfLifeDays,
                defaultDateKind: defaultDateKind,
                defaultLocation: defaultLocation,
                restock: restock,
                offCode: offCode,
                nutrientsPer100: nutrientsPer100,
                nutrientsBasis: nutrientsBasis,
                nutrientsSource: nutrientsSource,
                unitWeightG: unitWeightG,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String householdId,
                required String name,
                Value<String?> brand = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<String> baseUnit = const Value.absent(),
                Value<double?> packSize = const Value.absent(),
                Value<int?> sealedShelfLifeDays = const Value.absent(),
                Value<int?> openedShelfLifeDays = const Value.absent(),
                Value<String> defaultDateKind = const Value.absent(),
                Value<String> defaultLocation = const Value.absent(),
                Value<bool> restock = const Value.absent(),
                Value<String?> offCode = const Value.absent(),
                Value<String?> nutrientsPer100 = const Value.absent(),
                Value<String?> nutrientsBasis = const Value.absent(),
                Value<String?> nutrientsSource = const Value.absent(),
                Value<double?> unitWeightG = const Value.absent(),
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProductsCompanion.insert(
                id: id,
                householdId: householdId,
                name: name,
                brand: brand,
                categoryId: categoryId,
                baseUnit: baseUnit,
                packSize: packSize,
                sealedShelfLifeDays: sealedShelfLifeDays,
                openedShelfLifeDays: openedShelfLifeDays,
                defaultDateKind: defaultDateKind,
                defaultLocation: defaultLocation,
                restock: restock,
                offCode: offCode,
                nutrientsPer100: nutrientsPer100,
                nutrientsBasis: nutrientsBasis,
                nutrientsSource: nutrientsSource,
                unitWeightG: unitWeightG,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ProductsTable, Product>(table),
                  BaseReferences<_$AppDatabase, $ProductsTable, Product>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProductsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProductsTable,
      Product,
      $$ProductsTableFilterComposer,
      $$ProductsTableOrderingComposer,
      $$ProductsTableAnnotationComposer,
      $$ProductsTableCreateCompanionBuilder,
      $$ProductsTableUpdateCompanionBuilder,
      (Product, BaseReferences<_$AppDatabase, $ProductsTable, Product>),
      Product,
      PrefetchHooks Function()
    >;
typedef $$ProductBarcodesTableCreateCompanionBuilder =
    ProductBarcodesCompanion Function({
      required String householdId,
      required String ean,
      required String productId,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ProductBarcodesTableUpdateCompanionBuilder =
    ProductBarcodesCompanion Function({
      Value<String> householdId,
      Value<String> ean,
      Value<String> productId,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$ProductBarcodesTableFilterComposer
    extends Composer<_$AppDatabase, $ProductBarcodesTable> {
  $$ProductBarcodesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ean => $composableBuilder(
    column: $table.ean,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProductBarcodesTableOrderingComposer
    extends Composer<_$AppDatabase, $ProductBarcodesTable> {
  $$ProductBarcodesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ean => $composableBuilder(
    column: $table.ean,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProductBarcodesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProductBarcodesTable> {
  $$ProductBarcodesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ean =>
      $composableBuilder(column: $table.ean, builder: (column) => column);

  GeneratedColumn<String> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ProductBarcodesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProductBarcodesTable,
          ProductBarcode,
          $$ProductBarcodesTableFilterComposer,
          $$ProductBarcodesTableOrderingComposer,
          $$ProductBarcodesTableAnnotationComposer,
          $$ProductBarcodesTableCreateCompanionBuilder,
          $$ProductBarcodesTableUpdateCompanionBuilder,
          (
            ProductBarcode,
            BaseReferences<
              _$AppDatabase,
              $ProductBarcodesTable,
              ProductBarcode
            >,
          ),
          ProductBarcode,
          PrefetchHooks Function()
        > {
  $$ProductBarcodesTableTableManager(
    _$AppDatabase db,
    $ProductBarcodesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProductBarcodesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProductBarcodesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProductBarcodesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> householdId = const Value.absent(),
                Value<String> ean = const Value.absent(),
                Value<String> productId = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProductBarcodesCompanion(
                householdId: householdId,
                ean: ean,
                productId: productId,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String householdId,
                required String ean,
                required String productId,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ProductBarcodesCompanion.insert(
                householdId: householdId,
                ean: ean,
                productId: productId,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ProductBarcodesTable, ProductBarcode>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ProductBarcodesTable,
                    ProductBarcode
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProductBarcodesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProductBarcodesTable,
      ProductBarcode,
      $$ProductBarcodesTableFilterComposer,
      $$ProductBarcodesTableOrderingComposer,
      $$ProductBarcodesTableAnnotationComposer,
      $$ProductBarcodesTableCreateCompanionBuilder,
      $$ProductBarcodesTableUpdateCompanionBuilder,
      (
        ProductBarcode,
        BaseReferences<_$AppDatabase, $ProductBarcodesTable, ProductBarcode>,
      ),
      ProductBarcode,
      PrefetchHooks Function()
    >;
typedef $$ProductAliasesTableCreateCompanionBuilder =
    ProductAliasesCompanion Function({
      required String id,
      required String householdId,
      Value<String?> storeId,
      required String aliasText,
      required String productId,
      Value<int> hits,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$ProductAliasesTableUpdateCompanionBuilder =
    ProductAliasesCompanion Function({
      Value<String> id,
      Value<String> householdId,
      Value<String?> storeId,
      Value<String> aliasText,
      Value<String> productId,
      Value<int> hits,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$ProductAliasesTableFilterComposer
    extends Composer<_$AppDatabase, $ProductAliasesTable> {
  $$ProductAliasesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get storeId => $composableBuilder(
    column: $table.storeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get aliasText => $composableBuilder(
    column: $table.aliasText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get hits => $composableBuilder(
    column: $table.hits,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProductAliasesTableOrderingComposer
    extends Composer<_$AppDatabase, $ProductAliasesTable> {
  $$ProductAliasesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get storeId => $composableBuilder(
    column: $table.storeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aliasText => $composableBuilder(
    column: $table.aliasText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get hits => $composableBuilder(
    column: $table.hits,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProductAliasesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProductAliasesTable> {
  $$ProductAliasesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get storeId =>
      $composableBuilder(column: $table.storeId, builder: (column) => column);

  GeneratedColumn<String> get aliasText =>
      $composableBuilder(column: $table.aliasText, builder: (column) => column);

  GeneratedColumn<String> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  GeneratedColumn<int> get hits =>
      $composableBuilder(column: $table.hits, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$ProductAliasesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProductAliasesTable,
          ProductAlias,
          $$ProductAliasesTableFilterComposer,
          $$ProductAliasesTableOrderingComposer,
          $$ProductAliasesTableAnnotationComposer,
          $$ProductAliasesTableCreateCompanionBuilder,
          $$ProductAliasesTableUpdateCompanionBuilder,
          (
            ProductAlias,
            BaseReferences<_$AppDatabase, $ProductAliasesTable, ProductAlias>,
          ),
          ProductAlias,
          PrefetchHooks Function()
        > {
  $$ProductAliasesTableTableManager(
    _$AppDatabase db,
    $ProductAliasesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProductAliasesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProductAliasesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProductAliasesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> householdId = const Value.absent(),
                Value<String?> storeId = const Value.absent(),
                Value<String> aliasText = const Value.absent(),
                Value<String> productId = const Value.absent(),
                Value<int> hits = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProductAliasesCompanion(
                id: id,
                householdId: householdId,
                storeId: storeId,
                aliasText: aliasText,
                productId: productId,
                hits: hits,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String householdId,
                Value<String?> storeId = const Value.absent(),
                required String aliasText,
                required String productId,
                Value<int> hits = const Value.absent(),
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProductAliasesCompanion.insert(
                id: id,
                householdId: householdId,
                storeId: storeId,
                aliasText: aliasText,
                productId: productId,
                hits: hits,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ProductAliasesTable, ProductAlias>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ProductAliasesTable,
                    ProductAlias
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProductAliasesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProductAliasesTable,
      ProductAlias,
      $$ProductAliasesTableFilterComposer,
      $$ProductAliasesTableOrderingComposer,
      $$ProductAliasesTableAnnotationComposer,
      $$ProductAliasesTableCreateCompanionBuilder,
      $$ProductAliasesTableUpdateCompanionBuilder,
      (
        ProductAlias,
        BaseReferences<_$AppDatabase, $ProductAliasesTable, ProductAlias>,
      ),
      ProductAlias,
      PrefetchHooks Function()
    >;
typedef $$StoresTableCreateCompanionBuilder = StoresCompanion Function({
  required String id,
  required String householdId,
  required String chain,
  Value<String?> branch,
  required DateTime updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});
typedef $$StoresTableUpdateCompanionBuilder = StoresCompanion Function({
  Value<String> id,
  Value<String> householdId,
  Value<String> chain,
  Value<String?> branch,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});

class $$StoresTableFilterComposer
    extends Composer<_$AppDatabase, $StoresTable> {
  $$StoresTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chain => $composableBuilder(
    column: $table.chain,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branch => $composableBuilder(
    column: $table.branch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StoresTableOrderingComposer
    extends Composer<_$AppDatabase, $StoresTable> {
  $$StoresTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chain => $composableBuilder(
    column: $table.chain,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branch => $composableBuilder(
    column: $table.branch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StoresTableAnnotationComposer
    extends Composer<_$AppDatabase, $StoresTable> {
  $$StoresTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get chain =>
      $composableBuilder(column: $table.chain, builder: (column) => column);

  GeneratedColumn<String> get branch =>
      $composableBuilder(column: $table.branch, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$StoresTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $StoresTable,
          Store,
          $$StoresTableFilterComposer,
          $$StoresTableOrderingComposer,
          $$StoresTableAnnotationComposer,
          $$StoresTableCreateCompanionBuilder,
          $$StoresTableUpdateCompanionBuilder,
          (Store, BaseReferences<_$AppDatabase, $StoresTable, Store>),
          Store,
          PrefetchHooks Function()
        > {
  $$StoresTableTableManager(_$AppDatabase db, $StoresTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StoresTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StoresTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StoresTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> householdId = const Value.absent(),
                Value<String> chain = const Value.absent(),
                Value<String?> branch = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StoresCompanion(
                id: id,
                householdId: householdId,
                chain: chain,
                branch: branch,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String householdId,
                required String chain,
                Value<String?> branch = const Value.absent(),
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StoresCompanion.insert(
                id: id,
                householdId: householdId,
                chain: chain,
                branch: branch,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$StoresTable, Store>(table),
                  BaseReferences<_$AppDatabase, $StoresTable, Store>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StoresTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $StoresTable,
      Store,
      $$StoresTableFilterComposer,
      $$StoresTableOrderingComposer,
      $$StoresTableAnnotationComposer,
      $$StoresTableCreateCompanionBuilder,
      $$StoresTableUpdateCompanionBuilder,
      (Store, BaseReferences<_$AppDatabase, $StoresTable, Store>),
      Store,
      PrefetchHooks Function()
    >;
typedef $$ReceiptsTableCreateCompanionBuilder = ReceiptsCompanion Function({
  required String id,
  required String householdId,
  Value<String?> storeId,
  required DateTime purchasedAt,
  required int totalCents,
  Value<String> status,
  Value<String> source,
  Value<String?> externalId,
  Value<double?> confidence,
  Value<bool> sumMismatch,
  required DateTime updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});
typedef $$ReceiptsTableUpdateCompanionBuilder = ReceiptsCompanion Function({
  Value<String> id,
  Value<String> householdId,
  Value<String?> storeId,
  Value<DateTime> purchasedAt,
  Value<int> totalCents,
  Value<String> status,
  Value<String> source,
  Value<String?> externalId,
  Value<double?> confidence,
  Value<bool> sumMismatch,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});

class $$ReceiptsTableFilterComposer
    extends Composer<_$AppDatabase, $ReceiptsTable> {
  $$ReceiptsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get storeId => $composableBuilder(
    column: $table.storeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get purchasedAt => $composableBuilder(
    column: $table.purchasedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalCents => $composableBuilder(
    column: $table.totalCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get externalId => $composableBuilder(
    column: $table.externalId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get sumMismatch => $composableBuilder(
    column: $table.sumMismatch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReceiptsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReceiptsTable> {
  $$ReceiptsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get storeId => $composableBuilder(
    column: $table.storeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get purchasedAt => $composableBuilder(
    column: $table.purchasedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalCents => $composableBuilder(
    column: $table.totalCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get externalId => $composableBuilder(
    column: $table.externalId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get sumMismatch => $composableBuilder(
    column: $table.sumMismatch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReceiptsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReceiptsTable> {
  $$ReceiptsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get storeId =>
      $composableBuilder(column: $table.storeId, builder: (column) => column);

  GeneratedColumn<DateTime> get purchasedAt => $composableBuilder(
    column: $table.purchasedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalCents => $composableBuilder(
    column: $table.totalCents,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get externalId => $composableBuilder(
    column: $table.externalId,
    builder: (column) => column,
  );

  GeneratedColumn<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get sumMismatch => $composableBuilder(
    column: $table.sumMismatch,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$ReceiptsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReceiptsTable,
          Receipt,
          $$ReceiptsTableFilterComposer,
          $$ReceiptsTableOrderingComposer,
          $$ReceiptsTableAnnotationComposer,
          $$ReceiptsTableCreateCompanionBuilder,
          $$ReceiptsTableUpdateCompanionBuilder,
          (Receipt, BaseReferences<_$AppDatabase, $ReceiptsTable, Receipt>),
          Receipt,
          PrefetchHooks Function()
        > {
  $$ReceiptsTableTableManager(_$AppDatabase db, $ReceiptsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReceiptsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReceiptsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReceiptsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> householdId = const Value.absent(),
                Value<String?> storeId = const Value.absent(),
                Value<DateTime> purchasedAt = const Value.absent(),
                Value<int> totalCents = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String?> externalId = const Value.absent(),
                Value<double?> confidence = const Value.absent(),
                Value<bool> sumMismatch = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReceiptsCompanion(
                id: id,
                householdId: householdId,
                storeId: storeId,
                purchasedAt: purchasedAt,
                totalCents: totalCents,
                status: status,
                source: source,
                externalId: externalId,
                confidence: confidence,
                sumMismatch: sumMismatch,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String householdId,
                Value<String?> storeId = const Value.absent(),
                required DateTime purchasedAt,
                required int totalCents,
                Value<String> status = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String?> externalId = const Value.absent(),
                Value<double?> confidence = const Value.absent(),
                Value<bool> sumMismatch = const Value.absent(),
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReceiptsCompanion.insert(
                id: id,
                householdId: householdId,
                storeId: storeId,
                purchasedAt: purchasedAt,
                totalCents: totalCents,
                status: status,
                source: source,
                externalId: externalId,
                confidence: confidence,
                sumMismatch: sumMismatch,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ReceiptsTable, Receipt>(table),
                  BaseReferences<_$AppDatabase, $ReceiptsTable, Receipt>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReceiptsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReceiptsTable,
      Receipt,
      $$ReceiptsTableFilterComposer,
      $$ReceiptsTableOrderingComposer,
      $$ReceiptsTableAnnotationComposer,
      $$ReceiptsTableCreateCompanionBuilder,
      $$ReceiptsTableUpdateCompanionBuilder,
      (Receipt, BaseReferences<_$AppDatabase, $ReceiptsTable, Receipt>),
      Receipt,
      PrefetchHooks Function()
    >;
typedef $$ReceiptItemsTableCreateCompanionBuilder =
    ReceiptItemsCompanion Function({
      required String id,
      required String householdId,
      required String receiptId,
      required int lineNo,
      Value<String> kind,
      required String rawText,
      Value<String?> productId,
      Value<String?> categoryId,
      Value<String?> brand,
      Value<double> quantity,
      Value<String> quantityUnit,
      Value<int?> unitPriceCents,
      required int lineTotalCents,
      Value<int?> unitPriceNormCents,
      Value<String?> taxCode,
      Value<bool> needsReview,
      Value<bool> excluded,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$ReceiptItemsTableUpdateCompanionBuilder =
    ReceiptItemsCompanion Function({
      Value<String> id,
      Value<String> householdId,
      Value<String> receiptId,
      Value<int> lineNo,
      Value<String> kind,
      Value<String> rawText,
      Value<String?> productId,
      Value<String?> categoryId,
      Value<String?> brand,
      Value<double> quantity,
      Value<String> quantityUnit,
      Value<int?> unitPriceCents,
      Value<int> lineTotalCents,
      Value<int?> unitPriceNormCents,
      Value<String?> taxCode,
      Value<bool> needsReview,
      Value<bool> excluded,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$ReceiptItemsTableFilterComposer
    extends Composer<_$AppDatabase, $ReceiptItemsTable> {
  $$ReceiptItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get receiptId => $composableBuilder(
    column: $table.receiptId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lineNo => $composableBuilder(
    column: $table.lineNo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawText => $composableBuilder(
    column: $table.rawText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get brand => $composableBuilder(
    column: $table.brand,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get quantityUnit => $composableBuilder(
    column: $table.quantityUnit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unitPriceCents => $composableBuilder(
    column: $table.unitPriceCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lineTotalCents => $composableBuilder(
    column: $table.lineTotalCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unitPriceNormCents => $composableBuilder(
    column: $table.unitPriceNormCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get taxCode => $composableBuilder(
    column: $table.taxCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get needsReview => $composableBuilder(
    column: $table.needsReview,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get excluded => $composableBuilder(
    column: $table.excluded,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReceiptItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReceiptItemsTable> {
  $$ReceiptItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get receiptId => $composableBuilder(
    column: $table.receiptId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lineNo => $composableBuilder(
    column: $table.lineNo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawText => $composableBuilder(
    column: $table.rawText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get brand => $composableBuilder(
    column: $table.brand,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get quantityUnit => $composableBuilder(
    column: $table.quantityUnit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unitPriceCents => $composableBuilder(
    column: $table.unitPriceCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lineTotalCents => $composableBuilder(
    column: $table.lineTotalCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unitPriceNormCents => $composableBuilder(
    column: $table.unitPriceNormCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get taxCode => $composableBuilder(
    column: $table.taxCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get needsReview => $composableBuilder(
    column: $table.needsReview,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get excluded => $composableBuilder(
    column: $table.excluded,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReceiptItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReceiptItemsTable> {
  $$ReceiptItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get receiptId =>
      $composableBuilder(column: $table.receiptId, builder: (column) => column);

  GeneratedColumn<int> get lineNo =>
      $composableBuilder(column: $table.lineNo, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get rawText =>
      $composableBuilder(column: $table.rawText, builder: (column) => column);

  GeneratedColumn<String> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  GeneratedColumn<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get brand =>
      $composableBuilder(column: $table.brand, builder: (column) => column);

  GeneratedColumn<double> get quantity =>
      $composableBuilder(column: $table.quantity, builder: (column) => column);

  GeneratedColumn<String> get quantityUnit => $composableBuilder(
    column: $table.quantityUnit,
    builder: (column) => column,
  );

  GeneratedColumn<int> get unitPriceCents => $composableBuilder(
    column: $table.unitPriceCents,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lineTotalCents => $composableBuilder(
    column: $table.lineTotalCents,
    builder: (column) => column,
  );

  GeneratedColumn<int> get unitPriceNormCents => $composableBuilder(
    column: $table.unitPriceNormCents,
    builder: (column) => column,
  );

  GeneratedColumn<String> get taxCode =>
      $composableBuilder(column: $table.taxCode, builder: (column) => column);

  GeneratedColumn<bool> get needsReview => $composableBuilder(
    column: $table.needsReview,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get excluded =>
      $composableBuilder(column: $table.excluded, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$ReceiptItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReceiptItemsTable,
          ReceiptItem,
          $$ReceiptItemsTableFilterComposer,
          $$ReceiptItemsTableOrderingComposer,
          $$ReceiptItemsTableAnnotationComposer,
          $$ReceiptItemsTableCreateCompanionBuilder,
          $$ReceiptItemsTableUpdateCompanionBuilder,
          (
            ReceiptItem,
            BaseReferences<_$AppDatabase, $ReceiptItemsTable, ReceiptItem>,
          ),
          ReceiptItem,
          PrefetchHooks Function()
        > {
  $$ReceiptItemsTableTableManager(_$AppDatabase db, $ReceiptItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReceiptItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReceiptItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReceiptItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> householdId = const Value.absent(),
                Value<String> receiptId = const Value.absent(),
                Value<int> lineNo = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> rawText = const Value.absent(),
                Value<String?> productId = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<String?> brand = const Value.absent(),
                Value<double> quantity = const Value.absent(),
                Value<String> quantityUnit = const Value.absent(),
                Value<int?> unitPriceCents = const Value.absent(),
                Value<int> lineTotalCents = const Value.absent(),
                Value<int?> unitPriceNormCents = const Value.absent(),
                Value<String?> taxCode = const Value.absent(),
                Value<bool> needsReview = const Value.absent(),
                Value<bool> excluded = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReceiptItemsCompanion(
                id: id,
                householdId: householdId,
                receiptId: receiptId,
                lineNo: lineNo,
                kind: kind,
                rawText: rawText,
                productId: productId,
                categoryId: categoryId,
                brand: brand,
                quantity: quantity,
                quantityUnit: quantityUnit,
                unitPriceCents: unitPriceCents,
                lineTotalCents: lineTotalCents,
                unitPriceNormCents: unitPriceNormCents,
                taxCode: taxCode,
                needsReview: needsReview,
                excluded: excluded,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String householdId,
                required String receiptId,
                required int lineNo,
                Value<String> kind = const Value.absent(),
                required String rawText,
                Value<String?> productId = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<String?> brand = const Value.absent(),
                Value<double> quantity = const Value.absent(),
                Value<String> quantityUnit = const Value.absent(),
                Value<int?> unitPriceCents = const Value.absent(),
                required int lineTotalCents,
                Value<int?> unitPriceNormCents = const Value.absent(),
                Value<String?> taxCode = const Value.absent(),
                Value<bool> needsReview = const Value.absent(),
                Value<bool> excluded = const Value.absent(),
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReceiptItemsCompanion.insert(
                id: id,
                householdId: householdId,
                receiptId: receiptId,
                lineNo: lineNo,
                kind: kind,
                rawText: rawText,
                productId: productId,
                categoryId: categoryId,
                brand: brand,
                quantity: quantity,
                quantityUnit: quantityUnit,
                unitPriceCents: unitPriceCents,
                lineTotalCents: lineTotalCents,
                unitPriceNormCents: unitPriceNormCents,
                taxCode: taxCode,
                needsReview: needsReview,
                excluded: excluded,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ReceiptItemsTable, ReceiptItem>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ReceiptItemsTable,
                    ReceiptItem
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReceiptItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReceiptItemsTable,
      ReceiptItem,
      $$ReceiptItemsTableFilterComposer,
      $$ReceiptItemsTableOrderingComposer,
      $$ReceiptItemsTableAnnotationComposer,
      $$ReceiptItemsTableCreateCompanionBuilder,
      $$ReceiptItemsTableUpdateCompanionBuilder,
      (
        ReceiptItem,
        BaseReferences<_$AppDatabase, $ReceiptItemsTable, ReceiptItem>,
      ),
      ReceiptItem,
      PrefetchHooks Function()
    >;
typedef $$CategoryAliasesTableCreateCompanionBuilder =
    CategoryAliasesCompanion Function({
      required String id,
      required String householdId,
      required String aliasText,
      required String categoryId,
      Value<int> hits,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$CategoryAliasesTableUpdateCompanionBuilder =
    CategoryAliasesCompanion Function({
      Value<String> id,
      Value<String> householdId,
      Value<String> aliasText,
      Value<String> categoryId,
      Value<int> hits,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$CategoryAliasesTableFilterComposer
    extends Composer<_$AppDatabase, $CategoryAliasesTable> {
  $$CategoryAliasesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get aliasText => $composableBuilder(
    column: $table.aliasText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get hits => $composableBuilder(
    column: $table.hits,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CategoryAliasesTableOrderingComposer
    extends Composer<_$AppDatabase, $CategoryAliasesTable> {
  $$CategoryAliasesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aliasText => $composableBuilder(
    column: $table.aliasText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get hits => $composableBuilder(
    column: $table.hits,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CategoryAliasesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CategoryAliasesTable> {
  $$CategoryAliasesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get aliasText =>
      $composableBuilder(column: $table.aliasText, builder: (column) => column);

  GeneratedColumn<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get hits =>
      $composableBuilder(column: $table.hits, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$CategoryAliasesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CategoryAliasesTable,
          CategoryAlias,
          $$CategoryAliasesTableFilterComposer,
          $$CategoryAliasesTableOrderingComposer,
          $$CategoryAliasesTableAnnotationComposer,
          $$CategoryAliasesTableCreateCompanionBuilder,
          $$CategoryAliasesTableUpdateCompanionBuilder,
          (
            CategoryAlias,
            BaseReferences<_$AppDatabase, $CategoryAliasesTable, CategoryAlias>,
          ),
          CategoryAlias,
          PrefetchHooks Function()
        > {
  $$CategoryAliasesTableTableManager(
    _$AppDatabase db,
    $CategoryAliasesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CategoryAliasesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CategoryAliasesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CategoryAliasesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> householdId = const Value.absent(),
                Value<String> aliasText = const Value.absent(),
                Value<String> categoryId = const Value.absent(),
                Value<int> hits = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CategoryAliasesCompanion(
                id: id,
                householdId: householdId,
                aliasText: aliasText,
                categoryId: categoryId,
                hits: hits,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String householdId,
                required String aliasText,
                required String categoryId,
                Value<int> hits = const Value.absent(),
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CategoryAliasesCompanion.insert(
                id: id,
                householdId: householdId,
                aliasText: aliasText,
                categoryId: categoryId,
                hits: hits,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CategoryAliasesTable, CategoryAlias>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CategoryAliasesTable,
                    CategoryAlias
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CategoryAliasesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CategoryAliasesTable,
      CategoryAlias,
      $$CategoryAliasesTableFilterComposer,
      $$CategoryAliasesTableOrderingComposer,
      $$CategoryAliasesTableAnnotationComposer,
      $$CategoryAliasesTableCreateCompanionBuilder,
      $$CategoryAliasesTableUpdateCompanionBuilder,
      (
        CategoryAlias,
        BaseReferences<_$AppDatabase, $CategoryAliasesTable, CategoryAlias>,
      ),
      CategoryAlias,
      PrefetchHooks Function()
    >;
typedef $$ReceiptFilesTableCreateCompanionBuilder =
    ReceiptFilesCompanion Function({
      required String id,
      required String householdId,
      required String receiptId,
      required String kind,
      Value<int> pageNo,
      required String storagePath,
      Value<int?> sizeBytes,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$ReceiptFilesTableUpdateCompanionBuilder =
    ReceiptFilesCompanion Function({
      Value<String> id,
      Value<String> householdId,
      Value<String> receiptId,
      Value<String> kind,
      Value<int> pageNo,
      Value<String> storagePath,
      Value<int?> sizeBytes,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$ReceiptFilesTableFilterComposer
    extends Composer<_$AppDatabase, $ReceiptFilesTable> {
  $$ReceiptFilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get receiptId => $composableBuilder(
    column: $table.receiptId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pageNo => $composableBuilder(
    column: $table.pageNo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get storagePath => $composableBuilder(
    column: $table.storagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReceiptFilesTableOrderingComposer
    extends Composer<_$AppDatabase, $ReceiptFilesTable> {
  $$ReceiptFilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get receiptId => $composableBuilder(
    column: $table.receiptId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pageNo => $composableBuilder(
    column: $table.pageNo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get storagePath => $composableBuilder(
    column: $table.storagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReceiptFilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReceiptFilesTable> {
  $$ReceiptFilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get receiptId =>
      $composableBuilder(column: $table.receiptId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get pageNo =>
      $composableBuilder(column: $table.pageNo, builder: (column) => column);

  GeneratedColumn<String> get storagePath => $composableBuilder(
    column: $table.storagePath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$ReceiptFilesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReceiptFilesTable,
          ReceiptFile,
          $$ReceiptFilesTableFilterComposer,
          $$ReceiptFilesTableOrderingComposer,
          $$ReceiptFilesTableAnnotationComposer,
          $$ReceiptFilesTableCreateCompanionBuilder,
          $$ReceiptFilesTableUpdateCompanionBuilder,
          (
            ReceiptFile,
            BaseReferences<_$AppDatabase, $ReceiptFilesTable, ReceiptFile>,
          ),
          ReceiptFile,
          PrefetchHooks Function()
        > {
  $$ReceiptFilesTableTableManager(_$AppDatabase db, $ReceiptFilesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReceiptFilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReceiptFilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReceiptFilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> householdId = const Value.absent(),
                Value<String> receiptId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<int> pageNo = const Value.absent(),
                Value<String> storagePath = const Value.absent(),
                Value<int?> sizeBytes = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReceiptFilesCompanion(
                id: id,
                householdId: householdId,
                receiptId: receiptId,
                kind: kind,
                pageNo: pageNo,
                storagePath: storagePath,
                sizeBytes: sizeBytes,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String householdId,
                required String receiptId,
                required String kind,
                Value<int> pageNo = const Value.absent(),
                required String storagePath,
                Value<int?> sizeBytes = const Value.absent(),
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReceiptFilesCompanion.insert(
                id: id,
                householdId: householdId,
                receiptId: receiptId,
                kind: kind,
                pageNo: pageNo,
                storagePath: storagePath,
                sizeBytes: sizeBytes,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ReceiptFilesTable, ReceiptFile>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ReceiptFilesTable,
                    ReceiptFile
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReceiptFilesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReceiptFilesTable,
      ReceiptFile,
      $$ReceiptFilesTableFilterComposer,
      $$ReceiptFilesTableOrderingComposer,
      $$ReceiptFilesTableAnnotationComposer,
      $$ReceiptFilesTableCreateCompanionBuilder,
      $$ReceiptFilesTableUpdateCompanionBuilder,
      (
        ReceiptFile,
        BaseReferences<_$AppDatabase, $ReceiptFilesTable, ReceiptFile>,
      ),
      ReceiptFile,
      PrefetchHooks Function()
    >;
typedef $$InventoryItemsTableCreateCompanionBuilder =
    InventoryItemsCompanion Function({
      required String id,
      required String householdId,
      required String productId,
      Value<String?> receiptItemId,
      Value<String?> ean,
      Value<double> quantity,
      Value<String> unit,
      Value<String> location,
      Value<DateTime?> purchasedOn,
      Value<DateTime?> bestBefore,
      Value<String> dateKind,
      Value<DateTime?> openedOn,
      Value<int?> openShelfLifeDays,
      Value<String> status,
      Value<bool> isSuggestion,
      Value<DateTime?> closedAt,
      Value<DateTime?> expiresOn,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$InventoryItemsTableUpdateCompanionBuilder =
    InventoryItemsCompanion Function({
      Value<String> id,
      Value<String> householdId,
      Value<String> productId,
      Value<String?> receiptItemId,
      Value<String?> ean,
      Value<double> quantity,
      Value<String> unit,
      Value<String> location,
      Value<DateTime?> purchasedOn,
      Value<DateTime?> bestBefore,
      Value<String> dateKind,
      Value<DateTime?> openedOn,
      Value<int?> openShelfLifeDays,
      Value<String> status,
      Value<bool> isSuggestion,
      Value<DateTime?> closedAt,
      Value<DateTime?> expiresOn,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$InventoryItemsTableFilterComposer
    extends Composer<_$AppDatabase, $InventoryItemsTable> {
  $$InventoryItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get receiptItemId => $composableBuilder(
    column: $table.receiptItemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ean => $composableBuilder(
    column: $table.ean,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get purchasedOn => $composableBuilder(
    column: $table.purchasedOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get bestBefore => $composableBuilder(
    column: $table.bestBefore,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dateKind => $composableBuilder(
    column: $table.dateKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get openedOn => $composableBuilder(
    column: $table.openedOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get openShelfLifeDays => $composableBuilder(
    column: $table.openShelfLifeDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isSuggestion => $composableBuilder(
    column: $table.isSuggestion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get closedAt => $composableBuilder(
    column: $table.closedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get expiresOn => $composableBuilder(
    column: $table.expiresOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$InventoryItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $InventoryItemsTable> {
  $$InventoryItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get receiptItemId => $composableBuilder(
    column: $table.receiptItemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ean => $composableBuilder(
    column: $table.ean,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get purchasedOn => $composableBuilder(
    column: $table.purchasedOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get bestBefore => $composableBuilder(
    column: $table.bestBefore,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dateKind => $composableBuilder(
    column: $table.dateKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get openedOn => $composableBuilder(
    column: $table.openedOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get openShelfLifeDays => $composableBuilder(
    column: $table.openShelfLifeDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isSuggestion => $composableBuilder(
    column: $table.isSuggestion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get closedAt => $composableBuilder(
    column: $table.closedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get expiresOn => $composableBuilder(
    column: $table.expiresOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$InventoryItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $InventoryItemsTable> {
  $$InventoryItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  GeneratedColumn<String> get receiptItemId => $composableBuilder(
    column: $table.receiptItemId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ean =>
      $composableBuilder(column: $table.ean, builder: (column) => column);

  GeneratedColumn<double> get quantity =>
      $composableBuilder(column: $table.quantity, builder: (column) => column);

  GeneratedColumn<String> get unit =>
      $composableBuilder(column: $table.unit, builder: (column) => column);

  GeneratedColumn<String> get location =>
      $composableBuilder(column: $table.location, builder: (column) => column);

  GeneratedColumn<DateTime> get purchasedOn => $composableBuilder(
    column: $table.purchasedOn,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get bestBefore => $composableBuilder(
    column: $table.bestBefore,
    builder: (column) => column,
  );

  GeneratedColumn<String> get dateKind =>
      $composableBuilder(column: $table.dateKind, builder: (column) => column);

  GeneratedColumn<DateTime> get openedOn =>
      $composableBuilder(column: $table.openedOn, builder: (column) => column);

  GeneratedColumn<int> get openShelfLifeDays => $composableBuilder(
    column: $table.openShelfLifeDays,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<bool> get isSuggestion => $composableBuilder(
    column: $table.isSuggestion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get closedAt =>
      $composableBuilder(column: $table.closedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get expiresOn =>
      $composableBuilder(column: $table.expiresOn, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$InventoryItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $InventoryItemsTable,
          InventoryItem,
          $$InventoryItemsTableFilterComposer,
          $$InventoryItemsTableOrderingComposer,
          $$InventoryItemsTableAnnotationComposer,
          $$InventoryItemsTableCreateCompanionBuilder,
          $$InventoryItemsTableUpdateCompanionBuilder,
          (
            InventoryItem,
            BaseReferences<_$AppDatabase, $InventoryItemsTable, InventoryItem>,
          ),
          InventoryItem,
          PrefetchHooks Function()
        > {
  $$InventoryItemsTableTableManager(
    _$AppDatabase db,
    $InventoryItemsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InventoryItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$InventoryItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$InventoryItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> householdId = const Value.absent(),
                Value<String> productId = const Value.absent(),
                Value<String?> receiptItemId = const Value.absent(),
                Value<String?> ean = const Value.absent(),
                Value<double> quantity = const Value.absent(),
                Value<String> unit = const Value.absent(),
                Value<String> location = const Value.absent(),
                Value<DateTime?> purchasedOn = const Value.absent(),
                Value<DateTime?> bestBefore = const Value.absent(),
                Value<String> dateKind = const Value.absent(),
                Value<DateTime?> openedOn = const Value.absent(),
                Value<int?> openShelfLifeDays = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<bool> isSuggestion = const Value.absent(),
                Value<DateTime?> closedAt = const Value.absent(),
                Value<DateTime?> expiresOn = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InventoryItemsCompanion(
                id: id,
                householdId: householdId,
                productId: productId,
                receiptItemId: receiptItemId,
                ean: ean,
                quantity: quantity,
                unit: unit,
                location: location,
                purchasedOn: purchasedOn,
                bestBefore: bestBefore,
                dateKind: dateKind,
                openedOn: openedOn,
                openShelfLifeDays: openShelfLifeDays,
                status: status,
                isSuggestion: isSuggestion,
                closedAt: closedAt,
                expiresOn: expiresOn,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String householdId,
                required String productId,
                Value<String?> receiptItemId = const Value.absent(),
                Value<String?> ean = const Value.absent(),
                Value<double> quantity = const Value.absent(),
                Value<String> unit = const Value.absent(),
                Value<String> location = const Value.absent(),
                Value<DateTime?> purchasedOn = const Value.absent(),
                Value<DateTime?> bestBefore = const Value.absent(),
                Value<String> dateKind = const Value.absent(),
                Value<DateTime?> openedOn = const Value.absent(),
                Value<int?> openShelfLifeDays = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<bool> isSuggestion = const Value.absent(),
                Value<DateTime?> closedAt = const Value.absent(),
                Value<DateTime?> expiresOn = const Value.absent(),
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InventoryItemsCompanion.insert(
                id: id,
                householdId: householdId,
                productId: productId,
                receiptItemId: receiptItemId,
                ean: ean,
                quantity: quantity,
                unit: unit,
                location: location,
                purchasedOn: purchasedOn,
                bestBefore: bestBefore,
                dateKind: dateKind,
                openedOn: openedOn,
                openShelfLifeDays: openShelfLifeDays,
                status: status,
                isSuggestion: isSuggestion,
                closedAt: closedAt,
                expiresOn: expiresOn,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$InventoryItemsTable, InventoryItem>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $InventoryItemsTable,
                    InventoryItem
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$InventoryItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $InventoryItemsTable,
      InventoryItem,
      $$InventoryItemsTableFilterComposer,
      $$InventoryItemsTableOrderingComposer,
      $$InventoryItemsTableAnnotationComposer,
      $$InventoryItemsTableCreateCompanionBuilder,
      $$InventoryItemsTableUpdateCompanionBuilder,
      (
        InventoryItem,
        BaseReferences<_$AppDatabase, $InventoryItemsTable, InventoryItem>,
      ),
      InventoryItem,
      PrefetchHooks Function()
    >;
typedef $$InventoryMovementsTableCreateCompanionBuilder =
    InventoryMovementsCompanion Function({
      required String id,
      required String householdId,
      Value<String?> inventoryItemId,
      required String productId,
      required DateTime occurredAt,
      required String type,
      required double quantityDelta,
      required String unit,
      Value<String?> note,
      Value<String?> mealId,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$InventoryMovementsTableUpdateCompanionBuilder =
    InventoryMovementsCompanion Function({
      Value<String> id,
      Value<String> householdId,
      Value<String?> inventoryItemId,
      Value<String> productId,
      Value<DateTime> occurredAt,
      Value<String> type,
      Value<double> quantityDelta,
      Value<String> unit,
      Value<String?> note,
      Value<String?> mealId,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$InventoryMovementsTableFilterComposer
    extends Composer<_$AppDatabase, $InventoryMovementsTable> {
  $$InventoryMovementsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get inventoryItemId => $composableBuilder(
    column: $table.inventoryItemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get quantityDelta => $composableBuilder(
    column: $table.quantityDelta,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mealId => $composableBuilder(
    column: $table.mealId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$InventoryMovementsTableOrderingComposer
    extends Composer<_$AppDatabase, $InventoryMovementsTable> {
  $$InventoryMovementsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get inventoryItemId => $composableBuilder(
    column: $table.inventoryItemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get quantityDelta => $composableBuilder(
    column: $table.quantityDelta,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mealId => $composableBuilder(
    column: $table.mealId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$InventoryMovementsTableAnnotationComposer
    extends Composer<_$AppDatabase, $InventoryMovementsTable> {
  $$InventoryMovementsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get inventoryItemId => $composableBuilder(
    column: $table.inventoryItemId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  GeneratedColumn<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<double> get quantityDelta => $composableBuilder(
    column: $table.quantityDelta,
    builder: (column) => column,
  );

  GeneratedColumn<String> get unit =>
      $composableBuilder(column: $table.unit, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get mealId =>
      $composableBuilder(column: $table.mealId, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$InventoryMovementsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $InventoryMovementsTable,
          InventoryMovement,
          $$InventoryMovementsTableFilterComposer,
          $$InventoryMovementsTableOrderingComposer,
          $$InventoryMovementsTableAnnotationComposer,
          $$InventoryMovementsTableCreateCompanionBuilder,
          $$InventoryMovementsTableUpdateCompanionBuilder,
          (
            InventoryMovement,
            BaseReferences<
              _$AppDatabase,
              $InventoryMovementsTable,
              InventoryMovement
            >,
          ),
          InventoryMovement,
          PrefetchHooks Function()
        > {
  $$InventoryMovementsTableTableManager(
    _$AppDatabase db,
    $InventoryMovementsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InventoryMovementsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$InventoryMovementsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$InventoryMovementsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> householdId = const Value.absent(),
                Value<String?> inventoryItemId = const Value.absent(),
                Value<String> productId = const Value.absent(),
                Value<DateTime> occurredAt = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<double> quantityDelta = const Value.absent(),
                Value<String> unit = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<String?> mealId = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InventoryMovementsCompanion(
                id: id,
                householdId: householdId,
                inventoryItemId: inventoryItemId,
                productId: productId,
                occurredAt: occurredAt,
                type: type,
                quantityDelta: quantityDelta,
                unit: unit,
                note: note,
                mealId: mealId,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String householdId,
                Value<String?> inventoryItemId = const Value.absent(),
                required String productId,
                required DateTime occurredAt,
                required String type,
                required double quantityDelta,
                required String unit,
                Value<String?> note = const Value.absent(),
                Value<String?> mealId = const Value.absent(),
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InventoryMovementsCompanion.insert(
                id: id,
                householdId: householdId,
                inventoryItemId: inventoryItemId,
                productId: productId,
                occurredAt: occurredAt,
                type: type,
                quantityDelta: quantityDelta,
                unit: unit,
                note: note,
                mealId: mealId,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$InventoryMovementsTable, InventoryMovement>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $InventoryMovementsTable,
                    InventoryMovement
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$InventoryMovementsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $InventoryMovementsTable,
      InventoryMovement,
      $$InventoryMovementsTableFilterComposer,
      $$InventoryMovementsTableOrderingComposer,
      $$InventoryMovementsTableAnnotationComposer,
      $$InventoryMovementsTableCreateCompanionBuilder,
      $$InventoryMovementsTableUpdateCompanionBuilder,
      (
        InventoryMovement,
        BaseReferences<
          _$AppDatabase,
          $InventoryMovementsTable,
          InventoryMovement
        >,
      ),
      InventoryMovement,
      PrefetchHooks Function()
    >;
typedef $$MealsTableCreateCompanionBuilder = MealsCompanion Function({
  required String id,
  required String householdId,
  required DateTime eatenAt,
  Value<String> mealType,
  required String title,
  Value<String?> note,
  Value<String?> photoPath,
  Value<String?> recipeId,
  Value<double> servingsEaten,
  Value<double> servingsMade,
  Value<String> source,
  Value<bool> isEstimate,
  required DateTime updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});
typedef $$MealsTableUpdateCompanionBuilder = MealsCompanion Function({
  Value<String> id,
  Value<String> householdId,
  Value<DateTime> eatenAt,
  Value<String> mealType,
  Value<String> title,
  Value<String?> note,
  Value<String?> photoPath,
  Value<String?> recipeId,
  Value<double> servingsEaten,
  Value<double> servingsMade,
  Value<String> source,
  Value<bool> isEstimate,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});

class $$MealsTableFilterComposer extends Composer<_$AppDatabase, $MealsTable> {
  $$MealsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get eatenAt => $composableBuilder(
    column: $table.eatenAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mealType => $composableBuilder(
    column: $table.mealType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get photoPath => $composableBuilder(
    column: $table.photoPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recipeId => $composableBuilder(
    column: $table.recipeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get servingsEaten => $composableBuilder(
    column: $table.servingsEaten,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get servingsMade => $composableBuilder(
    column: $table.servingsMade,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isEstimate => $composableBuilder(
    column: $table.isEstimate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MealsTableOrderingComposer
    extends Composer<_$AppDatabase, $MealsTable> {
  $$MealsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get eatenAt => $composableBuilder(
    column: $table.eatenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mealType => $composableBuilder(
    column: $table.mealType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get photoPath => $composableBuilder(
    column: $table.photoPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recipeId => $composableBuilder(
    column: $table.recipeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get servingsEaten => $composableBuilder(
    column: $table.servingsEaten,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get servingsMade => $composableBuilder(
    column: $table.servingsMade,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isEstimate => $composableBuilder(
    column: $table.isEstimate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MealsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MealsTable> {
  $$MealsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get eatenAt =>
      $composableBuilder(column: $table.eatenAt, builder: (column) => column);

  GeneratedColumn<String> get mealType =>
      $composableBuilder(column: $table.mealType, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get photoPath =>
      $composableBuilder(column: $table.photoPath, builder: (column) => column);

  GeneratedColumn<String> get recipeId =>
      $composableBuilder(column: $table.recipeId, builder: (column) => column);

  GeneratedColumn<double> get servingsEaten => $composableBuilder(
    column: $table.servingsEaten,
    builder: (column) => column,
  );

  GeneratedColumn<double> get servingsMade => $composableBuilder(
    column: $table.servingsMade,
    builder: (column) => column,
  );

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<bool> get isEstimate => $composableBuilder(
    column: $table.isEstimate,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$MealsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MealsTable,
          Meal,
          $$MealsTableFilterComposer,
          $$MealsTableOrderingComposer,
          $$MealsTableAnnotationComposer,
          $$MealsTableCreateCompanionBuilder,
          $$MealsTableUpdateCompanionBuilder,
          (Meal, BaseReferences<_$AppDatabase, $MealsTable, Meal>),
          Meal,
          PrefetchHooks Function()
        > {
  $$MealsTableTableManager(_$AppDatabase db, $MealsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MealsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MealsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MealsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> householdId = const Value.absent(),
                Value<DateTime> eatenAt = const Value.absent(),
                Value<String> mealType = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<String?> photoPath = const Value.absent(),
                Value<String?> recipeId = const Value.absent(),
                Value<double> servingsEaten = const Value.absent(),
                Value<double> servingsMade = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<bool> isEstimate = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MealsCompanion(
                id: id,
                householdId: householdId,
                eatenAt: eatenAt,
                mealType: mealType,
                title: title,
                note: note,
                photoPath: photoPath,
                recipeId: recipeId,
                servingsEaten: servingsEaten,
                servingsMade: servingsMade,
                source: source,
                isEstimate: isEstimate,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String householdId,
                required DateTime eatenAt,
                Value<String> mealType = const Value.absent(),
                required String title,
                Value<String?> note = const Value.absent(),
                Value<String?> photoPath = const Value.absent(),
                Value<String?> recipeId = const Value.absent(),
                Value<double> servingsEaten = const Value.absent(),
                Value<double> servingsMade = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<bool> isEstimate = const Value.absent(),
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MealsCompanion.insert(
                id: id,
                householdId: householdId,
                eatenAt: eatenAt,
                mealType: mealType,
                title: title,
                note: note,
                photoPath: photoPath,
                recipeId: recipeId,
                servingsEaten: servingsEaten,
                servingsMade: servingsMade,
                source: source,
                isEstimate: isEstimate,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MealsTable, Meal>(table),
                  BaseReferences<_$AppDatabase, $MealsTable, Meal>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MealsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MealsTable,
      Meal,
      $$MealsTableFilterComposer,
      $$MealsTableOrderingComposer,
      $$MealsTableAnnotationComposer,
      $$MealsTableCreateCompanionBuilder,
      $$MealsTableUpdateCompanionBuilder,
      (Meal, BaseReferences<_$AppDatabase, $MealsTable, Meal>),
      Meal,
      PrefetchHooks Function()
    >;
typedef $$MealIngredientsTableCreateCompanionBuilder =
    MealIngredientsCompanion Function({
      required String id,
      required String householdId,
      required String mealId,
      Value<String?> productId,
      Value<String?> inventoryItemId,
      Value<String?> freeText,
      required double quantity,
      required String unit,
      Value<double?> amountG,
      Value<String> source,
      Value<double?> confidence,
      Value<double?> kcal,
      Value<double?> proteinG,
      Value<double?> fatG,
      Value<double?> carbsG,
      Value<double?> sugarG,
      Value<double?> fiberG,
      Value<double?> saltG,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$MealIngredientsTableUpdateCompanionBuilder =
    MealIngredientsCompanion Function({
      Value<String> id,
      Value<String> householdId,
      Value<String> mealId,
      Value<String?> productId,
      Value<String?> inventoryItemId,
      Value<String?> freeText,
      Value<double> quantity,
      Value<String> unit,
      Value<double?> amountG,
      Value<String> source,
      Value<double?> confidence,
      Value<double?> kcal,
      Value<double?> proteinG,
      Value<double?> fatG,
      Value<double?> carbsG,
      Value<double?> sugarG,
      Value<double?> fiberG,
      Value<double?> saltG,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$MealIngredientsTableFilterComposer
    extends Composer<_$AppDatabase, $MealIngredientsTable> {
  $$MealIngredientsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mealId => $composableBuilder(
    column: $table.mealId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get inventoryItemId => $composableBuilder(
    column: $table.inventoryItemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get freeText => $composableBuilder(
    column: $table.freeText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get amountG => $composableBuilder(
    column: $table.amountG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get kcal => $composableBuilder(
    column: $table.kcal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get proteinG => $composableBuilder(
    column: $table.proteinG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get fatG => $composableBuilder(
    column: $table.fatG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get carbsG => $composableBuilder(
    column: $table.carbsG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get sugarG => $composableBuilder(
    column: $table.sugarG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get fiberG => $composableBuilder(
    column: $table.fiberG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get saltG => $composableBuilder(
    column: $table.saltG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MealIngredientsTableOrderingComposer
    extends Composer<_$AppDatabase, $MealIngredientsTable> {
  $$MealIngredientsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mealId => $composableBuilder(
    column: $table.mealId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get inventoryItemId => $composableBuilder(
    column: $table.inventoryItemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get freeText => $composableBuilder(
    column: $table.freeText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get amountG => $composableBuilder(
    column: $table.amountG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get kcal => $composableBuilder(
    column: $table.kcal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get proteinG => $composableBuilder(
    column: $table.proteinG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get fatG => $composableBuilder(
    column: $table.fatG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get carbsG => $composableBuilder(
    column: $table.carbsG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get sugarG => $composableBuilder(
    column: $table.sugarG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get fiberG => $composableBuilder(
    column: $table.fiberG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get saltG => $composableBuilder(
    column: $table.saltG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MealIngredientsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MealIngredientsTable> {
  $$MealIngredientsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mealId =>
      $composableBuilder(column: $table.mealId, builder: (column) => column);

  GeneratedColumn<String> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  GeneratedColumn<String> get inventoryItemId => $composableBuilder(
    column: $table.inventoryItemId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get freeText =>
      $composableBuilder(column: $table.freeText, builder: (column) => column);

  GeneratedColumn<double> get quantity =>
      $composableBuilder(column: $table.quantity, builder: (column) => column);

  GeneratedColumn<String> get unit =>
      $composableBuilder(column: $table.unit, builder: (column) => column);

  GeneratedColumn<double> get amountG =>
      $composableBuilder(column: $table.amountG, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => column,
  );

  GeneratedColumn<double> get kcal =>
      $composableBuilder(column: $table.kcal, builder: (column) => column);

  GeneratedColumn<double> get proteinG =>
      $composableBuilder(column: $table.proteinG, builder: (column) => column);

  GeneratedColumn<double> get fatG =>
      $composableBuilder(column: $table.fatG, builder: (column) => column);

  GeneratedColumn<double> get carbsG =>
      $composableBuilder(column: $table.carbsG, builder: (column) => column);

  GeneratedColumn<double> get sugarG =>
      $composableBuilder(column: $table.sugarG, builder: (column) => column);

  GeneratedColumn<double> get fiberG =>
      $composableBuilder(column: $table.fiberG, builder: (column) => column);

  GeneratedColumn<double> get saltG =>
      $composableBuilder(column: $table.saltG, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$MealIngredientsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MealIngredientsTable,
          MealIngredient,
          $$MealIngredientsTableFilterComposer,
          $$MealIngredientsTableOrderingComposer,
          $$MealIngredientsTableAnnotationComposer,
          $$MealIngredientsTableCreateCompanionBuilder,
          $$MealIngredientsTableUpdateCompanionBuilder,
          (
            MealIngredient,
            BaseReferences<
              _$AppDatabase,
              $MealIngredientsTable,
              MealIngredient
            >,
          ),
          MealIngredient,
          PrefetchHooks Function()
        > {
  $$MealIngredientsTableTableManager(
    _$AppDatabase db,
    $MealIngredientsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MealIngredientsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MealIngredientsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MealIngredientsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> householdId = const Value.absent(),
                Value<String> mealId = const Value.absent(),
                Value<String?> productId = const Value.absent(),
                Value<String?> inventoryItemId = const Value.absent(),
                Value<String?> freeText = const Value.absent(),
                Value<double> quantity = const Value.absent(),
                Value<String> unit = const Value.absent(),
                Value<double?> amountG = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<double?> confidence = const Value.absent(),
                Value<double?> kcal = const Value.absent(),
                Value<double?> proteinG = const Value.absent(),
                Value<double?> fatG = const Value.absent(),
                Value<double?> carbsG = const Value.absent(),
                Value<double?> sugarG = const Value.absent(),
                Value<double?> fiberG = const Value.absent(),
                Value<double?> saltG = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MealIngredientsCompanion(
                id: id,
                householdId: householdId,
                mealId: mealId,
                productId: productId,
                inventoryItemId: inventoryItemId,
                freeText: freeText,
                quantity: quantity,
                unit: unit,
                amountG: amountG,
                source: source,
                confidence: confidence,
                kcal: kcal,
                proteinG: proteinG,
                fatG: fatG,
                carbsG: carbsG,
                sugarG: sugarG,
                fiberG: fiberG,
                saltG: saltG,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String householdId,
                required String mealId,
                Value<String?> productId = const Value.absent(),
                Value<String?> inventoryItemId = const Value.absent(),
                Value<String?> freeText = const Value.absent(),
                required double quantity,
                required String unit,
                Value<double?> amountG = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<double?> confidence = const Value.absent(),
                Value<double?> kcal = const Value.absent(),
                Value<double?> proteinG = const Value.absent(),
                Value<double?> fatG = const Value.absent(),
                Value<double?> carbsG = const Value.absent(),
                Value<double?> sugarG = const Value.absent(),
                Value<double?> fiberG = const Value.absent(),
                Value<double?> saltG = const Value.absent(),
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MealIngredientsCompanion.insert(
                id: id,
                householdId: householdId,
                mealId: mealId,
                productId: productId,
                inventoryItemId: inventoryItemId,
                freeText: freeText,
                quantity: quantity,
                unit: unit,
                amountG: amountG,
                source: source,
                confidence: confidence,
                kcal: kcal,
                proteinG: proteinG,
                fatG: fatG,
                carbsG: carbsG,
                sugarG: sugarG,
                fiberG: fiberG,
                saltG: saltG,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MealIngredientsTable, MealIngredient>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $MealIngredientsTable,
                    MealIngredient
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MealIngredientsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MealIngredientsTable,
      MealIngredient,
      $$MealIngredientsTableFilterComposer,
      $$MealIngredientsTableOrderingComposer,
      $$MealIngredientsTableAnnotationComposer,
      $$MealIngredientsTableCreateCompanionBuilder,
      $$MealIngredientsTableUpdateCompanionBuilder,
      (
        MealIngredient,
        BaseReferences<_$AppDatabase, $MealIngredientsTable, MealIngredient>,
      ),
      MealIngredient,
      PrefetchHooks Function()
    >;
typedef $$BugReportsTableCreateCompanionBuilder = BugReportsCompanion Function({
  required String id,
  required String householdId,
  Value<String> kind,
  required String title,
  Value<String?> description,
  required String appInfo,
  Value<String?> dataSnapshot,
  Value<String> status,
  Value<String?> severity,
  Value<String?> resolution,
  Value<String?> fixedInVersion,
  Value<DateTime?> statusUpdatedAt,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});
typedef $$BugReportsTableUpdateCompanionBuilder = BugReportsCompanion Function({
  Value<String> id,
  Value<String> householdId,
  Value<String> kind,
  Value<String> title,
  Value<String?> description,
  Value<String> appInfo,
  Value<String?> dataSnapshot,
  Value<String> status,
  Value<String?> severity,
  Value<String?> resolution,
  Value<String?> fixedInVersion,
  Value<DateTime?> statusUpdatedAt,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});

class $$BugReportsTableFilterComposer
    extends Composer<_$AppDatabase, $BugReportsTable> {
  $$BugReportsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get appInfo => $composableBuilder(
    column: $table.appInfo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dataSnapshot => $composableBuilder(
    column: $table.dataSnapshot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get severity => $composableBuilder(
    column: $table.severity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resolution => $composableBuilder(
    column: $table.resolution,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fixedInVersion => $composableBuilder(
    column: $table.fixedInVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get statusUpdatedAt => $composableBuilder(
    column: $table.statusUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BugReportsTableOrderingComposer
    extends Composer<_$AppDatabase, $BugReportsTable> {
  $$BugReportsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get appInfo => $composableBuilder(
    column: $table.appInfo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dataSnapshot => $composableBuilder(
    column: $table.dataSnapshot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get severity => $composableBuilder(
    column: $table.severity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resolution => $composableBuilder(
    column: $table.resolution,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fixedInVersion => $composableBuilder(
    column: $table.fixedInVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get statusUpdatedAt => $composableBuilder(
    column: $table.statusUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BugReportsTableAnnotationComposer
    extends Composer<_$AppDatabase, $BugReportsTable> {
  $$BugReportsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get appInfo =>
      $composableBuilder(column: $table.appInfo, builder: (column) => column);

  GeneratedColumn<String> get dataSnapshot => $composableBuilder(
    column: $table.dataSnapshot,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get severity =>
      $composableBuilder(column: $table.severity, builder: (column) => column);

  GeneratedColumn<String> get resolution => $composableBuilder(
    column: $table.resolution,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fixedInVersion => $composableBuilder(
    column: $table.fixedInVersion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get statusUpdatedAt => $composableBuilder(
    column: $table.statusUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$BugReportsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BugReportsTable,
          BugReport,
          $$BugReportsTableFilterComposer,
          $$BugReportsTableOrderingComposer,
          $$BugReportsTableAnnotationComposer,
          $$BugReportsTableCreateCompanionBuilder,
          $$BugReportsTableUpdateCompanionBuilder,
          (
            BugReport,
            BaseReferences<_$AppDatabase, $BugReportsTable, BugReport>,
          ),
          BugReport,
          PrefetchHooks Function()
        > {
  $$BugReportsTableTableManager(_$AppDatabase db, $BugReportsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BugReportsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BugReportsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BugReportsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> householdId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String> appInfo = const Value.absent(),
                Value<String?> dataSnapshot = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> severity = const Value.absent(),
                Value<String?> resolution = const Value.absent(),
                Value<String?> fixedInVersion = const Value.absent(),
                Value<DateTime?> statusUpdatedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BugReportsCompanion(
                id: id,
                householdId: householdId,
                kind: kind,
                title: title,
                description: description,
                appInfo: appInfo,
                dataSnapshot: dataSnapshot,
                status: status,
                severity: severity,
                resolution: resolution,
                fixedInVersion: fixedInVersion,
                statusUpdatedAt: statusUpdatedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String householdId,
                Value<String> kind = const Value.absent(),
                required String title,
                Value<String?> description = const Value.absent(),
                required String appInfo,
                Value<String?> dataSnapshot = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> severity = const Value.absent(),
                Value<String?> resolution = const Value.absent(),
                Value<String?> fixedInVersion = const Value.absent(),
                Value<DateTime?> statusUpdatedAt = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BugReportsCompanion.insert(
                id: id,
                householdId: householdId,
                kind: kind,
                title: title,
                description: description,
                appInfo: appInfo,
                dataSnapshot: dataSnapshot,
                status: status,
                severity: severity,
                resolution: resolution,
                fixedInVersion: fixedInVersion,
                statusUpdatedAt: statusUpdatedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BugReportsTable, BugReport>(table),
                  BaseReferences<_$AppDatabase, $BugReportsTable, BugReport>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BugReportsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BugReportsTable,
      BugReport,
      $$BugReportsTableFilterComposer,
      $$BugReportsTableOrderingComposer,
      $$BugReportsTableAnnotationComposer,
      $$BugReportsTableCreateCompanionBuilder,
      $$BugReportsTableUpdateCompanionBuilder,
      (BugReport, BaseReferences<_$AppDatabase, $BugReportsTable, BugReport>),
      BugReport,
      PrefetchHooks Function()
    >;
typedef $$ShoppingListsTableCreateCompanionBuilder =
    ShoppingListsCompanion Function({
      required String id,
      required String householdId,
      Value<String> name,
      Value<bool> isDefault,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$ShoppingListsTableUpdateCompanionBuilder =
    ShoppingListsCompanion Function({
      Value<String> id,
      Value<String> householdId,
      Value<String> name,
      Value<bool> isDefault,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$ShoppingListsTableFilterComposer
    extends Composer<_$AppDatabase, $ShoppingListsTable> {
  $$ShoppingListsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDefault => $composableBuilder(
    column: $table.isDefault,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ShoppingListsTableOrderingComposer
    extends Composer<_$AppDatabase, $ShoppingListsTable> {
  $$ShoppingListsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDefault => $composableBuilder(
    column: $table.isDefault,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ShoppingListsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ShoppingListsTable> {
  $$ShoppingListsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get isDefault =>
      $composableBuilder(column: $table.isDefault, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$ShoppingListsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ShoppingListsTable,
          ShoppingList,
          $$ShoppingListsTableFilterComposer,
          $$ShoppingListsTableOrderingComposer,
          $$ShoppingListsTableAnnotationComposer,
          $$ShoppingListsTableCreateCompanionBuilder,
          $$ShoppingListsTableUpdateCompanionBuilder,
          (
            ShoppingList,
            BaseReferences<_$AppDatabase, $ShoppingListsTable, ShoppingList>,
          ),
          ShoppingList,
          PrefetchHooks Function()
        > {
  $$ShoppingListsTableTableManager(_$AppDatabase db, $ShoppingListsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ShoppingListsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ShoppingListsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ShoppingListsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> householdId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<bool> isDefault = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ShoppingListsCompanion(
                id: id,
                householdId: householdId,
                name: name,
                isDefault: isDefault,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String householdId,
                Value<String> name = const Value.absent(),
                Value<bool> isDefault = const Value.absent(),
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ShoppingListsCompanion.insert(
                id: id,
                householdId: householdId,
                name: name,
                isDefault: isDefault,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ShoppingListsTable, ShoppingList>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ShoppingListsTable,
                    ShoppingList
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ShoppingListsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ShoppingListsTable,
      ShoppingList,
      $$ShoppingListsTableFilterComposer,
      $$ShoppingListsTableOrderingComposer,
      $$ShoppingListsTableAnnotationComposer,
      $$ShoppingListsTableCreateCompanionBuilder,
      $$ShoppingListsTableUpdateCompanionBuilder,
      (
        ShoppingList,
        BaseReferences<_$AppDatabase, $ShoppingListsTable, ShoppingList>,
      ),
      ShoppingList,
      PrefetchHooks Function()
    >;
typedef $$ShoppingListItemsTableCreateCompanionBuilder =
    ShoppingListItemsCompanion Function({
      required String id,
      required String householdId,
      required String listId,
      Value<String?> productId,
      Value<String?> freeText,
      Value<double> quantity,
      Value<String> unit,
      Value<bool> checked,
      Value<String> source,
      Value<bool> isSuggestion,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$ShoppingListItemsTableUpdateCompanionBuilder =
    ShoppingListItemsCompanion Function({
      Value<String> id,
      Value<String> householdId,
      Value<String> listId,
      Value<String?> productId,
      Value<String?> freeText,
      Value<double> quantity,
      Value<String> unit,
      Value<bool> checked,
      Value<String> source,
      Value<bool> isSuggestion,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$ShoppingListItemsTableFilterComposer
    extends Composer<_$AppDatabase, $ShoppingListItemsTable> {
  $$ShoppingListItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get listId => $composableBuilder(
    column: $table.listId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get freeText => $composableBuilder(
    column: $table.freeText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get checked => $composableBuilder(
    column: $table.checked,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isSuggestion => $composableBuilder(
    column: $table.isSuggestion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ShoppingListItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $ShoppingListItemsTable> {
  $$ShoppingListItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get listId => $composableBuilder(
    column: $table.listId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get freeText => $composableBuilder(
    column: $table.freeText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get checked => $composableBuilder(
    column: $table.checked,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isSuggestion => $composableBuilder(
    column: $table.isSuggestion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ShoppingListItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ShoppingListItemsTable> {
  $$ShoppingListItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get listId =>
      $composableBuilder(column: $table.listId, builder: (column) => column);

  GeneratedColumn<String> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  GeneratedColumn<String> get freeText =>
      $composableBuilder(column: $table.freeText, builder: (column) => column);

  GeneratedColumn<double> get quantity =>
      $composableBuilder(column: $table.quantity, builder: (column) => column);

  GeneratedColumn<String> get unit =>
      $composableBuilder(column: $table.unit, builder: (column) => column);

  GeneratedColumn<bool> get checked =>
      $composableBuilder(column: $table.checked, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<bool> get isSuggestion => $composableBuilder(
    column: $table.isSuggestion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$ShoppingListItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ShoppingListItemsTable,
          ShoppingListItem,
          $$ShoppingListItemsTableFilterComposer,
          $$ShoppingListItemsTableOrderingComposer,
          $$ShoppingListItemsTableAnnotationComposer,
          $$ShoppingListItemsTableCreateCompanionBuilder,
          $$ShoppingListItemsTableUpdateCompanionBuilder,
          (
            ShoppingListItem,
            BaseReferences<
              _$AppDatabase,
              $ShoppingListItemsTable,
              ShoppingListItem
            >,
          ),
          ShoppingListItem,
          PrefetchHooks Function()
        > {
  $$ShoppingListItemsTableTableManager(
    _$AppDatabase db,
    $ShoppingListItemsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ShoppingListItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ShoppingListItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ShoppingListItemsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> householdId = const Value.absent(),
                Value<String> listId = const Value.absent(),
                Value<String?> productId = const Value.absent(),
                Value<String?> freeText = const Value.absent(),
                Value<double> quantity = const Value.absent(),
                Value<String> unit = const Value.absent(),
                Value<bool> checked = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<bool> isSuggestion = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ShoppingListItemsCompanion(
                id: id,
                householdId: householdId,
                listId: listId,
                productId: productId,
                freeText: freeText,
                quantity: quantity,
                unit: unit,
                checked: checked,
                source: source,
                isSuggestion: isSuggestion,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String householdId,
                required String listId,
                Value<String?> productId = const Value.absent(),
                Value<String?> freeText = const Value.absent(),
                Value<double> quantity = const Value.absent(),
                Value<String> unit = const Value.absent(),
                Value<bool> checked = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<bool> isSuggestion = const Value.absent(),
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ShoppingListItemsCompanion.insert(
                id: id,
                householdId: householdId,
                listId: listId,
                productId: productId,
                freeText: freeText,
                quantity: quantity,
                unit: unit,
                checked: checked,
                source: source,
                isSuggestion: isSuggestion,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ShoppingListItemsTable, ShoppingListItem>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ShoppingListItemsTable,
                    ShoppingListItem
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ShoppingListItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ShoppingListItemsTable,
      ShoppingListItem,
      $$ShoppingListItemsTableFilterComposer,
      $$ShoppingListItemsTableOrderingComposer,
      $$ShoppingListItemsTableAnnotationComposer,
      $$ShoppingListItemsTableCreateCompanionBuilder,
      $$ShoppingListItemsTableUpdateCompanionBuilder,
      (
        ShoppingListItem,
        BaseReferences<
          _$AppDatabase,
          $ShoppingListItemsTable,
          ShoppingListItem
        >,
      ),
      ShoppingListItem,
      PrefetchHooks Function()
    >;
typedef $$OutboxTableCreateCompanionBuilder = OutboxCompanion Function({
  Value<int> id,
  required String remoteTable,
  required String rowId,
  required String payload,
  required DateTime createdAt,
  Value<int> attempts,
  Value<String?> lastError,
});
typedef $$OutboxTableUpdateCompanionBuilder = OutboxCompanion Function({
  Value<int> id,
  Value<String> remoteTable,
  Value<String> rowId,
  Value<String> payload,
  Value<DateTime> createdAt,
  Value<int> attempts,
  Value<String?> lastError,
});

class $$OutboxTableFilterComposer
    extends Composer<_$AppDatabase, $OutboxTable> {
  $$OutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteTable => $composableBuilder(
    column: $table.remoteTable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rowId => $composableBuilder(
    column: $table.rowId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OutboxTableOrderingComposer
    extends Composer<_$AppDatabase, $OutboxTable> {
  $$OutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteTable => $composableBuilder(
    column: $table.remoteTable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rowId => $composableBuilder(
    column: $table.rowId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutboxTableAnnotationComposer
    extends Composer<_$AppDatabase, $OutboxTable> {
  $$OutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get remoteTable => $composableBuilder(
    column: $table.remoteTable,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rowId =>
      $composableBuilder(column: $table.rowId, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$OutboxTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OutboxTable,
          OutboxEntry,
          $$OutboxTableFilterComposer,
          $$OutboxTableOrderingComposer,
          $$OutboxTableAnnotationComposer,
          $$OutboxTableCreateCompanionBuilder,
          $$OutboxTableUpdateCompanionBuilder,
          (
            OutboxEntry,
            BaseReferences<_$AppDatabase, $OutboxTable, OutboxEntry>,
          ),
          OutboxEntry,
          PrefetchHooks Function()
        > {
  $$OutboxTableTableManager(_$AppDatabase db, $OutboxTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> remoteTable = const Value.absent(),
                Value<String> rowId = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
              }) => OutboxCompanion(
                id: id,
                remoteTable: remoteTable,
                rowId: rowId,
                payload: payload,
                createdAt: createdAt,
                attempts: attempts,
                lastError: lastError,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String remoteTable,
                required String rowId,
                required String payload,
                required DateTime createdAt,
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
              }) => OutboxCompanion.insert(
                id: id,
                remoteTable: remoteTable,
                rowId: rowId,
                payload: payload,
                createdAt: createdAt,
                attempts: attempts,
                lastError: lastError,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OutboxTable, OutboxEntry>(table),
                  BaseReferences<_$AppDatabase, $OutboxTable, OutboxEntry>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OutboxTable,
      OutboxEntry,
      $$OutboxTableFilterComposer,
      $$OutboxTableOrderingComposer,
      $$OutboxTableAnnotationComposer,
      $$OutboxTableCreateCompanionBuilder,
      $$OutboxTableUpdateCompanionBuilder,
      (OutboxEntry, BaseReferences<_$AppDatabase, $OutboxTable, OutboxEntry>),
      OutboxEntry,
      PrefetchHooks Function()
    >;
typedef $$SyncStatesTableCreateCompanionBuilder = SyncStatesCompanion Function({
  required String remoteTable,
  Value<String?> lastPulledAt,
  Value<int> rowid,
});
typedef $$SyncStatesTableUpdateCompanionBuilder = SyncStatesCompanion Function({
  Value<String> remoteTable,
  Value<String?> lastPulledAt,
  Value<int> rowid,
});

class $$SyncStatesTableFilterComposer
    extends Composer<_$AppDatabase, $SyncStatesTable> {
  $$SyncStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get remoteTable => $composableBuilder(
    column: $table.remoteTable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastPulledAt => $composableBuilder(
    column: $table.lastPulledAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncStatesTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncStatesTable> {
  $$SyncStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get remoteTable => $composableBuilder(
    column: $table.remoteTable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastPulledAt => $composableBuilder(
    column: $table.lastPulledAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncStatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncStatesTable> {
  $$SyncStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get remoteTable => $composableBuilder(
    column: $table.remoteTable,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastPulledAt => $composableBuilder(
    column: $table.lastPulledAt,
    builder: (column) => column,
  );
}

class $$SyncStatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncStatesTable,
          SyncStateEntry,
          $$SyncStatesTableFilterComposer,
          $$SyncStatesTableOrderingComposer,
          $$SyncStatesTableAnnotationComposer,
          $$SyncStatesTableCreateCompanionBuilder,
          $$SyncStatesTableUpdateCompanionBuilder,
          (
            SyncStateEntry,
            BaseReferences<_$AppDatabase, $SyncStatesTable, SyncStateEntry>,
          ),
          SyncStateEntry,
          PrefetchHooks Function()
        > {
  $$SyncStatesTableTableManager(_$AppDatabase db, $SyncStatesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> remoteTable = const Value.absent(),
                Value<String?> lastPulledAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncStatesCompanion(
                remoteTable: remoteTable,
                lastPulledAt: lastPulledAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String remoteTable,
                Value<String?> lastPulledAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncStatesCompanion.insert(
                remoteTable: remoteTable,
                lastPulledAt: lastPulledAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncStatesTable, SyncStateEntry>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $SyncStatesTable,
                    SyncStateEntry
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncStatesTable,
      SyncStateEntry,
      $$SyncStatesTableFilterComposer,
      $$SyncStatesTableOrderingComposer,
      $$SyncStatesTableAnnotationComposer,
      $$SyncStatesTableCreateCompanionBuilder,
      $$SyncStatesTableUpdateCompanionBuilder,
      (
        SyncStateEntry,
        BaseReferences<_$AppDatabase, $SyncStatesTable, SyncStateEntry>,
      ),
      SyncStateEntry,
      PrefetchHooks Function()
    >;
typedef $$KeyValuesTableCreateCompanionBuilder = KeyValuesCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$KeyValuesTableUpdateCompanionBuilder = KeyValuesCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$KeyValuesTableFilterComposer
    extends Composer<_$AppDatabase, $KeyValuesTable> {
  $$KeyValuesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$KeyValuesTableOrderingComposer
    extends Composer<_$AppDatabase, $KeyValuesTable> {
  $$KeyValuesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$KeyValuesTableAnnotationComposer
    extends Composer<_$AppDatabase, $KeyValuesTable> {
  $$KeyValuesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$KeyValuesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $KeyValuesTable,
          KeyValueEntry,
          $$KeyValuesTableFilterComposer,
          $$KeyValuesTableOrderingComposer,
          $$KeyValuesTableAnnotationComposer,
          $$KeyValuesTableCreateCompanionBuilder,
          $$KeyValuesTableUpdateCompanionBuilder,
          (
            KeyValueEntry,
            BaseReferences<_$AppDatabase, $KeyValuesTable, KeyValueEntry>,
          ),
          KeyValueEntry,
          PrefetchHooks Function()
        > {
  $$KeyValuesTableTableManager(_$AppDatabase db, $KeyValuesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KeyValuesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KeyValuesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KeyValuesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => KeyValuesCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) => KeyValuesCompanion.insert(key: key, value: value, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$KeyValuesTable, KeyValueEntry>(table),
                  BaseReferences<_$AppDatabase, $KeyValuesTable, KeyValueEntry>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$KeyValuesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $KeyValuesTable,
      KeyValueEntry,
      $$KeyValuesTableFilterComposer,
      $$KeyValuesTableOrderingComposer,
      $$KeyValuesTableAnnotationComposer,
      $$KeyValuesTableCreateCompanionBuilder,
      $$KeyValuesTableUpdateCompanionBuilder,
      (
        KeyValueEntry,
        BaseReferences<_$AppDatabase, $KeyValuesTable, KeyValueEntry>,
      ),
      KeyValueEntry,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db, _db.categories);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db, _db.products);
  $$ProductBarcodesTableTableManager get productBarcodes =>
      $$ProductBarcodesTableTableManager(_db, _db.productBarcodes);
  $$ProductAliasesTableTableManager get productAliases =>
      $$ProductAliasesTableTableManager(_db, _db.productAliases);
  $$StoresTableTableManager get stores =>
      $$StoresTableTableManager(_db, _db.stores);
  $$ReceiptsTableTableManager get receipts =>
      $$ReceiptsTableTableManager(_db, _db.receipts);
  $$ReceiptItemsTableTableManager get receiptItems =>
      $$ReceiptItemsTableTableManager(_db, _db.receiptItems);
  $$CategoryAliasesTableTableManager get categoryAliases =>
      $$CategoryAliasesTableTableManager(_db, _db.categoryAliases);
  $$ReceiptFilesTableTableManager get receiptFiles =>
      $$ReceiptFilesTableTableManager(_db, _db.receiptFiles);
  $$InventoryItemsTableTableManager get inventoryItems =>
      $$InventoryItemsTableTableManager(_db, _db.inventoryItems);
  $$InventoryMovementsTableTableManager get inventoryMovements =>
      $$InventoryMovementsTableTableManager(_db, _db.inventoryMovements);
  $$MealsTableTableManager get meals =>
      $$MealsTableTableManager(_db, _db.meals);
  $$MealIngredientsTableTableManager get mealIngredients =>
      $$MealIngredientsTableTableManager(_db, _db.mealIngredients);
  $$BugReportsTableTableManager get bugReports =>
      $$BugReportsTableTableManager(_db, _db.bugReports);
  $$ShoppingListsTableTableManager get shoppingLists =>
      $$ShoppingListsTableTableManager(_db, _db.shoppingLists);
  $$ShoppingListItemsTableTableManager get shoppingListItems =>
      $$ShoppingListItemsTableTableManager(_db, _db.shoppingListItems);
  $$OutboxTableTableManager get outbox =>
      $$OutboxTableTableManager(_db, _db.outbox);
  $$SyncStatesTableTableManager get syncStates =>
      $$SyncStatesTableTableManager(_db, _db.syncStates);
  $$KeyValuesTableTableManager get keyValues =>
      $$KeyValuesTableTableManager(_db, _db.keyValues);
}
