import 'package:einkaufstracker/domain/products/off_quantity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseUnitWeightGrams', () {
    test('Gramm', () => expect(parseUnitWeightGrams('500 g'), 500));
    test('Gramm ohne Leerzeichen', () => expect(parseUnitWeightGrams('500g'), 500));
    test('Kilogramm wird in Gramm umgerechnet', () => expect(parseUnitWeightGrams('1 kg'), 1000));
    test('Komma als Dezimaltrennzeichen', () => expect(parseUnitWeightGrams('1,5kg'), 1500));

    test('Volumenangaben ergeben null (keine Dichte bekannt)', () {
      expect(parseUnitWeightGrams('1 l'), isNull);
      expect(parseUnitWeightGrams('500 ml'), isNull);
    });

    test('Mehrfachpackungen ergeben null statt zu raten', () {
      expect(parseUnitWeightGrams('6 x 33 cl'), isNull);
    });

    test('unlesbarer Text ergibt null', () {
      expect(parseUnitWeightGrams(''), isNull);
      expect(parseUnitWeightGrams('ca. 500g'), isNull);
    });
  });
}
