/// Fehlende Zutaten einer Mahlzeit (Doku 11 Phase 7f, offener Rest): "Das koche ich nochmal, was muss ich einkaufen?"
///
/// Anders als bei Rezeptvorschlaegen (`recipe_shopping_gap.dart`, ohne Mengen) ist bei einer erfassten Mahlzeit die Menge je Zutat
/// bekannt. Deshalb gilt hier: ein Produkt fehlt, wenn gar nichts da ist, und es reicht nicht, wenn der Bestand unter der
/// gebrauchten Menge liegt. Zutaten ohne Produkt (Freitext aus der Datenbank) lassen sich nicht gegen den Bestand pruefen und
/// werden nur angeboten, nicht vorausgewaehlt.
///
/// Reine Funktionen ohne Datenbankzugriff.
library;

/// Eine Zutat der Mahlzeit: [needed] ist die Menge in der Basiseinheit des Produkts ([baseUnit]), `null` wenn sie sich nicht
/// umrechnen laesst (Stueck ohne Gewicht).
typedef ShortageInput = ({String? productId, String name, double? needed, String? baseUnit});

enum ShortageKind {
  /// Von dem Produkt ist nichts im Bestand.
  missing,

  /// Es ist etwas da, aber weniger als die Mahlzeit braucht.
  insufficient,

  /// Zutat ohne Produkt: der Bestand kann nicht geprueft werden.
  unchecked,
}

/// Ein Vorschlag fuer die Einkaufsliste.
class ShoppingCandidate {
  const ShoppingCandidate({
    required this.name,
    required this.kind,
    this.productId,
    this.baseUnit,
    this.needed,
    this.available,
    this.alreadyOnList = false,
  });

  final String name;
  final ShortageKind kind;
  final String? productId;
  final String? baseUnit;

  /// Gebrauchte Menge und Bestand in der Basiseinheit des Produkts.
  final double? needed;
  final double? available;

  /// Steht schon (unabgehakt) auf der Einkaufsliste: kein zweiter Eintrag.
  final bool alreadyOnList;

  /// Ein sicher fehlendes Produkt, das noch nicht auf der Liste steht, ist vorausgewaehlt.
  bool get preselected => !alreadyOnList && kind != ShortageKind.unchecked;
}

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-zäöüß0-9]+'), ' ').trim();

/// Ermittelt die Vorschlaege. [stock] ist der aktive Bestand je Produkt-ID in der Basiseinheit, [listedProductIds] und [listedTexts]
/// sind die unabgehakten Eintraege der Einkaufsliste (Freitext beliebig geschrieben).
///
/// Dieselbe Zutat zweimal in einer Mahlzeit (zwei Mal Zwiebel) wird zusammengezaehlt. Ausgegeben wird zuerst, was sicher fehlt,
/// dann was nicht pruefbar ist, jeweils in der Reihenfolge der Mahlzeit. Gedeckte Zutaten kommen nicht vor.
List<ShoppingCandidate> findMealShortages(
  Iterable<ShortageInput> ingredients, {
  required Map<String, double> stock,
  Set<String> listedProductIds = const {},
  Set<String> listedTexts = const {},
}) {
  final neededSum = <String, double?>{};
  final order = <String>[];
  final names = <String, String>{};
  final units = <String, String?>{};
  final free = <String, String>{};
  final freeOrder = <String>[];

  for (final i in ingredients) {
    final id = i.productId;
    if (id == null) {
      final key = _norm(i.name);
      if (key.isEmpty || free.containsKey(key)) continue;
      free[key] = i.name.trim();
      freeOrder.add(key);
      continue;
    }
    if (!neededSum.containsKey(id)) order.add(id);
    names.putIfAbsent(id, () => i.name);
    units.putIfAbsent(id, () => i.baseUnit);
    final prev = neededSum[id];
    if (!neededSum.containsKey(id)) {
      neededSum[id] = i.needed;
    } else if (prev != null && i.needed != null) {
      neededSum[id] = prev + i.needed!;
    } else {
      neededSum[id] = null; // eine Teilmenge ist nicht umrechenbar: die Summe auch nicht
    }
  }

  final shortages = <ShoppingCandidate>[];
  for (final id in order) {
    final have = stock[id] ?? 0;
    final need = neededSum[id];
    final ShortageKind? kind = have <= 1e-9
        ? ShortageKind.missing
        : (need != null && have < need - 1e-9 ? ShortageKind.insufficient : null);
    if (kind == null) continue;
    shortages.add(ShoppingCandidate(
      name: names[id]!,
      kind: kind,
      productId: id,
      baseUnit: units[id],
      needed: need,
      available: have,
      alreadyOnList: listedProductIds.contains(id),
    ));
  }

  final unchecked = [
    for (final key in freeOrder)
      ShoppingCandidate(name: free[key]!, kind: ShortageKind.unchecked, alreadyOnList: listedTexts.map(_norm).contains(key)),
  ];
  return [...shortages, ...unchecked];
}
