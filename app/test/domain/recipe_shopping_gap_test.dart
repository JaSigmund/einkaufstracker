import 'package:einkaufstracker/domain/recipes/recipe_shopping_gap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('findMissingIngredients', () {
    test('ausreichend vorhanden: keine fehlende Zutat', () {
      final result = findMissingIngredients(
        [(productId: 'milch', productName: 'Milch', quantity: 0.5, unit: 'l')],
        [(productId: 'milch', quantity: 1.0)],
      );
      expect(result, isEmpty);
    });

    test('nicht vorhanden: komplette Menge fehlt', () {
      final result = findMissingIngredients(
        [(productId: 'eier', productName: 'Eier', quantity: 3, unit: 'piece')],
        const [],
      );
      expect(result.single.missingQuantity, 3);
      expect(result.single.productName, 'Eier');
    });

    test('teilweise vorhanden: nur die Differenz fehlt', () {
      final result = findMissingIngredients(
        [(productId: 'mehl', productName: 'Mehl', quantity: 1.0, unit: 'kg')],
        [(productId: 'mehl', quantity: 0.3)],
      );
      expect(result.single.missingQuantity, closeTo(0.7, 1e-9));
    });

    test('mehrere Inventar-Posten desselben Produkts werden summiert', () {
      final result = findMissingIngredients(
        [(productId: 'joghurt', productName: 'Joghurt', quantity: 500.0, unit: 'g')],
        [(productId: 'joghurt', quantity: 200.0), (productId: 'joghurt', quantity: 200.0)],
      );
      expect(result.single.missingQuantity, 100);
    });

    test('zwei Rezeptzeilen desselben Produkts verbrauchen denselben Bestand nicht doppelt', () {
      final result = findMissingIngredients(
        [
          (productId: 'zwiebel', productName: 'Zwiebel', quantity: 2, unit: 'piece'),
          (productId: 'zwiebel', productName: 'Zwiebel', quantity: 2, unit: 'piece'),
        ],
        [(productId: 'zwiebel', quantity: 3)],
      );
      // erste Zeile: 3 vorhanden, 2 gebraucht -> 1 Rest, 0 fehlt
      // zweite Zeile: 1 Rest, 2 gebraucht -> 1 fehlt
      expect(result, hasLength(1));
      expect(result.single.missingQuantity, 1);
    });

    test('keine Zutaten gebraucht: leere Liste', () {
      expect(findMissingIngredients(const [], const [(productId: 'x', quantity: 1)]), isEmpty);
    });
  });
}
