import 'package:einkaufstracker/domain/online_prices/heisse_preise_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Testet den Parser fuer den `heisse-preise.io`-Feed (ADR-019) gegen eine Stichprobe echter Eintraege
/// vom 2026-10-01 (heruntergeladen von `https://heisse-preise.io/data/latest-canonical.json`, trimmt
/// auf die fuer die Normalisierung relevanten Felder).
void main() {
  group('normalizeHeissePreiseEntry', () {
    test('Billa, saubere Einheit g, Packware: Grundpreis in Cent je kg', () {
      // Echter Eintrag: "11er 11 Minuten Pommes", 3,99 EUR / 600 g
      final result = normalizeHeissePreiseEntry((
        store: 'billa',
        id: '00-600283',
        name: '11er 11 Minuten Pommes',
        price: 3.99,
        unit: 'g',
        quantity: 600,
        isWeighted: false,
        unavailable: false,
      ));
      expect(result, isNotNull);
      expect(result!.priceCents, 399);
      expect(result.baseUnit, 'kg');
      // 399 Cent / 0,6 kg = 665 Cent/kg
      expect(result.unitPriceNormCents, 665);
    });

    test('Billa, Wiegeware (isWeighted): gleiche Formel wie Packware', () {
      // Echter Eintrag: "Ablinger Pikantwurst", 21,90 EUR / 1000 g
      final result = normalizeHeissePreiseEntry((
        store: 'billa',
        id: '00-32218',
        name: 'Ablinger Pikantwurst',
        price: 21.90,
        unit: 'g',
        quantity: 1000,
        isWeighted: true,
        unavailable: false,
      ));
      expect(result!.priceCents, 2190);
      expect(result.baseUnit, 'kg');
      expect(result.unitPriceNormCents, 2190);
    });

    test('Spar, Einheit l: Grundpreis in Cent je Liter', () {
      // Echter Eintrag: "A-zwei Vollmilch laenger frisch", 2,08 EUR / 1 l
      final result = normalizeHeissePreiseEntry((
        store: 'spar',
        id: '2020002600662',
        name: 'A-zwei Vollmilch laenger frisch',
        price: 2.08,
        unit: 'l',
        quantity: 1,
        isWeighted: false,
        unavailable: false,
      ));
      expect(result!.baseUnit, 'l');
      expect(result.unitPriceNormCents, 208);
    });

    test('unbekannte Einheit (z.B. "wg" fuer Waschgaenge): Preis ohne Grundpreis statt falschem Wert', () {
      // Echter Eintrag: "Ariel All in One Color Waschmittelpods", 8,49 EUR / 19 Waschgaenge
      final result = normalizeHeissePreiseEntry((
        store: 'billa',
        id: '00-771098',
        name: 'Ariel All in One Color Waschmittelpods',
        price: 8.49,
        unit: 'wg',
        quantity: 19,
        isWeighted: false,
        unavailable: false,
      ));
      expect(result!.priceCents, 849);
      expect(result.baseUnit, isNull);
      expect(result.unitPriceNormCents, isNull);
    });

    test('unavailable: wird als nicht (mehr) im Sortiment behandelt, kein Ergebnis', () {
      final result = normalizeHeissePreiseEntry((
        store: 'billa',
        id: '00-650902',
        name: 'Vivoy bei Blasenschwaeche Schwarze Pants fuer Frauen L',
        price: 6.49,
        unit: 'stk',
        quantity: 10,
        isWeighted: false,
        unavailable: true,
      ));
      expect(result, isNull);
    });

    test('Hofer liefert numerische IDs statt Strings: externalId wird trotzdem ein String', () {
      // Echter Eintrag, zufaellig auch unavailable (Hofer-Daten im Feed Stand 2026-10-01 durchgehend
      // veraltet, siehe Doku-Kommentar in heisse_preise_parser.dart) -- hier isoliert mit
      // unavailable: false getestet, damit die ID-Typumwandlung unabhaengig von diesem separaten
      // Befund geprueft ist.
      final result = normalizeHeissePreiseEntry((
        store: 'hofer',
        id: 547270,
        name: 'HOFER MARKTPLATZ Knoblauch 400g',
        price: 2.29,
        unit: 'g',
        quantity: 400,
        isWeighted: false,
        unavailable: false,
      ));
      expect(result!.externalId, '547270');
      expect(result.externalId, isA<String>());
    });

    test('Menge fehlt oder ist 0: kein Grundpreis, Preis bleibt erhalten', () {
      final result = normalizeHeissePreiseEntry((
        store: 'billa',
        id: '00-999999',
        name: 'Testprodukt ohne Mengenangabe',
        price: 1.50,
        unit: 'stk',
        quantity: null,
        isWeighted: false,
        unavailable: false,
      ));
      expect(result!.priceCents, 150);
      expect(result.unitPriceNormCents, isNull);
    });
  });
}
