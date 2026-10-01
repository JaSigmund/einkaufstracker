import 'package:einkaufstracker/domain/categorization/name_similarity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('levenshteinDistance', () {
    test('identische Strings: 0', () {
      expect(levenshteinDistance('paprika', 'paprika'), 0);
    });

    test('ein eingefuegtes Leerzeichen: 1', () {
      expect(levenshteinDistance('faschiertes', 'faschi ertes'), 1);
    });

    test('komplett verschiedene Woerter', () {
      expect(levenshteinDistance('rot', 'gelb'), 4);
    });

    test('leerer String gegen nicht-leeren: Laenge des anderen', () {
      expect(levenshteinDistance('', 'abc'), 3);
      expect(levenshteinDistance('abc', ''), 3);
    });
  });

  group('maxFuzzyDistance (ADR-023, konservativ gestaffelt nach Laenge)', () {
    test('kurz (< 5 Zeichen): keine Toleranz', () {
      expect(maxFuzzyDistance('ei'), 0);
      expect(maxFuzzyDistance('milch'.substring(0, 4)), 0);
    });

    test('mittel (5-9 Zeichen): Toleranz 1', () {
      expect(maxFuzzyDistance('milch'), 1);
      expect(maxFuzzyDistance('123456789'), 1);
    });

    test('lang (ab 10 Zeichen): Toleranz 2', () {
      expect(maxFuzzyDistance('faschiertes'), 2);
    });
  });

  group('closestWithinTolerance', () {
    test('OCR-Leerzeichen mitten im Wort: findet den bekannten Schluessel', () {
      final match = closestWithinTolerance('faschi ertes', ['bergkaese', 'faschiertes', 'vollmilch']);
      expect(match, 'faschiertes');
    });

    test('kein Kandidat innerhalb der Toleranz: null', () {
      final match = closestWithinTolerance('paprika rot', ['paprika gelb', 'bergkaese']);
      expect(match, isNull);
    });

    test('kurzer Schluessel (Toleranz 0): nie ein Fuzzy-Treffer', () {
      final match = closestWithinTolerance('ei', ['el', 'eis']);
      expect(match, isNull);
    });

    test('exakt gleicher Kandidat wird uebersprungen (laeuft schon vorher ueber den Alias-Lookup)', () {
      final match = closestWithinTolerance('faschiertes', ['faschiertes']);
      expect(match, isNull);
    });

    test('mehrere Kandidaten innerhalb der Toleranz: der naechstgelegene gewinnt', () {
      final match = closestWithinTolerance('faschiertes', ['faschi ertes', 'faschiertess']);
      expect(match, 'faschi ertes'); // Distanz 1 statt 1 bei "faschiertess" auch 1 -- erster Treffer gewinnt bei Gleichstand
    });
  });

  group('likelyDuplicatePairs (Vorschlags-Korridor, nicht automatisch zusammengefuehrt)', () {
    test('findet ein Paar knapp ausserhalb der automatischen Toleranz', () {
      final pairs = likelyDuplicatePairs(['paprika rot', 'paprika gelb', 'bergkaese']);
      expect(pairs, [(0, 1)]);
    });

    test('Paar innerhalb der automatischen Toleranz wird NICHT vorgeschlagen (waere schon automatisch zusammengefuehrt)', () {
      final pairs = likelyDuplicatePairs(['faschiertes', 'faschi ertes']);
      expect(pairs, isEmpty);
    });

    test('voellig verschiedene Namen: kein Vorschlag', () {
      final pairs = likelyDuplicatePairs(['milch', 'brot', 'kaese']);
      expect(pairs, isEmpty);
    });

    test('leere Eintraege werden ignoriert', () {
      final pairs = likelyDuplicatePairs(['', 'paprika rot', 'paprika gelb']);
      expect(pairs, [(1, 2)]);
    });
  });
}
