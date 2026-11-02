import 'dart:io';
import 'dart:typed_data';

import 'package:einkaufstracker/core/clock.dart';
import 'package:flutter/widgets.dart' show BuildContext;

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:einkaufstracker/data/cloud/cooking_cloud.dart';
import 'package:einkaufstracker/data/cloud/meal_analysis_cloud.dart';
import 'package:einkaufstracker/data/files/meal_photo_service.dart';
import 'package:einkaufstracker/data/household/household_invites.dart';
import 'package:einkaufstracker/data/files/receipt_file_service.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/nutrition/bls_food_search.dart';
import 'package:einkaufstracker/data/nutrition/food_units_source.dart';
import 'package:einkaufstracker/domain/nutrition/food_unit.dart';
import 'package:einkaufstracker/data/online_prices/online_price_remote.dart';
import 'package:einkaufstracker/data/repositories/online_price_repository.dart';
import 'package:einkaufstracker/domain/online_prices/online_price.dart';
import 'package:einkaufstracker/data/pdf/pdf_text_reader.dart';
import 'package:einkaufstracker/domain/nutrition/meal_analysis.dart';
import 'package:einkaufstracker/domain/recipes/recipe_suggestion.dart';
import 'package:einkaufstracker/features/recipes/cooking_chat_panel.dart';
import 'package:einkaufstracker/data/remote/remote_store.dart';
import 'package:einkaufstracker/data/repositories/auth_repository.dart';
import 'package:einkaufstracker/data/repositories/category_repository.dart';
import 'package:einkaufstracker/data/barcode/barcode_scanner.dart';
import 'package:einkaufstracker/data/products/off_client.dart';
import 'package:einkaufstracker/data/repositories/bug_report_repository.dart';
import 'package:einkaufstracker/data/repositories/inventory_repository.dart';
import 'package:einkaufstracker/data/repositories/food_link_repository.dart';
import 'package:einkaufstracker/data/repositories/meal_repository.dart';
import 'package:einkaufstracker/data/repositories/nutrition_targets_repository.dart';
import 'package:einkaufstracker/data/repositories/product_repository.dart';
import 'package:einkaufstracker/data/repositories/receipt_repository.dart';
import 'package:einkaufstracker/data/repositories/settings_repository.dart';
import 'package:einkaufstracker/data/repositories/shopping_list_repository.dart';
import 'package:einkaufstracker/data/notifications/notification_scheduler.dart';
import 'package:einkaufstracker/domain/notifications/expiry_reminders.dart';

