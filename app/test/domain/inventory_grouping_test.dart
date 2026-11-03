import 'package:einkaufstracker/domain/inventory/expiry.dart';
import 'package:einkaufstracker/domain/inventory/inventory_grouping.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bestand nach Produktkategorien (Inventar-Ansicht "Kategorien", 1.22).
GroupableItem<String> it(String id, String? cat, ExpiryLevel level, {DateTime? expires, String? name}) =>
    (item: id, categoryId: cat, name: name ?? id, level: level, expiresOn: expires);

void main() {
  final cats = <GroupCategory>[(id: 'milch', name: 'Milchprodukte'), (id: 'obst', name: 'Obst & Gemüse'), (id: 'leer', name: 'Leer')];

  test('Reihenfolge der Kategorieliste, nur mit Bestand, ohne Kategorie zuletzt', () {
    final groups = groupByCategory([
      it('a', 'obst', ExpiryLevel.ok),
      it('b', null, ExpiryLevel.ok),
      it('c', 'milch', ExpiryLevel.ok),
      it('d', 'geloescht', ExpiryLevel.ok),
    ], cats);
    expect(groups.map((g) => g.name), ['Milchprodukte', 'Obst & Gemüse', 'Ohne Kategorie']);
    expect(groups.last.key, uncategorizedKey);
    expect(groups.last.items.map((i) => i.item), ['b', 'd'], reason: 'unbekannte Kategorie zaehlt wie keine');
  });

  test('innerhalb einer Kategorie das Dringende zuerst, dann Datum, dann Name', () {
    final g = groupByCategory([
      it('ohne', 'milch', ExpiryLevel.unknown),
      it('gut-spaet', 'milch', ExpiryLevel.ok, expires: DateTime.utc(2026, 12, 1)),
      it('gut-frueh', 'milch', ExpiryLevel.ok, expires: DateTime.utc(2026, 11, 10)),
      it('ab', 'milch', ExpiryLevel.expired, expires: DateTime.utc(2026, 10, 1)),
      it('bald', 'milch', ExpiryLevel.soon, expires: DateTime.utc(2026, 11, 4)),
    ], cats).single;
    expect(g.items.map((i) => i.item), ['ab', 'bald', 'gut-frueh', 'gut-spaet', 'ohne']);
    expect([g.expired, g.soon], [1, 1]);
  });

  test('ohne Bestand keine Gruppen', () {
    expect(groupByCategory<String>(const [], cats), isEmpty);
  });

  group('Suche', () {
    test('ohne Gross-/Kleinschreibung und Umlaute', () {
      expect(matchesInventorySearch('kase', name: 'Käse'), isTrue);
      expect(matchesInventorySearch('KÄSE', name: 'Bergkäse'), isTrue);
      expect(matchesInventorySearch('strasse', name: 'Straße'), isTrue);
    });

    test('jedes Wort muss passen, in Name, Marke oder Kategorie', () {
      expect(matchesInventorySearch('barilla spag', name: 'Spaghetti', brand: 'Barilla'), isTrue);
      expect(matchesInventorySearch('barilla penne', name: 'Spaghetti', brand: 'Barilla'), isFalse);
      expect(matchesInventorySearch('obst', name: 'Äpfel', category: 'Obst & Gemüse'), isTrue);
    });

    test('leere Anfrage passt immer', () {
      expect(matchesInventorySearch('  ', name: 'Milch'), isTrue);
    });
  });
}
