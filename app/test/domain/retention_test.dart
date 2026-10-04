import 'dart:io';

import 'package:einkaufstracker/domain/nutrition/nutrient_registry.dart';
import 'package:einkaufstracker/domain/nutrition/retention.dart';
import 'package:einkaufstracker/domain/nutrition/retention_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// Garfaktoren (Phase N4, ADR-037): Zuordnung der BLS-Eintraege zu Kategorien (gegen die echte BLS) und Anwendung der USDA-Faktoren.
typedef Food = ({String code, String name, double? fat});

List<Food> _loadBls() {
  final sql = File('../tools/bls_foods_import.sql').readAsStringSync();
  final re = RegExp(r"\('([A-Z][A-Z0-9]{6})', '((?:[^']|'')*)', '((?:[^']|'')*)', ([\d.]+|null), ([\d.]+|null), ([\d.]+|null)");
  return [
    for (final m in re.allMatches(sql)) (code: m.group(1)!, name: m.group(2)!.replaceAll("''", "'"), fat: double.tryParse(m.group(6)!)),
  ];
}

void main() {
  final bls = _loadBls();
  Food food(String name) => bls.firstWhere((f) => f.name == name, orElse: () => throw StateError('BLS-Eintrag fehlt: $name'));
  String? cat(String name) {
    final f = food(name);
    return retentionCategory(blsCode: f.code, name: f.name, fatPer100: f.fat);
  }

  test('die BLS ist da und vollstaendig gelesen', () {
    expect(bls.length, 7140, reason: 'alle Eintraege der BLS');
  });

  group('Kategorien aus der echten BLS', () {
    test('typische Beispiele', () {
      final expected = {
        'Spinat roh': 'veg_leafy',
        'Grünkohl roh': 'veg_leafy',
        'Karotte/Möhre, roh': 'veg_root',
        'Rote Rübe/Rote Bete, roh': 'veg_root',
        'Tomate roh': 'tomato',
        'Gemüsepaprika rot, roh': 'veg_other',
        'Broccoli roh': 'veg_other',
        'Zucchini roh': 'veg_other',
        'Speisezwiebel roh': 'veg_other',
        'Linse reif': 'legumes',
        'Kichererbse reif': 'legumes',
        'Kartoffel geschält, roh': 'potato',
        'Kartoffel ungeschält, roh': 'potato',
        'Batate/Süßkartoffel, roh': 'sweetpotato',
        'Reis poliert, roh': 'rice',
        'Teigwaren eifrei, roh': 'pasta',
        'Eierteigwaren roh': 'pasta',
        'Hafer Flocken': 'oats',
        'Hühnerei roh': 'egg',
        'Rind Filet/Lende, roh': 'beef',
        'Schwein Filet/Lende, roh': 'pork',
        'Hähnchen Brustfilet, roh': 'poultry',
        'Pute Brust, ohne Haut, roh': 'poultry',
        'Kalb Schnitzel (Keule) roh': 'veal',
        'Rind Leber, roh': 'liver',
        'Hähnchen Leber, roh': 'liver',
        'Garnele/Granat/Krabbe, roh': 'shellfish',
        'Dorsch/Kabeljau, roh': 'fish_lean',
        'Lachs roh': 'fish_fat',
        'Hering roh': 'fish_fat',
      };
      for (final e in expected.entries) {
        expect(cat(e.key), e.value, reason: e.key);
      }
    });

    test('was man nicht gart oder was keine Faktoren hat, bekommt keine Kategorie', () {
      for (final n in [
        'Schnittlauch roh',
        'Rucola roh',
        'Kopfsalat roh',
        'Gurke roh',
        'Basilikum roh',
        'Kartoffelstärke (Kartoffelmehl)',
        'Rind Fettgewebe, intermuskulär roh',
        'Schwein Hackfleisch, roh',
        'Rind Blut, roh',
        'Hafer ganzes Korn, roh',
        'Champignon roh',
        'Kabeljaurogen roh',
        'Hühnerei Eigelb, roh',
        'Eierteigwaren Tortellini (Fleischfüllung) getrocknet',
      ]) {
        expect(cat(n), isNull, reason: n);
      }
    });

    test('Fisch ohne Fettangabe hat keine Kategorie (mager oder fett waere geraten)', () {
      final f = food('Lachs roh');
      expect(retentionCategory(blsCode: f.code, name: f.name), isNull);
    });

    test('der Fettgehalt entscheidet bei Fisch, die Grenze liegt bei 5 g', () {
      final f = food('Lachs roh');
      expect(retentionCategory(blsCode: f.code, name: f.name, fatPer100: 5), 'fish_lean');
      expect(retentionCategory(blsCode: f.code, name: f.name, fatPer100: 5.1), 'fish_fat');
    });

    test('nur rohe Eintraege: bei bereits gegarten Eintraegen gibt es nichts zu mindern', () {
      final categorized = [for (final f in bls) (f: f, c: retentionCategory(blsCode: f.code, name: f.name, fatPer100: f.fat))].where((e) => e.c != null).toList();
      expect(categorized.length, inInclusiveRange(300, 400), reason: 'die Zahl der Eintraege mit Garfaktoren');
      // roh heisst: der Name endet auf "roh"; ausgenommen sind die zwei ausdruecklich geregelten Faelle (Haferflocken, reife Huelsenfruechte)
      for (final e in categorized) {
        final rawName = e.f.name.toLowerCase().endsWith('roh');
        final exception = e.f.name == 'Hafer Flocken' || (e.c == 'legumes' && e.f.name.endsWith(' reif'));
        expect(rawName || exception, isTrue, reason: '${e.f.code} ${e.f.name} ist nicht roh');
      }
    });

    test('jede Kategorie hat mindestens einen BLS-Eintrag (sonst waeren ihre Faktoren totes Gewicht)', () {
      final used = {for (final f in bls) retentionCategory(blsCode: f.code, name: f.name, fatPer100: f.fat)};
      for (final c in retentionMethodCodes.keys) {
        expect(used.contains(c), isTrue, reason: c);
      }
    });

    test('leerer Code oder fremde Gruppe: keine Kategorie', () {
      expect(retentionCategory(blsCode: '', name: 'Spinat roh'), isNull);
      expect(retentionCategory(blsCode: 'P123400', name: 'Spinat roh'), isNull);
    });
  });

  group('Faktoren', () {
    test('jede Kategorie und Zubereitung hat Faktoren fuer alle 15 Naehrstoffe, alle zwischen 1 und 200 Prozent, alle im Register', () {
      for (final c in retentionMethodCodes.keys) {
        final methods = cookMethodsFor(c);
        expect(methods, isNotEmpty, reason: c);
        for (final m in methods) {
          final f = retentionFor(c, m)!;
          expect(f.percent.length, 15, reason: '$c $m');
          for (final e in f.percent.entries) {
            expect(nutrientDef(e.key), isNotNull, reason: e.key);
            expect(e.value, inInclusiveRange(1, 200), reason: '$c $m ${e.key}');
          }
          expect(f.usdaDescription, isNotEmpty);
        }
      }
    });

    test('Beispiel Gemuese, gekocht und abgegossen (USDA 3775): Vitamin C 75 %, Folat 65 %, Vitamin B12 100 %', () {
      final f = retentionFor('veg_other', CookMethod.boiled)!;
      expect(f.usdaCode, 3775);
      expect(f.percent['vit_c_mg'], 75);
      expect(f.percent['folate_ug'], 65);
      expect(f.percent['vit_b12_ug'], 100);
      expect(f.storageKey, 'veg_other:boiled');
    });

    test('Zubereitungen je Kategorie in fester Reihenfolge, nur die mit Daten', () {
      expect(cookMethodsFor('veg_other'), [CookMethod.boiled, CookMethod.steamed, CookMethod.fried, CookMethod.baked]);
      expect(cookMethodsFor('rice'), [CookMethod.boiled]);
      expect(cookMethodsFor('tomato'), [CookMethod.fried, CookMethod.baked, CookMethod.grilled]);
      expect(cookMethodsFor('gibt-es-nicht'), isEmpty);
      expect(retentionFor('rice', CookMethod.fried), isNull);
    });

    test('Speicherform: Rueckweg, Unbekanntes und Unsinn geben null', () {
      final f = retentionFromStorage('beef:grilled')!;
      expect([f.category, f.method], ['beef', CookMethod.grilled]);
      expect(retentionFromStorage(null), isNull);
      expect(retentionFromStorage('beef'), isNull);
      expect(retentionFromStorage('beef:smoked'), isNull);
      expect(retentionFromStorage('rice:fried'), isNull);
      expect(retentionFromStorage('a:b:c'), isNull);
    });
  });

  group('Anwenden', () {
    final f = retentionFor('veg_other', CookMethod.boiled)!;

    test('mindert Naehrstoffe mit Faktor, lasst die anderen unveraendert', () {
      final out = applyRetention({'vit_c_mg': 100.0, 'folate_ug': 200.0, 'vit_d_ug': 5.0, 'iron_mg': 2.0}, f)!;
      expect(out['vit_c_mg'], closeTo(75, 1e-9));
      expect(out['folate_ug'], closeTo(130, 1e-9));
      expect(out['vit_d_ug'], 5.0, reason: 'dafuer gibt es keinen Faktor');
      expect(out['iron_mg'], closeTo(1.9, 1e-9));
    });

    test('Umkehr ergibt die Ausgangswerte', () {
      final raw = {'vit_c_mg': 100.0, 'folate_ug': 200.0, 'vit_d_ug': 5.0, 'calcium_mg': 80.0};
      final back = undoRetention(applyRetention(raw, f), f)!;
      for (final e in raw.entries) {
        expect(back[e.key], closeTo(e.value, 1e-9), reason: e.key);
      }
    });

    test('null bleibt null, ohne Faktoren bleibt alles wie es ist', () {
      expect(applyRetention(null, f), isNull);
      expect(applyRetention({'vit_c_mg': 1.0}, null), {'vit_c_mg': 1.0});
      expect(undoRetention(null, f), isNull);
      expect(undoRetention({'vit_c_mg': 1.0}, null), {'vit_c_mg': 1.0});
    });

    test('ein echter Nullwert bleibt eine Null', () {
      expect(applyRetention({'vit_c_mg': 0.0}, f)!['vit_c_mg'], 0);
    });
  });

  group('lossSummary', () {
    final f = retentionFor('veg_other', CookMethod.boiled)!;

    test('die staerksten Verluste zuerst, gleiche alphabetisch, hoechstens drei', () {
      expect(lossSummary(f), 'Folat −35 %, Vitamin C −25 %, Vitamin B1 −20 %');
    });

    test('nur Naehrstoffe, die im Profil vorkommen', () {
      expect(lossSummary(f, present: ['vit_c_mg', 'iron_mg']), 'Vitamin C −25 %, Eisen −5 %');
      expect(lossSummary(f, present: ['vit_d_ug']), '');
    });
  });
}
