/// Eine Zutat, wie sie ein Rezept braucht (Doku 11 Phase 7f "Einkaufsliste aus Rezept", jetzt Teil
/// von ADR-021). Nur Zutaten mit bekannter Produkt-Zuordnung koennen automatisch mit dem Inventar
/// abgeglichen werden -- freitextliche Zutaten ohne `productId` landen immer auf der Liste.
typedef RecipeIngredientNeed = ({String productId, String productName, double quantity, String unit});

/// Ein verfuegbarer Inventar-Posten (es kann mehrere je Produkt geben, z.B. zwei offene Packungen).
typedef AvailableQuantity = ({String productId, double quantity});

/// Eine Zutat, die fehlt oder nicht ausreicht.
class MissingIngredient {
  const MissingIngredient({required this.productId, required this.productName, required this.missingQuantity, required this.unit});

  final String productId;
  final String productName;
  final double missingQuantity;
  final String unit;
}

/// Ermittelt, welche Rezept-Zutaten im aktuellen Inventar fehlen oder nicht ausreichen (Doku 11
/// Phase 7f). Summiert verfuegbare Mengen je Produkt zuerst (mehrere Posten desselben Produkts), und
/// zieht bei mehreren benoetigten Zeilen desselben Produkts (z.B. zwei Rezepte in einer Liste
/// zusammengefasst) die bereits verplante Menge ab, damit dieselbe Inventar-Menge nicht doppelt als
/// "vorhanden" fuer beide Rezepte zaehlt.
List<MissingIngredient> findMissingIngredients(
  Iterable<RecipeIngredientNeed> needed,
  Iterable<AvailableQuantity> available,
) {
  final remaining = <String, double>{};
  for (final a in available) {
    remaining.update(a.productId, (v) => v + a.quantity, ifAbsent: () => a.quantity);
  }

  final missing = <MissingIngredient>[];
  for (final n in needed) {
    final have = remaining[n.productId] ?? 0;
    final gap = n.quantity - have;
    if (gap > 0) {
      missing.add(MissingIngredient(productId: n.productId, productName: n.productName, missingQuantity: gap, unit: n.unit));
    }
    remaining[n.productId] = have - n.quantity > 0 ? have - n.quantity : 0;
  }
  return missing;
}
