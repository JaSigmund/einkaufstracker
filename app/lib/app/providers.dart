import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/files/receipt_file_service.dart';
import '../data/local/database.dart';
import '../data/cloud/cloud_receipt.dart';
import '../data/cloud/supabase_cloud_receipt_reader.dart';
import '../data/ocr/image_prep.dart';
import '../data/ocr/mlkit_receipt_scanner.dart';
import '../data/remote/remote_store.dart';
import '../data/repositories/auth_repository.dart';
import '../data/pdf/pdf_text_reader.dart';
import '../data/products/off_client.dart';
import '../data/barcode/barcode_scanner.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/inventory_repository.dart';
import '../data/repositories/product_repository.dart';
import '../data/share/shared_pdf_source.dart';
import '../data/repositories/receipt_repository.dart';
import '../features/receipt_import/photo_receipt_service.dart';
import '../features/receipt_import/receipt_import_service.dart';
import '../data/repositories/settings_repository.dart';
import '../data/sync/sync_engine.dart';

/// Wird in main() mit der echten (bzw. in Tests mit einer In-Memory-) Datenbank ueberschrieben.
final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError('databaseProvider nicht ueberschrieben'));

final supabaseClientProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

final authRepositoryProvider =
    Provider<AuthRepository>((ref) => SupabaseAuthRepository(ref.watch(supabaseClientProvider)));

final settingsRepositoryProvider =
    Provider<SettingsRepository>((ref) => SupabaseSettingsRepository(ref.watch(supabaseClientProvider)));

/// Aktuelle Sitzung (null = nicht angemeldet). Die Sitzung liegt lokal, der Start klappt auch offline.
final sessionProvider = StreamProvider<Session?>((ref) async* {
  final auth = ref.watch(supabaseClientProvider).auth;
  yield auth.currentSession;
  await for (final e in auth.onAuthStateChange) {
    yield e.session;
  }
});

/// Haushalt des angemeldeten Nutzers. Zuerst vom Server, bei fehlendem Netz aus dem lokalen Cache
/// (nur wenn er zum selben Nutzer gehoert).
final householdIdProvider = FutureProvider<String?>((ref) async {
  final session = ref.watch(sessionProvider).value;
  if (session == null) return null;
  final db = ref.watch(databaseProvider);
  final uid = session.user.id;
  final cachedUser = await db.getKv('household_user');
  final cachedHousehold = await db.getKv('household_id');
  try {
    final rows = await ref
        .watch(supabaseClientProvider)
        .from('household_members')
        .select('household_id')
        .eq('user_id', uid)
        .limit(1);
    if (rows.isNotEmpty) {
      final hid = rows.first['household_id'] as String;
      await db.setKv('household_user', uid);
      await db.setKv('household_id', hid);
      return hid;
    }
    return null;
  } catch (_) {
    if (cachedUser == uid) return cachedHousehold;
    rethrow;
  }
});

final remoteStoreProvider = Provider<RemoteStore>((ref) => SupabaseRemoteStore(ref.watch(supabaseClientProvider)));

final syncEngineProvider = Provider<SyncEngine>((ref) => SyncEngine(ref.watch(databaseProvider), ref.watch(remoteStoreProvider)));

class SyncStatus {
  const SyncStatus({this.lastSync, this.error, this.running = false});
  final DateTime? lastSync;
  final String? error;
  final bool running;
}

class SyncController extends Notifier<SyncStatus> {
  Timer? _retry;

  @override
  SyncStatus build() {
    ref.onDispose(() => _retry?.cancel());
    return const SyncStatus();
  }

  Future<void> sync() async {
    final engine = ref.read(syncEngineProvider);
    if (engine.isRunning) return;
    if (ref.read(sessionProvider).value == null) return;
    state = SyncStatus(lastSync: state.lastSync, running: true);
    try {
      await engine.sync();
      state = SyncStatus(lastSync: DateTime.now());
      // Kategorien oder Aliase koennen eben erst angekommen sein: bisher unzugeordnete Artikel nachziehen.
      // Aendert sich nichts, gibt es keine Folge-Synchronisation, also keine Schleife.
      await ref.read(receiptRepositoryProvider).categorizeMissing();
      // Wartende Belege (Fotos, PDFs) hochladen, jetzt wo das Netz da ist
      await ref.read(receiptFileServiceProvider).uploadPending();
    } catch (e) {
      state = SyncStatus(lastSync: state.lastSync, error: _friendly(e));
      // Netz war (noch) nicht da: nach kurzer Zeit erneut versuchen, statt auf den naechsten Anlass zu warten
      _retry?.cancel();
      _retry = Timer(const Duration(seconds: 15), sync);
    }
  }

  String _friendly(Object e) {
    if (e is SocketException || e.toString().contains('ClientException') || e.toString().contains('SocketException')) {
      return 'Kein Netz, Aenderungen werden spaeter gesendet.';
    }
    if (e is AuthException) return 'Anmeldung abgelaufen, bitte neu anmelden.';
    return e.toString();
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncStatus>(SyncController.new);

/// Anzahl der Aenderungen, die noch nicht beim Server angekommen sind.
final pendingChangesProvider =
    StreamProvider<int>((ref) => ref.watch(databaseProvider).select(ref.watch(databaseProvider).outbox).watch().map((l) => l.length));

final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  return CategoryRepository(
    ref.watch(databaseProvider),
    householdId: () async {
      final id = await ref.read(householdIdProvider.future);
      if (id == null) throw StateError('Kein Haushalt gefunden');
      return id;
    },
    onChanged: () => ref.read(syncControllerProvider.notifier).sync(),
  );
});

