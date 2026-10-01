import 'dart:io';

import 'package:einkaufstracker/domain/receipt/receipt_text_parser.dart';
import 'package:flutter_test/flutter_test.dart';

String _fixture(String name) => File('test/fixtures/receipts/$name.txt').readAsStringSync();

void main() {
  test('erkennt Hofer an der Kopfzeile und waehlt den Hofer-Parser', () {
    final r = parseReceiptText(_fixture('hofer_photo_01'));
    expect(r.chain, 'Hofer');
    expect(r.totalCents, 1725);
  });

  test('faellt ohne "HOFER" in der Kopfzeile auf Billa zurueck (bisheriges Verhalten)', () {
    final r = parseReceiptText(_fixture('billa_digital_04'));
    expect(r.chain, 'Billa');
  });

  test('"HOFER" spaeter im Text (z.B. in einem Artikelnamen) loest keinen Fehlgriff aus, nur die Kopfzeile zaehlt', () {
    final text = _fixture('billa_digital_04').replaceFirst('Clever Champignon weiß', 'HOFER Champignon weiß');
    final r = parseReceiptText(text);
    expect(r.chain, 'Billa');
  });

  group('detectChainHint (Codereview-Fund 2026-10-01: Hinweis fuer die Cloud-Erkennung, wenn der lokale Parser ganz scheitert)', () {
    test('erkennt Hofer an der Kopfzeile', () {
      expect(detectChainHint(_fixture('hofer_photo_01')), 'Hofer');
    });

    test('faellt ohne "HOFER" in der Kopfzeile auf Billa zurueck', () {
      expect(detectChainHint(_fixture('billa_digital_04')), 'Billa');
    });
  });
}
