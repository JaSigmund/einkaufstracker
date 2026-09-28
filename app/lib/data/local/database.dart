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

  /// 'kg' | 'l' | 'piece'
  TextColumn get baseUnit => text().withDefault(const Constant('piece'))();
  RealColumn get packSize => real().nullable()();

  /// Standardhaltbarkeit ab Kauf (Tage), falls kein MHD bekannt ist.
  IntColumn get sealedShelfLifeDays => integer().nullable()();

  /// Standardhaltbarkeit nach dem Oeffnen (Tage).
  IntColumn get openedShelfLifeDays => integer().nullable()();

  /// 'best_before' | 'use_by'
  TextColumn get defaultDateKind => text().withDefault(const Constant('best_before'))();

  /// 'fridge' | 'freezer' | 'pantry' | 'other'
  TextColumn get defaultLocation => text().withDefault(const Constant('pantry'))();

  /// Nachkaufprodukt: Vorschlag fuer die Einkaufsliste, wenn der letzte Bestand ausgeht (Phase 3).
  BoolColumn get restock => boolean().withDefault(const Constant(false))();
  TextColumn get offCode => text().nullable()();

  /// Naehrwerte je 100 g/ml als JSON (Phase 7): {kcal, protein_g, fat_g, sat_fat_g, carbs_g, sugar_g, fiber_g, salt_g}
  TextColumn get nutrientsPer100 => text().nullable()();

  /// 'g' | 'ml', nur gesetzt wenn nutrientsPer100 gesetzt ist.
  TextColumn get nutrientsBasis => text().nullable()();

  /// 'off' | 'usda' | 'manual' | 'llm_estimate'
  TextColumn get nutrientsSource => text().nullable()();

  /// Gewicht eines Stuecks in Gramm (z.B. Paprika ~150), fuer die Umrechnung Stueck <-> Gewicht.
  RealColumn get unitWeightG => real().nullable()();

  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// EAN -> Produkt (Spiegel von public.product_barcodes). Zusammengesetzter Primaerschluessel wie am Server.
class ProductBarcodes extends Table {
  TextColumn get householdId => text()();
  TextColumn get ean => text()();
  TextColumn get productId => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {householdId, ean};
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
  TextColumn get brand => text().nullable()();
  RealColumn get quantity => real().withDefault(const Constant(1))();

  /// 'piece' | 'kg' | 'l'
  TextColumn get quantityUnit => text().withDefault(const Constant('piece'))();
  IntColumn get unitPriceCents => integer().nullable()();
  IntColumn get lineTotalCents => integer()();

  /// Grundpreis je Basiseinheit des Produkts, in Cent (Doku 07 §3.1). `null`, wenn nicht berechenbar
  /// (kein Produkt zugeordnet oder Packware ohne bekannten Packungsinhalt).
  IntColumn get unitPriceNormCents => integer().nullable()();
  TextColumn get taxCode => text().nullable()();
  BoolColumn get needsReview => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Gelernte Zuordnung "normalisierter Artikelname -> Kategorie" (Spiegel von public.category_aliases).
@DataClassName('CategoryAlias')
class CategoryAliases extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();

  /// Ergebnis von normalizeItemName, z.B. "dkih paprika tricolore".
  TextColumn get aliasText => text()();
  TextColumn get categoryId => text()();
  IntColumn get hits => integer().withDefault(const Constant(1))();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Originalbeleg zu einem Bon: Foto ohne Zahlungsblock oder PDF (Spiegel von public.receipt_files).
/// Die Datei selbst liegt lokal im App-Ordner und im Storage-Bucket "receipts".
@DataClassName('ReceiptFile')
class ReceiptFiles extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get receiptId => text()();

  /// 'pdf' | 'image'
  TextColumn get kind => text()();
  IntColumn get pageNo => integer().withDefault(const Constant(1))();

  /// Pfad im Bucket: {household_id}/{receipt_id}/{file_id}.{ext}
  TextColumn get storagePath => text()();
  IntColumn get sizeBytes => integer().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Vorratseintrag (Spiegel von public.inventory_items). Doku 06 Inventar und Haltbarkeit.
class InventoryItems extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get productId => text()();

  /// Bon-Position, aus der dieser Eintrag als Vorschlag entstanden ist (Doku 06 §2).
  TextColumn get receiptItemId => text().nullable()();
  TextColumn get ean => text().nullable()();
  RealColumn get quantity => real().withDefault(const Constant(1))();

