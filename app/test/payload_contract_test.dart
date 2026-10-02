import 'dart:convert';
import 'dart:io';

import 'package:einkaufstracker/data/repositories/meal_repository.dart';
import 'package:einkaufstracker/domain/nutrition/ingredient_nutrition.dart';
import 'package:einkaufstracker/domain/nutrition/nutrient_scaling.dart';
import 'package:einkaufstracker/domain/nutrition/nutrition_targets.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Vertrag zwischen den Zeilen, die die App zum Server schickt, und dem echten Datenbankschema.
///
/// Die Sync-Tests laufen gegen einen Fake-Server und merken nicht, wenn die App eine Spalte schickt, die es nicht gibt,
/// oder einen Wert, den das Schema ablehnt (Enum, Check). Dann blieben alle betroffenen Eintraege fuer immer in der
/// Outbox haengen ("Datenfehler", werden uebersprungen). Dieser Test erzeugt deshalb mit den echten Repositories
/// realistische Outbox-Eintraege fuer das Essenstagebuch und legt sie als Fixture ab; `supabase/tests/run_schema_tests.py`
/// spielt sie in das echte Schema ein.
///
/// Das Fixture neu schreiben: `WRITE_FIXTURE=1 flutter test test/payload_contract_test.dart`
/// Ohne diese Variable prueft der Test nur, dass die Struktur (Tabellen und Spalten) noch zum Fixture passt.
const _fixturePath = '../supabase/tests/fixtures/app_payloads.json';

