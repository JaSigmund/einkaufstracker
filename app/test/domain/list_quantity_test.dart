import 'package:einkaufstracker/domain/shopping_list/list_quantity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Anzeige', () {
    test('Der gemeldete Fall: eine Packung Yakult mit 0,29 l zeigt nicht mehr "1 l"', () {
      final t = describeListQuantity(quantity: 1, unit: 'l', packSize: 0.29, productBaseUnit: 'l');
      expect(t.primary, '1 × 290 ml');
      expect(t.total, isNull);
    });

    test('Mehrere Packungen nennen zusaetzlich die Gesamtmenge', () {
      final t = describeListQuantity(quantity: 2, unit: 'l', packSize: 0.29, productBaseUnit: 'l');
      expect(t.primary, '2 × 290 ml');
      expect(t.total, '580 ml');
    });

    test('Ab einem Liter oder Kilo steht die grosse Einheit', () {
      expect(describeListQuantity(quantity: 3, unit: 'kg', packSize: 0.5, productBaseUnit: 'kg').total, '1,5 kg');
      expect(describeListQuantity(quantity: 1, unit: 'l', packSize: 1, productBaseUnit: 'l').primary, '1 × 1 l');
    });

    test('Bruchteil einer Packung zeigt die Menge', () {
      final t = describeListQuantity(quantity: 0.3, unit: 'kg', packSize: 0.5, productBaseUnit: 'kg');
      expect(t.primary, '150 g');
      expect(t.total, isNull);
    });

    test('Stueck: einzeln nur die Anzahl, im Mehrfachpack mit Inhalt', () {
      expect(describeListQuantity(quantity: 3, unit: 'piece', packSize: 1, productBaseUnit: 'piece').primary, '3 Stk');
      final eggs = describeListQuantity(quantity: 2, unit: 'piece', packSize: 6, productBaseUnit: 'piece');
      expect(eggs.primary, '2 × 6 Stk');
      expect(eggs.total, '12 Stk');
    });

    test('Ohne Inhalt ist die Zahl die Menge', () {
      expect(describeListQuantity(quantity: 2, unit: 'piece').primary, '2 Stk');
      expect(describeListQuantity(quantity: 0.25, unit: 'kg').primary, '250 g');
      expect(describeListQuantity(quantity: 1.5, unit: 'l', productBaseUnit: 'l').primary, '1,5 l');
    });

    test('Rundungsreste sieht man nicht', () {
      expect(formatListAmount(0.1 + 0.2, 'kg'), '300 g');
      expect(describeListQuantity(quantity: 0.331, unit: 'l', packSize: 0.29, productBaseUnit: 'l').primary, '96 ml');
    });
  });

  group('Eingabe', () {
    test('Menge bei Produkt mit Inhalt wird zu Packungen', () {
      final r = listQuantityFromAmount(150, ListAmountUnit.g, packSize: 0.5)!;
      expect(r.quantity, 0.3);
      expect(r.unit, 'kg');
    });

    test('Menge ohne Inhalt wird in Grundeinheit gespeichert', () {
      expect(listQuantityFromAmount(250, ListAmountUnit.ml), (quantity: 0.25, unit: 'l'));
      expect(listQuantityFromAmount(3, ListAmountUnit.piece), (quantity: 3.0, unit: 'piece'));
    });

    test('Was der Server auf 0 runden wuerde, wird abgelehnt', () {
      expect(listQuantityFromAmount(0, ListAmountUnit.g), isNull);
      expect(listQuantityFromAmount(-1, ListAmountUnit.kg), isNull);
      expect(listQuantityFromAmount(0.1, ListAmountUnit.g), isNull);
      expect(listQuantityFromAmount(1, ListAmountUnit.g, packSize: 10), isNull);
    });

    test('Einheiten passen zur Grundeinheit des Produkts', () {
      expect(ListAmountUnit.forBaseUnit('kg'), [ListAmountUnit.g, ListAmountUnit.kg]);
      expect(ListAmountUnit.forBaseUnit('l'), [ListAmountUnit.ml, ListAmountUnit.l]);
      expect(ListAmountUnit.forBaseUnit('piece'), [ListAmountUnit.piece]);
      expect(ListAmountUnit.forBaseUnit(null), ListAmountUnit.values);
    });
  });
}
