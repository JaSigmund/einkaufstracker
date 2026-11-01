import 'package:einkaufstracker/domain/receipt/unit_price.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('computeUnitPriceNormCents (Doku 07 §3.1)', () {
    test('Wiegeware: Bon-Menge steht schon in der Basiseinheit', () {
      // 0,62 kg Paprika fuer 249 Cent -> 401,6.. -> 402 Cent/kg
      final price = computeUnitPriceNormCents(lineTotalCents: 249, quantity: 0.62, quantityUnit: 'kg', productBaseUnit: 'kg');
      expect(price, 402);
    });

    test('Stueckware: kein Packungsinhalt noetig', () {
      final price = computeUnitPriceNormCents(lineTotalCents: 300, quantity: 6, quantityUnit: 'piece', productBaseUnit: 'piece');
      expect(price, 50); // 3,00 EUR / 6 Stk = 0,50 EUR/Stk
    });

    test('Packware mit bekanntem Inhalt: Bon-Menge sind Packungen, Inhalt skaliert auf die Basiseinheit', () {
      // 1 Packung Milch (1 l Inhalt) fuer 129 Cent -> 129 Cent/l
      final price = computeUnitPriceNormCents(lineTotalCents: 129, quantity: 1, quantityUnit: 'piece', productBaseUnit: 'l', packSize: 1);
      expect(price, 129);
    });

    test('Packware, mehrere Packungen', () {
      // 2 Packungen Champignons (je 150 g) fuer 398 Cent -> 398 / 0,3 kg = 1326,67 -> 1327 Cent/kg
      final price = computeUnitPriceNormCents(lineTotalCents: 398, quantity: 2, quantityUnit: 'piece', productBaseUnit: 'kg', packSize: 0.15);
      expect(price, 1327);
    });

    test('Packware mit stueckbasierter Basiseinheit: Grundpreis je Einzelstueck, nicht je Packung '
        '(Fehlerbericht "Preis wird nicht auf Einheit heruntergerechnet", 2026-09-28)', () {
      // 1 Packung Paprika Tricolore (4 Stueck je Packung) fuer 249 Cent -> 62,25 -> 62 Cent je Paprika
      final price = computeUnitPriceNormCents(lineTotalCents: 249, quantity: 1, quantityUnit: 'piece', productBaseUnit: 'piece', packSize: 4);
      expect(price, 62);
    });

    test('Packware ohne bekannten Inhalt: kein Grundpreis statt eines falschen Werts', () {
      final price = computeUnitPriceNormCents(lineTotalCents: 129, quantity: 1, quantityUnit: 'piece', productBaseUnit: 'l', packSize: null);
      expect(price, isNull);
    });

    test('Packungsinhalt 0 oder negativ: kein Grundpreis', () {
      expect(computeUnitPriceNormCents(lineTotalCents: 129, quantity: 1, quantityUnit: 'piece', productBaseUnit: 'l', packSize: 0), isNull);
    });

    test('Menge 0: kein Grundpreis (Division durch 0 vermeiden)', () {
      expect(computeUnitPriceNormCents(lineTotalCents: 129, quantity: 0, quantityUnit: 'kg', productBaseUnit: 'kg'), isNull);
    });

    test('Bon-Text geht packSize vor: Zwiebeln 3 kg bei einem Produkt, das mit 1 kg angelegt ist', () {
      final price = computeUnitPriceNormCents(
          lineTotalCents: 199, quantity: 1, quantityUnit: 'piece', productBaseUnit: 'kg', packSize: 1, rawText: 'Zwiebeln gelb 3kg');
      expect(price, 66); // 1,99 EUR / 3 kg
    });

    test('Bon-Text ohne Mengenangabe: packSize gilt', () {
      final price = computeUnitPriceNormCents(
          lineTotalCents: 199, quantity: 1, quantityUnit: 'piece', productBaseUnit: 'kg', packSize: 0.5, rawText: 'Zwiebeln gelb');
      expect(price, 398);
    });

    test('Bon-Text liefert den Inhalt, auch wenn das Produkt keinen packSize hat', () {
      final price = computeUnitPriceNormCents(
          lineTotalCents: 399, quantity: 1, quantityUnit: 'piece', productBaseUnit: 'kg', rawText: 'Heidelbeeren 300g');
      expect(price, 1330);
    });

    test('Mehrfachpackung aus dem Bon-Text, mehrere gekaufte Packungen', () {
      final price = computeUnitPriceNormCents(
          lineTotalCents: 798, quantity: 2, quantityUnit: 'piece', productBaseUnit: 'kg', rawText: 'Tyrolini mild 4x40g');
      expect(price, 2494); // 7,98 EUR / (2 * 0,16 kg)
    });

    test('Einheit im Bon-Text passt nicht zur Basiseinheit: packSize gilt, der Grundpreis bleibt je Stueck', () {
      expect(
          computeUnitPriceNormCents(lineTotalCents: 249, quantity: 1, quantityUnit: 'piece', productBaseUnit: 'piece', packSize: 4, rawText: 'Paprika 500g'),
          62);
      expect(computeUnitPriceNormCents(lineTotalCents: 249, quantity: 1, quantityUnit: 'piece', productBaseUnit: 'piece', rawText: 'Rote Papr i ka 500g'), 249);
      expect(computeUnitPriceNormCents(lineTotalCents: 129, quantity: 1, quantityUnit: 'piece', productBaseUnit: 'l', rawText: 'Kaese 200g'), isNull);
    });

    test('Wiegeware: die Bon-Menge zaehlt, eine Angabe im Text aendert nichts', () {
      final price = computeUnitPriceNormCents(lineTotalCents: 249, quantity: 0.62, quantityUnit: 'kg', productBaseUnit: 'kg', rawText: 'Trauben 500g');
      expect(price, 402);
    });
  });

  group('parsePackSizeFromReceiptText', () {
    // Schreibweisen von echten Bons (Stand der Produktbereinigung 2026-11-01)
    const realTexts = <String, ReceiptPackSize>{
      'Zwiebeln gelb 3kg': (amount: 3, unit: 'kg'),
      'IC DKIH Zwiebel gelb 1kg': (amount: 1, unit: 'kg'),
      'Heidelbeeren 300g': (amount: 0.3, unit: 'kg'),
      'BM GUACAMOLE 150 G': (amount: 0.15, unit: 'kg'),
      'SG RUCOLA SALAT 125G': (amount: 0.125, unit: 'kg'),
      'CV FASCHIERTES GEM.500G': (amount: 0.5, unit: 'kg'),
      'Chips Papr i ka 250g': (amount: 0.25, unit: 'kg'),
      'Tyrolini mild 4x40g': (amount: 0.16, unit: 'kg'),
      'BIO-MW Milch 1l': (amount: 1, unit: 'l'),
      'HAPPY DAY WINTERAPFEL 1 L': (amount: 1, unit: 'l'),
    };
    for (final e in realTexts.entries) {
      test(e.key, () {
        final size = parsePackSizeFromReceiptText(e.key)!;
        expect(size.amount, closeTo(e.value.amount, 1e-9));
        expect(size.unit, e.value.unit);
      });
    }

    test('weitere Schreibweisen: Komma, Punkt, dag, ml, cl, Mehrfachpackung mit Leerzeichen', () {
      expect(parsePackSizeFromReceiptText('Mineral 0,5l')!.amount, 0.5);
      expect(parsePackSizeFromReceiptText('Cola 1.5 L')!.amount, 1.5);
      expect(parsePackSizeFromReceiptText('Extrawurst 20 dag')!.amount, closeTo(0.2, 1e-9));
      expect(parsePackSizeFromReceiptText('Wurst 15dkg')!.amount, closeTo(0.15, 1e-9));
      expect(parsePackSizeFromReceiptText('Hafer 250 ml'), (amount: 0.25, unit: 'l'));
      expect(parsePackSizeFromReceiptText('Bier 33cl'), (amount: 0.33, unit: 'l'));
      expect(parsePackSizeFromReceiptText('Joghurt 4 X 150G')!.amount, closeTo(0.6, 1e-9));
    });

    test('keine Mengenangabe, auch wenn Ziffern im Text stehen', () {
      for (final text in [
        'Faschiertes',
        'FLASCHE 0.20',
        'IC CV Champig. 3.Wahl',
        'Frisch gekocht November 2',
        'Eier BH 10er',
        'IC Knoppers Kokosr. 3er',
        'Vollmilch 3,5%',
        'H2O Limo',
        'Gurke Stk.',
        '1 Liebe',
        'Kaese 0g',
      ]) {
        expect(parsePackSizeFromReceiptText(text), isNull, reason: text);
      }
    });

    test('mehrere verschiedene Angaben sind unklar, dieselbe doppelt nicht', () {
      expect(parsePackSizeFromReceiptText('Thunfisch 185g 140g'), isNull);
      expect(parsePackSizeFromReceiptText('Thunfisch 0,5kg 500g'), (amount: 0.5, unit: 'kg'));
    });
  });
}
