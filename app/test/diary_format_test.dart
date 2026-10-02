import 'package:einkaufstracker/core/format.dart';
import 'package:flutter_test/flutter_test.dart';

/// Anzeige-Helfer des Essenstagebuchs.
void main() {
  group('formatKcal', () {
    test('rundet und gruppiert Tausender mit Punkt', () {
      expect(formatKcal(1480.4), '1.480 kcal');
      expect(formatKcal(999.5), '1.000 kcal');
      expect(formatKcal(0), '0 kcal');
      expect(formatKcal(12345), '12.345 kcal');
    });
  });

  group('formatNutrientGrams', () {
    test('unter 10 g mit Nachkommastelle und Komma, sonst ganzzahlig', () {
      expect(formatNutrientGrams(5.43), '5,4 g');
      expect(formatNutrientGrams(0), '0,0 g');
      expect(formatNutrientGrams(62.4), '62 g');
      expect(formatNutrientGrams(9.96), '10,0 g', reason: 'Rundung an der 10er-Grenze ist akzeptabel');
    });
  });

  group('formatDayHeading', () {
    final today = DateTime(2026, 10, 2);
    test('Heute und Gestern', () {
      expect(formatDayHeading(DateTime(2026, 10, 2), today), 'Heute');
      expect(formatDayHeading(DateTime(2026, 10, 1), today), 'Gestern');
    });
    test('sonst Wochentag, Tag und Monat; Jahr nur wenn es nicht das laufende ist', () {
      expect(formatDayHeading(DateTime(2026, 9, 22), today), 'Dienstag, 22. September');
      expect(formatDayHeading(DateTime(2025, 12, 24), today), 'Mittwoch, 24. Dezember 2025');
    });
    test('Uhrzeit im Datum spielt keine Rolle', () {
      expect(formatDayHeading(DateTime(2026, 10, 2, 23, 59), DateTime(2026, 10, 2, 0, 1)), 'Heute');
    });
  });

  group('formatViennaTime', () {
    test('Sommerzeit UTC+2 und Winterzeit UTC+1', () {
      expect(formatViennaTime(DateTime.utc(2026, 7, 1, 10, 5)), '12:05');
      expect(formatViennaTime(DateTime.utc(2026, 1, 15, 10, 5)), '11:05');
    });
  });
}
