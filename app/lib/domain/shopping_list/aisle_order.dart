/// Regal-Reihenfolge je Haendler (Ausbau 1.14): in welcher Reihenfolge ein Markt seine Kategorien im Gang fuehrt (Obst, Milch, Brot, ...),
/// damit die Einkaufsliste dort ohne Hin- und Herlaufen abgearbeitet werden kann. Reine Funktionen.
///
/// Gespeichert als gemeinsame Einstellung des Haushalts (`household_prefs`, Schluessel [aislePrefFor]) mit der Liste der Kategorie-IDs
/// in Regal-Reihenfolge. Kategorien, die in der Liste fehlen (neu angelegt), kommen danach alphabetisch, Eintraege ohne Kategorie zuletzt.
library;

/// Schluessel der gemeinsamen Einstellung fuer einen Haendler (Filiale). Bleibt mit der UUID unter 64 Zeichen.
String aislePrefFor(String storeId) => 'aisle_order:$storeId';

/// Liest die gespeicherte Reihenfolge (Liste von Kategorie-IDs) defensiv: nur nicht leere Texte, ohne Doppelte. `null`, wenn nichts
/// Brauchbares uebrig bleibt (dann gibt es fuer diesen Haendler keine Reihenfolge).
List<String>? parseAisleOrder(Object? json) {
  if (json is! List) return null;
  final out = <String>[];
  for (final v in json) {
    if (v is String && v.trim().isNotEmpty && !out.contains(v)) out.add(v);
  }
  return out.isEmpty ? null : out;
}

/// Eine Kategorie fuer die Pflege der Reihenfolge.
typedef AisleCategory = ({String id, String name});

/// Die Reihenfolge zum Bearbeiten: gespeicherte Kategorien in ihrer Reihenfolge (geloeschte fallen weg), danach die uebrigen
/// alphabetisch.
List<AisleCategory> orderedForEditing(List<String> saved, Iterable<AisleCategory> categories) {
  final byId = {for (final c in categories) c.id: c};
  final first = [for (final id in saved) ?byId.remove(id)];
  final rest = byId.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return [...first, ...rest];
}

/// Sortiert Gruppen der Einkaufsliste nach der Regal-Reihenfolge. [idOf] liefert die Kategorie-ID einer Gruppe (`null` = ohne Kategorie).
/// Erst die Gruppen, deren Kategorie in [order] steht, in dieser Reihenfolge; dann die uebrigen alphabetisch nach [nameOf]; die Gruppe
/// ohne Kategorie ganz zuletzt. Ohne [order] (leer) bleibt es bei der alphabetischen Reihenfolge mit "ohne Kategorie" zuletzt.
List<T> sortGroupsByAisle<T>(Iterable<T> groups, {required List<String> order, required String? Function(T) idOf, required String Function(T) nameOf}) {
  final position = {for (var i = 0; i < order.length; i++) order[i]: i};
  int rank(T g) {
    final id = idOf(g);
    if (id == null) return 2;
    return position.containsKey(id) ? 0 : 1;
  }

  final list = groups.toList();
  list.sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    if (byRank != 0) return byRank;
    if (rank(a) == 0) return position[idOf(a)]!.compareTo(position[idOf(b)]!);
    return nameOf(a).toLowerCase().compareTo(nameOf(b).toLowerCase());
  });
  return list;
}
