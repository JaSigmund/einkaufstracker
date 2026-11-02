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
  /// Gesamtinhalt einer Packung in [baseUnit].
  RealColumn get packSize => real().nullable()();

  /// Mehrfachpackung (ADR-045): in wie viele Stuecke sich [packSize] teilt, nur bei kg und l. Regeln in `domain/products/packaging.dart`.
  IntColumn get piecesPerPack => integer().nullable()();

  /// Name der Stuecke in der Mehrzahl ("Fläschchen"), ohne Angabe "Stk".
  TextColumn get pieceLabel => text().nullable()();

  /// Vom Nutzer entschieden: trinkbar oder nicht (ADR-048). `null`: Die Regel in `domain/products/drinkable.dart` entscheidet.
  BoolColumn get isDrink => boolean().nullable()();

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

  /// 'off' | 'bls' | 'usda' | 'manual' | 'llm_estimate'
  TextColumn get nutrientsSource => text().nullable()();

  /// Mit welchem Eintrag der Lebensmitteldatenbank (BLS) ist das Produkt verknuepft (Phase N1). Das Profil steht als
  /// Snapshot in [nutrientsPer100], damit die Mahlzeitenerfassung ohne Abfrage offline laeuft.
  TextColumn get blsCode => text().nullable()();

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

  /// Von jemand anderem bezahlt (ADR-020 "Rechnungen teilen"): zaehlt nicht zur eigenen Auswertung,
  /// bleibt aber auf dem Bon sichtbar und wandert normal ins Inventar.
  BoolColumn get excluded => boolean().withDefault(const Constant(false))();
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

  /// Mahlzeit, die diese Bewegung ausgeloest hat (Abzug oder Gegenbuchung, Doku 15 §3.4, FR-12).
  TextColumn get mealId => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Mahlzeit im Essenstagebuch (Spiegel von public.meals, Doku 15 Essenstagebuch und Naehrwerte).
class Meals extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  DateTimeColumn get eatenAt => dateTime()();

  /// 'breakfast' | 'lunch' | 'dinner' | 'snack' | 'drink'
  TextColumn get mealType => text().withDefault(const Constant('lunch'))();
  TextColumn get title => text()();
  TextColumn get note => text().nullable()();

  /// Storage-Pfad im Bucket `meals` (`{household_id}/{meal_id}.jpg`), sobald das Foto hochgeladen ist.
  TextColumn get photoPath => text().nullable()();
  TextColumn get recipeId => text().nullable()();

  /// Anteil, der von der Person selbst gegessen wurde, und insgesamt zubereitete Portionen (FR-13).
  RealColumn get servingsEaten => real().withDefault(const Constant(1))();
  RealColumn get servingsMade => real().withDefault(const Constant(1))();

  /// 'manual' | 'photo_ai' | 'recipe'
  TextColumn get source => text().withDefault(const Constant('manual'))();

  /// Zutaten nur geschaetzt (z.B. Restaurant), in allen Auswertungen erkennbar (FR-17).
  BoolColumn get isEstimate => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Zutat einer Mahlzeit (Spiegel von public.meal_ingredients). Die Naehrwerte sind ein Snapshot zum
