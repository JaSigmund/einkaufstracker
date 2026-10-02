import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/async_lock.dart';
import '../local/database.dart';
import '../repositories/receipt_repository.dart';

/// Nach dieser Zeit gilt ein Netzaufruf als haengen geblieben und wird abgebrochen, statt den Sync (der auf
/// [ReceiptFileService.uploadPending] wartet) fuer immer in "Synchronisiere..." zu blockieren (Fehlerbericht
/// "Sync bleibt haengen", 2026-09-28 — die Tabellen-Synchronisierung hatte schon ein Timeout, der
/// Datei-Upload in den privaten Bucket noch nicht).
const _networkTimeout = Duration(seconds: 20);

/// Ort der Originaldateien auf dem Server (privater Bucket, Standard "receipts", fuer Essensfotos "meals").
abstract class RemoteFileStore {
  Future<void> upload(String path, Uint8List bytes, String contentType);
  Future<Uint8List> download(String path);
  Future<void> remove(List<String> paths);
}

class SupabaseFileStore implements RemoteFileStore {
  SupabaseFileStore(this._client, {String bucket = 'receipts'}) : _bucketName = bucket;
  final SupabaseClient _client;
  final String _bucketName;

  StorageFileApi get _bucket => _client.storage.from(_bucketName);

  @override
  Future<void> upload(String path, Uint8List bytes, String contentType) => _bucket
      .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: contentType, upsert: true))
      .timeout(_networkTimeout);

  @override
  Future<Uint8List> download(String path) => _bucket.download(path).timeout(_networkTimeout);

  @override
  Future<void> remove(List<String> paths) => _bucket.remove(paths).timeout(_networkTimeout);
}

/// Eine Datei, die zu einem Bon abgelegt werden soll (Bytes sind bereits aufbereitet).
class ReceiptAttachment {
  const ReceiptAttachment({required this.kind, required this.bytes, this.pageNo = 1});

  /// 'pdf' | 'image'
  final String kind;
  final Uint8List bytes;
  final int pageNo;
}

/// Legt Originalbelege (Foto ohne Zahlungsblock, PDF) zu Bons ab: sofort lokal im App-Ordner, danach im Storage.
/// Der Upload laeuft offline-tauglich ueber eine Warteschlange und wird nach jedem Sync fortgesetzt.
class ReceiptFileService {
  ReceiptFileService({
    required this.db,
    required this.repo,
    required this.remote,
    required this.baseDir,
    required this.keepFiles,
  });

  final AppDatabase db;
  final ReceiptRepository repo;
  final RemoteFileStore remote;

  /// Ordner fuer lokale Kopien (in Tests ein Temp-Ordner).
  final Future<Directory> Function() baseDir;

  /// Einstellung "Bon-Fotos speichern" (Server), mit Rueckfall auf den zuletzt bekannten Wert.
  final Future<bool> Function() keepFiles;

  static const _pendingKey = 'pending_file_uploads';

  /// Serialisiert nur das Lesen+Schreiben der Warteschlange selbst (Codereview-Fund 2026-10-01): `attach()`
  /// (direkt nach dem Speichern eines Bons) und `uploadPending()` (Timer/Connectivity/manueller Sync) lesen
  /// und schreiben denselben KV-Eintrag unabhaengig voneinander -- ohne das koennte der jeweils zuletzt
  /// schreibende Aufruf eine vom anderen inzwischen hinzugefuegte oder entfernte ID stillschweigend wieder
  /// ueberschreiben (Lost Update). Bewusst NICHT der eigentliche Netz-Upload mit darin eingeschlossen, sonst
  /// wuerde das Speichern eines neuen Bons auf einen laufenden, ggf. langsamen Upload warten muessen.
  final _pendingLock = AsyncLock();

  static String _ext(String kind) => kind == 'pdf' ? 'pdf' : 'jpg';
  static String contentType(String kind) => kind == 'pdf' ? 'application/pdf' : 'image/jpeg';

  Future<File> _localFile(ReceiptFile f) async {
    final dir = Directory('${(await baseDir()).path}/receipt_files');
    await dir.create(recursive: true);
    return File('${dir.path}/${f.id}.${_ext(f.kind)}');
  }

  Future<List<String>> _pending() async {
    final raw = await db.getKv(_pendingKey);
    return raw == null ? [] : (jsonDecode(raw) as List).cast<String>();
  }