Future<List<Map<String, dynamic>>> _collect() async {
  final db = memoryDb();
  addTearDown(db.close);
  final meals = mealRepo(db);

  final reis = await productRepo(db).create(
    name: 'Reis',
    baseUnit: 'kg',
    nutrientsPer100: {'kcal': 350, 'protein_g': 7, 'fat_g': 1, 'carbs_g': 77, 'sugar_g': 0.5, 'fiber_g': 1.5, 'salt_g': 0.01},
    nutrientsBasis: 'g',
    nutrientsSource: 'manual',
  );
  await inventoryRepo(db).recordFromScan(productId: reis.id, ean: '9001234567890', quantity: 1, unit: 'kg', bestBefore: DateTime.utc(2027, 1, 1), now: DateTime.utc(2026, 9, 1));

  // Mahlzeit 1: Produkt mit Abzug, BLS-artiger Freitext mit Profil, Handeingabe, Foto-KI-Zutat mit Konfidenz
  final first = await meals.create(MealDraft(
    title: 'Reispfanne',
    eatenAt: DateTime.utc(2026, 9, 22, 17, 30),
    mealType: 'dinner',
    note: 'mit Paprika',
    servingsEaten: 1,
    servingsMade: 4,
    isEstimate: true,
    source: 'photo_ai',
    ingredients: [
      IngredientDraft(productId: reis.id, quantity: 200, entryUnit: EntryUnit.g, source: 'photo_ai', confidence: 0.8),
      const IngredientDraft(
        freeText: 'Gemüsepaprika rot, roh',
        quantity: 80,
        entryUnit: EntryUnit.g,
        per100: NutrientsPer100(kcal: 36, proteinG: 1.0, fatG: 0.3, carbsG: 4.9, sugarG: 4.2, fiberG: 3.6, saltG: 0.01),
        per100Basis: 'g',
      ),
      const IngredientDraft(
        freeText: 'Nachspeise im Restaurant',
        quantity: 1,
        entryUnit: EntryUnit.piece,
        source: 'estimate',
        manualNutrients: NutrientAmounts(kcal: 450, proteinG: 6),
      ),
    ],
  ));
  await meals.setPhotoPath(first.id, 'h/${first.id}.jpg');

  // Mahlzeit 2: anlegen, aendern (Gegenbuchung, Zutaten ersetzt), loeschen (Gegenbuchung, Soft-Delete)
  final second = await meals.create(MealDraft(
    title: 'Reisbeilage',
    eatenAt: DateTime.utc(2026, 9, 23, 12),
    ingredients: [IngredientDraft(productId: reis.id, quantity: 100, entryUnit: EntryUnit.g)],
  ));
  await meals.update(
    second.id,
    MealDraft(
      title: 'Reisbeilage groß',
      eatenAt: DateTime.utc(2026, 9, 23, 12),
      ingredients: [IngredientDraft(productId: reis.id, quantity: 150, entryUnit: EntryUnit.g)],
    ),
  );
  await meals.delete(second.id);

  await nutritionTargetsRepo(db).save(const NutritionTargets()
      .withTarget(NutrientKey.kcal, const NutrientTarget(min: 1800, max: 2200))
      .withTarget(NutrientKey.saltG, const NutrientTarget(max: 6)));

  final outbox = await (db.select(db.outbox)..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
  return [for (final e in outbox) {'table': e.remoteTable, 'payload': jsonDecode(e.payload)}];
}

/// Tabelle -> Menge der Spalten, die die App mindestens einmal schickt (ueber alle Zeilen der Tabelle).
Map<String, List<String>> _signature(List<dynamic> entries) {
  final keys = <String, Set<String>>{};
  for (final e in entries) {
    keys.putIfAbsent(e['table'] as String, () => {}).addAll((e['payload'] as Map).keys.cast<String>());
  }
  return {for (final k in (keys.keys.toList()..sort())) k: (keys[k]!.toList()..sort())};
}

void main() {
  test('Tagebuch-Zeilen der App passen zum Fixture, das gegen das echte Schema geprueft wird', () async {
    final collected = await _collect();
    final file = File(_fixturePath);

    if (Platform.environment['WRITE_FIXTURE'] == '1') {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert({'entries': collected})}\n');
      return;
    }

    expect(file.existsSync(), isTrue, reason: 'Fixture fehlt: WRITE_FIXTURE=1 flutter test test/payload_contract_test.dart');
    final fixture = (jsonDecode(file.readAsStringSync()) as Map)['entries'] as List;
    expect(
      _signature(collected),
      _signature(fixture),
      reason: 'Die Spalten, die die App schickt, haben sich geaendert. Fixture neu schreiben '
          '(WRITE_FIXTURE=1 flutter test test/payload_contract_test.dart) und python supabase/tests/run_schema_tests.py ausfuehren.',
    );
  });

  test('das Fixture deckt die wichtigen Faelle ab (sonst prueft der Schema-Test zu wenig)', () async {
    final entries = await _collect();
    final tables = {for (final e in entries) e['table'] as String};
    expect(tables, containsAll(['products', 'inventory_items', 'inventory_movements', 'meals', 'meal_ingredients', 'nutrition_targets']));

    List<Map<String, dynamic>> rows(String table) => [for (final e in entries) if (e['table'] == table) (e['payload'] as Map).cast<String, dynamic>()];

    final movementTypes = {for (final m in rows('inventory_movements')) m['type']};
    expect(movementTypes, containsAll(['purchase', 'meal', 'adjustment']), reason: 'Abzug und Gegenbuchung');
    expect(rows('inventory_movements').any((m) => m['meal_id'] != null), isTrue);
    expect(rows('meals').any((m) => m['deleted_at'] != null), isTrue, reason: 'Soft-Delete');
    expect(rows('meals').any((m) => m['photo_path'] != null), isTrue);
    expect(rows('meals').any((m) => m['source'] == 'photo_ai' && m['is_estimate'] == true), isTrue);
    expect({for (final i in rows('meal_ingredients')) i['source']}, containsAll(['photo_ai', 'estimate', 'inventory', 'manual']));
    expect(rows('meal_ingredients').any((i) => i['confidence'] != null), isTrue);
    expect(rows('meal_ingredients').any((i) => i['product_id'] == null && i['free_text'] != null), isTrue);
  });
}
