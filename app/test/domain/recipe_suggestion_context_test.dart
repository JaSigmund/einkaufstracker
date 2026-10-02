import 'package:einkaufstracker/domain/inventory/expiry.dart';
import 'package:einkaufstracker/domain/recipes/recipe_suggestion_context.dart';
import 'package:flutter_test/flutter_test.dart';

InventoryIngredient _item(
  String productId,
  String name, {
  double quantity = 1,
  String unit = 'piece',
  DateTime? expiresOn,
  String dateKind = 'best_before',
}) =>
    (productId: productId, productName: name, quantity: quantity, unit: unit, expiresOn: expiresOn, dateKind: dateKind);

void main() {
  group('buildRecipeSuggestionContext', () {
    final today = DateTime.utc(2026, 10, 1);

    test('bald ablaufende Zutaten stehen vor unkritischen', () {
      final result = buildRecipeSuggestionContext([
        _item('a', 'Reis', expiresOn: DateTime.utc(2027, 1, 1)), // weit weg: ok
        _item('b', 'Joghurt', expiresOn: DateTime.utc(2026, 10, 2)), // morgen: soon
      ], today: today);

      expect(result.map((i) => i.productName), ['Joghurt', 'Reis']);
      expect(result[0].urgency, ExpiryLevel.soon);
      expect(result[1].urgency, ExpiryLevel.ok);
    });

    test('abgelaufenes Mindesthaltbarkeitsdatum (best_before) bleibt drin, hoechste Prioritaet', () {
      final result = buildRecipeSuggestionContext([
        _item('a', 'Reis', expiresOn: DateTime.utc(2027, 1, 1)),
        _item('b', 'Nudeln', expiresOn: DateTime.utc(2026, 9, 1), dateKind: 'best_before'),
      ], today: today);

      expect(result.first.productName, 'Nudeln');
      expect(result.first.urgency, ExpiryLevel.expired);
    });

    test('abgelaufenes Verbrauchsdatum (use_by) wird aus Sicherheitsgruenden ausgeschlossen', () {
      final result = buildRecipeSuggestionContext([
        _item('a', 'Hackfleisch', expiresOn: DateTime.utc(2026, 9, 1), dateKind: 'use_by'),
        _item('b', 'Reis', expiresOn: DateTime.utc(2027, 1, 1)),
      ], today: today);

      expect(result.map((i) => i.productName), ['Reis']);
    });

    test('gleiches Produkt (zwei offene Packungen) wird zusammengefuehrt, Menge addiert', () {
      final result = buildRecipeSuggestionContext([
        _item('a', 'Joghurt', quantity: 1, expiresOn: DateTime.utc(2026, 11, 1)),
        _item('a', 'Joghurt', quantity: 2, expiresOn: DateTime.utc(2026, 10, 2)),
      ], today: today);

      expect(result, hasLength(1));
      expect(result.single.quantity, 3);
      expect(result.single.urgency, ExpiryLevel.soon); // der dringlichere der beiden Posten gewinnt
    });

    test('kein Ablaufdatum bekannt: Zutat bleibt drin, aber mit niedrigster Prioritaet', () {
      final result = buildRecipeSuggestionContext([
        _item('a', 'Mehl', expiresOn: null),
        _item('b', 'Joghurt', expiresOn: DateTime.utc(2026, 10, 2)),
      ], today: today);

      expect(result.last.productName, 'Mehl');
      expect(result.last.urgency, ExpiryLevel.unknown);
    });

    test('leeres Inventar: leere Liste', () {
      expect(buildRecipeSuggestionContext(const [], today: today), isEmpty);
    });

    test('productId bleibt erhalten (fuer spaeteren Inventar-Abgleich beim Speichern)', () {
      final result = buildRecipeSuggestionContext([_item('p1', 'Joghurt')], today: today);
      expect(result.single.productId, 'p1');
    });
  });
}
