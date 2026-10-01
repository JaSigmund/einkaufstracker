import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:einkaufstracker/data/cloud/cloud_receipt.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/domain/ocr/row_cluster.dart';
import 'package:einkaufstracker/domain/receipt/parsed_receipt.dart';
import 'package:einkaufstracker/features/receipt_import/photo_receipt_service.dart';
import 'package:einkaufstracker/features/receipt_import/receipt_import_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/fakes.dart';

/// Echtes, dekodierbares JPEG (Codereview-Fund 2026-10-01: readSinglePhotoViaCloud dekodiert das Bild
/// jetzt tatsaechlich zum Zuschneiden, ein paar Platzhalter-Bytes reichen nicht mehr).
Uint8List _realJpeg({int w = 400, int h = 600}) => Uint8List.fromList(img.encodeJpg(img.Image(width: w, height: h)));

List<ScannedPage> _pages(String fixture) {
  final json = jsonDecode(File('test/fixtures/ocr/$fixture.json').readAsStringSync()) as Map<String, dynamic>;
  var n = 0;
  return [
    for (final page in json['pages'] as List)
      ScannedPage('page${n++}.jpg', [
        for (final l in page as List)
          OcrLine(l['text'] as String,
              Rect.fromLTRB((l['l'] as num).toDouble(), (l['t'] as num).toDouble(), (l['r'] as num).toDouble(), (l['b'] as num).toDouble())),
      ]),
  ];
}

Map<String, dynamic> _cloudJson(int total, List<int> itemCents, {String at = '2026-09-24T14:42:00+02:00'}) => {
      'receipt': {
        'store_name': 'BILLA',
        'purchased_at': at,
        'total_cents': total,
        'items': [
          for (var i = 0; i < itemCents.length; i++)
            {'raw_text': 'Artikel $i', 'kind': 'article', 'quantity': 1, 'quantity_unit': 'piece', 'line_total_cents': itemCents[i], 'uncertain': false},
        ],
      },
    };

class _FakeCloud implements CloudReceiptReader {
  _FakeCloud(this.answer);
  Object answer; // ParsedReceipt oder Exception
  int calls = 0;
  List<Uint8List> lastImages = const [];

  @override
  Future<ParsedReceipt> read(List<Uint8List> jpegs) async {
    calls++;
    lastImages = jpegs;
    final a = answer;
    if (a is Exception) throw a;
    return a as ParsedReceipt;
  }
}

