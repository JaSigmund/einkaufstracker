import 'package:einkaufstracker/domain/receipt/purchased_amount.dart';
import 'package:flutter_test/flutter_test.dart';

/// Die Faelle stammen aus echten Bonzeilen (Stand 2026-11-01), nur die Mengen sind teils zusammengefasst.
PurchasedAmount _of(List<({double qty, String unit, String text, String? base, double? pack})> lines) {
  final a = PurchasedAmount();
  for (final l in lines) {
    a.add(quantity: l.qty, quantityUnit: l.unit, rawText: l.text, productBaseUnit: l.base, productPackSize: l.pack);
  }
  return a;
}

({double qty, String unit, String text, String? base, double? pack}) _l(String text, {double qty = 1, String unit = 'piece', String? base, double? pack}) =>
    (qty: qty, unit: unit, text: text, base: base, pack: pack);

void main() {
  group('PurchasedAmount.describe', () {
    test('gleiche Packung mehrmals: Anzahl, Inhalt und Gesamtmenge', () {
      final faschiertes = _l('IC CV Faschiertes gem.', base: 'kg', pack: 0.5);
      expect(_of([faschiertes, faschiertes, faschiertes, faschiertes]).describe(), '4× je 500 g · 2 kg gesamt');
    });

    test('eine Zeile mit Bon-Menge 2 zaehlt zwei Packungen', () {
      expect(_of([_l('Srd Berghof Vollmilch', qty: 2, base: 'l', pack: 1)]).describe(), '2× je 1 l · 2 l gesamt');
    });

    test('eine einzelne Packung braucht keine Gesamtmenge', () {
      expect(_of([_l('IC Santa M Taco Kräut.m', base: 'kg', pack: 0.028)]).describe(), '1× 28 g');
    });

    test('Bon-Text schlaegt die Packungsgroesse des Produkts, verschiedene Packungen stehen einzeln da', () {
      expect(
        _of([_l('Zwiebeln gelb 1kg', base: 'kg', pack: 1), _l('Zwiebeln gelb 3kg', qty: 2, base: 'kg', pack: 1)]).describe(),
        '1× 1 kg, 2× 3 kg · 7 kg gesamt',
      );
    });

    test('Packungsgroesse aus Text und Produkt in leicht anderer Schreibweise sind dieselbe', () {
      expect(_of([_l('Baguette 170 G'), _l('Baguette', base: 'kg', pack: 0.17)]).describe(), '2× je 170 g · 340 g gesamt');
    });

    test('Mehrfachpackung im Bon-Text wird ausmultipliziert', () {
      expect(_of([_l('Tyrolini mild 4x40g', qty: 2)]).describe(), '2× je 160 g · 320 g gesamt');
    });

    test('Stueckpackungen', () {
      expect(_of([_l('IC DKIH Paprika Tricolore', qty: 3, base: 'piece', pack: 3)]).describe(), '3× je 3 Stk. · 9 Stk. gesamt');
    });

    test('gewogene Ware', () {
      expect(_of([_l('Bananen', qty: 0.555, unit: 'kg')]).describe(), '1× gewogen · 555 g gesamt');
      expect(_of([_l('Bananen', qty: 0.555, unit: 'kg'), _l('Bananen', qty: 1.17, unit: 'kg')]).describe(), '2× gewogen · 1,725 kg gesamt');
    });

    test('Packung und gewogen gemischt', () {
      expect(
        _of([_l('Äpfel 1kg'), _l('Äpfel', qty: 0.5, unit: 'kg')]).describe(),
        '1× 1 kg, 1× gewogen · 1,5 kg gesamt',
      );
    });

    test('ohne jede Angabe bleibt nur die Anzahl', () {
      expect(_of([_l('IC Gurke Stk.', qty: 2), _l('IC Gurke Stk.')]).describe(), '3× gekauft');
    });

    test('teils unbekannt: Gesamtmenge ist nur eine Untergrenze', () {
      expect(_of([_l('Pesto 200g'), _l('Pesto')]).describe(), '1× 200 g, 1× ohne Angabe · mind. 200 g gesamt');
    });

    test('verschiedene Einheiten werden nicht zusammengezaehlt', () {
      expect(_of([_l('Kokos 400g'), _l('Kokos 1l')]).describe(), '1× 400 g, 1× 1 l · 400 g + 1 l gesamt');
    });

    test('eine Stueck-"Packung" mit einem Stueck sagt nichts aus', () {
      expect(_of([_l('Avocado', base: 'piece', pack: 1)]).describe(), '1× gekauft');
    });

    test('nichts aufgenommen: kein Text', () {
      expect(PurchasedAmount().describe(), isNull);
    });
  });
}
