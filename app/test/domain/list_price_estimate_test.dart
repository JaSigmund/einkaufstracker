import 'package:einkaufstracker/domain/shopping_list/list_price_estimate.dart';
import 'package:flutter_test/flutter_test.dart';

/// Testet die Summenschaetzung der Einkaufsliste (Feature-Idee aus Wettbewerbsanalyse, Doku
/// [[21 Feature-Ideen aus Wettbewerbsanalyse]], beantwortet die offene Frage Q-10).
void main() {
  group('estimateShoppingListTotal', () {
    test('Packware mit bekanntem Packungsinhalt: Anzahl mal Inhalt mal Grundpreis', () {
      // 2 Packungen a 1 kg (packSize in der Basiseinheit des Produkts, hier 'kg'), Grundpreis 150 Cent/kg
      // -> 2 kg * 150 = 300 Cent
      final result = estimateShoppingListTotal([
        (quantity: 2.0, packSize: 1.0, lastUnitPriceNormCents: 150),
      ]);
      expect(result.totalCents, 300);
      expect(result.itemsWithPrice, 1);
      expect(result.itemsWithoutPrice, 0);
      expect(result.isComplete, isTrue);
    });

    test('Stueckware ohne Packungsinhalt: Anzahl direkt als Basiseinheit', () {
      // 3 Stueck, Grundpreis 50 Cent/Stk -> 150 Cent
      final result = estimateShoppingListTotal([
        (quantity: 3.0, packSize: null, lastUnitPriceNormCents: 50),
      ]);
      expect(result.totalCents, 150);
    });

    test('Produkt ohne bekannten Preis (nie gekauft): zaehlt nicht mit, wird aber gemeldet', () {
      final result = estimateShoppingListTotal([
        (quantity: 1.0, packSize: null, lastUnitPriceNormCents: 100),
        (quantity: 2.0, packSize: null, lastUnitPriceNormCents: null),
      ]);
      expect(result.totalCents, 100);
      expect(result.itemsWithPrice, 1);
      expect(result.itemsWithoutPrice, 1);
      expect(result.isComplete, isFalse);
    });

    test('leere Liste: Summe 0, nichts fehlt', () {
      final result = estimateShoppingListTotal(const []);
      expect(result.totalCents, 0);
      expect(result.isComplete, isTrue);
    });

    test('mehrere Positionen werden aufsummiert', () {
      final result = estimateShoppingListTotal([
        (quantity: 1.0, packSize: 0.5, lastUnitPriceNormCents: 200), // 0,5 kg * 200 = 100
        (quantity: 2.0, packSize: null, lastUnitPriceNormCents: 30), // 2 Stk * 30 = 60
      ]);
      expect(result.totalCents, 160);
      expect(result.itemsWithPrice, 2);
    });
  });

  group('EstimateVsActual', () {
    test('teurer als geschaetzt: positive Differenz', () {
      const e = EstimateVsActual(estimatedCents: 1000, actualCents: 1200);
      expect(e.differenceCents, 200);
    });

    test('guenstiger als geschaetzt: negative Differenz', () {
      const e = EstimateVsActual(estimatedCents: 1000, actualCents: 800);
      expect(e.differenceCents, -200);
    });

    test('exakt getroffen: Differenz 0', () {
      const e = EstimateVsActual(estimatedCents: 500, actualCents: 500);
      expect(e.differenceCents, 0);
    });
  });
}
