import 'package:einkaufstracker/domain/recipes/recipe_shopping_gap.dart';
import 'package:flutter_test/flutter_test.dart';

/// Codereview-Fund 2026-10-01: `findMissingIngredients` berechnet keine Mengen-Luecke mehr (eine
/// fruehere Fassung behandelte den Inventar-Bestand beim Speichern faelschlich als Rezeptbedarf) --
/// nur noch "ueberhaupt kein aktiver Bestand vorhanden" gilt als fehlend.
void main() {
  group('findMissingIngredients', () {
    test('etwas vorhanden (auch wenig): nicht als fehlend gemeldet', () {
      final result = findMissingIngredients(
        [(productId: 'milch', productName: 'Milch')],
        [(productId: 'milch', quantity: 0.1)], // koennte fuer das Rezept zu wenig sein, das wissen wir nicht
      );
      expect(result, isEmpty);
    });

    test('nichts vorhanden: fehlt', () {
      final result = findMissingIngredients(
        [(productId: 'eier', productName: 'Eier')],
        const [],
      );
      expect(result.single.productId, 'eier');
      expect(result.single.productName, 'Eier');
    });

    test('mehrere Inventar-Posten desselben Produkts werden zusammengezaehlt (auch 0 bleibt 0)', () {
      final result = findMissingIngredients(
        [(productId: 'joghurt', productName: 'Joghurt')],
        [(productId: 'joghurt', quantity: 0.0), (productId: 'joghurt', quantity: 0.0)],
      );
      expect(result.single.productId, 'joghurt');
    });

    test('dieselbe Zutat zweimal in der Bedarfsliste erscheint nur einmal im Ergebnis', () {
      final result = findMissingIngredients(
        [
          (productId: 'zwiebel', productName: 'Zwiebel'),
          (productId: 'zwiebel', productName: 'Zwiebel'),
        ],
        const [],
      );
      expect(result, hasLength(1));
    });

    test('keine Zutaten gebraucht: leere Liste', () {
      expect(findMissingIngredients(const [], const [(productId: 'x', quantity: 1)]), isEmpty);
    });

    test('Produkt ohne jeden Inventar-Eintrag: fehlt', () {
      final result = findMissingIngredients(
        [(productId: 'mehl', productName: 'Mehl')],
        [(productId: 'anderes-produkt', quantity: 5)],
      );
      expect(result.single.productId, 'mehl');
    });
  });
}
