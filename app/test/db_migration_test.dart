import 'package:drift/drift.dart' show Value;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated_migrations/schema.dart';
import 'support/fakes.dart';

/// Datenbank-Migration der App (Drift): jede installierte Version muss sich auf das aktuelle Schema hochziehen
/// lassen, ohne Daten zu verlieren. Ohne diesen Test faellt ein Fehler in `onUpgrade` erst auf, wenn die App auf einem
/// echten Geraet nach dem Update nicht mehr startet.
///
/// Zeiten stehen in der Datenbank als ISO-Text (build.yaml: store_date_time_values_as_text), nicht als Zahl.
///
/// Die Schema-Staende liegen als JSON in `drift_schemas/`, die Hilfsklassen in `test/generated_migrations/`.
/// Bei jeder Schema-Aenderung (neue `schemaVersion`):
///   dart run drift_dev schema dump lib/data/local/database.dart drift_schemas/
///   dart run drift_dev schema generate drift_schemas/ test/generated_migrations/
/// und die neue Version unten in [_olderVersions] bzw. den Datentests ergaenzen.
void main() {
  late SchemaVerifier verifier;
  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  /// Vorherige Staende, auf denen Installationen stehen koennen (14 war nie in einem Release, 15 ab 1.8.0, 16 ab 1.9.0, 17 ab 1.10.0, 18 ab 1.10.1, 19 ab 1.11.0, 20 ab 1.13.0, 21 ab 1.15.0, 22 ab 1.17.0, 24 ab 1.18.0, 25 ab 1.19.0, 26 ab 1.20.0).
  const olderVersions = [9, 10, 11, 12, 13, 15, 16, 17, 18, 19, 20, 21, 22, 24, 25, 26];

  for (final from in olderVersions) {
    test('Schema $from -> aktuelle Version stimmt mit dem Sollschema ueberein', () async {
      final schema = await verifier.schemaAt(from);
      final db = AppDatabase(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, db.schemaVersion);
    });
  }

  test('drift_schemas/ ist aktuell: das gespeicherte Schema der aktuellen Version entspricht dem Code', () async {
    final version = (memoryDb()..close()).schemaVersion;
    // Wirft, wenn fuer die aktuelle schemaVersion keine JSON-Datei erzeugt wurde, und schlaegt fehl, wenn sie vom Code
    // abweicht (Tabelle oder Spalte geaendert, ohne `drift_dev schema dump` zu wiederholen).
    final schema = await verifier.schemaAt(version);
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, version);
  });

  test('Daten aus Version 13 bleiben beim Hochziehen erhalten, neue Tabellen sind leer und nutzbar', () async {
    final schema = await verifier.schemaAt(13);
    schema.rawDatabase.execute(
      "INSERT INTO products (id, household_id, name, updated_at) VALUES ('p1', 'h1', 'Reis', '2026-09-01T10:00:00.000Z')",
    );
    schema.rawDatabase.execute(
      "INSERT INTO inventory_movements (id, household_id, product_id, occurred_at, type, quantity_delta, unit, updated_at) "
      "VALUES ('m1', 'h1', 'p1', '2026-09-01T10:00:00.000Z', 'purchase', 2.0, 'kg', '2026-09-01T10:00:00.000Z')",
    );
    schema.rawDatabase.execute(
      "INSERT INTO key_values (key, value) VALUES ('pending_file_uploads', '[\"a\"]')",
    );

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, db.schemaVersion);

    final product = await (db.select(db.products)..where((p) => p.id.equals('p1'))).getSingle();
    expect(product.name, 'Reis');
    final movement = await db.select(db.inventoryMovements).getSingle();
    expect(movement.quantityDelta, 2.0);
    expect(movement.mealId, isNull, reason: 'neue Spalte, bestehende Zeilen bleiben ohne Mahlzeit');
    expect(await db.getKv('pending_file_uploads'), '["a"]');

    // die in 14/15 neu angelegten Tabellen sind leer und schreibbar
    expect(await db.select(db.meals).get(), isEmpty);
    expect(await db.select(db.mealIngredients).get(), isEmpty);
    expect(await db.select(db.nutritionTargetRows).get(), isEmpty);
    await db.into(db.nutritionTargetRows).insert(NutritionTargetRowsCompanion.insert(householdId: 'h1', updatedAt: DateTime.utc(2026)));
    expect(await db.select(db.nutritionTargetRows).get(), hasLength(1));
  });

  test('Daten aus Version 15 bleiben beim Hochziehen erhalten, die Online-Preis-Tabellen sind leer und nutzbar', () async {
    final schema = await verifier.schemaAt(15);
    schema.rawDatabase.execute(
      "INSERT INTO products (id, household_id, name, updated_at) VALUES ('p1', 'h1', 'Vollmilch', '2026-09-01T10:00:00.000Z')",
    );
    schema.rawDatabase.execute(
      "INSERT INTO meals (id, household_id, eaten_at, meal_type, title, servings_eaten, servings_made, source, is_estimate, updated_at) "
      "VALUES ('m1', 'h1', '2026-09-02T10:00:00.000Z', 'lunch', 'Reis', 1.0, 1.0, 'manual', 0, '2026-09-02T10:00:00.000Z')",
    );

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, db.schemaVersion);

    expect((await db.select(db.products).getSingle()).name, 'Vollmilch');
    expect((await db.select(db.meals).getSingle()).title, 'Reis');
    expect(await db.select(db.productOnlineLinks).get(), isEmpty);
    expect(await db.select(db.onlinePriceCache).get(), isEmpty);

    await db.into(db.productOnlineLinks).insert(ProductOnlineLinksCompanion.insert(
          id: 'l1', householdId: 'h1', productId: 'p1', store: 'billa', externalId: '00-1', linkedName: 'Clever Vollmilch', updatedAt: DateTime.utc(2026, 10, 2),
        ));
    await db.into(db.onlinePriceCache).insert(OnlinePriceCacheCompanion.insert(
          store: 'billa', externalId: '00-1', name: 'Clever Vollmilch', fetchedAt: DateTime.utc(2026, 10, 2),
        ));
    expect(await db.select(db.productOnlineLinks).get(), hasLength(1));
    expect((await db.select(db.onlinePriceCache).getSingle()).available, isTrue, reason: 'Standardwert: verfuegbar');
  });

  test('Daten aus Version 16 bleiben beim Hochziehen erhalten, neue Spalten sind leer, das Gedaechtnis der Zuordnung ist nutzbar', () async {
    final schema = await verifier.schemaAt(16);
    schema.rawDatabase.execute(
      "INSERT INTO products (id, household_id, name, updated_at) VALUES ('p1', 'h1', 'Vollmilch', '2026-09-01T10:00:00.000Z')",
    );
    schema.rawDatabase.execute(
      "INSERT INTO meals (id, household_id, eaten_at, meal_type, title, servings_eaten, servings_made, source, is_estimate, updated_at) "
      "VALUES ('m1', 'h1', '2026-09-02T10:00:00.000Z', 'lunch', 'Reis', 1.0, 1.0, 'manual', 0, '2026-09-02T10:00:00.000Z')",
    );
    schema.rawDatabase.execute(
      "INSERT INTO meal_ingredients (id, household_id, meal_id, free_text, quantity, unit, amount_g, source, updated_at) "
      "VALUES ('i1', 'h1', 'm1', 'Paprika', 0.08, 'kg', 80.0, 'manual', '2026-09-02T10:00:00.000Z')",
    );

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, db.schemaVersion);

    final product = await db.select(db.products).getSingle();
    expect(product.name, 'Vollmilch');
    expect(product.blsCode, isNull, reason: 'neue Spalte, bestehende Produkte bleiben ohne Zuordnung');
    final ingredient = await db.select(db.mealIngredients).getSingle();
    expect(ingredient.freeText, 'Paprika');
    expect(ingredient.blsCode, isNull);
    expect(ingredient.nutrientBasis, isNull, reason: 'bei alten Zeilen ist die Herkunft nicht bekannt');
    expect(await db.select(db.householdFoodLinks).get(), isEmpty);

    await db.into(db.householdFoodLinks).insert(HouseholdFoodLinksCompanion.insert(
          id: 'l1', householdId: 'h1', nameNorm: 'Quark', blsCode: 'M713300', updatedAt: DateTime.utc(2026, 10, 3),
        ));
    expect((await db.select(db.householdFoodLinks).getSingle()).blsCode, 'M713300');
  });

  test('Daten aus Version 17 bleiben beim Hochziehen erhalten, das Stueckgewicht der Zuordnung ist leer und nutzbar', () async {
    final schema = await verifier.schemaAt(17);
    schema.rawDatabase.execute(
      "INSERT INTO household_food_links (id, household_id, name_norm, bls_code, updated_at) "
      "VALUES ('l1', 'h1', 'Quark', 'M713300', '2026-10-02T10:00:00.000Z')",
    );

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, db.schemaVersion);

    final link = await db.select(db.householdFoodLinks).getSingle();
    expect(link.nameNorm, 'Quark');
    expect(link.blsCode, 'M713300');
    expect(link.unitWeightG, isNull, reason: 'neue Spalte, bestehende Zuordnungen haben noch kein eigenes Gewicht');

    await (db.update(db.householdFoodLinks)..where((l) => l.id.equals('l1'))).write(const HouseholdFoodLinksCompanion(unitWeightG: Value(135)));
    expect((await db.select(db.householdFoodLinks).getSingle()).unitWeightG, 135);
  });

  test('Daten aus Version 18 bleiben beim Hochziehen erhalten, Zutaten bekommen eine leere Mikronaehrstoff-Spalte', () async {
    final schema = await verifier.schemaAt(18);
    schema.rawDatabase.execute(
      "INSERT INTO meals (id, household_id, eaten_at, meal_type, title, servings_eaten, servings_made, source, is_estimate, updated_at) "
      "VALUES ('m1', 'h1', '2026-10-02T10:00:00.000Z', 'lunch', 'Reis', 1.0, 1.0, 'manual', 0, '2026-10-02T10:00:00.000Z')",
    );
    schema.rawDatabase.execute(
      "INSERT INTO meal_ingredients (id, household_id, meal_id, free_text, quantity, unit, amount_g, source, kcal, updated_at) "
      "VALUES ('i1', 'h1', 'm1', 'Banane', 2.0, 'piece', 236.0, 'manual', 186.0, '2026-10-02T10:00:00.000Z')",
    );

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, db.schemaVersion);

    final ing = await db.select(db.mealIngredients).getSingle();
    expect(ing.freeText, 'Banane');
    expect(ing.kcal, 186);
    expect(ing.micros, isNull, reason: 'alte Zutaten haben keine Mikronaehrstoffe, das ist "unbekannt" und nicht 0');

    await (db.update(db.mealIngredients)..where((i) => i.id.equals('i1'))).write(const MealIngredientsCompanion(micros: Value('{"vit_c_mg":26}')));
    expect((await db.select(db.mealIngredients).getSingle()).micros, '{"vit_c_mg":26}');
  });

  test('Daten aus Version 19 bleiben beim Hochziehen erhalten, Ergaenzungen und Einstellungen sind neu, leer und nutzbar', () async {
    final schema = await verifier.schemaAt(19);
    schema.rawDatabase.execute(
      "INSERT INTO meals (id, household_id, eaten_at, meal_type, title, servings_eaten, servings_made, source, is_estimate, updated_at) "
      "VALUES ('m1', 'h1', '2026-10-03T10:00:00.000Z', 'lunch', 'Reis', 1.0, 1.0, 'manual', 0, '2026-10-03T10:00:00.000Z')",
    );
    schema.rawDatabase.execute(
      "INSERT INTO meal_ingredients (id, household_id, meal_id, quantity, unit, source, micros, updated_at) "
      "VALUES ('i1', 'h1', 'm1', 100.0, 'g', 'manual', '{\"iron_mg\":1.5}', '2026-10-03T10:00:00.000Z')",
    );

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, db.schemaVersion);

    final ingredient = await db.select(db.mealIngredients).getSingle();
    expect(ingredient.micros, '{"iron_mg":1.5}');
    expect(await db.select(db.supplements).get(), isEmpty);
    expect(await db.select(db.supplementIntakes).get(), isEmpty);
    expect(await db.select(db.householdPrefs).get(), isEmpty);
    await db.into(db.supplements).insert(SupplementsCompanion.insert(id: 's1', householdId: 'h1', name: 'D3', updatedAt: DateTime.utc(2026)));
    await db.into(db.supplementIntakes).insert(SupplementIntakesCompanion.insert(id: 'e1', householdId: 'h1', name: 'D3', takenAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026)));
    await db.into(db.householdPrefs).insert(HouseholdPrefsCompanion.insert(householdId: 'h1', key: 'k', value: 'true', updatedAt: DateTime.utc(2026)));
    expect((await db.select(db.supplements).getSingle()).servingLabel, 'Tablette', reason: 'Vorbelegung');
    expect((await db.select(db.supplementIntakes).getSingle()).servings, 1.0);
    expect(await db.select(db.householdPrefs).get(), hasLength(1));
  });

  test('Daten aus Version 20 bleiben beim Hochziehen erhalten, die Zubereitung der Zutaten ist neu und leer', () async {
    final schema = await verifier.schemaAt(20);
    schema.rawDatabase.execute(
      "INSERT INTO meals (id, household_id, eaten_at, meal_type, title, servings_eaten, servings_made, source, is_estimate, updated_at) "
      "VALUES ('m1', 'h1', '2026-10-04T10:00:00.000Z', 'lunch', 'Paprika', 1.0, 1.0, 'manual', 0, '2026-10-04T10:00:00.000Z')",
    );
    schema.rawDatabase.execute(
      "INSERT INTO meal_ingredients (id, household_id, meal_id, quantity, unit, source, bls_code, micros, updated_at) "
      "VALUES ('i1', 'h1', 'm1', 100.0, 'g', 'manual', 'G543100', '{\"vit_c_mg\":100.0}', '2026-10-04T10:00:00.000Z')",
    );

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, db.schemaVersion);

    final ingredient = await db.select(db.mealIngredients).getSingle();
    expect(ingredient.micros, '{"vit_c_mg":100.0}');
    expect(ingredient.blsCode, 'G543100');
    expect(ingredient.preparation, isNull, reason: 'bestehende Zutaten sind roh bzw. ohne Angabe');
    await (db.update(db.mealIngredients)..where((i) => i.id.equals('i1'))).write(const MealIngredientsCompanion(preparation: Value('veg_other:boiled')));
    expect((await db.select(db.mealIngredients).getSingle()).preparation, 'veg_other:boiled');
    expect((await db.select(db.mealIngredients).getSingle()).unitKey, isNull, reason: 'bestehende Zutaten zaehlen als ganze Stueck');
    await (db.update(db.mealIngredients)..where((i) => i.id.equals('i1'))).write(const MealIngredientsCompanion(unitKey: Value('slice')));
    expect((await db.select(db.mealIngredients).getSingle()).unitKey, 'slice');
  });
}
