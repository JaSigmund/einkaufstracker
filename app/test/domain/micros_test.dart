import 'package:einkaufstracker/domain/nutrition/micros.dart';
import 'package:einkaufstracker/domain/nutrition/nutrient_registry.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mikronaehrstoffe als Wertetabelle (Phase N3, ADR-032): ein fehlender Schluessel ist unbekannt, 0 eine echte Null.
void main() {
  group('parseMicros', () {
    test('liest nur Registerschluessel, Zahlen und Text-Zahlen', () {
      final m = parseMicros({'vit_c_mg': 11, 'iron_mg': '0,4', 'calcium_mg': 6.5, 'unbekannt_mg': 3, 'zinc_mg': 'viel'})!;
      expect(m, {'vit_c_mg': 11.0, 'iron_mg': 0.4, 'calcium_mg': 6.5});
    });

    test('eine echte 0 bleibt, negative und nicht endliche Werte fallen weg', () {
      expect(parseMicros({'vit_d_ug': 0, 'iron_mg': -1, 'zinc_mg': double.nan, 'iodine_ug': double.infinity}), {'vit_d_ug': 0.0});
    });

    test('liest auch JSON-Text; Unlesbares, Leeres und falsche Typen ergeben null', () {
      expect(parseMicros('{"vit_c_mg": 11}'), {'vit_c_mg': 11.0});
      expect(parseMicros('kaputt'), isNull);
      expect(parseMicros(''), isNull);
      expect(parseMicros('[1,2]'), isNull);
      expect(parseMicros(null), isNull);
      expect(parseMicros(5), isNull);
      expect(parseMicros(<String, dynamic>{}), isNull);
      expect(parseMicros({'unbekannt_mg': 3}), isNull, reason: 'nichts uebrig');
    });

    test('das Makroprofil eines Produkts enthaelt keine Mikronaehrstoffe, ein erweitertes schon', () {
      expect(parseMicros({'kcal': 52, 'protein_g': 0.3}), isNull);
      expect(parseMicros({'kcal': 52, 'vit_c_mg': 4.6})!.keys, ['vit_c_mg']);
    });
  });

  group('Umrechnung', () {
    test('scaleMicros: je 100 g auf die Menge', () {
      expect(scaleMicros({'vit_c_mg': 11, 'iron_mg': 0.4}, 236), {'vit_c_mg': closeTo(25.96, 1e-9), 'iron_mg': closeTo(0.944, 1e-9)});
    });

    test('ohne Profil oder ohne Menge: null (unbekannt, nicht 0)', () {
      expect(scaleMicros(null, 100), isNull);
      expect(scaleMicros({}, 100), isNull);
      expect(scaleMicros({'vit_c_mg': 1}, null), isNull);
      expect(scaleMicros({'vit_c_mg': 1}, 0), isNull);
      expect(scaleMicros({'vit_c_mg': 1}, -5), isNull);
    });

    test('eine echte 0 je 100 g bleibt 0 in der Menge', () {
      expect(scaleMicros({'vit_d_ug': 0}, 150), {'vit_d_ug': 0.0});
    });

    test('micros100From ist die Umkehrung', () {
      final abs = scaleMicros({'vit_c_mg': 11, 'iron_mg': 0.4}, 236)!;
      final back = micros100From(abs, 236)!;
      expect(back['vit_c_mg'], closeTo(11, 1e-9));
      expect(back['iron_mg'], closeTo(0.4, 1e-9));
      expect(micros100From(abs, null), isNull);
      expect(micros100From(null, 100), isNull);
      expect(micros100From(abs, 0), isNull);
    });
  });

  group('encodeMicros', () {
    test('JSON in Registerreihenfolge, vier Nachkommastellen', () {
      expect(encodeMicros({'iron_mg': 0.944444, 'vit_c_mg': 25.96}), '{"vit_c_mg":25.96,"iron_mg":0.9444}');
    });

    test('leer oder null ergibt null (keine Daten)', () {
      expect(encodeMicros(null), isNull);
      expect(encodeMicros({}), isNull);
    });

    test('Schluessel ausserhalb des Registers werden nicht geschrieben; die Null bleibt', () {
      expect(encodeMicros({'unbekannt_mg': 1, 'vit_d_ug': 0}), '{"vit_d_ug":0.0}');
    });

    test('Hin und zurueck', () {
      final m = {'vit_c_mg': 25.96, 'iron_mg': 0.9444, 'vit_d_ug': 0.0};
      expect(parseMicros(encodeMicros(m)), m);
    });
  });

  group('formatMicro', () {
    NutrientDef def(String key) => nutrientDef(key)!;

    test('Nachkommastellen aus dem Register, Dezimalkomma, Einheit', () {
      expect(formatMicro(def('vit_c_mg'), 12.4), '12 mg');
      expect(formatMicro(def('iron_mg'), 12.44), '12,4 mg');
      expect(formatMicro(def('vit_b12_ug'), 2.57), '2,6 µg');
      expect(formatMicro(def('vit_b1_mg'), 1.1), '1,10 mg');
      expect(formatMicro(def('omega3_g'), 2.587), '2,59 g');
    });

    test('kleine echte Werte zeigen nicht 0', () {
      expect(formatMicro(def('vit_c_mg'), 0.4), '0,4 mg');
      expect(formatMicro(def('iron_mg'), 0.04), '0,04 mg');
      expect(formatMicro(def('vit_c_mg'), 0), '0 mg');
    });
  });
}
