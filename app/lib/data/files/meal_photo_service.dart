import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../../core/async_lock.dart';
import '../local/database.dart';
import '../ocr/image_prep.dart';
import '../repositories/meal_repository.dart';
import 'receipt_file_service.dart' show RemoteFileStore;

/// Laengste Kante und Groessengrenze eines Essensfotos (Doku 15 §12: max. 1600 px, JPEG ca. 300 KB).
const mealPhotoMaxEdge = 1600;
const mealPhotoMaxBytes = 400000;

/// Verkleinert ein Foto fuers Tagebuch. Laeuft in einem eigenen Isolate, damit die Oberflaeche nicht ruckelt.
Future<Uint8List> prepareMealPhoto(Uint8List bytes) =>
    Isolate.run(() => prepareForCloudBytes(bytes, maxEdge: mealPhotoMaxEdge, maxBytes: mealPhotoMaxBytes));

/// Essensfotos zu Mahlzeiten (Doku 15 §3.1): sofort lokal im App-Ordner, danach im privaten Bucket `meals`
/// (`{household_id}/{meal_id}.jpg`). Der Upload laeuft offline-tauglich ueber eine Warteschlange und wird nach jedem
/// Sync fortgesetzt, genau wie bei den Belegfotos ([ReceiptFileService]). Anders als dort gibt es keine
/// Server-Einstellung: das Foto entsteht durch eine ausdrueckliche Handlung des Nutzers in der Mahlzeit.
class MealPhotoService {
  MealPhotoService({
    required this.db,
    required this.meals,
    required this.remote,
    required this.baseDir,
    this.prepare = prepareMealPhoto,
  });

  final AppDatabase db;
  final MealRepository meals;
  final RemoteFileStore remote;

  /// Ordner fuer lokale Kopien (in Tests ein Temp-Ordner).
  final Future<Directory> Function() baseDir;

  /// Verkleinern; in Tests austauschbar (Isolates laufen nicht ueberall unter `testWidgets`).
  final Future<Uint8List> Function(Uint8List bytes) prepare;

  static const _pendingKey = 'pending_meal_photo_uploads';
  static const contentType = 'image/jpeg';

  /// Serialisiert Lesen+Schreiben der Warteschlange (gleicher Grund wie bei den Belegfotos), nicht den Netz-Upload.
  final _pendingLock = AsyncLock();

  Future<File> _localFile(String mealId) async {
    final dir = Directory('${(await baseDir()).path}/meal_photos');
    await dir.create(recursive: true);
    return File('${dir.path}/$mealId.jpg');
  }

  static String storagePathOf(String householdId, String mealId) => '$householdId/$mealId.jpg';

  Future<List<String>> _pending() async {
    final raw = await db.getKv(_pendingKey);
    return raw == null ? [] : (jsonDecode(raw) as List).cast<String>();
  }

  Future<void> _setPending(List<String> ids) => db.setKv(_pendingKey, jsonEncode(ids));

  /// Legt das Foto der Mahlzeit ab (ersetzt ein vorhandenes): verkleinern, lokal speichern, Pfad an der Mahlzeit
  /// setzen (wird synchronisiert) und den Upload einreihen. Wirft [FormatException], wenn das Bild nicht lesbar ist.
  /// [prepared] = die Bytes sind schon mit [prepare] verkleinert (das Formular tut das beim Aufnehmen, um ein
  /// unlesbares Bild sofort zu melden), sie werden dann nicht noch einmal neu kodiert.
  Future<void> attach(Meal meal, Uint8List photo, {bool prepared = false}) async {
    final bytes = prepared ? photo : await prepare(photo);
    await (await _localFile(meal.id)).writeAsBytes(bytes, flush: true);
    await meals.setPhotoPath(meal.id, storagePathOf(meal.householdId, meal.id));
    await _pendingLock.run(() async {
      final current = await _pending();
      await _setPending({...current, meal.id}.toList());
    });
  }

  /// Laedt wartende Fotos hoch. Fehler (kein Netz) lassen den Rest in der Warteschlange. Rueckgabe: Anzahl hochgeladen.
  Future<int> uploadPending() async {
    final pending = await _pending();
    if (pending.isEmpty) return 0;
    // Nur definitiv erledigte IDs merken und spaeter gegen die dann aktuelle Warteschlange abziehen, damit ein
    // waehrend des Uploads per attach() hinzugekommener Eintrag nicht verloren geht (siehe ReceiptFileService).
    final settled = <String>[];
    var done = 0;
    for (final id in pending) {
      final meal = await meals.get(id);
      if (meal == null || meal.deletedAt != null || meal.photoPath == null) {
        settled.add(id); // Mahlzeit oder Foto ist inzwischen weg
        continue;
      }
      final file = await _localFile(id);
      if (!await file.exists()) {
        settled.add(id); // Datei verschwunden, nicht wiederherstellbar
        continue;
      }
      try {
        await remote.upload(meal.photoPath!, await file.readAsBytes(), contentType);
        settled.add(id);
        done++;
      } catch (_) {
        // bleibt in der Warteschlange, naechster Versuch beim naechsten Sync
      }
    }
    if (settled.isNotEmpty) {
      await _pendingLock.run(() async {
        final current = await _pending();
        await _setPending(current.where((id) => !settled.contains(id)).toList());
      });
    }
    return done;
  }

  /// Bytes des Fotos: lokale Kopie, sonst vom Server holen und lokal merken. Null ohne Foto oder wenn beides nicht geht.
  Future<Uint8List?> bytes(Meal meal) async {
    final path = meal.photoPath;
    if (path == null) return null;
    final file = await _localFile(meal.id);
    if (await file.exists()) return file.readAsBytes();
    try {
      final data = await remote.download(path);
      await file.writeAsBytes(data, flush: true);
      return data;
    } catch (_) {
      return null;
    }
  }

  /// Entfernt das Foto einer Mahlzeit: lokale Kopie, Warteschlange und (soweit moeglich) die Server-Datei. Mit
  /// [clearPath] wird zusaetzlich der Pfad an der Mahlzeit geloescht (Foto entfernt, Mahlzeit bleibt).
  Future<void> purge(Meal meal, {bool clearPath = false}) async {
    final file = await _localFile(meal.id);
    if (await file.exists()) await file.delete();
    await _pendingLock.run(() async {
      final pending = await _pending();
      await _setPending(pending.where((id) => id != meal.id).toList());
    });
    if (clearPath) await meals.setPhotoPath(meal.id, null);
    final path = meal.photoPath;
    if (path == null) return;
    try {
      await remote.remove([path]);
    } catch (_) {
      // kein Netz: die Datei bleibt im privaten Bucket, ohne Verweis nicht mehr abrufbar
    }
  }
}