  Future<void> _setPending(List<String> ids) => db.setKv(_pendingKey, jsonEncode(ids));

  /// Speichert die Dateien lokal, legt die Verweise an (werden synchronisiert) und stellt den Upload in die
  /// Warteschlange. Ohne Einwilligung (Einstellung aus) passiert nichts. Rueckgabe: Anzahl abgelegter Dateien.
  Future<int> attach(String receiptId, List<ReceiptAttachment> attachments) async {
    if (attachments.isEmpty || !await keepFiles()) return 0;
    final hid = await repo.householdId();
    final now = DateTime.now().toUtc();
    final newIds = <String>[];
    var n = 0;
    for (final a in attachments) {
      // deterministisch: derselbe Bon zweimal abgelegt ergibt dieselbe Datei
      final id = const Uuid().v5(Namespace.url.value, 'receipt-file:$receiptId:${a.kind}:${a.pageNo}');
      final f = ReceiptFile(
        id: id,
        householdId: hid,
        receiptId: receiptId,
        kind: a.kind,
        pageNo: a.pageNo,
        storagePath: '$hid/$receiptId/$id.${_ext(a.kind)}',
        sizeBytes: a.bytes.length,
        updatedAt: now,
      );
      await (await _localFile(f)).writeAsBytes(a.bytes, flush: true);
      await repo.putFile(f);
      newIds.add(id);
      n++;
    }
    // Nur dieser letzte Schritt (lesen+schreiben der gemeinsamen Warteschlange) ist gesperrt, siehe
    // _pendingLock -- die Datei-/DB-Schreibvorgaenge oben sind rein lokal und brauchen das nicht.
    await _pendingLock.run(() async {
      final current = await _pending();
      await _setPending({...current, ...newIds}.toList());
    });
    return n;
  }

  /// Laedt wartende Dateien hoch. Fehler (kein Netz) lassen den Rest in der Warteschlange. Rueckgabe: Anzahl hochgeladen.
  Future<int> uploadPending() async {
    final pending = await _pending();
    if (pending.isEmpty) return 0;
    // Nur die IDs merken, die definitiv erledigt sind (hochgeladen, oder der Bon/die Datei ist weg) --
    // beim Schreiben wird das gegen die dann AKTUELLE Warteschlange abgezogen, nicht gegen diese Kopie von
    // vorhin ueberschrieben (Codereview-Fund 2026-10-01: sonst ginge ein waehrend des -- je nach
    // Netzgeschwindigkeit potenziell lang laufenden -- Uploads per attach() neu hinzugekommener Eintrag
    // verloren, weil diese Methode von seiner Existenz noch gar nichts wissen konnte).
    final settled = <String>[];
    var done = 0;
    for (final id in pending) {
      final f = await (db.select(db.receiptFiles)..where((x) => x.id.equals(id))).getSingleOrNull();
      if (f == null || f.deletedAt != null) {
        settled.add(id); // Bon wurde inzwischen geloescht
        continue;
      }
      final file = await _localFile(f);
      if (!await file.exists()) {
        settled.add(id); // Datei verschwunden, nicht wiederherstellbar -- weiter warten haette keinen Sinn
        continue;
      }
      try {
        await remote.upload(f.storagePath, await file.readAsBytes(), contentType(f.kind));
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

  /// Bytes der Datei: lokale Kopie, sonst vom Server holen und lokal merken. Null, wenn beides nicht geht.
  Future<Uint8List?> bytes(ReceiptFile f) async {
    final file = await _localFile(f);
    if (await file.exists()) return file.readAsBytes();
    try {
      final data = await remote.download(f.storagePath);
      await file.writeAsBytes(data, flush: true);
      return data;
    } catch (_) {
      return null;
    }
  }

  /// Entfernt lokale Kopien und (soweit moeglich) die Server-Dateien geloeschter Bons.
  Future<void> purge(List<ReceiptFile> files) async {
    if (files.isEmpty) return;
    for (final f in files) {
      final file = await _localFile(f);
      if (await file.exists()) await file.delete();
    }
    await _pendingLock.run(() async {
      final pending = await _pending();
      await _setPending(pending.where((id) => !files.any((f) => f.id == id)).toList());
    });
    try {
      await remote.remove([for (final f in files) f.storagePath]);
    } catch (_) {
      // kein Netz: die Datei bleibt im privaten Bucket, ohne Verweis nicht mehr abrufbar
    }
  }
}
