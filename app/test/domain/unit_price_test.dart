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
  });
}
