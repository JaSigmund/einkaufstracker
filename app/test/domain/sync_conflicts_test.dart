import 'package:einkaufstracker/domain/sync/sync_conflicts.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _C = ({String table, String rowId});

_C _c(String table, String id) => (table: table, rowId: id);

void main() {
  group('conflictAreaLabel', () {
    test('Tabellen gehoeren zu verstaendlichen Bereichen', () {
      expect(conflictAreaLabel('shopping_list_items'), 'Einkaufsliste');
      expect(conflictAreaLabel('shopping_lists'), 'Einkaufsliste');
      expect(conflictAreaLabel('inventory_items'), 'Inventar');
      expect(conflictAreaLabel('products'), 'Produkte');
      expect(conflictAreaLabel('receipt_items'), 'Bons');
      expect(conflictAreaLabel('categories'), 'Kategorien');
      expect(conflictAreaLabel('meals'), 'Tagebuch');
      expect(conflictAreaLabel('meal_ingredients'), 'Tagebuch');
      expect(conflictAreaLabel('nutrition_targets'), 'Richtwerte');
    });

    test('eine unbekannte Tabelle zeigt keinen internen Namen', () {
      expect(conflictAreaLabel('irgendwas_neues'), 'Daten');
    });
  });

  group('conflictSummary', () {
    test('ohne Konflikte: nichts anzeigen', () => expect(conflictSummary(const []), isNull));

    test('ein Konflikt: Einzahl, mit dem Bereich', () {
      expect(conflictSummary([_c('shopping_list_items', 'a')]), 'Deine Änderung hat eine neuere von jemand anderem überschrieben (Einkaufsliste).');
    });

    test('mehrere: Anzahl und Bereiche ohne Wiederholung, in der Reihenfolge des ersten Auftretens', () {
      final text = conflictSummary([_c('shopping_list_items', 'a'), _c('inventory_items', 'b'), _c('shopping_lists', 'c')]);
      expect(text, '3 Änderungen von dir haben neuere von anderen überschrieben (Einkaufsliste, Inventar).');
    });

    test('mehrere Konflikte im selben Bereich nennen ihn einmal', () {
      expect(conflictSummary([_c('meals', 'a'), _c('meal_ingredients', 'b')]), contains('(Tagebuch)'));
    });
  });

  group('mergeConflicts', () {
    test('neue Konflikte kommen hinzu', () {
      expect(mergeConflicts([_c('products', 'a')], [_c('products', 'b')]), [_c('products', 'a'), _c('products', 'b')]);
    });

    test('dieselbe Zeile wird nicht doppelt gefuehrt, auch nicht innerhalb der neuen', () {
      final merged = mergeConflicts([_c('products', 'a')], [_c('products', 'a'), _c('products', 'b'), _c('products', 'b')]);
      expect(merged, [_c('products', 'a'), _c('products', 'b')]);
    });

    test('gleiche ID in einer anderen Tabelle ist ein anderer Konflikt', () {
      expect(mergeConflicts([_c('products', 'a')], [_c('categories', 'a')]), hasLength(2));
    });

    test('leer plus leer bleibt leer', () => expect(mergeConflicts(const [], const []), isEmpty));
  });
}
