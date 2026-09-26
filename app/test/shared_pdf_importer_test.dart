import 'dart:async';
import 'dart:typed_data';

import 'package:einkaufstracker/data/share/shared_pdf_source.dart';
import 'package:einkaufstracker/domain/receipt/parsed_receipt.dart';
import 'package:einkaufstracker/features/receipt_import/receipt_import_service.dart';
import 'package:einkaufstracker/features/receipt_import/shared_pdf_importer.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSource implements SharedPdfSource {
  _FakeSource(this.initial);
  Uint8List? initial;
  final controller = StreamController<Uint8List>.broadcast();

  @override
  Future<Uint8List?> takeInitial() async {
    final b = initial;
    initial = null;
    return b;
  }

  @override
  Stream<Uint8List> get incoming => controller.stream;
}

void main() {
  final bytesA = Uint8List.fromList([1]);
  final bytesB = Uint8List.fromList([2]);

  late List<ImportPreview> opened;
  late List<Uint8List> previewed;
  var signedIn = true;

  SharedPdfImporter make(_FakeSource src) => SharedPdfImporter(
        source: src,
        isSignedIn: () => signedIn,
        preview: (b) async {
          previewed.add(b);
          return ImportPreview(receipt: const ParsedReceipt.failed([]), error: 'x${b.first}');
        },
        openReview: opened.add,
      );

  setUp(() {
    opened = [];
    previewed = [];
    signedIn = true;
  });

  test('PDF beim App-Start: Vorschau wird geoeffnet, und nur einmal', () async {
    final src = _FakeSource(bytesA);
    final imp = make(src);
    await imp.start();
    expect(opened.single.error, 'x1');
    await imp.start(); // erneuter Start holt nichts mehr
    expect(opened, hasLength(1));
    imp.dispose();
  });

  test('PDF bei laufender App kommt ueber den Stream an', () async {
    final src = _FakeSource(null);
    final imp = make(src);
    await imp.start();
    expect(opened, isEmpty);
    src.controller.add(bytesB);
    await pumpEventQueue();
    expect(previewed.single, bytesB);
    expect(opened, hasLength(1));
    imp.dispose();
  });

  test('Ohne Anmeldung wird gewartet und nach dem Login importiert', () async {
    signedIn = false;
    final src = _FakeSource(bytesA);
    final imp = make(src);
    await imp.start();
    expect(opened, isEmpty);
    expect(previewed, isEmpty);

    signedIn = true;
    await imp.onSignedIn();
    expect(opened, hasLength(1));
    await imp.onSignedIn(); // kein zweites Mal
    expect(opened, hasLength(1));
    imp.dispose();
  });

  test('Kein PDF vorhanden: nichts passiert', () async {
    final imp = make(_FakeSource(null));
    await imp.start();
    await imp.onSignedIn();
    expect(opened, isEmpty);
    imp.dispose();
  });
}
