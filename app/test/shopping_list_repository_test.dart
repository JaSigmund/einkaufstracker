import 'package:einkaufstracker/data/local/database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  late AppDatabase db;
  late String productId;

  setUp(() async {
    db = memoryDb();
    productId = (await productRepo(db).create(name: 'Vollmilch', baseUnit: 'l', restock: true)).id;
  });
  tearDown(() => db.close());

  group('addManual', () {
    test('an ein Produkt gebunden: legt beim ersten Eintrag die Standardliste an, landet in der Outbox', () async {
      final repo = shoppingListRepo(db);
      final item = await repo.addManual(productId: productId, unit: 'l');
      expect(item.source, 'manual');
      expect(item.isSuggestion, isFalse);
      expect(item.checked, isFalse);

      final list = await (db.select(db.shoppingLists)..where((l) => l.id.equals(item.listId))).getSingle();
      expect(list.isDefault, isTrue);
      expect(list.householdId, 'h1');

      final outbox = await db.select(db.outbox).get();
      expect(outbox.map((o) => o.remoteTable), containsAll(['shopping_lists', 'shopping_list_items']));
    });

    test('frei getippt: kein Produkt, aber ein Text', () async {
      final item = await shoppingListRepo(db).addManual(freeText: 'Klopapier');
      expect(item.freeText, 'Klopapier');
      expect(item.productId, isNull);
    });

    test('zweiter Eintrag nutzt dieselbe Standardliste', () async {
      final repo = shoppingListRepo(db);
      final first = await repo.addManual(freeText: 'A');
      final second = await repo.addManual(freeText: 'B');
      expect(second.listId, first.listId);
      expect(await db.select(db.shoppingLists).get(), hasLength(1));
    });
  });

  group('setChecked / delete', () {
    test('abhaken und wieder aktivieren', () async {
      final repo = shoppingListRepo(db);
      final item = await repo.addManual(freeText: 'Milch');
      await repo.setChecked(item.id, true);
      var row = await (db.select(db.shoppingListItems)..where((i) => i.id.equals(item.id))).getSingle();
      expect(row.checked, isTrue);

      await repo.setChecked(item.id, false);
      row = await (db.select(db.shoppingListItems)..where((i) => i.id.equals(item.id))).getSingle();
      expect(row.checked, isFalse);
    });
  });

  group('setQuantity (Wunsch "Menge angeben", 2026-09-28) / delete', () {
    test('aendert die Anzahl', () async {
      final repo = shoppingListRepo(db);
      final item = await repo.addManual(productId: productId, unit: 'l');
      await repo.setQuantity(item.id, 3);
      final row = await (db.select(db.shoppingListItems)..where((i) => i.id.equals(item.id))).getSingle();
      expect(row.quantity, 3);
    });

    test('kann mehrfach hintereinander geaendert werden', () async {
      final repo = shoppingListRepo(db);
      final item = await repo.addManual(freeText: 'Klopapier');
      await repo.setQuantity(item.id, 2);
      await repo.setQuantity(item.id, 5);
      final row = await (db.select(db.shoppingListItems)..where((i) => i.id.equals(item.id))).getSingle();
      expect(row.quantity, 5);
    });

    test('loeschen setzt deletedAt, erscheint nicht mehr im Stream', () async {
      final repo = shoppingListRepo(db);
      final item = await repo.addManual(freeText: 'Milch');
      await repo.delete(item.id);
      final row = await (db.select(db.shoppingListItems)..where((i) => i.id.equals(item.id))).getSingle();
      expect(row.deletedAt, isNotNull);
      expect(await repo.watchItems().first, isEmpty);
    });
  });

  group('confirmSuggestion', () {
    test('macht aus einem Vorschlag einen normalen Eintrag', () async {
      final repo = shoppingListRepo(db);
      await repo.suggestDepleted(productId);
      final suggestion = (await repo.watchItems().first).single;
      expect(suggestion.isSuggestion, isTrue);

      await repo.confirmSuggestion(suggestion.id);
      final row = await (db.select(db.shoppingListItems)..where((i) => i.id.equals(suggestion.id))).getSingle();
      expect(row.isSuggestion, isFalse);
    });
  });

  group('suggestDepleted (Doku 06 §6, Ausloeser "Leer")', () {
    test('legt einen Vorschlag an, wenn das Produkt ein Nachkaufprodukt ist', () async {
      final repo = shoppingListRepo(db);
      await repo.suggestDepleted(productId);
      final items = await repo.watchItems().first;
      expect(items, hasLength(1));
      expect(items.single.productId, productId);
      expect(items.single.source, 'depleted');
      expect(items.single.isSuggestion, isTrue);
      expect(items.single.unit, 'l');
    });

    test('kein Nachkaufprodukt: kein Vorschlag', () async {
      final other = await productRepo(db).create(name: 'Deko-Kerze', restock: false);
      await shoppingListRepo(db).suggestDepleted(other.id);
      expect(await shoppingListRepo(db).watchItems().first, isEmpty);
    });

    test('steht schon (unbestaetigt) auf der Liste: kein zweiter Vorschlag', () async {
      final repo = shoppingListRepo(db);
      await repo.suggestDepleted(productId);
      await repo.suggestDepleted(productId);
      expect(await repo.watchItems().first, hasLength(1));
    });

    test('unbekanntes Produkt: kein Absturz', () async {
      await shoppingListRepo(db).suggestDepleted('does-not-exist');
      expect(await shoppingListRepo(db).watchItems().first, isEmpty);
    });
  });

  group('addFromExpiryReminder (Doku 06 §5, Aktion "Auf Liste setzen")', () {
    test('legt sofort einen normalen Eintrag an, keinen weiteren Vorschlag', () async {
      final repo = shoppingListRepo(db);
      await repo.addFromExpiryReminder(productId);
      final items = await repo.watchItems().first;
      expect(items, hasLength(1));
      expect(items.single.source, 'expiring');
      expect(items.single.isSuggestion, isFalse);
      expect(items.single.unit, 'l');
    });

    test('steht schon unbestaetigt auf der Liste: kein zweiter Eintrag', () async {
      final repo = shoppingListRepo(db);
      await repo.suggestDepleted(productId);
      await repo.addFromExpiryReminder(productId);
      expect(await repo.watchItems().first, hasLength(1));
    });

    test('funktioniert auch fuer Produkte ohne restock (die Erinnerung ist schon eine explizite Bestaetigung)', () async {
      final other = await productRepo(db).create(name: 'Einmalkauf', restock: false);
      final repo = shoppingListRepo(db);
      await repo.addFromExpiryReminder(other.id);
      expect(await repo.watchItems().first, hasLength(1));
    });

    test('unbekanntes Produkt: kein Absturz', () async {
      await shoppingListRepo(db).addFromExpiryReminder('does-not-exist');
      expect(await shoppingListRepo(db).watchItems().first, isEmpty);
    });
  });

  group('checkOffForProduct (Doku 06 §7, Bon-Import hakt die Liste ab)', () {
    test('hakt offene, bestaetigte Eintraege desselben Produkts ab', () async {
      final repo = shoppingListRepo(db);
      final item = await repo.addManual(productId: productId, unit: 'l');
      await repo.checkOffForProduct(productId);
      final row = await (db.select(db.shoppingListItems)..where((i) => i.id.equals(item.id))).getSingle();
      expect(row.checked, isTrue);
    });

    test('hakt mehrere offene Eintraege desselben Produkts gleichzeitig ab', () async {
      final repo = shoppingListRepo(db);
      final a = await repo.addManual(productId: productId, unit: 'l');
      final b = await repo.addManual(productId: productId, unit: 'l');
      await repo.checkOffForProduct(productId);
      final rows = await db.select(db.shoppingListItems).get();
      expect(rows.where((r) => r.id == a.id || r.id == b.id).every((r) => r.checked), isTrue);
    });

    test('laesst unbestaetigte Vorschlaege (isSuggestion) in Ruhe', () async {
      final repo = shoppingListRepo(db);
      await repo.suggestDepleted(productId);
      final suggestion = (await repo.watchItems().first).single;
      await repo.checkOffForProduct(productId);
      final row = await (db.select(db.shoppingListItems)..where((i) => i.id.equals(suggestion.id))).getSingle();
      expect(row.checked, isFalse);
    });

    test('laesst bereits abgehakte und geloeschte Eintraege unangetastet, kein Fehler ohne Treffer', () async {
      final repo = shoppingListRepo(db);
      final checked = await repo.addManual(productId: productId, unit: 'l');
      await repo.setChecked(checked.id, true);
      await repo.checkOffForProduct(productId); // kein offener Eintrag mehr -> kein Effekt, kein Fehler
      final row = await (db.select(db.shoppingListItems)..where((i) => i.id.equals(checked.id))).getSingle();
      expect(row.checked, isTrue);
    });

    test('anderes Produkt ohne Listeneintrag: kein Fehler', () async {
      await shoppingListRepo(db).checkOffForProduct('does-not-exist');
    });
  });
}