AppDatabase memoryDb() {
  // Mehrere In-Memory-Datenbanken je Test sind gewollt (simulieren mehrere Geraete)
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

/// Server-Attrappe im Speicher. Verhaelt sich wie Supabase: ein Trigger setzt updated_at bei jedem
/// Schreiben (streng monoton), Unique-Verletzung auf (household_id, name) bei categories.
class FakeRemoteStore implements RemoteStore {
  final Map<String, Map<String, Map<String, dynamic>>> tables = {};
  int _tick = 0;

  /// true = naechster Aufruf wirft einen Netzfehler
  bool offline = false;

  /// true = nur das Holen von Aenderungen scheitert (Senden geht): das Netz bricht zwischen Senden und Holen ab
  bool failFetch = false;

  int upsertCalls = 0;

  Map<String, Map<String, dynamic>> table(String name) => tables.putIfAbsent(name, () => {});

  @override
  Future<List<Map<String, dynamic>>> fetchChanges(String tableName,
      {String? since, int limit = 500, int offset = 0, List<String> orderKeys = const ['id']}) async {
    if (offline || failFetch) throw const SocketException('offline');
    final rows = table(tableName).values.where((r) => since == null || (r['updated_at'] as String).compareTo(since) >= 0).toList()
      ..sort((a, b) {
        final byTime = (a['updated_at'] as String).compareTo(b['updated_at'] as String);
        if (byTime != 0) return byTime;
        // wie ORDER BY updated_at, <Primaerschluessel> beim Server: stabile Reihenfolge bei gleichem Zeitstempel
        for (final k in orderKeys) {
          final c = '${a[k]}'.compareTo('${b[k]}');
          if (c != 0) return c;
        }
        return 0;
      });
    return rows.skip(offset).take(limit).map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Simuliert eine Server-Transaktion, die viele Zeilen auf einmal schreibt (z.B. eine Daten-Migration): alle Zeilen
  /// bekommen denselben `updated_at`, wie bei Postgres, wo now() innerhalb einer Transaktion konstant ist.
  String insertInOneTransaction(String tableName, List<Map<String, dynamic>> rows) {
    final stamp = DateTime.utc(2026, 9, 26, 12).add(Duration(seconds: ++_tick)).toIso8601String();
    for (final r in rows) {
      table(tableName)[r['id'] as String] = {...r, 'updated_at': stamp};
    }
    return stamp;
  }

  /// Wie oft [fetchUpdatedAt] gerufen wurde (Konflikterkennung beim Senden, ADR-018).
  int updatedAtLookups = 0;

  /// Tabellen, bei denen nur [fetchUpdatedAt] mit einem unerwarteten Fehler scheitert (z.B. Rechte); Senden und
  /// Holen gehen weiter.
  final failLookupFor = <String>{};

  @override
  Future<Map<String, String>> fetchUpdatedAt(String tableName, List<String> ids) async {
    if (offline) throw const SocketException('offline');
    updatedAtLookups++;
    if (failLookupFor.contains(tableName)) throw StateError('unerwartete Antwort');
    return {
      for (final id in ids)
        if (table(tableName)[id] case final row?) id: row['updated_at'] as String,
    };
  }

  /// Simuliert, dass ein anderes Geraet oder Haushaltsmitglied die Zeile beim Server geaendert hat (neuer `updated_at`,
  /// ohne dass dieses Geraet sie schon geholt haette).
  void simulateOtherEdit(String tableName, String id, Map<String, dynamic> changes) {
    final stored = table(tableName)[id]!;
    stored.addAll(changes);
    stored['updated_at'] = DateTime.utc(2026, 9, 26, 12).add(Duration(seconds: ++_tick)).toIso8601String();
  }

  @override
  Future<String?> upsert(String tableName, Map<String, dynamic> row) async {
    if (offline) throw const SocketException('offline');
    upsertCalls++;
    if (tableName == 'categories') {
      final clash = table(tableName).values.any((r) =>
          r['id'] != row['id'] && r['household_id'] == row['household_id'] && r['name'] == row['name']);
      if (clash) throw RemoteDataException('23505: duplicate key value violates unique constraint');
    }
    if (tableName == 'receipts' && row['external_id'] != null && row['deleted_at'] == null) {
      // wie der Unique-Index receipts_external_id_uniq: gleiche Re-Nr, anderer Datensatz, nicht geloescht
      final clash = table(tableName).values.any((r) =>
          r['id'] != row['id'] &&
          r['household_id'] == row['household_id'] &&
          r['external_id'] == row['external_id'] &&
          r['deleted_at'] == null);
      if (clash) throw RemoteDataException('23505: duplicate key value violates unique constraint receipts_external_id_uniq');
    }
    if (tableName == 'inventory_items') {
      // expires_on ist in Postgres eine generated column: hier nachgebildet, damit der zweite Sync in Tests
      // dasselbe Ergebnis liefert wie gegen den echten Server (siehe computeExpiresOn im Client).
      DateTime? date(String? s) => s == null ? null : DateTime.parse(s);
      final bestBefore = date(row['best_before'] as String?);
      final openedOn = date(row['opened_on'] as String?);
      final openDays = (row['open_shelf_life_days'] as num?)?.toInt();
      DateTime? expiresOn;
      if (openedOn != null && openDays != null) {
        final openExpiry = openedOn.add(Duration(days: openDays));
        expiresOn = bestBefore == null || openExpiry.isBefore(bestBefore) ? openExpiry : bestBefore;
      } else {
        expiresOn = bestBefore;
      }
      row = {...row, 'expires_on': expiresOn == null ? null : '${expiresOn.year.toString().padLeft(4, '0')}-${expiresOn.month.toString().padLeft(2, '0')}-${expiresOn.day.toString().padLeft(2, '0')}'};
    }
    final stored = Map<String, dynamic>.from(row);
    final stamp = DateTime.utc(2026, 9, 26, 12).add(Duration(seconds: ++_tick)).toIso8601String();
    stored['updated_at'] = stamp;
    // Tabellen ohne Spalte "id": zusammengesetzter bzw. Haushalts-Primaerschluessel wie am Server
    final key = switch (tableName) {
      'product_barcodes' => '${row['household_id']}:${row['ean']}',
      'nutrition_targets' => row['household_id'] as String,
      _ => row['id'] as String,
    };
    table(tableName)[key] = stored;
    return stamp;
  }
}

class FakeAuth implements AuthRepository {
  FakeAuth({this.failWith, this.failSignOutWith});
  String? failWith;

  /// Laesst nur `signOut()` scheitern (unabhaengig von [failWith], das signIn/deleteAccount betrifft) --
  /// fuer Tests, die pruefen, dass eine bereits erfolgreiche Konto-Loeschung trotzdem versucht, lokal
  /// aufzuraeumen (Codereview-Fund 2026-10-01).
  final String? failSignOutWith;
  final signIns = <(String, String)>[];

  @override
  String? get currentEmail => 'test@example.com';

  @override
  Future<void> signIn(String email, String password) async {
    signIns.add((email, password));
    if (failWith != null) throw SignInFailure(failWith!);
  }

  var signOutCalls = 0;

  @override
  Future<void> signOut() async {
    signOutCalls++;
    if (failSignOutWith != null) throw SignInFailure(failSignOutWith!);
  }

  var deleteAccountCalls = 0;

  @override
  Future<void> deleteAccount() async {
    deleteAccountCalls++;
    if (failWith != null) throw SignInFailure(failWith!);
  }
}

CategoryRepository categoryRepo(AppDatabase db, {String household = 'h1', void Function()? onChanged}) =>
    CategoryRepository(db, householdId: () async => household, onChanged: onChanged);

ReceiptRepository receiptRepo(
  AppDatabase db, {
  String household = 'h1',
  void Function()? onChanged,
  ProductRepository? productRepo,
  InventoryRepository? inventoryRepo,
  ShoppingListRepository? shoppingListRepo,
}) =>
    ReceiptRepository(
      db,
      householdId: () async => household,
      onChanged: onChanged,
      productRepo: productRepo,
      inventoryRepo: inventoryRepo,
      shoppingListRepo: shoppingListRepo,
    );

/// PDF-Leser-Attrappe: liefert den Text einer Fixture oder wirft.
class FakePdfReader implements PdfTextReader {
  FakePdfReader({this.text, this.error});
  final String? text;
  final PdfReadException? error;

  @override
  Future<String> readText(Uint8List bytes) async {
    if (error != null) throw error!;
    return text!;
  }
}

/// Die 17 Standardkategorien mit festen IDs ("cat:NAME"), damit mehrere Test-Geraete dieselben IDs haben.
const defaultCategoryNames = [
  'Obst', 'Gemüse', 'Fleisch & Wurst', 'Fisch', 'Milch & Milchprodukte', 'Eier', 'Brot & Backwaren', 'Käse',
  'Getränke', 'Tiefkühl', 'Konserven & Trockenware', 'Öle, Gewürze & Saucen', 'Süßes & Snacks', 'Fertiggerichte',
  'Haushalt & Drogerie', 'Pfand', 'Sonstiges',
];

Future<Map<String, String>> seedCategories(AppDatabase db, {String household = 'h1'}) async {
  final ids = <String, String>{};
  var order = 0;
  for (final name in defaultCategoryNames) {
    final id = 'cat:$name';
    ids[name] = id;
    await db.into(db.categories).insert(CategoriesCompanion.insert(
          id: id,
          householdId: household,
          name: name,
          updatedAt: DateTime.utc(2026),
          sortOrder: Value(order += 10),
          isStorable: Value(name != 'Pfand'), // wie supabase/migrations/0002_default_categories.sql
        ));
  }
  return ids;
}

/// Storage-Attrappe: Dateien im Speicher. [offline] laesst jeden Zugriff mit einem Netzfehler scheitern.
/// Beleg-Dienst ohne Dateizugriff, zaehlt nur, ob die lokalen Kopien geloescht wurden (Abmelden, Konto loeschen).
class FakeReceiptFileService extends ReceiptFileService {
  FakeReceiptFileService(AppDatabase db)
      : super(
          db: db,
          repo: receiptRepo(db),
          remote: FakeRemoteFileStore(),
          baseDir: () async => throw UnimplementedError('Datei-Zugriff im Widget-Test'),
          keepFiles: () async => true,
        );

  var deleteAllLocalCalls = 0;

  @override
  Future<void> deleteAllLocal() async => deleteAllLocalCalls++;
}

class FakeRemoteFileStore implements RemoteFileStore {
  final Map<String, Uint8List> files = {};
  final Map<String, String> contentTypes = {};
  bool offline = false;
  int uploads = 0;

  /// Laesst `upload()` warten, bis dieser Future abgeschlossen ist -- simuliert einen langsamen Netz-Upload,
  /// um die Race Condition zwischen `uploadPending()` und einem parallelen `attach()` testbar zu machen
  /// (Codereview-Fund 2026-10-01).
  Future<void>? uploadGate;

  @override
  Future<void> upload(String path, Uint8List bytes, String contentType) async {
    if (offline) throw const SocketException('offline');
    if (uploadGate != null) await uploadGate;
    uploads++;
    files[path] = bytes;
    contentTypes[path] = contentType;
  }

  @override
  Future<Uint8List> download(String path) async {
    if (offline) throw const SocketException('offline');
    final f = files[path];
    if (f == null) throw StateError('not found: $path');
    return f;
  }

  @override
  Future<void> remove(List<String> paths) async {
    if (offline) throw const SocketException('offline');
    for (final p in paths) {
      files.remove(p);
    }
  }
}

/// Ablage der Originalbelege mit Temp-Ordner. [keep] steuert die Einstellung "Bon-Fotos speichern".
ReceiptFileService fileService(AppDatabase db, FakeRemoteFileStore remote, Directory dir,
        {bool keep = true, String household = 'h1', ReceiptRepository? repo}) =>
    ReceiptFileService(
      db: db,
      repo: repo ?? receiptRepo(db, household: household),
      remote: remote,
      baseDir: () async => dir,
      keepFiles: () async => keep,
    );

/// Essensfotos mit Temp-Ordner; [prepare] ist standardmaessig die Identitaet (kein Isolate, kein JPEG noetig).
MealPhotoService mealPhotoService(AppDatabase db, FakeRemoteFileStore remote, Directory dir,
        {String household = 'h1', MealRepository? meals, Future<Uint8List> Function(Uint8List)? prepare}) =>
    MealPhotoService(
      db: db,
      meals: meals ?? mealRepo(db, household: household),
      remote: remote,
      baseDir: () async => dir,
      prepare: prepare ?? (b) async => b,
    );

/// Foto-Dienst im Speicher fuer Widget-Tests: dart:io laeuft unter `testWidgets` nicht in der simulierten Zeit. Das
/// Dateiverhalten selbst ist in `meal_photo_service_test.dart` mit echten Dateien abgedeckt.
class FakeMealPhotoService extends MealPhotoService {
  FakeMealPhotoService(AppDatabase db, MealRepository meals, {Future<Uint8List> Function(Uint8List)? prepare})
      : super(
          db: db,
          meals: meals,
          remote: FakeRemoteFileStore(),
          baseDir: () async => throw UnimplementedError('Datei-Zugriff im Widget-Test'),
          prepare: prepare ?? (b) async => b,
        );

  /// Mahlzeit-ID -> Foto
  final photos = <String, Uint8List>{};
  final attached = <({String mealId, Uint8List bytes, bool prepared})>[];
  final purged = <({String mealId, bool clearPath})>[];

  /// Wenn gesetzt, wirft [attach] diesen Fehler.
  Object? attachError;

  var deleteAllLocalCalls = 0;

  @override
  Future<void> deleteAllLocal() async {
    deleteAllLocalCalls++;
    photos.clear();
  }

  @override
  Future<void> attach(Meal meal, Uint8List photo, {bool prepared = false}) async {
    if (attachError != null) throw attachError!;
    photos[meal.id] = photo;
    attached.add((mealId: meal.id, bytes: photo, prepared: prepared));
    await meals.setPhotoPath(meal.id, MealPhotoService.storagePathOf(meal.householdId, meal.id));
  }

  @override
  Future<Uint8List?> bytes(Meal meal) async => meal.photoPath == null ? null : photos[meal.id];

  @override
  Future<void> purge(Meal meal, {bool clearPath = false}) async {
    photos.remove(meal.id);
    purged.add((mealId: meal.id, clearPath: clearPath));
    if (clearPath) await meals.setPhotoPath(meal.id, null);
  }

  @override
  Future<int> uploadPending() async => 0;
}

ProductRepository productRepo(AppDatabase db, {String household = 'h1', OffClient? off, void Function()? onChanged}) =>
    ProductRepository(db, householdId: () async => household, off: off, onChanged: onChanged);

InventoryRepository inventoryRepo(AppDatabase db,
        {String household = 'h1', void Function()? onChanged, Future<void> Function(String productId)? onDepleted}) =>
    InventoryRepository(db, householdId: () async => household, onChanged: onChanged, onDepleted: onDepleted);

MealRepository mealRepo(AppDatabase db, {String household = 'h1', void Function()? onChanged, InventoryRepository? inventory}) =>
    MealRepository(db, householdId: () async => household, inventory: inventory ?? inventoryRepo(db, household: household), onChanged: onChanged);

FoodLinkRepository foodLinkRepo(AppDatabase db, {String household = 'h1', void Function()? onChanged}) =>
    FoodLinkRepository(db, householdId: () async => household, onChanged: onChanged);

NutritionTargetsRepository nutritionTargetsRepo(AppDatabase db, {String household = 'h1', void Function()? onChanged}) =>
    NutritionTargetsRepository(db, householdId: () async => household, onChanged: onChanged);

ShoppingListRepository shoppingListRepo(AppDatabase db, {String household = 'h1', void Function()? onChanged}) =>
    ShoppingListRepository(db, householdId: () async => household, onChanged: onChanged);

/// Einstellungen-Attrappe (die echte Implementierung ist online-only ueber Supabase).
class FakeSettingsRepository implements SettingsRepository {
  FakeSettingsRepository(this.settings);
  HouseholdSettings settings;
  Map<String, dynamic>? lastUpdate;

  /// Wenn gesetzt, wirft [load] diesen Fehler (kein Netz).
  Object? loadError;

  @override
  Future<HouseholdSettings> load(String householdId) async {
    if (loadError != null) throw loadError!;
    return settings;
  }

  @override
  Future<void> update(String householdId, Map<String, dynamic> changes) async {
    lastUpdate = changes;
  }
}

/// Benachrichtigungs-Attrappe: haelt den zuletzt geplanten Stand fest, ohne Plattform-Kanaele
/// (flutter_local_notifications hat keinen Testmodus fuer `flutter test`).
class FakeNotificationScheduler implements NotificationScheduler {
  List<ExpiryReminderDay>? lastScheduled;
  String? lastNotifyTime;
  int? lastLeadDays;
  var initializeCalls = 0;
  var cancelCalls = 0;

  @override
  Future<void> initialize() async => initializeCalls++;

  @override
  Future<void> cancelExpiryReminders() async {
    cancelCalls++;
    lastScheduled = const [];
  }

  @override
  Future<void> scheduleExpiryReminders(List<ExpiryReminderDay> reminders, {required String notifyTime, required int leadDays}) async {
    lastScheduled = reminders;
    lastNotifyTime = notifyTime;
    lastLeadDays = leadDays;
  }
}

/// Barcode-Scanner-Attrappe: liefert immer denselben Code (oder null bei Abbruch).
class FakeBarcodeScanner implements BarcodeScanner {
  FakeBarcodeScanner(this.code);
  final String? code;
  int calls = 0;

  @override
  Future<String?> scan(BuildContext context) async {
    calls++;
    return code;
  }
}

/// OFF-Client-Attrappe fuer Tests.
class FakeOffClient implements OffClient {
  FakeOffClient([this.result]);
  OffProduct? result;

  @override
  Future<OffProduct?> lookup(String ean) async => result;
}

BugReportRepository bugReportRepo(AppDatabase db, {String household = 'h1', void Function()? onChanged}) =>
    BugReportRepository(db, householdId: () async => household, onChanged: onChanged);

/// Attrappe fuer die Online-Suche in der Lebensmitteldatenbank (BLS, ADR-024, Zuordnung Phase N1). Die Reihung der echten
/// Suche steckt im Server; hier genuegt: Treffer enthaelt die Eingabe, Namen mit der Eingabe am Anfang zuerst.
class FakeBlsFoodSearch implements BlsFoodSearch {
  FakeBlsFoodSearch({this.foods = const [], this.fail = false, Map<String, List<BlsFood>>? resolved}) : resolved = resolved ?? {};

  List<BlsFood> foods;

  /// Vorgegebene Antworten von [resolve] je Name (kleingeschrieben); ohne Eintrag ist die Antwort leer.
  Map<String, List<BlsFood>> resolved;

  /// true = Suche meldet [BlsSearchUnavailable]
  bool fail;
  final queries = <String>[];
  final resolveQueries = <String>[];

  @override
  Future<List<BlsFood>> search(String query) async {
    queries.add(query);
    if (fail) throw const BlsSearchUnavailable();
    final q = query.trim().toLowerCase();
    final hits = foods.where((f) => f.nameDe.toLowerCase().contains(q)).toList()
      ..sort((a, b) {
        final byStart = (a.nameDe.toLowerCase().startsWith(q) ? 0 : 1).compareTo(b.nameDe.toLowerCase().startsWith(q) ? 0 : 1);
        return byStart != 0 ? byStart : a.nameDe.length.compareTo(b.nameDe.length);
      });
    return hits.take(blsSearchMaxResults).toList();
  }

  /// Angefragte Code-Listen von [byCodes].
  final codeQueries = <List<String>>[];

  @override
  Future<List<BlsFood>> byCodes(Iterable<String> codes) async {
    codeQueries.add(codes.toList());
    if (fail) throw const BlsSearchUnavailable();
    final wanted = codes.toSet();
    return [...foods, for (final l in resolved.values) ...l].where((f) => wanted.contains(f.code)).toList();
  }

  @override
  Future<List<BlsFood>> resolve(String name, {int limit = 3}) async {
    resolveQueries.add(name);
    if (fail) throw const BlsSearchUnavailable();
    return (resolved[name.trim().toLowerCase()] ?? const <BlsFood>[]).take(limit).toList();
  }
}

/// Attrappe fuer die Haushaltsmasse (`food_units`, Phase N2): je BLS-Code vorgegebene Einheiten, sonst leer.
class FakeFoodUnitsSource implements FoodUnitsSource {
  FakeFoodUnitsSource([Map<String, List<FoodUnit>>? units]) : units = units ?? {};

  Map<String, List<FoodUnit>> units;
  final requested = <String>[];

  /// true = Abfrage scheitert (kein Netz): wie in der echten Fassung bleibt die Liste dann leer
  bool fail = false;

  @override
  Future<List<FoodUnit>> unitsFor(String blsCode) async {
    requested.add(blsCode);
    if (fail) return const [];
    return units[blsCode] ?? const [];
  }
}

/// Banane (F503100) mit Groessen und ein Brot (B311000) mit Scheibe, wie in der Tabelle `food_units`.
Map<String, List<FoodUnit>> sampleFoodUnits() => {
      'F503100': const [
        FoodUnit(blsCode: 'F503100', key: FoodUnitKey.piece, size: UnitSize.small, gramsEdible: 101),
        FoodUnit(blsCode: 'F503100', key: FoodUnitKey.piece, size: UnitSize.medium, gramsEdible: 118),
        FoodUnit(blsCode: 'F503100', key: FoodUnitKey.piece, size: UnitSize.large, gramsEdible: 136),
      ],
      'B311000': const [FoodUnit(blsCode: 'B311000', key: FoodUnitKey.slice, gramsEdible: 28)],
      'Q120000': const [
        FoodUnit(blsCode: 'Q120000', key: FoodUnitKey.tbsp, gramsEdible: 13.5),
        FoodUnit(blsCode: 'Q120000', key: FoodUnitKey.tsp, gramsEdible: 4.5),
      ],
    };

/// Attrappe fuer die Online-Preise (Tabelle `online_prices`, ADR-019): ein Sortiment im Speicher, durchsucht nach
/// Namensbestandteilen, mit Netzfehler zum Einschalten.
class FakeOnlinePriceRemote implements OnlinePriceRemote {
  FakeOnlinePriceRemote({List<OnlineArticle> articles = const [], this.feedLastModified}) : articles = [...articles];

  /// Das Online-Sortiment. Ein Artikel, der hier fehlt, gilt beim Abruf als aus dem Feed verschwunden.
  List<OnlineArticle> articles;

  /// Stand des Feeds, `null` = der Server war noch nie erfolgreich.
  DateTime? feedLastModified;

  /// true = Suche und Abruf melden [OnlinePricesUnavailable]
  bool fail = false;

  final searches = <({String query, List<String> stores, int perStore, String? preferBase})>[];
  var fetchCalls = 0;

  @override
  Future<List<OnlineArticle>> search(String query, {List<String> stores = const ['billa', 'spar'], int perStore = 8, String? preferBase}) async {
    searches.add((query: query, stores: stores, perStore: perStore, preferBase: preferBase));
    if (fail) throw const OnlinePricesUnavailable();
    final words = query.toLowerCase().split(RegExp(r'[^a-zäöüß]+')).where((w) => w.length >= 2).toList();
    return [
      for (final a in articles)
        if (stores.contains(a.store) && words.any((w) => a.name.toLowerCase().contains(w))) a,
    ];
  }

  @override
  Future<OnlineFetchResult> fetch(List<({String store, String externalId})> links) async {
    fetchCalls++;
    if (fail) throw const OnlinePricesUnavailable();
    final wanted = {for (final l in links) onlineKey(l.store, l.externalId)};
    return OnlineFetchResult(
      found: {for (final a in articles) if (wanted.contains(onlineKey(a.store, a.externalId))) onlineKey(a.store, a.externalId): a},
      feedLastModified: feedLastModified,
    );
  }
}

/// Ein Online-Artikel fuer Tests, Vollmilch bei Billa als Standard.
OnlineArticle onlineArticle({
  String store = 'billa',
  String externalId = '00-1',
  String name = 'Clever Vollmilch',
  int priceCents = 132,
  double? quantity = 1,
  String? unit = 'l',
  String? baseUnit = 'l',
  int? unitPriceNormCents = 132,
  DateTime? seenAt,
}) =>
    OnlineArticle(
      store: store,
      externalId: externalId,
      name: name,
      priceCents: priceCents,
      quantity: quantity,
      unit: unit,
      baseUnit: baseUnit,
      unitPriceNormCents: unitPriceNormCents,
      seenAt: seenAt,
    );

OnlinePriceRepository onlinePriceRepo(AppDatabase db, OnlinePriceRemote remote,
        {String household = 'h1', void Function()? onChanged, DateTime Function()? now}) =>
    OnlinePriceRepository(db, remote, householdId: () async => household, onChanged: onChanged, now: now);

/// Cloud-Attrappe fuer Rezeptvorschlaege/Koch-Chat (ADR-021).
class FakeCookingCloud implements CookingCloud {
  FakeCookingCloud({this.suggestions = const [], this.chatReply = 'ok', this.error});

  String? lastDish;

  List<RecipeSuggestion> suggestions;
  String chatReply;
  Exception? error;

  int suggestCalls = 0;
  List<SuggestionIngredient>? lastIngredients;
  bool? lastAllowMissing;
  int chatCalls = 0;
  String? lastMessage;
  CookingChatContext? lastContext;

  @override
  Future<List<RecipeSuggestion>> suggestRecipes(List<SuggestionIngredient> ingredients, {bool allowMissing = false, String? dish}) async {
    suggestCalls++;
    lastIngredients = ingredients;
    lastAllowMissing = allowMissing;
    lastDish = dish;
    if (error != null) throw error!;
    return suggestions;
  }

  @override
  Future<String> chat(String message, CookingChatContext context) async {
    chatCalls++;
    lastMessage = message;
    lastContext = context;
    if (error != null) throw error!;
    return chatReply;
  }
}

/// Cloud-Attrappe fuer die Foto-Analyse einer Mahlzeit (Phase 7c).
class FakeMealAnalysisCloud implements MealAnalysisCloud {
  FakeMealAnalysisCloud({this.analysis = const MealAnalysis(), this.error});

  MealAnalysis analysis;
  Object? error;

  int calls = 0;
  Uint8List? lastPhoto;
  List<AnalysisProduct>? lastProducts;
  MealAnalysisContext? lastContext;

  @override
  Future<MealAnalysis> analyze(Uint8List photo, List<AnalysisProduct> products, {MealAnalysisContext context = const MealAnalysisContext()}) async {
    calls++;
    lastPhoto = photo;
    lastProducts = products;
    lastContext = context;
    if (error != null) throw error!;
    return analysis;
  }
}

/// Einladungen im Speicher (Phase 6). [failWith] laesst den naechsten Aufruf scheitern.
class FakeHouseholdInviteRepository implements HouseholdInviteRepository {
  FakeHouseholdInviteRepository({List<HouseholdInvite>? invites, this.members = 1}) : invites = invites ?? [];

  final List<HouseholdInvite> invites;
  int members;
  InviteFailure? failWith;
  final created = <String>[];
  final revoked = <String>[];
  var _n = 0;

  @override
  Future<List<HouseholdInvite>> pending() async {
    if (failWith != null) throw failWith!;
    return List.of(invites);
  }

  @override
  Future<HouseholdInvite> create(String email) async {
    if (failWith != null) throw failWith!;
    created.add(email);
    _n++;
    final invite = HouseholdInvite(
      id: 'inv$_n',
      email: email,
      token: 'ABCDEFGHJKM${'NPQRSTUVWXYZ'[_n % 12]}',
      expiresAt: appClock.now().toUtc().add(const Duration(days: 7)),
      createdAt: appClock.now().toUtc(),
    );
    invites.insert(0, invite);
    return invite;
  }

  @override
  Future<void> revoke(String id) async {
    if (failWith != null) throw failWith!;
    revoked.add(id);
    invites.removeWhere((i) => i.id == id);
  }

  var memberCountCalls = 0;

  @override
  Future<int> memberCount() async {
    memberCountCalls++;
    if (failWith != null) throw failWith!;
    return members;
  }
}

/// "Einladung annehmen" ohne Netz: merkt sich die Aufrufe, scheitert auf Wunsch.
class FakeAcceptInviteApi implements AcceptInviteApi {
  InviteFailure? error;
  final calls = <({String code, String email, String password})>[];

  @override
  Future<void> accept({required String code, required String email, required String password}) async {
    calls.add((code: code, email: email, password: password));
    if (error != null) throw error!;
  }
}
