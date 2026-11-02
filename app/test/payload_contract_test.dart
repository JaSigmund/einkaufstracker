import 'dart:convert';
import 'dart:io';

import 'package:einkaufstracker/data/nutrition/bls_food_search.dart';
import 'package:einkaufstracker/data/repositories/household_prefs_repository.dart';
import 'package:einkaufstracker/data/repositories/meal_repository.dart';
import 'package:einkaufstracker/data/repositories/online_price_repository.dart';
import 'package:einkaufstracker/data/repositories/cooking_session_repository.dart';
import 'package:einkaufstracker/data/repositories/meal_plan_repository.dart';
import 'package:einkaufstracker/data/repositories/supplement_repository.dart';
import 'package:einkaufstracker/domain/recipes/saved_recipe.dart';
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
        blsCode: 'G543100',
        nutrientBasis: 'bls_exact',
      ),
      const IngredientDraft(
        freeText: 'Quark',
        quantity: 50,
        entryUnit: EntryUnit.g,
        per100: NutrientsPer100(kcal: 100, proteinG: 12),
        per100Basis: 'g',
        blsCode: 'M713300',
        nutrientBasis: 'bls_matched',
      ),
      const IngredientDraft(freeText: 'Gewürzmischung', quantity: 5, entryUnit: EntryUnit.g),
      // Stueckmenge mit Gewicht einer Einheit (Phase N2): 2 Scheiben a 28 g
      const IngredientDraft(
        freeText: 'Weizenbrot/Weißbrot',
        quantity: 2,
        entryUnit: EntryUnit.piece,
        per100: NutrientsPer100(kcal: 260, proteinG: 8),
        per100Basis: 'g',
        blsCode: 'B311000',
        nutrientBasis: 'bls_exact',
        unitWeightG: 28,
        microsPer100: {'iron_mg': 2.0, 'vit_b1_mg': 0.18, 'iodine_ug': 0.0},
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

  // Zuordnung zur Lebensmitteldatenbank (Phase N1): Produkt ohne Profil bekommt eins, Gedaechtnis lernen und vergessen
  final milch = await productRepo(db).create(name: 'Milch', baseUnit: 'l');
  await productRepo(db).setBlsProfile(
    milch.id,
    const BlsFood(
      code: 'M111300',
      nameDe: 'Vollmilch frisch, 3,5 % Fett',
      per100: NutrientsPer100(kcal: 65, proteinG: 3.4, fatG: 3.6, satFatG: 2.3, carbsG: 4.7, sugarG: 4.7, fiberG: 0, saltG: 0.1),
      micros: {'calcium_mg': 117.0, 'vit_b12_ug': 0.37},
    ),
  );
  final links = foodLinkRepo(db);
  await links.learn('Quark', 'M713300');
  await links.learn('Skyr', 'M710100');
  await links.forget((await links.all()).firstWhere((l) => l.nameNorm == 'Skyr').id);
  await links.setUnitWeight('Banane', 'F503100', 135); // eigenes Stueckgewicht (Phase N2)
  await productRepo(db).setUnitWeight(milch.id, 250);

  // Online-Preise (ADR-019): zwei Artikel beim selben Haendler (Bio und normal), einer bei einem anderen, einer wieder geloest
  final online = OnlinePriceRepository(db, FakeOnlinePriceRemote(), householdId: () async => 'h1');
  await online.link(reis.id, onlineArticle(externalId: '00-1', name: 'Clever Vollmilch'));
  await online.link(reis.id, onlineArticle(externalId: '00-2', name: 'Ja! Natürlich Vollmilch', priceCents: 189));
  await online.link(reis.id, onlineArticle(store: 'spar', externalId: '2020', name: 'A-zwei Vollmilch'));
  await online.unlink((await online.activeLinks()).firstWhere((l) => l.store == 'spar').id);

  // Garfaktoren (Phase N4, ADR-037): gekochtes Gemuese, Mikronaehrstoffe um die Verluste gemindert, Zubereitung festgehalten
  await meals.create(MealDraft(
    title: 'Paprikagemuese',
    eatenAt: DateTime.utc(2026, 9, 24, 12),
    ingredients: const [
      IngredientDraft(
        freeText: 'Gemüsepaprika rot, roh',
        quantity: 150,
        entryUnit: EntryUnit.g,
        per100: NutrientsPer100(kcal: 36, proteinG: 1.0, fatG: 0.2),
        per100Basis: 'g',
        blsCode: 'G543100',
        nutrientBasis: 'bls_exact',
        microsPer100: {'vit_c_mg': 100.0, 'folate_ug': 50.0},
        preparation: 'veg_other:boiled',
      ),
    ],
  ));

  // Nahrungsergaenzung und gemeinsame Einstellungen (Phase N4): Ergaenzung anlegen, aendern, Einnahmen (eine zurueckgenommen), eine geloeschte
  final supplements = SupplementRepository(db, householdId: () async => 'h1');
  final d3 = await supplements.save(name: 'Vitamin D3', servingLabel: 'Tablette', micros: {'vit_d_ug': 20.0});
  await supplements.save(id: d3.id, name: 'Vitamin D3', servingLabel: 'Tablette', micros: {'vit_d_ug': 25.0}, note: 'zum Frühstück');
  final multi = await supplements.save(name: 'Multi', servingLabel: 'Kapsel', micros: {'vit_c_mg': 80.0, 'iron_mg': 14.0});
  await supplements.take(d3, at: DateTime.utc(2026, 9, 22, 6, 30));
  final twice = await supplements.take(multi, at: DateTime.utc(2026, 9, 22, 6, 31), servings: 2);
  await supplements.deleteIntake(twice.id);
  await supplements.delete((await supplements.save(name: 'Alt', servingLabel: 'Tropfen', micros: {'zinc_mg': 1.0})).id);
  final plan = MealPlanRepository(db, householdId: () async => 'h1');
  final planned = await plan.add(day: DateTime(2026, 9, 23), title: 'Linsencurry', ingredients: const [SavedIngredient(productId: null, name: 'Linsen', unit: 'piece')], sourceUrl: 'https://example.com/suche');
  await plan.move(planned.id, DateTime(2026, 9, 24));
  await plan.delete((await plan.add(day: DateTime(2026, 9, 25), title: 'Alt', slot: 'lunch')).id);
  final sessions = CookingSessionRepository(db, householdId: () async => 'h1');
  await sessions.add(recipeTitle: 'Linsencurry', startedAt: DateTime.utc(2026, 9, 24, 17), endedAt: DateTime.utc(2026, 9, 24, 17, 50), activeSeconds: 2520);
  await sessions.delete((await sessions.add(recipeTitle: 'Versehen', startedAt: DateTime.utc(2026, 9, 24, 18), endedAt: DateTime.utc(2026, 9, 24, 18, 2), activeSeconds: 120)).id);
  final prefs = HouseholdPrefsRepository(db, householdId: () async => 'h1');
  await prefs.set(microReferenceOnPref, true);
  await prefs.set(microReferenceOverridesPref, {'vit_c_mg': 100.0});

  // Mehrfachpackung (ADR-045): Produkt mit Stueckzahl und Namen, ein Flaeschchen verbraucht
  final mehrfach = await productRepo(db).create(name: 'Yakult Drink', baseUnit: 'l', packSize: 0.39, piecesPerPack: 6, pieceLabel: 'Fläschchen', unitWeightG: 65);
  final inventory = inventoryRepo(db);
  final flaeschchen = await inventory.recordFromScan(productId: mehrfach.id, ean: '9001234567891', quantity: 0.39, unit: 'l', now: DateTime.utc(2026, 9, 1));
  await inventory.consumePart(flaeschchen.id, 0.065, opens: false, now: DateTime.utc(2026, 9, 2));

  // Einkaufsliste mit abgeschlossenem Einkauf (ADR-043): archiviert, zurueckgeholt, wieder archiviert
  final shopping = shoppingListRepo(db);
  final bought = await shopping.addManual(productId: reis.id, unit: 'kg');
  await shopping.setChecked(bought.id, true);
  await shopping.archiveItems([bought.id]);
  await shopping.unarchive([bought.id]);
  await shopping.archiveItems([bought.id]);

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
    expect(tables, containsAll(['products', 'inventory_items', 'inventory_movements', 'meals', 'meal_ingredients', 'nutrition_targets', 'product_online_links', 'household_food_links', 'supplements', 'supplement_intakes', 'household_prefs', 'meal_plan_entries', 'cooking_sessions', 'shopping_lists', 'shopping_list_items']));

    List<Map<String, dynamic>> rows(String table) => [for (final e in entries) if (e['table'] == table) (e['payload'] as Map).cast<String, dynamic>()];

    expect(rows('cooking_sessions').any((s) => s['deleted_at'] != null), isTrue, reason: 'Kochzeit zurueckgenommen');
    expect(rows('cooking_sessions').any((s) => s['active_seconds'] == 2520 && s['recipe_title'] == 'Linsencurry'), isTrue);
    expect(rows('shopping_list_items').any((i) => i['archived_at'] != null), isTrue, reason: 'abgeschlossener Einkauf');
    expect(rows('shopping_list_items').any((i) => i['archived_at'] == null), isTrue, reason: 'offener oder zurueckgeholter Eintrag');
    expect(rows('products').any((p) => p['pieces_per_pack'] == 6 && p['piece_label'] == 'Fläschchen'), isTrue, reason: 'Mehrfachpackung');
    expect(rows('inventory_movements').any((m) => m['type'] == 'consumed' && m['quantity_delta'] == -0.065), isTrue, reason: 'ein Flaeschchen verbraucht');
    final movementTypes = {for (final m in rows('inventory_movements')) m['type']};
    expect(movementTypes, containsAll(['purchase', 'meal', 'adjustment']), reason: 'Abzug und Gegenbuchung');
    expect(rows('inventory_movements').any((m) => m['meal_id'] != null), isTrue);
    expect(rows('meals').any((m) => m['deleted_at'] != null), isTrue, reason: 'Soft-Delete');
    expect(rows('meals').any((m) => m['photo_path'] != null), isTrue);
    expect(rows('meals').any((m) => m['source'] == 'photo_ai' && m['is_estimate'] == true), isTrue);
    expect({for (final i in rows('meal_ingredients')) i['source']}, containsAll(['photo_ai', 'estimate', 'inventory', 'manual']));
    expect(rows('meal_ingredients').any((i) => i['confidence'] != null), isTrue);
    expect(rows('meal_ingredients').any((i) => i['product_id'] == null && i['free_text'] != null), isTrue);
    expect({for (final i in rows('meal_ingredients')) i['nutrient_basis']}, containsAll(['bls_exact', 'bls_matched', 'product', 'manual', null]));
    expect(rows('meal_ingredients').any((i) => i['bls_code'] == 'G543100'), isTrue);
    expect(rows('products').any((p) => p['bls_code'] == 'M111300' && p['nutrients_source'] == 'bls'), isTrue, reason: 'Profil aus der BLS im Produkt');
    expect(rows('household_food_links').any((l) => l['deleted_at'] != null), isTrue, reason: 'Zuordnung vergessen (Soft-Delete)');
    expect({for (final l in rows('household_food_links')) l['bls_code']}, {'M713300', 'M710100', 'F503100'}, reason: 'Quark gelernt, Skyr gelernt und wieder vergessen, Banane mit eigenem Gewicht');
    expect(rows('household_food_links').any((l) => l['unit_weight_g'] == 135), isTrue);
    expect(rows('meal_ingredients').any((i) => i['unit'] == 'piece' && i['amount_g'] == 56), isTrue, reason: '2 Scheiben a 28 g');
    expect(rows('meal_ingredients').any((i) => i['micros'] is Map && (i['micros'] as Map)['iron_mg'] == 1.12), isTrue, reason: 'Mikronaehrstoffe der verzehrten Menge als Objekt');
    expect(rows('meal_ingredients').any((i) => i['micros'] == null), isTrue, reason: 'Zutaten ohne Daten schicken null');
    expect(rows('products').any((p) => (p['nutrients_per_100'] as Map?)?['calcium_mg'] == 117), isTrue, reason: 'Profil aus der BLS mit Mikronaehrstoffen');
    expect(
      rows('meal_ingredients').any((i) => i['preparation'] == 'veg_other:boiled' && (i['micros'] as Map)['vit_c_mg'] == 112.5),
      isTrue,
      reason: 'Zubereitung festgehalten, Vitamin C 100 mg je 100 g, 150 g, mal 0,75',
    );
    expect(rows('meal_ingredients').any((i) => i['preparation'] == null), isTrue, reason: 'ohne Zubereitung schicken die uebrigen null');
    expect(rows('supplements').any((s) => s['deleted_at'] != null), isTrue, reason: 'Ergaenzung geloescht (Soft-Delete)');
    expect(rows('supplements').any((s) => s['note'] == 'zum Frühstück' && (s['micros'] as Map)['vit_d_ug'] == 25), isTrue, reason: 'geaenderte Ergaenzung, Mikros als Objekt');
    expect(rows('supplement_intakes').any((i) => i['deleted_at'] != null), isTrue, reason: 'Einnahme zurueckgenommen');
    expect(rows('supplement_intakes').any((i) => i['servings'] == 2 && (i['micros'] as Map)['iron_mg'] == 28), isTrue, reason: 'zwei Kapseln: absolute Mengen');
    expect(rows('supplement_intakes').every((i) => i['name'] != null && i['taken_at'] != null), isTrue);
    expect({for (final p in rows('household_prefs')) p['key']}, {'micro_reference_on', 'micro_reference_overrides'});
    expect(rows('household_prefs').any((p) => p['value'] is Map && (p['value'] as Map)['vit_c_mg'] == 100), isTrue, reason: 'jsonb-Wert als Objekt');
    expect(rows('household_prefs').any((p) => p['value'] == true), isTrue, reason: 'jsonb-Wert als Wahrheitswert');
    expect(rows('product_online_links').any((l) => l['deleted_at'] != null), isTrue, reason: 'Online-Zuordnung geloest (Soft-Delete)');
    expect({for (final l in rows('product_online_links')) l['store']}, {'billa', 'spar'});
    expect(
      rows('product_online_links').where((l) => l['store'] == 'billa' && l['deleted_at'] == null).map((l) => l['external_id']).toSet(),
      {'00-1', '00-2'},
      reason: 'zwei aktive Artikel beim selben Haendler',
    );
  });
}
