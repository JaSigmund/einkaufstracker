/// Ein abgeschlossener Einkauf im Archiv (ADR-043): alle Eintraege, die mit einem Tipp auf "Einkauf abschließen" archiviert wurden.
class ArchivedPurchase<T> {
  const ArchivedPurchase({required this.archivedAt, required this.listId, required this.items});

  final DateTime archivedAt;
  final String listId;
  final List<T> items;
}

/// Fasst archivierte Eintraege zu Einkaeufen zusammen, der neueste zuerst. Eintraege eines Abschlusses tragen denselben Zeitstempel;
/// eine geloeschte Liste gibt ihre Eintraege an die Standardliste weiter, deshalb zaehlt die Liste beim Zusammenfassen nicht.
List<ArchivedPurchase<T>> groupArchivedPurchases<T>(Iterable<T> items, {required DateTime Function(T) archivedAt, required String Function(T) listId}) {
  final byTime = <DateTime, List<T>>{};
  for (final item in items) {
    byTime.putIfAbsent(archivedAt(item).toUtc(), () => []).add(item);
  }
  return [
    for (final e in byTime.entries) ArchivedPurchase(archivedAt: e.key, listId: listId(e.value.first), items: e.value),
  ]..sort((a, b) => b.archivedAt.compareTo(a.archivedAt));
}
