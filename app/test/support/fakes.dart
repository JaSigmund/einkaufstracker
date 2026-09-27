import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show BuildContext;

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:einkaufstracker/data/files/receipt_file_service.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/pdf/pdf_text_reader.dart';
import 'package:einkaufstracker/data/remote/remote_store.dart';
import 'package:einkaufstracker/data/repositories/auth_repository.dart';
import 'package:einkaufstracker/data/repositories/category_repository.dart';
import 'package:einkaufstracker/data/barcode/barcode_scanner.dart';
import 'package:einkaufstracker/data/products/off_client.dart';
import 'package:einkaufstracker/data/repositories/bug_report_repository.dart';
import 'package:einkaufstracker/data/repositories/inventory_repository.dart';
import 'package:einkaufstracker/data/repositories/product_repository.dart';
import 'package:einkaufstracker/data/repositories/receipt_repository.dart';

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

  int upsertCalls = 0;

  Map<String, Map<String, dynamic>> table(String name) => tables.putIfAbsent(name, () => {});

  @override
  Future<List<Map<String, dynamic>>> fetchChanges(String tableName, {String? since, int limit = 500}) async {
    if (offline) throw const SocketException('offline');
    final rows = table(tableName).values.where((r) => since == null || (r['updated_at'] as String).compareTo(since) >= 0).toList()
      ..sort((a, b) => (a['updated_at'] as String).compareTo(b['updated_at'] as String));
    return rows.take(limit).map((r) => Map<String, dynamic>.from(r)).toList();
  }

  @override
  Future<void> upsert(String tableName, Map<String, dynamic> row) async {
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
    stored['updated_at'] = DateTime.utc(2026, 9, 26, 12).add(Duration(seconds: ++_tick)).toIso8601String();
    final key = tableName == 'product_barcodes' ? '${row['household_id']}:${row['ean']}' : row['id'] as String;
    table(tableName)[key] = stored;
  }
}

class FakeAuth implements AuthRepository {
  FakeAuth({this.failWith});
  final String? failWith;
  final signIns = <(String, String)>[];

  @override
  String? get currentEmail => 'test@example.com';

  @override
  Future<void> signIn(String email, String password) async {
    signIns.add((email, password));
    if (failWith != null) throw SignInFailure(failWith!);
  }

  @override
  Future<void> signOut() async {}
}

CategoryRepository categoryRepo(AppDatabase db, {String household = 'h1', void Function()? onChanged}) =>
    CategoryRepository(db, householdId: () async => household, onChanged: onChanged);

ReceiptRepository receiptRepo(
  AppDatabase db, {
  String household = 'h1',
  void Function()? onChanged,
  ProductRepository? productRepo,
  InventoryRepository? inventoryRepo,
}) =>
    ReceiptRepository(
      db,
      householdId: () async => household,
      onChanged: onChanged,
      productRepo: productRepo,
      inventoryRepo: inventoryRepo,
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
class FakeRemoteFileStore implements RemoteFileStore {
  final Map<String, Uint8List> files = {};
  final Map<String, String> contentTypes = {};
  bool offline = false;
  int uploads = 0;

  @override
  Future<void> upload(String path, Uint8List bytes, String contentType) async {
    if (offline) throw const SocketException('offline');
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

ProductRepository productRepo(AppDatabase db, {String household = 'h1', OffClient? off, void Function()? onChanged}) =>
    ProductRepository(db, householdId: () async => household, off: off, onChanged: onChanged);

InventoryRepository inventoryRepo(AppDatabase db, {String household = 'h1', void Function()? onChanged}) =>
    InventoryRepository(db, householdId: () async => household, onChanged: onChanged);

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
