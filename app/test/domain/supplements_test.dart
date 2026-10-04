import 'package:einkaufstracker/domain/nutrition/supplements.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('summarizeMicros', () {
    test('Register-Reihenfolge, Einheiten und Zusatz bei mehr als drei', () {
      expect(summarizeMicros({'iron_mg': 14.0, 'vit_d_ug': 25.0}), 'Vitamin D 25,0 µg, Eisen 14,0 mg');
      expect(summarizeMicros({'iron_mg': 14.0, 'vit_d_ug': 25.0, 'vit_c_mg': 80.0, 'zinc_mg': 10.0, 'iodine_ug': 150.0}), 'Vitamin D 25,0 µg, Vitamin C 80 mg, Eisen 14,0 mg +2');
    });

    test('Klammerzusaetze im Namen fallen in der Kurzfassung weg', () {
      expect(summarizeMicros({'vit_b1_mg': 1.1}), 'Vitamin B1 1,10 mg');
      expect(summarizeMicros({'folate_ug': 200.0}), 'Folat 200 µg');
    });

    test('leer ohne Werte, auch bei Schluesseln ausserhalb des Registers', () {
      expect(summarizeMicros(const {}), '');
      expect(summarizeMicros(const {'gibts_nicht': 1.0}), '');
    });
  });

  test('formatServings: Zahl ohne unnoetige Stellen, Einheit unveraendert', () {
    expect(formatServings(1, 'Tablette'), '1 × Tablette');
    expect(formatServings(2, 'Kapsel'), '2 × Kapsel');
    expect(formatServings(0.5, 'Messlöffel'), '0,5 × Messlöffel');
  });

  test('isValidServings: groesser 0, hoechstens 100, endlich', () {
    expect([for (final v in [1.0, 0.5, 100.0]) isValidServings(v)], [true, true, true]);
    expect([for (final v in [0.0, -1.0, 100.5, double.nan, double.infinity, null]) isValidServings(v)], [false, false, false, false, false, false]);
  });

  test('parseAmount liest Komma und Punkt, sonst null', () {
    expect(parseAmount('2'), 2);
    expect(parseAmount(' 0,5 '), 0.5);
    expect(parseAmount('12.5'), 12.5);
    expect(parseAmount(''), isNull);
    expect(parseAmount('abc'), isNull);
    expect(parseAmount('1,2,3'), isNull);
    expect(parseAmount('NaN'), isNull);
    expect(parseAmount('Infinity'), isNull);
  });
}
