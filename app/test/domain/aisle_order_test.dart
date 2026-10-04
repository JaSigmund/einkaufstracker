import 'package:einkaufstracker/domain/shopping_list/aisle_order.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regal-Reihenfolge je Haendler (Ausbau 1.14).
typedef G = ({String? id, String name});

G g(String? id, String name) => (id: id, name: name);

List<String> names(List<G> l) => [for (final x in l) x.name];

void main() {
  List<G> sort(List<G> groups, List<String> order) => sortGroupsByAisle(groups, order: order, idOf: (x) => x.id, nameOf: (x) => x.name);

  group('sortGroupsByAisle', () {
    final groups = [g('k-milch', 'Milchprodukte'), g('k-obst', 'Obst'), g(null, 'Ohne Kategorie'), g('k-brot', 'Brot'), g('k-tk', 'Tiefkühl')];

    test('ohne Reihenfolge: alphabetisch, ohne Kategorie zuletzt', () {
      expect(names(sort(groups, const [])), ['Brot', 'Milchprodukte', 'Obst', 'Tiefkühl', 'Ohne Kategorie']);
    });

    test('mit Reihenfolge: erst nach Regal, dann die uebrigen alphabetisch, ohne Kategorie zuletzt', () {
      final r = sort(groups, ['k-obst', 'k-brot', 'k-milch']);
      expect(names(r), ['Obst', 'Brot', 'Milchprodukte', 'Tiefkühl', 'Ohne Kategorie']);
    });

    test('Kategorien in der Reihenfolge, die es auf der Liste nicht gibt, stoeren nicht', () {
      final r = sort([g('k-brot', 'Brot'), g('k-obst', 'Obst')], ['k-geloescht', 'k-obst', 'k-brot']);
      expect(names(r), ['Obst', 'Brot']);
    });

    test('Gross- und Kleinschreibung zaehlt bei der alphabetischen Reihenfolge nicht', () {
      expect(names(sort([g('b', 'brot'), g('a', 'Apfel'), g('c', 'Chips')], const [])), ['Apfel', 'brot', 'Chips']);
    });

    test('eine leere Eingabe bleibt leer', () {
      expect(sort(const [], ['x']), isEmpty);
    });
  });

  group('parseAisleOrder', () {
    test('liest Texte ohne Doppelte in der gespeicherten Reihenfolge', () {
      expect(parseAisleOrder(['a', 'b', 'a', 'c']), ['a', 'b', 'c']);
    });

    test('nur nicht leere Texte, alles andere fehlt; nichts Brauchbares ist null', () {
      expect(parseAisleOrder(['a', '', ' ', 3, null, 'b']), ['a', 'b']);
      expect(parseAisleOrder(const []), isNull);
      expect(parseAisleOrder([1, 2]), isNull);
      expect(parseAisleOrder('a'), isNull);
      expect(parseAisleOrder(null), isNull);
    });
  });

  group('orderedForEditing', () {
    const cats = <AisleCategory>[(id: 'a', name: 'Backwaren'), (id: 'b', name: 'Obst'), (id: 'c', name: 'Dosen')];

    test('gespeicherte zuerst in ihrer Reihenfolge, neue danach alphabetisch, geloeschte fallen weg', () {
      final r = orderedForEditing(['b', 'zz', 'a'], cats);
      expect(r.map((c) => c.id), ['b', 'a', 'c']);
    });

    test('ohne gespeicherte Reihenfolge alphabetisch', () {
      expect(orderedForEditing(const [], cats).map((c) => c.name), ['Backwaren', 'Dosen', 'Obst']);
    });
  });

  test('der Schluessel je Haendler bleibt unter 64 Zeichen (Grenze der Einstellungen)', () {
    expect(aislePrefFor('12345678-1234-1234-1234-123456789012').length, lessThanOrEqualTo(64));
  });
}