final categoriesStreamProvider = StreamProvider((ref) => ref.watch(categoryRepositoryProvider).watchAll());

final offClientProvider = Provider<OffClient>((ref) => HttpOffClient());

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepository(
    ref.watch(databaseProvider),
    householdId: () async {
      final id = await ref.read(householdIdProvider.future);
      if (id == null) throw StateError('Kein Haushalt gefunden');
      return id;
    },
    off: ref.watch(offClientProvider),
    onChanged: () => ref.read(syncControllerProvider.notifier).sync(),
  );
});

final productsStreamProvider = StreamProvider((ref) => ref.watch(productRepositoryProvider).watchAll());

final barcodeScannerProvider = Provider<BarcodeScanner>((ref) => MobileBarcodeScanner());

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  return InventoryRepository(
    ref.watch(databaseProvider),
    householdId: () async {
      final id = await ref.read(householdIdProvider.future);
      if (id == null) throw StateError('Kein Haushalt gefunden');
      return id;
    },
    onChanged: () => ref.read(syncControllerProvider.notifier).sync(),
  );
});

final activeInventoryStreamProvider = StreamProvider((ref) => ref.watch(inventoryRepositoryProvider).watchActive());
final inventorySuggestionsStreamProvider = StreamProvider((ref) => ref.watch(inventoryRepositoryProvider).watchSuggestions());

final receiptRepositoryProvider = Provider<ReceiptRepository>((ref) {
  return ReceiptRepository(
    ref.watch(databaseProvider),
    householdId: () async {
      final id = await ref.read(householdIdProvider.future);
      if (id == null) throw StateError('Kein Haushalt gefunden');
      return id;
    },
    onChanged: () => ref.read(syncControllerProvider.notifier).sync(),
  );
});

final receiptsStreamProvider = StreamProvider((ref) => ref.watch(receiptRepositoryProvider).watchAll());

final storesStreamProvider = StreamProvider((ref) => ref.watch(receiptRepositoryProvider).watchStores());

final allItemsStreamProvider = StreamProvider((ref) => ref.watch(receiptRepositoryProvider).watchAllItems());

final receiptProvider =
    StreamProvider.family((ref, String id) => ref.watch(receiptRepositoryProvider).watchReceipt(id));

final receiptItemsProvider =
    StreamProvider.family((ref, String id) => ref.watch(receiptRepositoryProvider).watchItems(id));

final sharedPdfSourceProvider = Provider<SharedPdfSource>((ref) => AndroidSharedPdfSource());

final pdfTextReaderProvider = Provider<PdfTextReader>((ref) => const PdfrxTextReader());

final remoteFileStoreProvider = Provider<RemoteFileStore>((ref) => SupabaseFileStore(ref.watch(supabaseClientProvider)));

/// Originalbelege (Foto ohne Zahlungsblock, PDF): lokal ablegen, danach in den Storage hochladen.
final receiptFileServiceProvider = Provider<ReceiptFileService>((ref) {
  final db = ref.watch(databaseProvider);
  return ReceiptFileService(
    db: db,
    repo: ref.watch(receiptRepositoryProvider),
    remote: ref.watch(remoteFileStoreProvider),
    baseDir: getApplicationDocumentsDirectory,
    // Einstellung "Bon-Fotos speichern" liegt auf dem Server. Offline gilt der zuletzt bekannte Wert (Standard: an).
    keepFiles: () async {
      const key = 'keep_receipt_files';
      try {
        final id = await ref.read(householdIdProvider.future);
        if (id == null) return true;
        final keep = (await ref.read(settingsRepositoryProvider).load(id)).keepReceiptImages;
        await db.setKv(key, keep.toString());
        return keep;
      } catch (_) {
        return (await db.getKv(key)) != 'false';
      }
    },
  );
});

final receiptFilesStreamProvider =
    StreamProvider.family((ref, String receiptId) => ref.watch(receiptRepositoryProvider).watchFiles(receiptId));

final receiptImportServiceProvider = Provider<ReceiptImportService>(
  (ref) => ReceiptImportService(
    ref.watch(pdfTextReaderProvider),
    ref.watch(receiptRepositoryProvider),
    files: ref.watch(receiptFileServiceProvider),
    prepareImage: prepareForStorage,
  ),
);

final receiptScannerProvider = Provider<ReceiptScanner>((ref) => MlKitReceiptScanner());

final cloudReceiptReaderProvider = Provider<CloudReceiptReader>(
  (ref) => SupabaseCloudReceiptReader(ref.watch(supabaseClientProvider), () async {
    final id = await ref.read(householdIdProvider.future);
    if (id == null) throw const CloudUnavailable('kein Haushalt');
    return id;
  }),
);

final photoReceiptServiceProvider = Provider<PhotoReceiptService>(
  (ref) => PhotoReceiptService(
    repo: ref.watch(receiptRepositoryProvider),
    cloud: ref.watch(cloudReceiptReaderProvider),
    // Einwilligung liegt beim Server (household_settings)
    cloudAllowed: () async {
      try {
        final id = await ref.read(householdIdProvider.future);
        if (id == null) return false;
        return (await ref.read(settingsRepositoryProvider).load(id)).allowCloudOcr;
      } catch (_) {
        // Einwilligung nicht abrufbar = kein Netz: das ist etwas anderes als "ausgeschaltet"
        throw const CloudUnavailable('kein Netz');
      }
    },
    prepare: prepareForCloud,
  ),
);
