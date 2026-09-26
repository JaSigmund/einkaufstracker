import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// Kategorien (Spiegel der Tabelle public.categories).
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get parentId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get icon => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isStorable => boolean().withDefault(const Constant(true))();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Produkte (Teilspiegel von public.products, Pilotobjekt fuer den Sync in Phase 1).
class Products extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get name => text()();
  TextColumn get brand => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get baseUnit => text().withDefault(const Constant('piece'))();
  RealColumn get packSize => real().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Haendler/Filialen (Spiegel von public.stores). Je Kette und Filialnummer eine Zeile.
class Stores extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get chain => text()();

  /// Filialkennung, z.B. "0643"
  TextColumn get branch => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Bons (Teilspiegel von public.receipts).
class Receipts extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get storeId => text().nullable()();
  DateTimeColumn get purchasedAt => dateTime()();
  IntColumn get totalCents => integer()();

  /// 'draft' | 'confirmed' | 'pending'
  TextColumn get status => text().withDefault(const Constant('confirmed'))();

  /// 'pdf_text' | 'on_device' | 'llm' | 'manual'
  TextColumn get source => text().withDefault(const Constant('manual'))();

  /// Eindeutige Kennung des Kaufs (bei Billa die Re-Nr), Grundlage der Duplikaterkennung.
  TextColumn get externalId => text().nullable()();
  RealColumn get confidence => real().nullable()();
  BoolColumn get sumMismatch => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Bon-Positionen (Teilspiegel von public.receipt_items).
class ReceiptItems extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get receiptId => text()();
  IntColumn get lineNo => integer()();

  /// 'article' | 'deposit' | 'discount'
  TextColumn get kind => text().withDefault(const Constant('article'))();
  TextColumn get rawText => text()();
  TextColumn get productId => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  RealColumn get quantity => real().withDefault(const Constant(1))();

  /// 'piece' | 'kg' | 'l'
  TextColumn get quantityUnit => text().withDefault(const Constant('piece'))();
  IntColumn get unitPriceCents => integer().nullable()();
  IntColumn get lineTotalCents => integer()();
  TextColumn get taxCode => text().nullable()();
  BoolColumn get needsReview => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Warteschlange fuer Schreibzugriffe, die noch nicht beim Server angekommen sind (Outbox-Muster).
@DataClassName('OutboxEntry')
class Outbox extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Name der Zieltabelle auf dem Server (z.B. 'categories').
  TextColumn get remoteTable => text()();
  TextColumn get rowId => text()();

  /// JSON der Zeile im Server-Format (snake_case).
  TextColumn get payload => text()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
}

/// Pro Tabelle der Zeitstempel (Server-Format) der zuletzt geholten Aenderung.
@DataClassName('SyncStateEntry')
class SyncStates extends Table {
  TextColumn get remoteTable => text()();
  TextColumn get lastPulledAt => text().nullable()();

  @override
  Set<Column> get primaryKey => {remoteTable};
}

/// Kleine Schluessel-Wert-Ablage (z.B. zuletzt bekannte Haushalts-ID fuer den Offline-Start).
@DataClassName('KeyValueEntry')
class KeyValues extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Categories, Products, Stores, Receipts, ReceiptItems, Outbox, SyncStates, KeyValues])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Dauerhafte Datenbank auf dem Geraet.
  AppDatabase.persistent() : super(driftDatabase(name: 'einkaufstracker'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // 1 -> 2: Bon-Tabellen (Phase 2). Bestehende Installationen behalten Kategorien und Outbox.
          if (from < 2) {
            await m.createTable(stores);
            await m.createTable(receipts);
            await m.createTable(receiptItems);
          }
        },
      );

  Future<String?> getKv(String key) async {
    final row = await (select(keyValues)..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setKv(String key, String value) =>
      into(keyValues).insertOnConflictUpdate(KeyValuesCompanion.insert(key: key, value: value));

  /// Loescht alle lokalen Daten (beim Abmelden, damit auf dem Geraet nichts zurueckbleibt).
  Future<void> wipe() async {
    await transaction(() async {
      for (final t in allTables) {
        await delete(t).go();
      }
    });
  }
}
