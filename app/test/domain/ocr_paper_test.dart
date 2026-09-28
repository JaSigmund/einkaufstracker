import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:einkaufstracker/domain/ocr/ocr_text.dart';
import 'package:einkaufstracker/domain/ocr/row_cluster.dart';
import 'package:einkaufstracker/domain/receipt/billa_text_parser.dart';
import 'package:einkaufstracker/domain/receipt/parsed_receipt.dart';
import 'package:flutter_test/flutter_test.dart';

List<OcrLine> _load(String name) {
  final json = jsonDecode(File('test/fixtures/ocr/$name.json').readAsStringSync()) as Map<String, dynamic>;
  final lines = <OcrLine>[];
  for (final page in json['pages'] as List) {
    for (final l in page as List) {
      lines.add(OcrLine(l['text'] as String, Rect.fromLTRB((l['l'] as num).toDouble(), (l['t'] as num).toDouble(), (l['r'] as num).toDouble(), (l['b'] as num).toDouble())));
    }
  }
  return lines;
}

ParsedReceipt _read(String name) {
  final lines = _load(name);
  final rows = clusterRows(lines, slope: estimateSlope(lines));
  return const BillaTextParser(lenient: true).parse(ocrRowsToText(rows));
}

void main() {
  group('Papierbon 2 (sauberer Scan, 17 Positionszeilen): besteht das Pruef-Tor lokal', () {
    final r = _read('billa_paper_02');

    test('Kopfdaten und Summe', () {
      expect(r.isParsed, isTrue);
      expect(r.totalCents, 2638);
      expect(r.purchasedAtUtc, DateTime.utc(2026, 9, 26, 14, 38)); // 16:38 Wiener Sommerzeit
    });

    test('Summe der Positionen stimmt, Steuerblock stimmt', () {
      expect(r.checks!.itemsSumCents, 2638);
      expect(r.checks!.totalMatches, isTrue);
      expect(r.checks!.taxBlockGrossSumCents, 2638);
      expect(r.checks!.taxMatches, isTrue);
      expect(r.isTrustworthy, isTrue);
    });

    test('Mengenzeilen werden Menge und Einzelpreis der Position darunter, keine eigene Position', () {
      final byName = {for (final i in r.items) i.rawText: i};
      final edamer = r.items.firstWhere((i) => i.rawText.contains('Edamer'));
      expect(edamer.lineTotalCents, 299);
      final kichererbsen = r.items.firstWhere((i) => i.rawText.contains('Kichererbs'));
      expect((kichererbsen.quantity, kichererbsen.unitPriceCents, kichererbsen.lineTotalCents), (2, 119, 238));
      final einweg = r.items.firstWhere((i) => i.rawText.contains('EINWEGPFAND'));
      expect((einweg.quantity, einweg.unitPriceCents, einweg.lineTotalCents, einweg.kind), (-2, 25, -50, ReceiptItemKind.deposit));
      expect(byName.length, r.items.length); // keine doppelten Namen durch Mengenzeilen
    });

    test('Pfandrueckgaben und Rabatt haben die richtige Art', () {
      expect(r.items.where((i) => i.kind == ReceiptItemKind.deposit), hasLength(3));
      expect(r.items.where((i) => i.kind == ReceiptItemKind.discount).single.lineTotalCents, -86);
    });

    test('Positionen ohne gelesenen Steuerbuchstaben werden gezaehlt', () {
      expect(r.checks!.unlabeledItems, greaterThan(0));
    });
  });

  group('Papierbon 1 (schlechte Scans): das Pruef-Tor haelt sie zurueck', () {
    for (final name in ['billa_paper_01_scan1', 'billa_paper_01_scan3']) {
      test('$name ist nicht vertrauenswuerdig (Summe 23,19 nicht erreicht)', () {
        final r = _read(name);
        expect(r.isParsed, isTrue);
        expect(r.totalCents, 2319);
        expect(r.isTrustworthy, isFalse);
        expect(r.checks!.totalMatches, isFalse);
      });
    }
  });

  group('Digitaler Text bleibt vom lenienten Modus unberuehrt', () {
    test('Strenger und lenienter Parser liefern dasselbe fuer einen digitalen Bon', () {
      final text = File('test/fixtures/receipts/billa_digital_03.txt').readAsStringSync();
      final strict = const BillaTextParser().parse(text);
      final lenient = const BillaTextParser(lenient: true).parse(text);
      expect(lenient.items.length, strict.items.length);
      expect(lenient.checks!.unlabeledItems, 0);
      expect(lenient.isTrustworthy, strict.isTrustworthy);
      expect(lenient.bonDiscounts.length, strict.bonDiscounts.length);
    });
  });

  group('ocrRowsToText', () {
    String t(List<String> cells) => ocrRowsToText([
          [for (final c in cells) OcrLine(c, const Rect.fromLTWH(0, 0, 10, 10))]
        ]);

    test('Preise mit Leerraum', () {
      expect(t(['Zwetschken 1kg', '2. 75']), 'Zwetschken 1kg 2.75');
      expect(t(['EXTREM AKTION', '-0. 96']), 'EXTREM AKTION -0.96');
      expect(t(['Summe', 'EUR', '23, 19']), 'Summe EUR 23.19');
    });

    test('Datum und Zeit', () {
      expect(t(['Datum: 24. 09. 2026', 'Zeit: 14:42']), 'Datum: 24.09.2026 Zeit: 14:42');
    });

    test('Mengenzeilen', () {
      expect(t(['-2_X', '0. 25']), '-2 x 0.25');
      expect(t(['2x 1. 19']), '2 x 1.19');
      expect(t(['0.986 kg (N) X', '4. 99 EÜR/kg']), '0.986 kg (N) x 4.99 EUR/kg');
    });

    test('Steuerblock', () {
      expect(t(['B: 10.00% MwSt von', '15.99 =', '1.60']), 'B: 10.00% MwSt von 15.99 = 1.60');
    });
  });

  group('paymentCutY (Zahlungsdaten verlassen das Geraet nie, B4)', () {
    test('Schnitt liegt direkt unter der Zeile Summe, weit vor dem Kundenbeleg', () {
      final lines = _load('billa_paper_02');
      final y = paymentCutY(lines, slope: estimateSlope(lines))!;
      final summe = lines.firstWhere((l) => l.text == 'Summe');
      final kundenbeleg = lines.firstWhere((l) => l.text.contains('Kundenbeleg'));
      expect(y, greaterThan(summe.box.bottom));
      expect(y, lessThan(kundenbeleg.box.top));
      // Nichts, was unter dem Schnitt beginnt, darf Kartendaten enthalten
      final below = lines.where((l) => l.box.top >= y).map((l) => l.text).join(' ');
      expect(below.contains('Terminal'), isTrue); // es liegt unten (wird abgeschnitten) ...
      expect(lines.where((l) => l.box.top < y).any((l) => RegExp(r'Terminal|VU-Nr|Trace|#\*').hasMatch(l.text)), isFalse);
    });

    test('Ohne Zeile Summe: Schnitt vor dem ersten Zahlungsstichwort', () {
      final lines = _load('billa_paper_02').where((l) => l.text != 'Summe' && l.text != 'EUR' && l.text != '26.38' && !l.text.startsWith('Gegeben')).toList();
      final y = paymentCutY(lines)!;
      final kundenbeleg = lines.firstWhere((l) => l.text.contains('Kundenbeleg'));
      expect(y, lessThanOrEqualTo(kundenbeleg.box.top));
    });

    test('Nichts erkannt: null, also kein Upload', () {
      expect(paymentCutY(const []), isNull);
      expect(paymentCutY([const OcrLine('Zwetschken 2.75', Rect.fromLTWH(0, 0, 100, 20))]), isNull);
    });

    test('Zahlungszeile ueberlappt die Zeile davor (unregelmaessiges Foto): kein Absturz statt ArgumentError '
        '(Fehlerbericht "Scan nicht möglich: invalid argument(s): 0", 2026-09-28, Hofer-Bon)', () {
      // Die Zeile davor endet (b=50) UNTERHALB des Beginns der Zahlungszeile (t=40): negative Differenz.
      final lines = [
        const OcrLine('166908 Bananen lose 1,11 A', Rect.fromLTRB(0, 0, 400, 50)),
        const OcrLine('Visa Debit', Rect.fromLTRB(0, 40, 200, 90)),
      ];
      final y = paymentCutY(lines);
      expect(y, 50); // kein zusaetzlicher Rand, Schnitt direkt an der Zeile davor
    });
  });
}
