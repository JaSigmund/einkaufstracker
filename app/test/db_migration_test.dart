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

  /// Vorherige Staende, auf denen Installationen stehen koennen (14 war nie in einem Release).
  const olderVersions = [9, 10, 11, 12, 13];

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
}
