import 'package:einkaufstracker/domain/inventory/label_dates.dart';
import 'package:flutter_test/flutter_test.dart';

/// Datumserkennung fuer das MHD-Foto (Ausbau 1.14). Heute ist der 4. Oktober 2026.
final today = DateTime.utc(2026, 10, 4);

DateTime d(int y, int m, int day) => DateTime.utc(y, m, day);

List<LabelDate> read(String text) => extractLabelDates(text, today: today);

void main() {
  group('Formate', () {
    test('Tag.Monat.Jahr mit vierstelligem und zweistelligem Jahr', () {
      expect(read('MHD 12.03.2027').single.date, d(2027, 3, 12));
      expect(read('MHD 12.03.27').single.date, d(2027, 3, 12));
      expect(read('12/03/2027').single.date, d(2027, 3, 12));
      expect(read('12-03-2027').single.date, d(2027, 3, 12));
      expect(read('1.4.2027').single.date, d(2027, 4, 1));
    });

    test('ISO-Datum', () {
      expect(read('2027-03-12').single.date, d(2027, 3, 12));
    });

    test('Monat und Jahr: der letzte Tag des Monats', () {
      expect(read('MHD 03.2027').single.date, d(2027, 3, 31));
      expect(read('EXP 02/2028').single.date, d(2028, 2, 29), reason: '2028 ist ein Schaltjahr');
      expect(read('best before 10/26').single.date, d(2026, 10, 31));
    });

    test('Monatsnamen deutsch und englisch, mit und ohne Tag, auch zusammengeschrieben', () {
      expect(read('12 MAR 2027').single.date, d(2027, 3, 12));
      expect(read('12MAR27').single.date, d(2027, 3, 12));
      expect(read('12. MÄRZ 2027').single.date, d(2027, 3, 12));
      expect(read('BEST BEFORE END MAY 2027').single.date, d(2027, 5, 31));
      expect(read('15 DEZ 2026').single.date, d(2026, 12, 15));
      expect(read('3.OKT.2027').single.date, d(2027, 10, 3));
    });

    test('Typische OCR-Fehler: O statt 0 und l statt 1 zwischen Ziffern', () {
      expect(read('MHD 1O.O3.2027').single.date, d(2027, 3, 10));
      expect(read('MHD l2.03.2027').single.date, d(2027, 3, 12));
    });
  });

  group('Plausibilitaet', () {
    test('ein Tag ohne Jahr wird nicht geraten', () {
      expect(read('MHD 12.03.'), isEmpty);
      expect(read('12.03'), isEmpty);
    });

    test('unmoegliche Daten fallen weg', () {
      expect(read('31.02.2027'), isEmpty);
      expect(read('45.03.2027'), isEmpty);
      expect(read('12.13.2027'), isEmpty);
      expect(read('13/2027'), isEmpty);
    });

    test('hoechstens gut ein Jahr abgelaufen und hoechstens zehn Jahre voraus', () {
      expect(read('MHD 12.03.2020'), isEmpty);
      expect(read('MHD 12.03.2040'), isEmpty);
      expect(read('MHD 01.09.2026').single.date, d(2026, 9, 1), reason: 'erst vor einem Monat abgelaufen: das ist noch ein Fund');
    });

    test('Losnummern, Mengen und Preise sind keine Daten', () {
      expect(read('L2310543 500 g 1,99 EUR'), isEmpty);
      expect(read('Nettofüllmenge 0,5 l  EAN 9001234567890'), isEmpty);
      expect(read('Charge 12.2027.5'), isEmpty);
    });
  });

  group('Art und Stichworte', () {
    test('MHD und Mindesthaltbarkeit sind best_before, Verbrauchsdatum ist use_by', () {
      expect(read('Mindestens haltbar bis: 12.03.2027').single.kind, 'best_before');
      expect(read('MHD 12.03.2027').single.kind, 'best_before');
      expect(read('Best before 12.03.2027').single.kind, 'best_before');
      expect(read('zu verbrauchen bis 12.03.2027').single.kind, 'use_by');
      expect(read('Use by: 12.03.2027').single.kind, 'use_by');
    });

    test('ohne Stichwort gibt es keine Art', () {
      expect(read('12.03.2027').single.kind, isNull);
    });

    test('der Fund nennt die Textstelle', () {
      expect(read('Kühl lagern. MHD 12.03.2027').single.source, 'MHD 12.03.2027');
    });

    test('Herstellungsdatum zaehlt nicht, auch wenn es spaeter im Text steht', () {
      final r = read('hergestellt am 01.10.2026  MHD 12.03.2027');
      expect(r.map((x) => x.date), [d(2027, 3, 12)]);
      expect(read('Produziert: 01.10.2026'), isEmpty);
      expect(read('abgepackt am 01.10.2026'), isEmpty);
    });
  });

  group('Reihenfolge', () {
    test('Funde mit Stichwort stehen vor Funden ohne, danach das spaetere Datum zuerst', () {
      final r = read('15.11.2026 20.12.2026 MHD 01.03.2027');
      expect(r.map((x) => x.date), [d(2027, 3, 1), d(2026, 12, 20), d(2026, 11, 15)]);
      expect(r.first.kind, 'best_before');
    });

    test('dasselbe Datum zweimal wird einmal gezeigt', () {
      expect(read('MHD 12.03.2027 und 12.03.2027'), hasLength(1));
    });

    test('zwei Angaben mit unterschiedlichem Stichwort behalten ihre Art', () {
      final r = read('zu verbrauchen bis 10.10.2026 ungeöffnet MHD 12.03.2027');
      expect(r.length, 2);
      expect({for (final x in r) x.date: x.kind}, {d(2026, 10, 10): 'use_by', d(2027, 3, 12): 'best_before'});
    });
  });

  test('leerer oder sinnloser Text ergibt keine Funde', () {
    expect(read(''), isEmpty);
    expect(read('   \n  '), isEmpty);
    expect(read('Zutaten: Milch, Zucker, Salz'), isEmpty);
  });

  test('Zeilenumbrueche wie im Etikett: Stichwort in der Zeile davor', () {
    final r = read('Mindestens haltbar bis\n12.03.2027\nL0123');
    expect(r.single.date, d(2027, 3, 12));
    expect(r.single.kind, 'best_before');
  });
}
