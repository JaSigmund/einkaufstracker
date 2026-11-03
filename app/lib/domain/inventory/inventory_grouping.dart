/// Bestand nach Produktkategorien (Inventar-Ansicht "Kategorien", Release 1.22). Reine Funktionen ohne Datenbankzugriff.
///
/// Regeln:
/// - Eine Position gehoert zur Kategorie ihres Produkts. Ohne Produkt, ohne Kategorie oder mit geloeschter Kategorie landet sie unter
///   "Ohne Kategorie", ganz unten.
/// - Kategorien in der Reihenfolge der Kategorieliste (Sortierung, dann Name), nur die mit Bestand.
/// - Innerhalb einer Kategorie das Dringende zuerst: abgelaufen, bald faellig, gut, ohne Datum; dann nach Datum und Name.
/// - Jede Gruppe zaehlt ihre abgelaufenen und bald faelligen Positionen, damit die eingeklappte Kopfzeile sie zeigen kann.
library;

import 'expiry.dart';

/// Schluessel der Gruppe fuer Positionen ohne (bekannte) Kategorie.
const uncategorizedKey = '_none';

/// Eine Position, wie die Gruppierung sie braucht. [T] ist die Position selbst (in der App ein `InventoryItem`).
typedef GroupableItem<T> = ({T item, String? categoryId, String name, ExpiryLevel level, DateTime? expiresOn});

/// Eine Kategorie aus der Kategorieliste, schon in Anzeigereihenfolge.
typedef GroupCategory = ({String id, String name});

class InventoryCategoryGroup<T> {
  InventoryCategoryGroup({required this.key, required this.name, required this.items, required this.expired, required this.soon});

  /// Kategorie-ID oder [uncategorizedKey].
  final String key;
  final String name;
  final List<GroupableItem<T>> items;
  final int expired;
  final int soon;
}

const _levelOrder = [ExpiryLevel.expired, ExpiryLevel.soon, ExpiryLevel.ok, ExpiryLevel.unknown];

int _compare<T>(GroupableItem<T> a, GroupableItem<T> b) {
  final byLevel = _levelOrder.indexOf(a.level).compareTo(_levelOrder.indexOf(b.level));
  if (byLevel != 0) return byLevel;
  final ae = a.expiresOn, be = b.expiresOn;
  if (ae != null && be != null && ae != be) return ae.compareTo(be);
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

/// Gruppiert [items] nach [categories] (bereits in Anzeigereihenfolge).
List<InventoryCategoryGroup<T>> groupByCategory<T>(Iterable<GroupableItem<T>> items, List<GroupCategory> categories) {
  final known = {for (final c in categories) c.id};
  final byKey = <String, List<GroupableItem<T>>>{};
  for (final i in items) {
    final key = i.categoryId != null && known.contains(i.categoryId) ? i.categoryId! : uncategorizedKey;
    byKey.putIfAbsent(key, () => []).add(i);
  }
  InventoryCategoryGroup<T> group(String key, String name) {
    final list = byKey[key]!..sort(_compare);
    return InventoryCategoryGroup(
      key: key,
      name: name,
      items: list,
      expired: list.where((i) => i.level == ExpiryLevel.expired).length,
      soon: list.where((i) => i.level == ExpiryLevel.soon).length,
    );
  }

  return [
    for (final c in categories)
      if (byKey.containsKey(c.id)) group(c.id, c.name),
    if (byKey.containsKey(uncategorizedKey)) group(uncategorizedKey, 'Ohne Kategorie'),
  ];
}

String _fold(String s) => s
    .toLowerCase()
    .replaceAll('ä', 'a')
    .replaceAll('ö', 'o')
    .replaceAll('ü', 'u')
    .replaceAll('ß', 'ss')
    .trim();

/// Suche im Bestand: jedes Wort der Anfrage muss in Name, Marke oder Kategorie vorkommen, ohne Gross-/Kleinschreibung und Umlaute
/// ("kase" findet "Käse"). Eine leere Anfrage passt immer.
bool matchesInventorySearch(String query, {required String name, String? brand, String? category}) {
  final words = _fold(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (words.isEmpty) return true;
  final hay = _fold([name, brand ?? '', category ?? ''].join(' '));
  return words.every(hay.contains);
}
