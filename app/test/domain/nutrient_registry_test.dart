import 'dart:convert';
import 'dart:io';

import 'package:einkaufstracker/domain/nutrition/nutrient_registry.dart';
import 'package:flutter_test/flutter_test.dart';

/// Register der Mikronaehrstoffe (Phase N3, ADR-032): die Dart-Fassung ist aus `tools/nutrient_registry.json` erzeugt und muss mit
/// ihr uebereinstimmen (die CI prueft es zusaetzlich mit `tools/build_bls_nutrients.py --check`).
void main() {
  test('39 Naehrstoffe, Schluessel eindeutig, Einheit steht im Schluessel', () {
    expect(nutrientRegistry, hasLength(39));
    expect(nutrientKeys.toSet(), hasLength(39));
    for (final n in nutrientRegistry) {
      final suffix = n.key.split('_').last;
      expect({'g': 'g', 'mg': 'mg', 'ug': 'µg'}[suffix], n.unit, reason: n.key);
      expect(n.decimals, inInclusiveRange(0, 2), reason: n.key);
      expect(n.label, isNotEmpty);
    }
  });

  test('14 Naehrstoffe stehen in der Vorauswahl, darunter Alkohol und Koffein, jede Gruppe hat Eintraege', () {
    expect(nutrientRegistry.where((n) => n.featured), hasLength(14));
    expect(nutrientDef('alcohol_g')!.featured, isTrue);
    expect(nutrientDef('caffeine_mg')!.featured, isTrue);
    for (final g in NutrientGroup.values) {
      expect(nutrientRegistry.where((n) => n.group == g), isNotEmpty, reason: g.name);
    }
  });

  test('Referenzmengen nur bei Vitaminen und Mineralstoffen, nie negativ; Selen fehlt', () {
    for (final n in nutrientRegistry) {
      if (n.euReference != null) {
        expect(n.euReference, greaterThan(0), reason: n.key);
        expect([NutrientGroup.vitamin, NutrientGroup.mineral], contains(n.group), reason: n.key);
      }
    }
    expect(nutrientRegistry.where((n) => n.euReference != null), hasLength(26));
    expect(nutrientKeys.any((k) => k.contains('selen')), isFalse);
    expect(nutrientDef('caffeine_mg')!.euReference, isNull);
  });

  test('bekannte Referenzmengen laut Verordnung (EU) 1169/2011', () {
    expect(nutrientDef('vit_c_mg')!.euReference, 80);
    expect(nutrientDef('iron_mg')!.euReference, 14);
    expect(nutrientDef('vit_d_ug')!.euReference, 5);
    expect(nutrientDef('calcium_mg')!.euReference, 800);
    expect(nutrientDef('omega3_g')!.euReference, isNull, reason: 'fuer Fettsaeuren gibt es keine Kennzeichnungsmenge');
  });

  test('nutrientDef: unbekannter Schluessel ist null', () {
    expect(nutrientDef('selenium_ug'), isNull);
    expect(nutrientDef('vit_c_mg')!.label, 'Vitamin C');
  });

  test('stimmt mit tools/nutrient_registry.json ueberein (Schluessel, Reihenfolge, Einheit, Stellen, Referenz, Vorauswahl)', () {
    final file = File('../tools/nutrient_registry.json');
    expect(file.existsSync(), isTrue, reason: 'Test laeuft im Ordner app/');
    final items = (jsonDecode(file.readAsStringSync()) as Map)['nutrients'] as List;
    expect(items, hasLength(nutrientRegistry.length));
    for (var i = 0; i < items.length; i++) {
      final j = items[i] as Map;
      final n = nutrientRegistry[i];
      expect(n.key, j['key']);
      expect(n.label, j['label_de']);
      expect(n.unit, j['unit']);
      expect(n.decimals, j['decimals']);
      expect(n.group.name, j['group']);
      expect(n.featured, j['featured']);
      expect(n.euReference, (j['eu_reference'] as num?)?.toDouble());
    }
  });
}
