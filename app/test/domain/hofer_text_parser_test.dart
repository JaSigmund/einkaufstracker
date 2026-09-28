import 'dart:io';

import 'package:einkaufstracker/domain/receipt/hofer_text_parser.dart';
import 'package:einkaufstracker/domain/receipt/parsed_receipt.dart';
import 'package:flutter_test/flutter_test.dart';

const _parser = HoferTextParser();

String _fixture(String name) => File('test/fixtures/receipts/$name.txt').readAsStringSync();

/// Testet gegen einen einzelnen echten Hofer-Bon (Fehlerbericht "Scan nicht möglich", 2026-09-28,
/// `testdata/receipts/hofer_01.webp`) — noch kein Golden Set wie bei Billa (Doku 11 Roadmap, B3).
void main() {
  test('echter Hofer-Bon: Haendler, Datum, Summe und alle sechs Positionen stimmen', () {
    final r = _parser.parse(_fixture('hofer_photo_01'));

    expect(r.isParsed, isTrue, reason: r.warnings.join('; '));
    expect(r.chain, 'Hofer');
    expect(r.purchasedAtUtc, DateTime.utc(2026, 9, 28, 11, 56)); // 13:56 Wiener Sommerzeit
    expect(r.totalCents, 1725);
    expect(r.externalId, 'hofer-633-076-4381');

    final names = r.items.map((i) => i.rawText).toList();
    expect(names, ['KNOBLAUCH 400 G', 'Faschiertes 1kg', 'Zwiebeln gelb 3kg', 'Chips Paprika 250g', 'Rote Paprika 500g', 'Bananen lose']);
    expect(r.items.map((i) => i.lineTotalCents), [218, 849, 199, 149, 199, 111]);
    expect(r.items.map((i) => i.taxCode), ['E', 'A', 'E', 'A', 'E', 'A']);
    expect(r.items.every((i) => i.kind == ReceiptItemKind.article), isTrue);
  });

  test('Waegware (Bananen lose): Menge und Kilopreis aus der (N)-Zeile, Preis bleibt von der Artikelzeile', () {
    final r = _parser.parse(_fixture('hofer_photo_01'));
    final bananen = r.items.singleWhere((i) => i.rawText == 'Bananen lose');
    expect(bananen.quantity, 1.170);
    expect(bananen.quantityUnit, 'kg');
    expect(bananen.unitPriceCents, 95);
    expect(bananen.lineTotalCents, 111); // Preis kommt von der Artikelzeile, nicht aus Menge x Kilopreis gerechnet
  });

  test('Pruefung: Positionssumme entspricht der Bon-Summe, kein Steuerblock-Abgleich (Rundung)', () {
    final r = _parser.parse(_fixture('hofer_photo_01'));
    final c = r.checks!;
    expect(c.itemsSumCents, 1725);
    expect(c.totalMatches, isTrue);
    expect(c.taxMatches, isTrue); // kein harter Klassen-Abgleich, siehe Klassendoku
    expect(r.isTrustworthy, isTrue);
  });

  test('Bon ohne "Total-EFT": faellt auf die Zeile mit der Zahlungsart zurueck', () {
    final text = _fixture('hofer_photo_01').replaceFirst('Total-EFT EUR:                           17.25', '');
    final r = _parser.parse(text);
    expect(r.totalCents, 1725);
  });

  test('kein Datum gefunden: nicht gelesen statt Absturz', () {
    final r = _parser.parse('irgendein Text ohne Bon-Format');
    expect(r.isParsed, isFalse);
  });

  test('Datum gefunden, aber keine Summe: nicht gelesen statt Absturz', () {
    final r = _parser.parse('xxxxxxxxxxx5153/28.09.2026/13:56/05/236\nkeine Summe hier');
    expect(r.isParsed, isFalse);
  });
}
