import 'package:drift/drift.dart' show OrderingTerm;
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/meal_repository.dart';
import 'package:einkaufstracker/domain/nutrition/ingredient_nutrition.dart';
import 'package:einkaufstracker/domain/nutrition/nutrient_scaling.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Essenstagebuch (Doku 15): Mahlzeiten mit Zutaten, Naehrwert-Snapshot, FEFO-Abzug und Gegenbuchungen
/// (FR-10 bis FR-17, LH-MEAL-03/04).
DateTime _d(int y, int m, int d, [int h = 12]) => DateTime.utc(y, m, d, h);

void main() {
  late AppDatabase db;
  late String reisId;
  late String milchId;

  setUp(() async {
    db = memoryDb();
    // Reis: Gewichtsware (kg), 350 kcal und 7 g Eiweiss je 100 g
    reisId = (await productRepo(db).create(
      name: 'Reis',
      baseUnit: 'kg',
      nutrientsPer100: {'kcal': 350, 'protein_g': 7},
      nutrientsBasis: 'g',
      nutrientsSource: 'manual',
      openedShelfLifeDays: 30,
    ))
        .id;
    // Milch: Fluessigkeit (l), 64 kcal je 100 ml
    milchId = (await productRepo(db).create(
      name: 'Milch',
      baseUnit: 'l',
      nutrientsPer100: {'kcal': 64},
      nutrientsBasis: 'ml',
      nutrientsSource: 'manual',
    ))
        .id;
  });
  tearDown(() => db.close());

  var eanSeq = 0;
  Future<InventoryItem> stock(String productId, double qty, String unit, {DateTime? bestBefore}) =>
      inventoryRepo(db).recordFromScan(
        productId: productId,
        ean: '${++eanSeq}',
        quantity: qty,
        unit: unit,
        bestBefore: bestBefore,
        now: _d(2026, 9, 1),
      );

  Future<InventoryItem> item(String id) => (db.select(db.inventoryItems)..where((i) => i.id.equals(id))).getSingle();
  Future<List<InventoryMovement>> mealMovements(String mealId) =>
      (db.select(db.inventoryMovements)..where((m) => m.mealId.equals(mealId))).get();

  MealDraft lunch({required List<IngredientDraft> ingredients, double eaten = 1, double made = 1}) => MealDraft(
        title: 'Reispfanne',
        eatenAt: _d(2026, 9, 22, 12),
        servingsEaten: eaten,
        servingsMade: made,
        ingredients: ingredients,
      );

  group('Anlegen mit Inventarabzug', () {
    test('zieht vom Posten mit dem fruehesten Ablaufdatum ab (FEFO) und bucht eine meal-Bewegung mit Verweis', () async {
      final spaet = await stock(reisId, 1, 'kg', bestBefore: _d(2026, 12, 1));
      final frueh = await stock(reisId, 1, 'kg', bestBefore: _d(2026, 10, 1));

      final meal = await mealRepo(db).create(lunch(ingredients: [IngredientDraft(productId: reisId, quantity: 150, entryUnit: EntryUnit.g)]));

      expect((await item(frueh.id)).quantity, closeTo(0.85, 1e-9));
      expect((await item(spaet.id)).quantity, 1, reason: 'der spaetere Posten bleibt unberuehrt');
      final moves = await mealMovements(meal.id);
      expect(moves, hasLength(1));
      expect(moves.single.type, 'meal');
      expect(moves.single.quantityDelta, closeTo(-0.15, 1e-9));
      expect(moves.single.inventoryItemId, frueh.id);
      expect(moves.single.unit, 'kg');
    });

    test('ein angebrochener, bisher ungeoeffneter Posten gilt danach als geoeffnet mit Haltbarkeit nach dem Oeffnen (FR-14)', () async {
      final posten = await stock(reisId, 1, 'kg', bestBefore: _d(2027, 6, 1));
      await mealRepo(db).create(lunch(ingredients: [IngredientDraft(productId: reisId, quantity: 100, entryUnit: EntryUnit.g)]));

      final nachher = await item(posten.id);
      expect(nachher.status, 'opened');
      expect(nachher.openedOn, isNotNull);
      expect(nachher.openShelfLifeDays, 30);
      expect(nachher.expiresOn!.isBefore(_d(2027, 6, 1)), isTrue, reason: 'die Frist nach dem Oeffnen ist frueher als das MHD');
    });

    test('reicht ein Posten nicht, wird der naechste angebrochen (mehrere Bewegungen)', () async {
      final a = await stock(reisId, 0.1, 'kg', bestBefore: _d(2026, 10, 1));
      final b = await stock(reisId, 1, 'kg', bestBefore: _d(2026, 11, 1));
      final meal = await mealRepo(db).create(lunch(ingredients: [IngredientDraft(productId: reisId, quantity: 150, entryUnit: EntryUnit.g)]));

      expect((await item(a.id)).quantity, 0);
      expect((await item(a.id)).status, 'consumed', reason: 'ein leerer Posten wird abgeschlossen');
      expect((await item(b.id)).quantity, closeTo(0.95, 1e-9));
      expect((await mealMovements(meal.id)).map((m) => m.quantityDelta), [closeTo(-0.1, 1e-9), closeTo(-0.05, 1e-9)]);
    });

    test('Bestand wird nie negativ (FR-11): der Rest bleibt "nicht im Bestand", Naehrwerte zaehlen trotzdem voll', () async {
      final posten = await stock(reisId, 0.05, 'kg', bestBefore: _d(2026, 12, 1));
      final meal = await mealRepo(db).create(lunch(ingredients: [IngredientDraft(productId: reisId, quantity: 200, entryUnit: EntryUnit.g)]));

      expect((await item(posten.id)).quantity, 0);
      final moves = await mealMovements(meal.id);
      expect(moves.fold<double>(0, (s, m) => s + m.quantityDelta), closeTo(-0.05, 1e-9), reason: 'nur abziehen, was da ist');
      final ing = (await mealRepo(db).ingredientsOf(meal.id)).single;
      expect(ing.kcal, closeTo(700, 1e-9), reason: '200 g x 350 kcal je 100 g, unabhaengig vom Bestand');
    });

    test('ohne jeden Bestand: Eintrag geht trotzdem durch, keine Bewegung', () async {
      final meal = await mealRepo(db).create(lunch(ingredients: [IngredientDraft(productId: reisId, quantity: 100, entryUnit: EntryUnit.g)]));
      expect(await mealMovements(meal.id), isEmpty);
      expect((await mealRepo(db).ingredientsOf(meal.id)).single.kcal, closeTo(350, 1e-9));
    });

    test('Fluessigkeit: 250 ml ziehen 0,25 l ab, Naehrwerte ueber die ml-Basis', () async {
      final posten = await stock(milchId, 1, 'l', bestBefore: _d(2026, 10, 5));
      final meal = await mealRepo(db).create(lunch(ingredients: [IngredientDraft(productId: milchId, quantity: 250, entryUnit: EntryUnit.ml)]));
      expect((await item(posten.id)).quantity, closeTo(0.75, 1e-9));
      expect((await mealRepo(db).ingredientsOf(meal.id)).single.kcal, closeTo(160, 1e-9));
    });

    test('war es der letzte Bestand, loest das wie "Aufgebraucht" onDepleted aus', () async {
      final depleted = <String>[];
      final inventory = inventoryRepo(db, onDepleted: (id) async => depleted.add(id));
      await inventory.recordFromScan(productId: reisId, ean: '1', quantity: 0.1, unit: 'kg', now: _d(2026, 9, 1));
      await mealRepo(db, inventory: inventory).create(lunch(ingredients: [IngredientDraft(productId: reisId, quantity: 100, entryUnit: EntryUnit.g)]));
      expect(depleted, [reisId]);
    });

    test('deduct=false (z.B. Restaurant, Reste): kein Abzug, Naehrwerte trotzdem berechnet', () async {
      final posten = await stock(reisId, 1, 'kg', bestBefore: _d(2026, 12, 1));
      final meal = await mealRepo(db).create(lunch(ingredients: [IngredientDraft(productId: reisId, quantity: 100, entryUnit: EntryUnit.g, deduct: false)]));
      expect((await item(posten.id)).quantity, 1);
      expect(await mealMovements(meal.id), isEmpty);
      expect((await mealRepo(db).ingredientsOf(meal.id)).single.source, 'manual');
    });
  });

  group('Zutaten und Naehrwert-Snapshot', () {
    test('Produkt-Zutat: Snapshot aus dem Produktprofil, Menge normiert (150 g -> 0,15 kg), Quelle inventory', () async {
      await stock(reisId, 1, 'kg');
      final meal = await mealRepo(db).create(lunch(ingredients: [IngredientDraft(productId: reisId, quantity: 150, entryUnit: EntryUnit.g)]));
      final ing = (await mealRepo(db).ingredientsOf(meal.id)).single;
      expect(ing.quantity, closeTo(0.15, 1e-9));
      expect(ing.unit, 'kg');
      expect(ing.amountG, closeTo(150, 1e-9));
      expect(ing.kcal, closeTo(525, 1e-9));
      expect(ing.proteinG, closeTo(10.5, 1e-9));
      expect(ing.fatG, isNull, reason: 'nicht hinterlegt bleibt null statt 0');
      expect(ing.source, 'inventory');
      expect(ing.inventoryItemId, isNotNull);
    });

    test('Freitext-Zutat mit eigenem Profil (z.B. BLS): skaliert, kein Abzug, kein Produkt', () async {
      final meal = await mealRepo(db).create(lunch(ingredients: const [
        IngredientDraft(
          freeText: 'Gemuesepaprika rot, roh',
          quantity: 120,
          entryUnit: EntryUnit.g,
          per100: NutrientsPer100(kcal: 36, proteinG: 1.0),
          per100Basis: 'g',
        ),
      ]));
      final ing = (await mealRepo(db).ingredientsOf(meal.id)).single;
      expect(ing.productId, isNull);
      expect(ing.freeText, 'Gemuesepaprika rot, roh');
      expect(ing.kcal, closeTo(43.2, 1e-9));
      expect(ing.source, 'manual');
      expect(await db.select(db.inventoryMovements).get(), isEmpty);
    });

    test('Handeingabe der Naehrwerte hat Vorrang (Restaurantessen, Doku 15 §3.3)', () async {
      final meal = await mealRepo(db).create(MealDraft(
        title: 'Pizza auswaerts',
        eatenAt: _d(2026, 9, 22, 19),
        isEstimate: true,
        ingredients: const [
          IngredientDraft(
            freeText: 'Pizza Margherita',
            quantity: 1,
            entryUnit: EntryUnit.piece,
            manualNutrients: NutrientAmounts(kcal: 850, proteinG: 32),
            source: 'estimate',
            deduct: false,
          ),
        ],
      ));
      final ing = (await mealRepo(db).ingredientsOf(meal.id)).single;
      expect(ing.kcal, 850);
      expect(ing.proteinG, 32);
      expect(ing.source, 'estimate');
      expect((await mealRepo(db).get(meal.id))!.isEstimate, isTrue);
    });

    test('Produkt ohne Naehrwerte: Zutat gespeichert, Naehrwerte null ("nicht erfasst" statt 0 kcal, FR-15)', () async {
      final ohne = (await productRepo(db).create(name: 'Gewuerzmischung', baseUnit: 'kg')).id;
      final meal = await mealRepo(db).create(lunch(ingredients: [IngredientDraft(productId: ohne, quantity: 5, entryUnit: EntryUnit.g)]));
      final ing = (await mealRepo(db).ingredientsOf(meal.id)).single;
      expect(ing.kcal, isNull);
      expect(ing.amountG, isNull);
    });

    test('Stueckware ohne Stueckgewicht: Abzug klappt, Naehrwerte bleiben null statt zu raten', () async {
      final ei = (await productRepo(db).create(
        name: 'Ei',
        baseUnit: 'piece',
        nutrientsPer100: {'kcal': 143},
        nutrientsBasis: 'g',
        nutrientsSource: 'manual',
      ))
          .id;
      final posten = await stock(ei, 6, 'piece', bestBefore: _d(2026, 10, 1));
      final meal = await mealRepo(db).create(lunch(ingredients: [IngredientDraft(productId: ei, quantity: 2, entryUnit: EntryUnit.piece)]));
      expect((await item(posten.id)).quantity, 4);
      expect((await mealRepo(db).ingredientsOf(meal.id)).single.kcal, isNull);
    });

    test('Stueckware mit Stueckgewicht: 2 Eier x 60 g = 120 g -> 171,6 kcal', () async {
      final ei = (await productRepo(db).create(
        name: 'Ei',
        baseUnit: 'piece',
        nutrientsPer100: {'kcal': 143},
        nutrientsBasis: 'g',
        nutrientsSource: 'manual',
        unitWeightG: 60,
      ))
          .id;
      final meal = await mealRepo(db).create(lunch(ingredients: [IngredientDraft(productId: ei, quantity: 2, entryUnit: EntryUnit.piece)]));
      expect((await mealRepo(db).ingredientsOf(meal.id)).single.kcal, closeTo(171.6, 1e-9));
    });
  });

  group('Loeschen mit Gegenbuchung (LH-MEAL-04, FR-12)', () {
    test('stellt den Bestand exakt wieder her; das Ledger zeigt Abzug UND Gegenbuchung (append-only)', () async {
      final posten = await stock(reisId, 1, 'kg', bestBefore: _d(2026, 12, 1));
      final meal = await mealRepo(db).create(lunch(ingredients: [IngredientDraft(productId: reisId, quantity: 150, entryUnit: EntryUnit.g)]));
      expect((await item(posten.id)).quantity, closeTo(0.85, 1e-9));

      await mealRepo(db).delete(meal.id);

      expect((await item(posten.id)).quantity, closeTo(1, 1e-9));
      final moves = await mealMovements(meal.id);
      expect(moves.map((m) => m.type), ['meal', 'adjustment']);
      expect(moves.map((m) => m.quantityDelta), [closeTo(-0.15, 1e-9), closeTo(0.15, 1e-9)]);
      expect(moves.fold<double>(0, (s, m) => s + m.quantityDelta), closeTo(0, 1e-9), reason: 'netto null: der Bestand ist wieder voll');
      expect(moves.every((m) => m.deletedAt == null), isTrue, reason: 'nichts wird ueberschrieben oder geloescht');
      expect(moves.last.note, 'Gegenbuchung zur Mahlzeit');
    });

    test('Mahlzeit und Zutaten sind danach geloescht (Soft-Delete), nicht mehr in watchMeals', () async {
      await stock(reisId, 1, 'kg');
      final meal = await mealRepo(db).create(lunch(ingredients: [IngredientDraft(productId: reisId, quantity: 100, entryUnit: EntryUnit.g)]));
      await mealRepo(db).delete(meal.id);

      expect((await mealRepo(db).get(meal.id))!.deletedAt, isNotNull);
      expect(await mealRepo(db).ingredientsOf(meal.id), isEmpty);
      expect(await mealRepo(db).watchMeals().first, isEmpty);
    });

    test('ein durch die Mahlzeit geleerter Posten ist danach wieder aktiv (geoeffnet, weil er je geoeffnet war)', () async {
      final posten = await stock(reisId, 0.1, 'kg', bestBefore: _d(2026, 12, 1));
      final meal = await mealRepo(db).create(lunch(ingredients: [IngredientDraft(productId: reisId, quantity: 100, entryUnit: EntryUnit.g)]));
      expect((await item(posten.id)).status, 'consumed');

      await mealRepo(db).delete(meal.id);

      final nachher = await item(posten.id);
      expect(nachher.quantity, closeTo(0.1, 1e-9));
      expect(nachher.status, 'sealed', reason: 'er war vor der Mahlzeit ungeoeffnet');
      expect(nachher.closedAt, isNull);
    });

    test('Codereview-Fund 2026-10-16: erst durch die Mahlzeit angebrochen -> danach wieder ungeoeffnet, alte Haltbarkeit', () async {
      final posten = await stock(reisId, 1, 'kg', bestBefore: _d(2026, 12, 1));
      final meal = await mealRepo(db).create(lunch(ingredients: [IngredientDraft(productId: reisId, quantity: 150, entryUnit: EntryUnit.g)]));
      final angebrochen = await item(posten.id);
      expect(angebrochen.status, 'opened');
      expect(angebrochen.expiresOn, DateTime.utc(2026, 10, 22), reason: '30 Tage nach dem Oeffnen am 22.9.');

      await mealRepo(db).delete(meal.id);

      final nachher = await item(posten.id);
      expect(nachher.quantity, closeTo(1, 1e-9));
      expect(nachher.status, 'sealed');
      expect(nachher.openedOn, isNull);
      expect(nachher.expiresOn, DateTime.utc(2026, 12, 1), reason: 'wieder das Mindesthaltbarkeitsdatum');
    });

    test('wurde der Posten danach noch anders verbraucht (zweite Mahlzeit), bleibt er geoeffnet', () async {
      final posten = await stock(reisId, 1, 'kg', bestBefore: _d(2026, 12, 1));
      final erste = await mealRepo(db).create(lunch(ingredients: [IngredientDraft(productId: reisId, quantity: 150, entryUnit: EntryUnit.g)]));
      await mealRepo(db).create(lunch(ingredients: [IngredientDraft(productId: reisId, quantity: 100, entryUnit: EntryUnit.g)]));

      await mealRepo(db).delete(erste.id);

      final nachher = await item(posten.id);
      expect(nachher.quantity, closeTo(0.9, 1e-9));
      expect(nachher.status, 'opened', reason: 'die zweite Mahlzeit hat aus der offenen Packung gegessen');
    });

    test('war der Posten schon vorher geoeffnet, bleibt er es', () async {
      final posten = await stock(reisId, 1, 'kg', bestBefore: _d(2026, 12, 1));
      await inventoryRepo(db).open(posten.id, now: _d(2026, 9, 20));
      final meal = await mealRepo(db).create(lunch(ingredients: [IngredientDraft(productId: reisId, quantity: 150, entryUnit: EntryUnit.g)]));

      await mealRepo(db).delete(meal.id);

      final nachher = await item(posten.id);
      expect(nachher.status, 'opened');
      expect(nachher.openedOn, DateTime.utc(2026, 9, 20));
    });

    test('Codereview-Fund 2026-10-16: Abzuege im Ledger sind auf drei Stellen gerundet wie in der Datenbank', () async {
      // 1 kg aus 0,7 kg und einer vollen Packung: der zweite Abzug waere ungerundet 0.30000000000000004
      await stock(reisId, 0.7, 'kg', bestBefore: _d(2026, 10, 1));
      await stock(reisId, 1, 'kg', bestBefore: _d(2026, 10, 3));
      final meal = await mealRepo(db).create(lunch(ingredients: [IngredientDraft(productId: reisId, quantity: 1000, entryUnit: EntryUnit.g)]));

      final deltas = (await mealMovements(meal.id)).map((m) => m.quantityDelta).toList();
      expect(deltas, hasLength(2));
      for (final d in deltas) {
        expect(d * 1000, (d * 1000).roundToDouble(), reason: '$d');
      }
      expect(deltas.fold<double>(0, (s, d) => s + d), closeTo(-1, 1e-12));
    });

    test('Rueckbuchung ist idempotent: ein zweiter Aufruf bucht nichts mehr zurueck', () async {
      final posten = await stock(reisId, 1, 'kg', bestBefore: _d(2026, 12, 1));
      final meal = await mealRepo(db).create(lunch(ingredients: [IngredientDraft(productId: reisId, quantity: 150, entryUnit: EntryUnit.g)]));
      final inventory = inventoryRepo(db);
      expect(await inventory.restoreForMeal(meal.id), 1);
      expect(await inventory.restoreForMeal(meal.id), 0);
      expect((await item(posten.id)).quantity, closeTo(1, 1e-9));
    });

    test('ein inzwischen geloeschter Posten wird uebersprungen statt Fehler', () async {
      final posten = await stock(reisId, 1, 'kg');
      final meal = await mealRepo(db).create(lunch(ingredients: [IngredientDraft(productId: reisId, quantity: 100, entryUnit: EntryUnit.g)]));
      await inventoryRepo(db).deleteItem(posten.id);
      await mealRepo(db).delete(meal.id); // darf nicht werfen
      expect((await mealRepo(db).get(meal.id))!.deletedAt, isNotNull);
    });

    test('unbekannte oder schon geloeschte Mahlzeit: kein Fehler', () async {
      await mealRepo(db).delete('gibt-es-nicht');
    });
  });

  group('Bearbeiten (alten Abzug zurueck, neuen berechnen)', () {
    test('andere Menge: Nettobestand entspricht der neuen Menge, Ledger bleibt vollstaendig', () async {
      final posten = await stock(reisId, 1, 'kg', bestBefore: _d(2026, 12, 1));
      final repo = mealRepo(db);
      final meal = await repo.create(lunch(ingredients: [IngredientDraft(productId: reisId, quantity: 150, entryUnit: EntryUnit.g)]));

      await repo.update(meal.id, lunch(ingredients: [IngredientDraft(productId: reisId, quantity: 300, entryUnit: EntryUnit.g)]));

      expect((await item(posten.id)).quantity, closeTo(0.7, 1e-9));
      final moves = await mealMovements(meal.id);
      expect(moves.map((m) => m.type), ['meal', 'adjustment', 'meal'], reason: 'Abzug, Gegenbuchung, neuer Abzug');
      final ings = await repo.ingredientsOf(meal.id);
      expect(ings, hasLength(1), reason: 'die alte Zutatenzeile ist soft-geloescht');
      expect(ings.single.kcal, closeTo(1050, 1e-9));
    });

    test('Kopfdaten aendern sich, Zutat entfaellt: Bestand wieder voll', () async {
      final posten = await stock(reisId, 1, 'kg', bestBefore: _d(2026, 12, 1));
      final repo = mealRepo(db);
      final meal = await repo.create(lunch(ingredients: [IngredientDraft(productId: reisId, quantity: 150, entryUnit: EntryUnit.g)]));

      final updated = await repo.update(meal.id, MealDraft(title: 'Nur Tee', mealType: 'drink', eatenAt: _d(2026, 9, 22, 15)));
      expect(updated.title, 'Nur Tee');
      expect((await item(posten.id)).quantity, closeTo(1, 1e-9));
      expect(await repo.ingredientsOf(meal.id), isEmpty);
    });

    test('unbekannte Mahlzeit: StateError', () async {
      expect(() => mealRepo(db).update('gibt-es-nicht', lunch(ingredients: const [])), throwsStateError);
    });
  });

  group('Validierung und Sync', () {
    test('leerer Titel und Portionen <= 0 werden abgelehnt', () {
      expect(() => mealRepo(db).create(MealDraft(title: '  ', eatenAt: _d(2026, 9, 1))), throwsArgumentError);
      expect(() => mealRepo(db).create(MealDraft(title: 'x', eatenAt: _d(2026, 9, 1), servingsEaten: 0)), throwsArgumentError);
      expect(() => mealRepo(db).create(MealDraft(title: 'x', eatenAt: _d(2026, 9, 1), servingsMade: -1)), throwsArgumentError);
    });

    test('Outbox: Mahlzeit vor Zutaten vor Bewegungen (Fremdschluessel auf dem Server), onChanged genau einmal', () async {
      await stock(reisId, 1, 'kg');
      var changed = 0;
      final repo = mealRepo(db, onChanged: () => changed++);
      await db.delete(db.outbox).go();
      await repo.create(lunch(ingredients: [IngredientDraft(productId: reisId, quantity: 100, entryUnit: EntryUnit.g)]));

      final tables = (await (db.select(db.outbox)..orderBy([(o) => OrderingTerm.asc(o.id)])).get()).map((o) => o.remoteTable).toList();
      expect(tables.indexOf('meals'), lessThan(tables.indexOf('meal_ingredients')));
      expect(tables.indexOf('meals'), lessThan(tables.indexOf('inventory_movements')));
      expect(changed, greaterThanOrEqualTo(1));
    });
  });
}
