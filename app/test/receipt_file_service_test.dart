import 'dart:io';
import 'dart:typed_data';

import 'package:einkaufstracker/data/files/receipt_file_service.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/receipt_repository.dart';
import 'package:einkaufstracker/data/sync/sync_engine.dart';
import 'package:einkaufstracker/domain/receipt/billa_text_parser.dart';
import 'package:einkaufstracker/features/receipt_import/receipt_import_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Uint8List _bytes(List<int> v) => Uint8List.fromList(v);

void main() {
  late AppDatabase db;
  late FakeRemoteFileStore remote;
  late Directory dir;
  late String receiptId;

  final parsed = const BillaTextParser().parse(File('test/fixtures/receipts/billa_digital_04.txt').readAsStringSync());

  setUp(() async {
    db = memoryDb();
    remote = FakeRemoteFileStore();
    dir = Directory.systemTemp.createTempSync('rfs');
    receiptId = (await receiptRepo(db).saveParsed(parsed)).receiptId;
  });
  tearDown(() async {
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('attach: lokal gespeichert, Verweis angelegt, in der Outbox, Upload wartet', () async {
    final svc = fileService(db, remote, dir);
    final n = await svc.attach(receiptId, [ReceiptAttachment(kind: 'pdf', bytes: _bytes([1, 2, 3]))]);
    expect(n, 1);

    final f = await db.select(db.receiptFiles).getSingle();
    expect((f.kind, f.pageNo, f.sizeBytes), ('pdf', 1, 3));
    expect(f.storagePath, 'h1/$receiptId/${f.id}.pdf');
    expect(File('${dir.path}/receipt_files/${f.id}.pdf').existsSync(), isTrue);
    expect((await db.select(db.outbox).get()).map((o) => o.remoteTable), contains('receipt_files'));
    expect(remote.uploads, 0);

    expect(await svc.uploadPending(), 1);
    expect(remote.files[f.storagePath], _bytes([1, 2, 3]));
    expect(remote.contentTypes[f.storagePath], 'application/pdf');
    expect(await svc.uploadPending(), 0); // Warteschlange leer
  });

  test('Einstellung "Bon-Fotos speichern" aus: nichts wird abgelegt', () async {
    final svc = fileService(db, remote, dir, keep: false);
    expect(await svc.attach(receiptId, [ReceiptAttachment(kind: 'image', bytes: _bytes([9]))]), 0);
    expect(await db.select(db.receiptFiles).get(), isEmpty);
  });

  test('Offline: Datei bleibt lokal und in der Warteschlange, spaeter geht der Upload durch', () async {
    final svc = fileService(db, remote, dir);
    await svc.attach(receiptId, [ReceiptAttachment(kind: 'image', bytes: _bytes([7, 7]))]);
    remote.offline = true;
    expect(await svc.uploadPending(), 0);
    expect(remote.files, isEmpty);

    remote.offline = false;
    expect(await svc.uploadPending(), 1);
    expect(remote.files.values.single, _bytes([7, 7]));
    expect(remote.contentTypes.values.single, 'image/jpeg');
  });

  test('Mehrere Seiten: eine Datei je Seite, dieselbe Seite zweimal ergibt keine zweite Datei', () async {
    final svc = fileService(db, remote, dir);
    final two = [
      ReceiptAttachment(kind: 'image', bytes: _bytes([1]), pageNo: 1),
      ReceiptAttachment(kind: 'image', bytes: _bytes([2]), pageNo: 2),
    ];
    await svc.attach(receiptId, two);
    await svc.attach(receiptId, two);
    final files = await db.select(db.receiptFiles).get();
    expect(files.map((f) => f.pageNo).toList()..sort(), [1, 2]);
  });

  test('bytes: lokale Kopie, sonst Download vom Server, sonst null', () async {
    final svc = fileService(db, remote, dir);
    await svc.attach(receiptId, [ReceiptAttachment(kind: 'pdf', bytes: _bytes([5, 6]))]);
    await svc.uploadPending();
    final f = await db.select(db.receiptFiles).getSingle();

    expect(await svc.bytes(f), _bytes([5, 6])); // lokal

    File('${dir.path}/receipt_files/${f.id}.pdf').deleteSync();
    expect(await svc.bytes(f), _bytes([5, 6])); // vom Server geholt
    expect(File('${dir.path}/receipt_files/${f.id}.pdf').existsSync(), isTrue); // und lokal gemerkt

    File('${dir.path}/receipt_files/${f.id}.pdf').deleteSync();
    remote.offline = true;
    expect(await svc.bytes(f), isNull); // weder lokal noch erreichbar
  });

  test('Zweites Geraet: Verweis kommt per Sync, die Datei per Download', () async {
    final server = FakeRemoteStore();
    final svc = fileService(db, remote, dir);
    await svc.attach(receiptId, [ReceiptAttachment(kind: 'pdf', bytes: _bytes([4, 2]))]);
    await svc.uploadPending();
    await SyncEngine(db, server).sync();

    final db2 = memoryDb();
    addTearDown(db2.close);
    await SyncEngine(db2, server).sync();
    final f = await db2.select(db2.receiptFiles).getSingle();
    expect(f.kind, 'pdf');

    final dir2 = Directory.systemTemp.createTempSync('rfs2');
    addTearDown(() => dir2.deleteSync(recursive: true));
    expect(await fileService(db2, remote, dir2).bytes(f), _bytes([4, 2]));
  });

  test('Bon loeschen: Verweise werden geloescht (synchronisiert), purge entfernt lokale und Server-Datei', () async {
    final svc = fileService(db, remote, dir);
    await svc.attach(receiptId, [ReceiptAttachment(kind: 'pdf', bytes: _bytes([1]))]);
    await svc.uploadPending();
    final files = await receiptRepo(db).filesOf(receiptId);
    await db.delete(db.outbox).go();

    await receiptRepo(db).softDelete(receiptId);
    expect((await db.select(db.receiptFiles).getSingle()).deletedAt, isNotNull);
    expect((await db.select(db.outbox).get()).map((o) => o.remoteTable), contains('receipt_files'));

    await svc.purge(files);
    expect(Directory('${dir.path}/receipt_files').listSync(), isEmpty);
    expect(remote.files, isEmpty);
  });

  test('Bon geloescht, bevor der Upload lief: wartende Datei wird uebersprungen', () async {
    final svc = fileService(db, remote, dir);
    await svc.attach(receiptId, [ReceiptAttachment(kind: 'pdf', bytes: _bytes([1]))]);
    await receiptRepo(db).softDelete(receiptId);
    expect(await svc.uploadPending(), 0);
    expect(remote.files, isEmpty);
  });

  group('Import-Service legt Belege ab', () {
    ReceiptImportService service({Future<Uint8List> Function(String, {double? cutY})? prepare, ReceiptFileService? files}) =>
        ReceiptImportService(FakePdfReader(text: File('test/fixtures/receipts/billa_digital_03.txt').readAsStringSync()), receiptRepo(db),
            files: files ?? fileService(db, remote, dir), prepareImage: prepare);

    test('PDF: Vorschau haengt das PDF an, Speichern legt es ab', () async {
      final s = service();
      final preview = await s.preview(_bytes([0x25, 0x50, 0x44, 0x46]));
      expect(preview.attachments.single.kind, 'pdf');
      final result = await s.save(preview);
      final f = await db.select(db.receiptFiles).getSingle();
      expect(f.receiptId, result.receiptId);
      expect(File('${dir.path}/receipt_files/${f.id}.pdf').readAsBytesSync(), [0x25, 0x50, 0x44, 0x46]);
    });

    test('Duplikat: es wird nichts doppelt abgelegt', () async {
      final s = service();
      await s.save(await s.preview(_bytes([1])));
      final again = await s.preview(_bytes([1]));
      expect(again.isDuplicate, isTrue);
      expect(await db.select(db.receiptFiles).get(), hasLength(1));
    });

    test('Fotos: werden mit dem Schnitt aufbereitet (ohne Zahlungsblock) und je Seite abgelegt', () async {
      final calls = <(String, double?)>[];
      final s = service(prepare: (path, {cutY}) async {
        calls.add((path, cutY));
        return _bytes([path.length]);
      });
      final base = await s.preview(_bytes([1]));
      final photo = ImportPreview(
        receipt: base.receipt,
        source: ReceiptSources.photoLocal,
        attachments: const [
          AttachmentSource.image('p1.jpg', cutY: null, pageNo: 1),
          AttachmentSource.image('p2.jpg', cutY: 812.5, pageNo: 2),
        ],
      );
      await db.delete(db.receipts).go(); // der PDF-Import oben soll kein Duplikat sein
      await db.delete(db.receiptItems).go();
      await s.save(photo);

      expect(calls, [('p1.jpg', null), ('p2.jpg', 812.5)]);
      final files = await db.select(db.receiptFiles).get();
      expect(files.map((f) => (f.kind, f.pageNo)).toList()..sort((a, b) => a.$2.compareTo(b.$2)), [('image', 1), ('image', 2)]);
    });

    test('Ablegen schlaegt fehl: der Bon ist trotzdem gespeichert', () async {
      final s = service(files: fileService(db, remote, Directory('${dir.path}/gibt-es-nicht/\u0000')));
      final result = await s.save(await s.preview(_bytes([1])));
      expect(result.outcome, ReceiptSaveOutcome.saved);
      expect(await db.select(db.receipts).get(), hasLength(2)); // der Bon aus setUp und dieser
    });

    test('Ohne Dienst (files = null): kein Fehler, nichts abgelegt', () async {
      final s = ReceiptImportService(FakePdfReader(text: File('test/fixtures/receipts/billa_digital_03.txt').readAsStringSync()), receiptRepo(db));
      final result = await s.save(await s.preview(_bytes([1])));
      expect(result.outcome, ReceiptSaveOutcome.saved);
      expect(await db.select(db.receiptFiles).get(), isEmpty);
    });
  });
}
