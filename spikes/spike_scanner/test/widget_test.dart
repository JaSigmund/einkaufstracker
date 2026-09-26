import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:spike_scanner/row_cluster.dart';

OcrLine line(String t, double l, double top, {double w = 100, double h = 20}) =>
    OcrLine(t, Rect.fromLTWH(l, top, w, h));

/// Bon-Zeile mit Name links (x=10) und Preis rechts (x=700), um [skew] Pixel schraeg (Preis hoeher).
List<OcrLine> receiptRow(String name, String price, double y, {double skew = 0}) => [
      line(name, 10, y, w: 300),
      line(price, 700, y + skew, w: 90),
    ];

void main() {
  group('Zeilenclustering', () {
    test('Name links und Preis rechts landen in derselben Bildzeile', () {
      final rows = clusterRows([
        line('2,49', 300, 103),
        line('MILCH 1L', 10, 100),
        line('BROT', 10, 130),
        line('1,99', 300, 131),
      ]);
      expect(rows.length, 2);
      expect(renderRows(rows), 'MILCH 1L | 2,49\nBROT | 1,99');
    });

    test('Zeilen werden von oben nach unten sortiert', () {
      final rows = clusterRows([line('B', 0, 200), line('A', 0, 100), line('C', 0, 300)]);
      expect(rows.map((r) => r.single.text), ['A', 'B', 'C']);
    });

    test('Leere Eingabe ergibt keine Zeilen', () {
      expect(clusterRows([]), isEmpty);
    });

    test('Nahe, aber getrennte Zeilen werden nicht verschmolzen', () {
      final rows = clusterRows([line('X', 0, 100), line('Y', 0, 125)]);
      expect(rows.length, 2);
    });
  });

  group('Preise', () {
    test('parsePrice liest verrauschte OCR-Preise', () {
      expect(parsePrice('2. 75'), 2.75);
      expect(parsePrice('.-0. 96'), -0.96);
      expect(parsePrice('23, 19'), 23.19);
      expect(parsePrice('-0.86'), -0.86);
      expect(parsePrice('0.'), isNull);
      expect(parsePrice('Summe'), isNull);
      expect(parsePrice('ATU 15255907'), isNull);
    });
  });

  group('Schraeglage', () {
    // 10 Zeilen, Preis rechts um 35 px hoeher als der Name (Bon schraeg fotografiert), Zeilenabstand 40 px
    List<OcrLine> skewed() => [
          for (var i = 0; i < 10; i++) ...receiptRow('ARTIKEL $i', '${i + 1}.00', 100.0 + i * 40, skew: -35),
        ];

    test('ohne Korrektur werden Preise falschen Zeilen zugeordnet', () {
      final rows = clusterRows(skewed());
      final paired = rows.where((r) => r.length == 2).length;
      expect(paired, lessThan(10));
    });

    test('estimateSlope findet die Schraeglage, danach passen alle Paare', () {
      final lines = skewed();
      final slope = estimateSlope(lines);
      expect(slope, closeTo(-35 / 690, 0.02)); // dy/dx zwischen Namensmitte und Preismitte
      final rows = clusterRows(lines, slope: slope);
      expect(rows.length, 10);
      expect(rows.every((r) => r.length == 2), isTrue);
      expect(rows.first.first.text, 'ARTIKEL 0');
      expect(rows.first.last.text, '1.00');
    });

    test('gerader Bon ergibt Steigung nahe 0', () {
      final lines = [for (var i = 0; i < 8; i++) ...receiptRow('ART $i', '1.00', 100.0 + i * 40)];
      expect(estimateSlope(lines).abs(), lessThan(0.02));
    });
  });

  group('Summencheck', () {
    List<List<OcrLine>> bon(List<String> prices, String total) => [
          [line('Datum: 24.09.2026', 10, 50)],
          for (var i = 0; i < prices.length; i++) [line('ART $i', 10, 100.0 + i * 40), line(prices[i], 700, 100.0 + i * 40)],
          [line('Summe', 10, 600), line(total, 700, 600)],
        ];

    test('passt, wenn Positionen die Bon-Summe ergeben (inkl. Rabatt)', () {
      final c = checkSum(bon(['2.75', '-0.96', '4.92'], '6.71'));
      expect(c.ok, isTrue);
      expect(c.pricesFound, 3);
    });

    test('meldet Abweichung, wenn Preise fehlen', () {
      final c = checkSum(bon(['2.75', '-0.96'], '6.71'));
      expect(c.ok, isFalse);
      expect(c.difference, closeTo(4.92, 0.001));
    });

    test('ohne Summenzeile keine Aussage', () {
      final c = checkSum([
        [line('Datum: 24.09.2026', 10, 50)],
        [line('ART', 10, 100), line('1.00', 700, 100)],
      ]);
      expect(c.billTotal, isNull);
      expect(c.ok, isFalse);
    });
  });

  // Regressionstest mit einem echten Billa-Bon (Golden Set, lokal, nicht im Git).
  // Wird uebersprungen, wenn die Datei fehlt.
  group('Echter Billa-Bon (billa-001)', () {
    final file = File('../../testdata/receipts/billa-001.ocr.json');
    final skip = file.existsSync() ? null : 'testdata/receipts/billa-001.ocr.json fehlt';

    List<OcrLine> load() {
      final j = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final page = (j['pages'] as List).first as Map<String, dynamic>;
      return [
        for (final l in page['lines'] as List)
          OcrLine(l['text'] as String, Rect.fromLTRB((l['l'] as num).toDouble(), (l['t'] as num).toDouble(), (l['r'] as num).toDouble(), (l['b'] as num).toDouble())),
      ];
    }

    test('Schraeglage wird erkannt (ca. -3,4 Grad)', () {
      expect(estimateSlope(load()), closeTo(-0.06, 0.02));
    }, skip: skip);

    test('Summencheck erkennt die fehlenden Preise (Soll 23,19, erkannt 9,98)', () {
      final lines = load();
      final rows = clusterRows(lines, slope: estimateSlope(lines));
      final c = checkSum(rows);
      expect(c.billTotal, 23.19);
      expect(c.ok, isFalse);
      expect(c.pricesSum, closeTo(9.98, 0.001));
      expect(c.difference, closeTo(13.21, 0.001));
    }, skip: skip);

    test('Zwetschken und 2,75 stehen nach der Korrektur in einer Zeile', () {
      final lines = load();
      final rows = clusterRows(lines, slope: estimateSlope(lines));
      final row = rows.firstWhere((r) => r.any((l) => l.text.startsWith('Zwetschken')));
      expect(row.any((l) => parsePrice(l.text) == 2.75), isTrue);
    }, skip: skip);
  });

  group('Mengenzeilen', () {
    test('isQuantityRow erkennt typische Billa-Mengenzeilen', () {
      expect(isQuantityRow([line('2x', 10, 0), line('1. 19', 300, 0)]), isTrue);
      expect(isQuantityRow([line('2x 1. 19', 10, 0)]), isTrue);
      expect(isQuantityRow([line('-2_X', 10, 0), line('0. 25', 300, 0)]), isTrue);
      expect(isQuantityRow([line('0.986 kg (N) X', 10, 0), line('4. 99 EUR/kg', 300, 0)]), isTrue);
      expect(isQuantityRow([line('IC CV gehackte Tomaten', 10, 0), line('1.38', 300, 0)]), isFalse);
      expect(isQuantityRow([line('2 Stk Bio Milch', 10, 0), line('1.29', 300, 0)]), isFalse);
    });

    test('Mengenzeile und Zwischensumme zaehlen nicht zur Summe', () {
      final rows = <List<OcrLine>>[
        [line('Datum: 24.09.2026', 10, 50)],
        [line('ART A', 10, 100), line('2.99', 700, 100)],
        [line('2x', 10, 140), line('1.19', 300, 140)],
        [line('ART B', 10, 180), line('2.38', 700, 180)],
        [line('Zwischensumme', 10, 220), line('5.37', 700, 220)],
        [line('Summe', 10, 260), line('5.37', 700, 260)],
      ];
      final c = checkSum(rows);
      expect(c.pricesSum, closeTo(5.37, 0.001));
      expect(c.ok, isTrue);
    });
  });

  group('Echter Billa-Bon (billa-002, Papier 26.09.)', () {
    final file = File('../../testdata/receipts/billa-002.ocr.json');
    final skip = file.existsSync() ? null : 'testdata/receipts/billa-002.ocr.json fehlt';

    List<OcrLine> load() {
      final j = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final page = (j['pages'] as List).first as Map<String, dynamic>;
      return [
        for (final l in page['lines'] as List)
          OcrLine(l['text'] as String, Rect.fromLTRB((l['l'] as num).toDouble(), (l['t'] as num).toDouble(), (l['r'] as num).toDouble(), (l['b'] as num).toDouble())),
      ];
    }

    test('Alle 17 Preise erkannt, Summencheck besteht (26,38 EUR)', () {
      final lines = load();
      final rows = clusterRows(lines, slope: estimateSlope(lines));
      final c = checkSum(rows);
      expect(c.billTotal, 26.38);
      expect(c.pricesFound, 17);
      expect(c.pricesSum, closeTo(26.38, 0.001));
      expect(c.ok, isTrue);
    }, skip: skip);
  });
}