  /// 'piece' | 'kg' | 'l'
  TextColumn get unit => text().withDefault(const Constant('piece'))();

  /// 'fridge' | 'freezer' | 'pantry' | 'other'
  TextColumn get location => text().withDefault(const Constant('pantry'))();

  DateTimeColumn get purchasedOn => dateTime().nullable()();
  DateTimeColumn get bestBefore => dateTime().nullable()();

  /// 'best_before' | 'use_by'
  TextColumn get dateKind => text().withDefault(const Constant('best_before'))();
  DateTimeColumn get openedOn => dateTime().nullable()();
  IntColumn get openShelfLifeDays => integer().nullable()();

  /// 'sealed' | 'opened' | 'consumed' | 'discarded'
  TextColumn get status => text().withDefault(const Constant('sealed'))();

  /// Aus einem Bon vorgeschlagen, noch nicht per Barcode bestaetigt (Doku 06 §2, INV-08).
  BoolColumn get isSuggestion => boolean().withDefault(const Constant(false))();
  DateTimeColumn get closedAt => dateTime().nullable()();

  /// Fruehestes aus bestBefore und openedOn+openShelfLifeDays (siehe computeExpiresOn), vom Server berechnet
  /// und hier gespiegelt; fuer optimistische lokale Anzeige vor dem naechsten Sync selbst gesetzt.
  DateTimeColumn get expiresOn => dateTime().nullable()();

  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Bestandsbewegung (Ledger, Spiegel von public.inventory_movements). Doku 06 §9.
class InventoryMovements extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get inventoryItemId => text().nullable()();
  TextColumn get productId => text()();
  DateTimeColumn get occurredAt => dateTime()();

  /// 'purchase' | 'consumed' | 'meal' | 'discarded' | 'adjustment'
  TextColumn get type => text()();

  /// Vorzeichen: Zugang +, Abgang -.
  RealColumn get quantityDelta => real()();

  /// 'piece' | 'kg' | 'l'
  TextColumn get unit => text()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Gelernte Zuordnung "normalisierter Bon-Text -> Produkt" (Spiegel von public.product_aliases, ADR-010).
/// Anders als category_aliases haendlerabhaengig (storeId), weil derselbe Kurztext bei zwei Haendlern
/// verschiedene Produkte meinen kann; storeId null = haendlerunabhaengig gelernt.
@DataClassName('ProductAlias')
class ProductAliases extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get storeId => text().nullable()();
  TextColumn get aliasText => text()();
  TextColumn get productId => text()();
  IntColumn get hits => integer().withDefault(const Constant(1))();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Fehlerbericht oder Feature-Vorschlag aus der App (Spiegel von public.bug_reports). appInfo/dataSnapshot
/// sind als JSON-Text gespeichert (drift kennt kein natives jsonb), beim Sync wird daraus/dahin dekodiert.
/// Beide Arten teilen sich Tabelle und Status-Workflow (Gesamtkonzept Feedback-Warteschlange, 2026-09-28):
/// 'confirmed' bedeutet bei einem Feature "angenommen" (Gate vor der Umsetzung), die Planungsliste ist keine
/// eigene Tabelle, sondern die Abfrage kind='feature' AND status='confirmed'.
@DataClassName('BugReport')
class BugReports extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();

  /// 'bug' | 'feature'
  TextColumn get kind => text().withDefault(const Constant('bug'))();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get appInfo => text()();
  TextColumn get dataSnapshot => text().nullable()();

  /// 'new' | 'confirmed' | 'in_progress' | 'fixed' | 'verified' | 'wont_fix' | 'duplicate'
  TextColumn get status => text().withDefault(const Constant('new'))();