void main() {
  late AppDatabase db;
  late _FakeCloud cloud;
  late List<(String, double?)> prepared;
  var allowed = true;

  PhotoReceiptService service() => PhotoReceiptService(
        repo: receiptRepo(db),
        cloud: cloud,
        cloudAllowed: () async => allowed,
        prepare: (path, {cutY}) async {
          prepared.add((path, cutY));
          return Uint8List.fromList([1, 2, 3]);
        },
      );

  setUp(() {
    db = memoryDb();
    cloud = _FakeCloud(parsedReceiptFromCloud(_cloudJson(2319, [2319])));
    prepared = [];
    allowed = true;
  });
  tearDown(() => db.close());

  group('readSinglePhotoViaCloud (Foto-Scan im Browser, Doku 14 iOS-Strategie Option D)', () {
    final jpeg = _realJpeg();

    test('Cloud erlaubt und Ergebnis vertrauenswuerdig: Vorschau mit Quelle photoCloud', () async {
      final p = await service().readSinglePhotoViaCloud(jpeg, cutY: 300);
      expect(p.source, ReceiptSources.photoCloud);
      expect(p.receipt.isTrustworthy, isTrue);
      expect(p.canImport, isTrue);
      expect(p.note, isNull);
      expect(cloud.calls, 1);
    });

    test('Codereview-Fund 2026-10-01: das hochgeladene Bild ist unterhalb von cutY zugeschnitten, nicht das Originalfoto', () async {
      await service().readSinglePhotoViaCloud(jpeg, cutY: 300);
      expect(cloud.lastImages, isNot([jpeg])); // nicht mehr das unveraenderte Originalfoto
      final uploaded = img.decodeJpg(cloud.lastImages.single)!;
      expect(uploaded.height, 300);
    });

    test('Cloud ausgeschaltet: Fehlermeldung erklaert, dass es im Browser keine lokale Erkennung gibt', () async {
      allowed = false;
      final p = await service().readSinglePhotoViaCloud(jpeg, cutY: 300);
      expect(p.canImport, isFalse);
      expect(p.error, contains('Browser'));
      expect(cloud.calls, 0);
    });

    test('Ergebnis nicht vertrauenswuerdig (Summe passt nicht): trotzdem uebernehmbar, mit Hinweis', () async {
      cloud = _FakeCloud(parsedReceiptFromCloud(_cloudJson(2319, [1000])));
      final p = await service().readSinglePhotoViaCloud(jpeg, cutY: 300);
      expect(p.receipt.isTrustworthy, isFalse);
      expect(p.canImport, isTrue);
      expect(p.note, contains('Summe'));
    });

    test('Cloud liefert kein Ergebnis (nicht gelesen): Fehler statt Absturz', () async {
      cloud = _FakeCloud(const ParsedReceipt.failed(['keine Summe']));
      final p = await service().readSinglePhotoViaCloud(jpeg, cutY: 300);
      expect(p.canImport, isFalse);
      expect(p.receipt.isParsed, isFalse);
    });

    test('Cloud nicht erreichbar: Fehlermeldung statt Absturz', () async {
      cloud = _FakeCloud(Exception('offline'));
      final p = await service().readSinglePhotoViaCloud(jpeg, cutY: 300);
      expect(p.canImport, isFalse);
      expect(p.error, isNotNull);
    });

    test('Einwilligung nicht abrufbar (kein Netz): Fehlermeldung statt Absturz', () async {
      final p = await PhotoReceiptService(
        repo: receiptRepo(db),
        cloud: cloud,
        cloudAllowed: () async => throw const CloudUnavailable('kein Netz'),
        prepare: (path, {cutY}) async => Uint8List.fromList([1, 2, 3]),
      ).readSinglePhotoViaCloud(jpeg, cutY: 300);
      expect(p.canImport, isFalse);
      expect(cloud.calls, 0);
    });

    test('Codereview-Fund 2026-10-01: ein nicht dekodierbares Foto fuehrt zu einer Fehlermeldung statt eines Absturzes oder eines ungeprueften Uploads', () async {
      final p = await service().readSinglePhotoViaCloud(Uint8List.fromList([1, 2, 3]), cutY: 100);
      expect(p.canImport, isFalse);
      expect(cloud.calls, 0); // auf keinen Fall hochladen, wenn der Zuschnitt nicht garantiert werden konnte
    });
  });

  test('Sauberer Scan besteht das Pruef-Tor lokal: keine Cloud, nichts wird hochgeladen', () async {
    final p = await service().read(_pages('billa_paper_02'));
    expect(p.source, ReceiptSources.photoLocal);
    expect(p.receipt.isTrustworthy, isTrue);
    expect(p.canImport, isTrue);
    expect(cloud.calls, 0);
    expect(prepared, isEmpty);
  });

  test('Hofer-Bon wird lokal erkannt (Featurevorschlag Hofer-Erkennung, 2026-09-28): kein Cloud-Aufruf noetig', () async {
    final p = await service().read(_pages('hofer_paper_01'));
    expect(p.source, ReceiptSources.photoLocal);
    expect(p.receipt.chain, 'Hofer');
    expect(p.receipt.totalCents, 1725);
    expect(p.receipt.isTrustworthy, isTrue);
    expect(cloud.calls, 0);
  });

  test('Schlechter Scan: Cloud wird befragt, das Bild wird vor dem Zahlungsblock abgeschnitten', () async {
    final pages = _pages('billa_paper_01_scan3');
    final p = await service().read(pages);

    expect(p.source, ReceiptSources.photoCloud);
    expect(p.receipt.isTrustworthy, isTrue);
    expect(p.receipt.totalCents, 2319);
    expect(cloud.calls, 1);

    final (path, cutY) = prepared.single;
    expect(path, 'page0.jpg');
    final lines = pages.single.lines;
    final summe = lines.firstWhere((l) => l.text.startsWith('Summe'));
    final payment = lines.firstWhere((l) => RegExp(r'Kundenbeleg|Bezahlung|Contactless').hasMatch(l.text));
    expect(cutY, greaterThan(summe.box.bottom));
    expect(cutY, lessThan(payment.box.top));
    expect(p.note, contains('Cloud'));
  });

  test('Cloud ausgeschaltet: lokales Ergebnis mit Hinweis, kein Upload', () async {
    allowed = false;
    final p = await service().read(_pages('billa_paper_01_scan3'));
    expect(p.source, ReceiptSources.photoLocal);
    expect(p.receipt.isTrustworthy, isFalse);
    expect(p.canImport, isTrue); // Speichern nur nach Rueckfrage in der Pruefansicht
    expect(cloud.calls, 0);
    expect(prepared, isEmpty);
    expect(p.note, isNotNull);
  });

  test('Bildvorbereitung fuer die Cloud wirft einen Fehler: lokales Ergebnis statt Absturz '
      '(Fehlerbericht "Scan nicht möglich: invalid argument(s): 0", 2026-09-28)', () async {
    final service = PhotoReceiptService(
      repo: receiptRepo(db),
      cloud: cloud,
      cloudAllowed: () async => true,
      prepare: (path, {cutY}) async => throw ArgumentError.value(0),
    );
    final p = await service.read(_pages('billa_paper_01_scan3'));
    expect(p.source, ReceiptSources.photoLocal);
    expect(cloud.calls, 0);
    expect(p.note, contains('fehlgeschlagen'));
  });

  test('Cloud nicht erreichbar (offline): lokales Ergebnis mit Hinweis statt Absturz', () async {
    cloud.answer = const CloudUnavailable('kein Netz');
    final p = await service().read(_pages('billa_paper_01_scan3'));
    expect(p.source, ReceiptSources.photoLocal);
    expect(p.note, contains('kein Netz'));
    expect(p.receipt.isParsed, isTrue);
  });

  test('Einwilligung serverseitig verweigert: Hinweis', () async {
    cloud.answer = const CloudNotAllowed();
    final p = await service().read(_pages('billa_paper_01_scan3'));
    expect(p.note, contains('ausgeschaltet'));
  });

  test('Ohne erkennbare Summenzeile wird NICHTS hochgeladen (B4)', () async {
    final page = ScannedPage('x.jpg', const [
      OcrLine('Zwetschken 1kg', Rect.fromLTWH(100, 100, 300, 40)),
      OcrLine('2.75', Rect.fromLTWH(900, 100, 100, 40)),
    ]);
    final p = await service().read([page]);
    expect(cloud.calls, 0);
    expect(prepared, isEmpty);
    expect(p.error, contains('nichts hochgeladen'));
    expect(p.canImport, isFalse);
  });

  test('Cloud trifft die Summe auch nicht: das Ergebnis mit der kleineren Abweichung wird gezeigt', () async {
    cloud.answer = parsedReceiptFromCloud(_cloudJson(2319, [1000])); // Abweichung 13,19 EUR
    final p = await service().read(_pages('billa_paper_01_scan3'));
    expect(p.receipt.isTrustworthy, isFalse);
    expect(p.note, isNotNull);
  });

  test('Mehrere Seiten: Bilder vor der Summenseite ganz, die Summenseite abgeschnitten, spaetere Seiten entfallen', () async {
    final good = _pages('billa_paper_02').single;
    const head = ScannedPage('p0.jpg', [OcrLine('Zwetschken 1kg', Rect.fromLTWH(100, 100, 300, 40))]);
    const tail = ScannedPage('p2.jpg', [
      OcrLine('Kundenbeleg', Rect.fromLTWH(100, 100, 300, 40)),
      OcrLine('Nr. 1234', Rect.fromLTWH(100, 200, 300, 40)),
    ]);
    await service().read([head, ScannedPage('p1.jpg', good.lines.where((l) => !l.text.contains('Datum')).toList()), tail]);
    expect(prepared.map((e) => e.$1), ['p0.jpg', 'p1.jpg']);
    expect(prepared.first.$2, isNull);
    expect(prepared.last.$2, isNotNull);
  });

  test('Derselbe Einkauf, schon gespeichert: Duplikat (auch ueber Summe und Uhrzeit)', () async {
    final first = await service().read(_pages('billa_paper_02'));
    await receiptRepo(db).saveParsed(first.receipt, source: first.source);
    final again = await service().read(_pages('billa_paper_02'));
    expect(again.isDuplicate, isTrue);
    expect(again.canImport, isFalse);

    // Cloud-Lesung ohne Re-Nr, aber gleiche Summe und Zeit wie der gespeicherte Bon
    final asCloud = parsedReceiptFromCloud(_cloudJson(2638, [2638], at: '2026-09-26T16:38:00+02:00'));
    expect(asCloud.externalId, isNull);
    expect(await receiptRepo(db).findDuplicate(asCloud), isNotNull);
    final other = parsedReceiptFromCloud(_cloudJson(2638, [2638], at: '2026-09-26T18:38:00+02:00'));
    expect(await receiptRepo(db).findDuplicate(other), isNull);
  });

  test('Speichern uebernimmt die Quelle (lokal = on_device, Cloud = llm)', () async {
    final local = await service().read(_pages('billa_paper_02'));
    await receiptRepo(db).saveParsed(local.receipt, source: local.source);
    expect((await db.select(db.receipts).getSingle()).source, 'on_device');

    final remote = await service().read(_pages('billa_paper_01_scan3'));
    await receiptRepo(db).saveParsed(remote.receipt, source: remote.source);
    final sources = (await db.select(db.receipts).get()).map((r) => r.source).toSet();
    expect(sources, {'on_device', 'llm'});
  });

  test('Belegfoto: Seiten bis zur Summenseite, die Summenseite mit Schnitt vor dem Zahlungsblock', () async {
    final pages = _pages('billa_paper_02');
    final p = await service().read(pages);
    final a = p.attachments.single;
    expect((a.kind, a.pageNo, a.imagePath), ('image', 1, 'page0.jpg'));
    final lines = pages.single.lines;
    expect(a.cutY, greaterThan(lines.firstWhere((l) => l.text.startsWith('Summe')).box.bottom));
    expect(a.cutY, lessThan(lines.firstWhere((l) => l.text.contains('Kundenbeleg')).box.top));
  });

  test('Belegfoto: ohne erkennbaren Zahlungsschnitt wird kein Foto zum Ablegen vorgemerkt', () async {
    final page = ScannedPage('x.jpg', const [OcrLine('Zwetschken 1kg', Rect.fromLTWH(100, 100, 300, 40))]);
    final p = await service().read([page]);
    expect(p.attachments, isEmpty);
  });

  group('parsedReceiptFromCloud', () {
    test('Zeit mit Offset und ohne (Wiener Ortszeit)', () {
      expect(parsedReceiptFromCloud(_cloudJson(100, [100], at: '2026-09-24T14:42:00+02:00')).purchasedAtUtc, DateTime.utc(2026, 9, 24, 12, 42));
      expect(parsedReceiptFromCloud(_cloudJson(100, [100], at: '2026-09-24T14:42:00')).purchasedAtUtc, DateTime.utc(2026, 9, 24, 12, 42));
      expect(parsedReceiptFromCloud(_cloudJson(100, [100], at: '2026-01-15T14:42:00Z')).purchasedAtUtc, DateTime.utc(2026, 1, 15, 14, 42));
    });

    test('Summe stimmt oder stimmt nicht bestimmt die Vertrauenswuerdigkeit', () {
      expect(parsedReceiptFromCloud(_cloudJson(300, [100, 200])).isTrustworthy, isTrue);
      final bad = parsedReceiptFromCloud(_cloudJson(300, [100, 100]));
      expect(bad.isTrustworthy, isFalse);
      expect(bad.checks!.differenceCents, 100);
    });

    test('Arten, Menge, unsichere und betraglose Positionen', () {
      final r = parsedReceiptFromCloud({
        'receipt': {
          'store_name': 'Billa AG',
          'purchased_at': '2026-09-24T14:42:00',
          'total_cents': 30,
          'items': [
            {'raw_text': 'Pfand', 'kind': 'deposit', 'quantity': -2, 'quantity_unit': 'piece', 'line_total_cents': -50, 'uncertain': false},
            {'raw_text': 'Aktion', 'kind': 'discount', 'quantity': 1, 'quantity_unit': 'piece', 'line_total_cents': -20, 'uncertain': false},
            {'raw_text': 'Trauben', 'kind': 'article', 'quantity': 0.986, 'quantity_unit': 'kg', 'unit_price_cents': 499, 'line_total_cents': 100, 'uncertain': true},
            {'raw_text': 'Ohne Betrag', 'kind': 'article', 'quantity': 1, 'quantity_unit': 'piece', 'line_total_cents': null, 'uncertain': false},
          ],
        },
      });
      expect(r.chain, 'Billa');
      expect(r.items.map((i) => i.kind), [ReceiptItemKind.deposit, ReceiptItemKind.discount, ReceiptItemKind.article]);
      expect(r.items.last.quantityUnit, 'kg');
      expect(r.warnings, containsAll(['Unsicher gelesen: Trauben', 'Position ohne Betrag ausgelassen: Ohne Betrag']));
      expect(r.checks!.itemsSumCents, 30);
    });

    test('Fehlende Summe oder Datum: nicht gelesen', () {
      expect(parsedReceiptFromCloud({'receipt': {'items': []}}).isParsed, isFalse);
      expect(parsedReceiptFromCloud({'receipt': {'total_cents': 100, 'items': []}}).isParsed, isFalse);
      expect(parsedReceiptFromCloud({}).isParsed, isFalse);
    });
  });
}