/// Erfassungszeitpunkt (Doku 15 §5.4): spaetere Korrekturen am Produkt aendern alte Eintraege nicht.
class MealIngredients extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get mealId => text()();
  TextColumn get productId => text().nullable()();

  /// Erster Inventar-Posten, aus dem abgezogen wurde (die Aufteilung auf mehrere Posten steht im Ledger).
  TextColumn get inventoryItemId => text().nullable()();
  TextColumn get freeText => text().nullable()();

  /// Erfasste Menge in einer der Datenbank-Einheiten `kg` | `l` | `piece`.
  RealColumn get quantity => real()();
  TextColumn get unit => text()();

  /// Menge in g bzw. ml, Basis der Naehrwertrechnung; `null`, wenn nicht bestimmbar.
  RealColumn get amountG => real().nullable()();

  /// 'inventory' | 'photo_ai' | 'recipe' | 'manual' | 'estimate'
  TextColumn get source => text().withDefault(const Constant('manual'))();
  RealColumn get confidence => real().nullable()();

  /// Aus welchem BLS-Eintrag stammen die Naehrwerte (Phase N1), null bei Produkt- und Handwerten.
  TextColumn get blsCode => text().nullable()();

  /// Wie sicher die Naehrwerte sind: 'product' | 'bls_exact' | 'bls_matched' (automatisch zugeordnet, in der App mit ~
  /// markiert) | 'llm_estimate' | 'manual' | 'unknown'. null bei Zutaten aus aelteren Versionen.
  TextColumn get nutrientBasis => text().nullable()();

  /// Mikronaehrstoffe der verzehrten Menge als JSON-Objekt mit Registerschluesseln (Phase N3, ADR-032), `null` ohne Daten.
  /// Ein fehlender Schluessel heisst unbekannt, 0 ist eine echte Null.
  TextColumn get micros => text().nullable()();

  /// Zubereitung der Zutat, auf die sich die Garfaktoren stuetzen (Phase N4, ADR-037): `kategorie:zubereitung`, z.B. `veg_other:boiled`.
  /// `null` = roh oder nicht angegeben. Die gespeicherten [micros] sind dann schon um die Verluste gemindert.
  TextColumn get preparation => text().nullable()();
  RealColumn get kcal => real().nullable()();
  RealColumn get proteinG => real().nullable()();
  RealColumn get fatG => real().nullable()();
  RealColumn get carbsG => real().nullable()();
  RealColumn get sugarG => real().nullable()();
  RealColumn get fiberG => real().nullable()();
  RealColumn get saltG => real().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Richtwerte der Naehrwerte je Haushalt (Spiegel von public.nutrition_targets, LH-MEAL-09). Hoechstens eine Zeile
/// je Haushalt; `targets` ist das Server-JSON `{"kcal": {"min": .., "max": ..}, ...}` als Text.
@DataClassName('NutritionTargetRow')
class NutritionTargetRows extends Table {
  TextColumn get householdId => text()();
  TextColumn get targets => text().withDefault(const Constant('{}'))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {householdId};
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

  /// Gesetzt, sobald der Eintrag mit "Einkauf abschließen" archiviert wurde (ADR-043); Eintraege eines Abschlusses tragen denselben Wert.
  DateTimeColumn get archivedAt => dateTime().nullable()();
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

/// Zuordnung "dieses Produkt entspricht diesem Online-Artikel" (Spiegel von public.product_online_links, ADR-019).
/// Je Produkt und Haendler hoechstens eine aktive Zeile (der Server erzwingt es ueber einen Unique-Index). Der Nutzer
/// bestaetigt jede Zuordnung selbst, der Feed hat keine EAN, ein automatisches Matching waere unzuverlaessig.
@DataClassName('ProductOnlineLink')
class ProductOnlineLinks extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get productId => text()();

  /// 'billa' | 'spar' (Schluessel im Feed)
  TextColumn get store => text()();
  TextColumn get externalId => text()();