  /// 'low' | 'medium' | 'high' | 'critical', von der Entwicklung gesetzt.
  TextColumn get severity => text().nullable()();
  TextColumn get resolution => text().nullable()();
  TextColumn get fixedInVersion => text().nullable()();
  DateTimeColumn get statusUpdatedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Einkaufsliste (Spiegel von public.shopping_lists). MVP: je Haushalt genau eine Standardliste, die
/// beim ersten Eintrag angelegt wird (Doku 06 §6/§7, Roadmap Phase 3).
@DataClassName('ShoppingList')
class ShoppingLists extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get name => text().withDefault(const Constant('Einkaufsliste'))();
  BoolColumn get isDefault => boolean().withDefault(const Constant(true))();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Position auf der Einkaufsliste (Spiegel von public.shopping_list_items). Entweder an ein Produkt
/// gebunden (`productId`) oder frei getippt (`freeText`); `isSuggestion` markiert einen noch unbestaetigten
/// automatischen Vorschlag (Doku 06 §6: Ablauf/Leer/Wiederkehrend), bis der Nutzer ihn bestaetigt oder verwirft.
@DataClassName('ShoppingListItem')
class ShoppingListItems extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get listId => text()();
  TextColumn get productId => text().nullable()();
  TextColumn get freeText => text().nullable()();
  RealColumn get quantity => real().withDefault(const Constant(1))();

  /// 'piece' | 'kg' | 'l'
  TextColumn get unit => text().withDefault(const Constant('piece'))();
  BoolColumn get checked => boolean().withDefault(const Constant(false))();

  /// 'manual' | 'expiring' | 'depleted' | 'recurring' | 'scan'
  TextColumn get source => text().withDefault(const Constant('manual'))();
  BoolColumn get isSuggestion => boolean().withDefault(const Constant(false))();
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

@DriftDatabase(tables: [
  Categories, Products, ProductBarcodes, ProductAliases, Stores, Receipts, ReceiptItems, CategoryAliases,
  ReceiptFiles, InventoryItems, InventoryMovements, BugReports, ShoppingLists, ShoppingListItems, Outbox,
  SyncStates, KeyValues,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Dauerhafte Datenbank auf dem Geraet.
  AppDatabase.persistent() : super(driftDatabase(name: 'einkaufstracker'));

  @override
  int get schemaVersion => 12;

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
          // 2 -> 3: gelernte Kategorie-Zuordnungen
          if (from < 3) {
            await m.createTable(categoryAliases);
          }
          // 3 -> 4: Originalbelege (Fotos, PDFs)
          if (from < 4) {
            await m.createTable(receiptFiles);
          }
          // 4 -> 5: erweiterte Produktdaten (Haltbarkeit, Naehrwerte) und Barcode-Zuordnung
          if (from < 5) {
            await m.addColumn(products, products.sealedShelfLifeDays);
            await m.addColumn(products, products.openedShelfLifeDays);
            await m.addColumn(products, products.defaultDateKind);
            await m.addColumn(products, products.defaultLocation);
            await m.addColumn(products, products.restock);
            await m.addColumn(products, products.offCode);
            await m.addColumn(products, products.nutrientsPer100);
            await m.addColumn(products, products.nutrientsBasis);
            await m.addColumn(products, products.nutrientsSource);
            await m.addColumn(products, products.unitWeightG);
            await m.createTable(productBarcodes);
          }
          // 5 -> 6: Inventar (Phase 3)
          if (from < 6) {
            await m.createTable(inventoryItems);
            await m.createTable(inventoryMovements);
          }
          // 6 -> 7: gelernte Bon-Text-zu-Produkt-Zuordnung (schliesst Bon -> Inventar-Vorschlag)
          if (from < 7) {
            await m.createTable(productAliases);
          }
          // 7 -> 8: Fehlerberichte
          if (from < 8) {
            await m.createTable(bugReports);
          }
          // 8 -> 9: Bearbeitungsstatus fuer Fehlerberichte
          if (from < 9) {
            await m.addColumn(bugReports, bugReports.status);
            await m.addColumn(bugReports, bugReports.severity);
            await m.addColumn(bugReports, bugReports.resolution);
            await m.addColumn(bugReports, bugReports.fixedInVersion);
            await m.addColumn(bugReports, bugReports.statusUpdatedAt);
          }
          // 9 -> 10: Einkaufsliste (Phase 3)
          if (from < 10) {
            await m.createTable(shoppingLists);
            await m.createTable(shoppingListItems);
          }
          // 10 -> 11: Grundpreis und Marke je Bon-Position (Phase 4)
          if (from < 11) {
            await m.addColumn(receiptItems, receiptItems.brand);
            await m.addColumn(receiptItems, receiptItems.unitPriceNormCents);
          }
          // 11 -> 12: Feature-Vorschlaege teilen sich die Fehlerbericht-Tabelle (kind-Feld)
          if (from < 12) {
            await m.addColumn(bugReports, bugReports.kind);
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
