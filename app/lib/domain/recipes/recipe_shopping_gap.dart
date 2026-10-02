/// Eine Rezept-Zutat mit bekannter Produkt-Zuordnung (Doku 11 Phase 7f "Einkaufsliste aus Rezept",
/// Teil von ADR-021). Nur Zutaten mit bekannter Produkt-Zuordnung koennen automatisch mit dem Inventar
/// abgeglichen werden -- freitextliche Zutaten ohne `productId` landen immer auf der Liste.
///
/// Bewusst OHNE Mengenangabe (Codereview-Fund 2026-10-01, siehe `saved_recipe.dart`): wie viel ein
/// Rezept von einer Zutat braucht, ist nicht bekannt.
typedef RecipeIngredientNeed = ({String productId, String productName});

/// Ein verfuegbarer Inventar-Posten (es kann mehrere je Produkt geben, z.B. zwei offene Packungen).
typedef AvailableQuantity = ({String productId, double quantity});

/// Eine Zutat, von der ueberhaupt kein aktiver Bestand vorhanden ist.
class MissingIngredient {
  const MissingIngredient({required this.productId, required this.productName});

  final String productId;
  final String productName;
}

/// Ermittelt, welche Rezept-Zutaten im aktuellen Inventar komplett fehlen (Doku 11 Phase 7f).
///
/// Bewusst nur "vorhanden ja/nein", keine Mengen-Luecke mehr (Codereview-Fund 2026-10-01): eine fruehere
/// Fassung zog die beim Speichern vorhandene Inventar-Menge als "benoetigte Menge" heran und berechnete
/// daraus eine fehlende Menge -- das war strukturell falsch, ein Lagerbestand ist kein Rezeptbedarf.
/// Ehrliches Verhalten statt eines geratenen Bedarfs: hat der Haushalt ueberhaupt etwas von der Zutat,
/// gilt sie als gedeckt, egal ob die Menge fuer das konkrete Rezept reichen wuerde. Die Oberflaeche legt
/// fehlende Zutaten mit einer festen Menge 1 an, der Nutzer passt sie bei Bedarf selbst an (gleicher
/// Mengen-Stepper wie bei jedem anderen manuellen Einkaufslisten-Eintrag).
List<MissingIngredient> findMissingIngredients(
  Iterable<RecipeIngredientNeed> needed,
  Iterable<AvailableQuantity> available,
) {
  final totalAvailable = <String, double>{};
  for (final a in available) {
    totalAvailable.update(a.productId, (v) => v + a.quantity, ifAbsent: () => a.quantity);
  }

  final seen = <String>{};
  final missing = <MissingIngredient>[];
  for (final n in needed) {
    if (!seen.add(n.productId)) continue; // dieselbe Zutat nicht zweimal vorschlagen
    if ((totalAvailable[n.productId] ?? 0) <= 0) {
      missing.add(MissingIngredient(productId: n.productId, productName: n.productName));
    }
  }
  return missing;
}
