import 'dart:convert';
import 'dart:io';

import 'package:einkaufstracker/domain/receipt/billa_text_parser.dart';
import 'package:einkaufstracker/domain/receipt/parsed_receipt.dart';
import 'package:einkaufstracker/domain/receipt/vienna_time.dart';
import 'package:flutter_test/flutter_test.dart';

const _parser = BillaTextParser();

String _fixture(String name) => File('test/fixtures/receipts/$name.txt').readAsStringSync();
Map<String, dynamic> _expected(String name) =>
    jsonDecode(File('test/fixtures/receipts/$name.expected.json').readAsStringSync()) as Map<String, dynamic>;

int _cents(String s) {
  final neg = s.startsWith('-');
  final p = s.replaceFirst('-', '').replaceAll(',', '.').split('.');
  final v = int.parse(p[0]) * 100 + int.parse(p[1]);
  return neg ? -v : v;
}

void main() {
  group('sechs echte digitale Billa-Bons (anonymisiert) gegen die Referenz des Python-Prototyps', () {
    for (var n = 1; n <= 6; n++) {
      final name = 'billa_digital_${n.toString().padLeft(2, '0')}';

      test('$name: Positionen, Summe, Steuerblock und Re-Nr stimmen exakt', () {
        final exp = _expected(name);
        final r = _parser.parse(_fixture(name));

        expect(r.isParsed, isTrue, reason: r.warnings.join('; '));
        expect(r.warnings, isEmpty);
        expect(r.totalCents, exp['total']);
        expect(r.subtotalCents, exp['subtotal']);
        expect(r.externalId, exp['reNr']);
        expect(r.branchCode, exp['branch']);

        final items = (exp['items'] as List).cast<Map<String, dynamic>>();
        expect(r.items.length, items.length);
        for (var i = 0; i < items.length; i++) {
          expect(r.items[i].rawText, items[i]['name'], reason: 'Position ${i + 1}');
          expect(r.items[i].lineTotalCents, items[i]['cents'], reason: r.items[i].rawText);
          expect(r.items[i].taxCode, items[i]['tax'], reason: r.items[i].rawText);
          expect(r.items[i].kind.name, items[i]['kind'], reason: r.items[i].rawText);
          final q = items[i]['qty'] as List?;
          if (q != null) {
            expect(r.items[i].quantity, double.parse(q[0] as String), reason: r.items[i].rawText);
            expect(r.items[i].unitPriceCents, _cents(q[2] as String), reason: r.items[i].rawText);
          } else {
            expect(r.items[i].quantity, 1);
          }
        }

        final bon = (exp['bon_discounts'] as List).cast<Map<String, dynamic>>();
        expect(r.bonDiscounts.length, bon.length);
        for (var i = 0; i < bon.length; i++) {
          expect(r.bonDiscounts[i].cents, bon[i]['cents']);
        }

        final tax = (exp['tax'] as Map).cast<String, dynamic>();
        expect(r.taxBlock.keys.toSet(), tax.keys.toSet());
        tax.forEach((code, v) => expect(r.taxBlock[code]!.grossCents, (v as Map)['gross'], reason: 'Klasse $code'));
      });

      test('$name: alle Plausibilitaetspruefungen bestehen', () {
        final r = _parser.parse(_fixture(name));
        final c = r.checks!;
        expect(c.totalMatches, isTrue, reason: 'Differenz ${c.differenceCents} Cent');
        expect(c.subtotalMatches ?? true, isTrue);
        expect(c.taxMatches, isTrue, reason: '${c.classDifferences} fehlend: ${c.missingTaxClasses}');
        expect(r.isTrustworthy, isTrue);
      });
    }
  });

  group('Sonderfaelle', () {
    test('Bon mit Rabattsammler: Zwischensumme, Bon-Rabatt, Mengenzeile, Pfand und Hinweiszeile', () {
      final r = _parser.parse(_fixture('billa_digital_03'));
      expect(r.subtotalCents, 5330);
      expect(r.totalCents, 4879);
      expect(r.bonDiscounts.single.cents, -451);
      expect(r.bonDiscounts.single.percent, 20);
      expect(r.items.where((i) => i.kind == ReceiptItemKind.deposit), isNotEmpty);
      // "2 x 2.85" steht VOR der Artikelzeile und gehoert zu den Cherrytomaten (5,70 EUR)
      final tomaten = r.items.firstWhere((i) => i.rawText.contains('Cherrytomaten'));
      expect(tomaten.quantity, 2);
      expect(tomaten.unitPriceCents, 285);
      expect(tomaten.lineTotalCents, 570);
      // die Mengenzeile selbst taucht nicht als Position auf
      expect(r.items.any((i) => i.rawText.startsWith('2 x')), isFalse);
    });

    test('Codereview-Fund 2026-10-01: ein positiv bepreister "AKTION"-Artikel ist kein Rabatt (nur negative Betraege sind Rabatte)', () {
      const text = '''
Billa AG
Datum: 01.10.2026          Zeit: 18:00

Milch                     H       1.50
AKTION Paradeiser 1kg     H       1.99
Summe EUR                         3.49
''';
      final r = _parser.parse(text);
      expect(r.isParsed, isTrue, reason: r.warnings.join('; '));
      final aktion = r.items.firstWhere((i) => i.rawText.startsWith('AKTION'));
      expect(aktion.kind, ReceiptItemKind.article);
      expect(aktion.lineTotalCents, 199);

      // Ein echter (negativ bepreister) Rabatt mit demselben Namensmuster bleibt weiterhin erkannt.
      final r2 = _parser.parse(text.replaceFirst('1.99', '-1.99'));
      final realDiscount = r2.items.firstWhere((i) => i.rawText.startsWith('AKTION'));
      expect(realDiscount.kind, ReceiptItemKind.discount);
    });

    test('Mengenrabatt "NIMM MEHR" ist ein Rabatt, Pfandartikel in Klasse D ein Pfand', () {
      final r = _parser.parse(_fixture('billa_digital_03'));
      final nimm = r.items.where((i) => i.rawText.startsWith('NIMM MEHR')).toList();
      expect(nimm, hasLength(3));
      expect(nimm.every((i) => i.kind == ReceiptItemKind.discount && i.lineTotalCents == -50), isTrue);
      final pfand = r.items.firstWhere((i) => i.rawText == 'PFANDARTIKEL');
      expect(pfand.kind, ReceiptItemKind.deposit);
      expect(pfand.taxCode, 'D');
      expect(r.taxBlock['D']!.grossCents, 25);
      expect(r.taxBlock['D']!.ratePercent, isNull);
    });

    test('Kaufzeit in Wiener Sommerzeit wird nach UTC umgerechnet (02.07.2026 19:51 = 17:51 UTC)', () {
      final r = _parser.parse(_fixture('billa_digital_04'));
      expect(r.purchasedAtUtc, DateTime.utc(2026, 7, 2, 17, 51));
    });

    test('Geschuetzte Leerzeichen (NBSP) und Windows-Zeilenenden stoeren nicht', () {
      final t = _fixture('billa_digital_04').replaceAll(' ', ' ').replaceAll('\n', '\r\n');
      final r = _parser.parse(t);
      expect(r.isTrustworthy, isTrue);
      expect(r.items.length, 10);
    });

    test('Fehlende Zeile in den Positionen wird von Summen- und Steuercheck bemerkt', () {
      // erste Position (Champignon 1,89) entfernen
      final lines = _fixture('billa_digital_04').split('\n');
      lines.removeWhere((l) => l.contains('Clever Champignon'));
      final r = _parser.parse(lines.join('\n'));
      expect(r.isParsed, isTrue);
      expect(r.checks!.totalMatches, isFalse);
      expect(r.checks!.differenceCents, 189);
      expect(r.checks!.taxMatches, isFalse);
      expect(r.checks!.classDifferences['H'], -189);
      expect(r.isTrustworthy, isFalse);
    });

    test('Falsch gelesene Ziffer wird bemerkt (2.85 statt 2.35)', () {
      final t = _fixture('billa_digital_04').replaceFirst('2.85', '2.35');
      final r = _parser.parse(t);
      expect(r.checks!.totalMatches, isFalse);
      expect(r.checks!.differenceCents, 50);
    });

    test('Kein Bon: liefert ein Fehlerergebnis statt einer Ausnahme', () {
      final r = _parser.parse('Das ist keine Rechnung.\nNur Text.');
      expect(r.isParsed, isFalse);
      expect(r.warnings, isNotEmpty);
      expect(r.isTrustworthy, isFalse);
    });

    test('Leere Eingabe', () {
      expect(_parser.parse('').isParsed, isFalse);
    });

    test('Artikelname mit Sonderzeichen bleibt eine normale Position', () {
      final t = _fixture('billa_digital_04').replaceFirst('Clever Hirtenkäse', '@@@ Clever Hirtenkäse ###');
      final r = _parser.parse(t);
      expect(r.items.any((i) => i.rawText.contains('@@@')), isTrue); // Name mit Sonderzeichen bleibt Position
    });
  });

  group('Wiener Zeit', () {
    test('Winterzeit: UTC+1', () {
      expect(viennaLocalToUtc(2026, 1, 15, 12, 0), DateTime.utc(2026, 1, 15, 11, 0));
    });
    test('Sommerzeit: UTC+2', () {
      expect(viennaLocalToUtc(2026, 7, 15, 12, 0), DateTime.utc(2026, 7, 15, 10, 0));
    });
    test('Umstellung im Maerz 2026: 29.03. 03:30 lokal ist schon Sommerzeit', () {
      expect(viennaLocalToUtc(2026, 3, 29, 3, 30), DateTime.utc(2026, 3, 29, 1, 30));
      expect(viennaLocalToUtc(2026, 3, 28, 12, 0), DateTime.utc(2026, 3, 28, 11, 0)); // Tag davor Winterzeit
    });
    test('Umstellung im Oktober 2026: 25.10. 12:00 lokal ist wieder Winterzeit', () {
      expect(viennaLocalToUtc(2026, 10, 25, 12, 0), DateTime.utc(2026, 10, 25, 11, 0));
      expect(viennaLocalToUtc(2026, 10, 24, 12, 0), DateTime.utc(2026, 10, 24, 10, 0)); // Tag davor Sommerzeit
    });
  });
}