  /// Name des Online-Artikels bei der Bestaetigung, fuer die Anzeige, falls der Artikel aus dem Feed verschwindet.
  TextColumn get linkedName => text()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Zuletzt bekannter Preis eines verknuepften Online-Artikels, nur lokal (kein Sync, jedes Geraet holt ihn selbst aus
/// `online_prices`). So bleibt der Preis offline sichtbar, und ein aus dem Feed verschwundener Artikel zeigt seinen
/// letzten bekannten Preis als "zuletzt bekannt" (ADR-019: die Anzeige faellt sauber aus, statt zu verschwinden).
@DataClassName('OnlinePriceCacheRow')
class OnlinePriceCache extends Table {
  TextColumn get store => text()();
  TextColumn get externalId => text()();
  TextColumn get name => text()();

  /// null, wenn der Artikel nie mit Preis geholt werden konnte.
  IntColumn get priceCents => integer().nullable()();
  RealColumn get quantity => real().nullable()();
  TextColumn get unit => text().nullable()();

  /// 'kg' | 'l' | 'stk', null bei unbekannter Einheit.
  TextColumn get baseUnit => text().nullable()();
  IntColumn get unitPriceNormCents => integer().nullable()();

  /// Beim letzten Abruf noch im Online-Sortiment (im Feed verfuegbar).
  BoolColumn get available => boolean().withDefault(const Constant(true))();

  /// Stand des Feeds selbst (Last-Modified) beim Abruf; Basis von "Stand vom ..." und "zuletzt bekannt".
  DateTimeColumn get feedUpdatedAt => dateTime().nullable()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {store, externalId};
}

/// Gedaechtnis des Haushalts: "diesen Namen habe ich diesem BLS-Eintrag zugeordnet" (Spiegel von public.household_food_links,
/// Phase N1, ADR-031). Der Server macht aus [nameNorm] den Schluessel (food_key), lokal steht zunaechst der Name, wie der Nutzer
/// ihn sah. Beim naechsten Foto sucht der Server zuerst hier.
@DataClassName('HouseholdFoodLink')
class HouseholdFoodLinks extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get nameNorm => text()();
  TextColumn get blsCode => text()();

  /// Eigenes Gewicht von 1 Stueck in g (essbarer Anteil), wenn der Haushalt es einmal angegeben hat (Phase N2, ADR-033).
  /// Es geht jedem Tabellenwert vor.
  RealColumn get unitWeightG => real().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Nahrungsergaenzung des Haushalts (Spiegel von public.supplements, Phase N4, ADR-035): Name, was eine Einheit ist und die
/// Mikronaehrstoffe je Einheit (absolute Mengen laut Packung, Schluessel des Registers).
@DataClassName('Supplement')
class Supplements extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get name => text()();
  TextColumn get servingLabel => text().withDefault(const Constant('Tablette'))();

  /// Mikronaehrstoffe je Einheit als JSON-Objekt (`jsonb` auf dem Server).
  TextColumn get micros => text().withDefault(const Constant('{}'))();
  TextColumn get note => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Eine Einnahme als Snapshot (Spiegel von public.supplement_intakes): Name und absolute Mengen fuer die genommenen Einheiten, damit
/// eine spaetere Aenderung der Ergaenzung die Vergangenheit nicht veraendert.
@DataClassName('SupplementIntake')
class SupplementIntakes extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get supplementId => text().nullable()();
  TextColumn get name => text()();
  DateTimeColumn get takenAt => dateTime()();
  RealColumn get servings => real().withDefault(const Constant(1.0))();
  TextColumn get micros => text().withDefault(const Constant('{}'))();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Ein geplantes Gericht im Wochenplan (Spiegel von public.meal_plan_entries, ADR-042). `plannedOn` ist die UTC-Mitternacht des
/// Kalendertags, die Zutaten sind eine JSON-Kopie (`domain/recipes/meal_plan.dart`).
@DataClassName('MealPlanEntry')
class MealPlanEntries extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  DateTimeColumn get plannedOn => dateTime()();
  TextColumn get slot => text().withDefault(const Constant('dinner'))();
  TextColumn get title => text()();
  TextColumn get ingredients => text().withDefault(const Constant('[]'))();
  TextColumn get sourceUrl => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Eine abgeschlossene Kochzeit (Spiegel von public.cooking_sessions, ADR-046). `activeSeconds` zaehlt ohne Pausen.
@DataClassName('CookingSession')
class CookingSessions extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get recipeTitle => text()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime()();
  IntColumn get activeSeconds => integer()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Gemeinsame Einstellungen des Haushalts als Schluessel-Wert-Zeilen (Spiegel von public.household_prefs, Phase N4, ADR-035).
@DataClassName('HouseholdPref')
class HouseholdPrefs extends Table {
  TextColumn get householdId => text()();
  TextColumn get key => text()();

  /// JSON-Wert (`jsonb` auf dem Server).
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {householdId, key};
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
  ReceiptFiles, InventoryItems, InventoryMovements, Meals, MealIngredients, NutritionTargetRows, BugReports,
  ShoppingLists, ShoppingListItems, ProductOnlineLinks, OnlinePriceCache, HouseholdFoodLinks, Supplements, SupplementIntakes, HouseholdPrefs, MealPlanEntries, CookingSessions, Outbox, SyncStates, KeyValues,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Dauerhafte Datenbank auf dem Geraet. `web:` wird nur fuer die iOS-PWA gebraucht (Doku 14
  /// iOS-Strategie, Option D) -- auf Android ohne Wirkung, drift_flutter waehlt je Plattform selbst
  /// die passende Umsetzung. Die WASM-Datei und der Worker liegen in `web/` (aus dem drift-Paket
  /// kopiert, siehe `tools/deploy_web.sh`-Kommentar).
  AppDatabase.persistent()
      : super(driftDatabase(
          name: 'einkaufstracker',
          web: DriftWebOptions(
            sqlite3Wasm: Uri.parse('sqlite3.wasm'),
            driftWorker: Uri.parse('drift_worker.js'),
          ),
        ));

  @override
  int get schemaVersion => 26;

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
          // 12 -> 13: ausgeschlossene Bon-Positionen (ADR-020)
          if (from < 13) {
            await m.addColumn(receiptItems, receiptItems.excluded);
          }
          // 13 -> 14: Essenstagebuch (Phase 7), Bewegungen kennen ihre Mahlzeit
          if (from < 14) {
            await m.createTable(meals);
            await m.createTable(mealIngredients);
            await m.addColumn(inventoryMovements, inventoryMovements.mealId);
          }
          // 14 -> 15: Richtwerte fuer die Naehrwerte (Phase 7d)
          if (from < 15) {
            await m.createTable(nutritionTargetRows);
          }
          // 15 -> 16: Online-Preise (ADR-019): Verknuepfung Produkt <-> Online-Artikel und lokaler Preis-Zwischenspeicher
          if (from < 16) {
            await m.createTable(productOnlineLinks);
            await m.createTable(onlinePriceCache);
          }
          // 16 -> 17: Zuordnung von Zutaten zur Lebensmitteldatenbank (Phase N1): BLS-Code und Sicherheit der Naehrwerte
          if (from < 17) {
            await m.addColumn(products, products.blsCode);
            // Installationen vor 14 haben die Zutaten-Tabelle oben schon mit den neuen Spalten angelegt bekommen
            if (from >= 14) {
              await m.addColumn(mealIngredients, mealIngredients.blsCode);
              await m.addColumn(mealIngredients, mealIngredients.nutrientBasis);
            }
            await m.createTable(householdFoodLinks);
          }
          // 17 -> 18: eigenes Stueckgewicht je Zuordnung (Phase N2). Installationen vor 17 legen die Tabelle oben schon mit
          // der Spalte an.
          if (from >= 17 && from < 18) {
            await m.addColumn(householdFoodLinks, householdFoodLinks.unitWeightG);
          }
          // 18 -> 19: Mikronaehrstoffe je Zutat (Phase N3). Installationen vor 14 legen die Zutaten-Tabelle oben schon mit der
          // Spalte an.
          if (from >= 14 && from < 19) {
            await m.addColumn(mealIngredients, mealIngredients.micros);
          }
          // 19 -> 20: Nahrungsergaenzung und gemeinsame Einstellungen des Haushalts (Phase N4)
          if (from < 20) {
            await m.createTable(supplements);
            await m.createTable(supplementIntakes);
            await m.createTable(householdPrefs);
          }
          // 20 -> 21: Zubereitung je Zutat fuer die Garfaktoren (Phase N4). Installationen vor 14 legen die Zutaten-Tabelle oben schon mit
          // der Spalte an.
          if (from >= 14 && from < 21) {
            await m.addColumn(mealIngredients, mealIngredients.preparation);
          }
          // 21 -> 22: Wochenplan (ADR-042)
          if (from < 22) {
            await m.createTable(mealPlanEntries);
          }
          // 22 -> 23: Einkaeufe archivieren (ADR-043). Installationen vor 10 legen die Tabelle oben schon mit der Spalte an.
          if (from >= 10 && from < 23) {
            await m.addColumn(shoppingListItems, shoppingListItems.archivedAt);
          }
          // 23 -> 24: Mehrfachpackungen (ADR-045)
          if (from < 24) {
            await m.addColumn(products, products.piecesPerPack);
            await m.addColumn(products, products.pieceLabel);
          }
          // 24 -> 25: Kochzeiten (ADR-046)
          if (from < 25) {
            await m.createTable(cookingSessions);
          }
          // 25 -> 26: Trinkbare Produkte (ADR-048)
          if (from < 26) {
            await m.addColumn(products, products.isDrink);
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
