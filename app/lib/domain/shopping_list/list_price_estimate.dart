/// Eine Einkaufslistenposition mit den Feldern, die fuer die Summenschaetzung noetig sind: Anzahl
/// (Stepper-Wert, wie in `shopping_list_page.dart` "Gesamtmenge"), Packungsinhalt (`products.pack_size`,
/// `null` bei Stueckware ohne Packungsangabe) und der zuletzt bezahlte Grundpreis in Cent je Basiseinheit
/// (aus `buildPriceHistory`, Doku 07 §3.1 — derselbe Wert, den `computeUnitPriceNormCents` beim Bon-Import
/// berechnet). `null`, wenn das Produkt noch nie gekauft wurde.
typedef EstimatableListItem = ({double quantity, double? packSize, int? lastUnitPriceNormCents});

/// Ergebnis der Summenschaetzung einer Einkaufsliste (offene Frage Q-10 in
/// [[13 Risiken und offene Fragen]]: "Braucht der Nutzer die Preise in der Einkaufsliste?").
class ListTotalEstimate {
  const ListTotalEstimate({required this.totalCents, required this.itemsWithPrice, required this.itemsWithoutPrice});

  /// Summe aller Positionen mit bekanntem Preis, in Cent.
  final int totalCents;
  final int itemsWithPrice;

  /// Anzahl Positionen ohne bekannten Preis (neues Produkt, nie gekauft) — zaehlen nicht in [totalCents]
  /// mit. Wird in der UI angezeigt, damit die Schaetzung nie vollstaendiger wirkt als sie ist (gleiches
  /// Prinzip wie beim Haendlervergleich, Doku 07 §3.2 "zu wenig Daten statt Zufallsaussage").
  final int itemsWithoutPrice;

  bool get isComplete => itemsWithoutPrice == 0;
}

/// Schaetzt die Gesamtsumme einer Einkaufsliste aus dem zuletzt bezahlten Grundpreis je Produkt: Menge in
/// Basiseinheit (Anzahl × Packungsinhalt, wie beim Grundpreis selbst) mal Grundpreis je Basiseinheit —
/// die Umkehrung von `computeUnitPriceNormCents` (`unit_price.dart`).
ListTotalEstimate estimateShoppingListTotal(Iterable<EstimatableListItem> items) {
  var totalCents = 0;
  var withPrice = 0;
  var withoutPrice = 0;
  for (final item in items) {
    final cost = _estimateItemCostCents(item);
    if (cost == null) {
      withoutPrice++;
    } else {
      totalCents += cost;
      withPrice++;
    }
  }
  return ListTotalEstimate(totalCents: totalCents, itemsWithPrice: withPrice, itemsWithoutPrice: withoutPrice);
}

int? _estimateItemCostCents(EstimatableListItem item) {
  final price = item.lastUnitPriceNormCents;
  if (price == null) return null;
  final packSize = item.packSize;
  final baseUnitAmount = (packSize != null && packSize > 0) ? item.quantity * packSize : item.quantity;
  if (baseUnitAmount <= 0) return null;
  return (baseUnitAmount * price).round();
}

/// Vergleicht die vor dem Einkauf geschaetzte Summe mit der tatsaechlichen Bon-Summe danach (Ergaenzung
/// zu [estimateShoppingListTotal] und [[21 Feature-Ideen aus Wettbewerbsanalyse]] — vergleichbare Apps
/// zeigen die Schaetzung vor dem Einkauf neben dem echten Bon danach als Ist-Soll-Abgleich).
class EstimateVsActual {
  const EstimateVsActual({required this.estimatedCents, required this.actualCents});

  final int estimatedCents;
  final int actualCents;

  /// Positiv: teurer als geschaetzt. Negativ: guenstiger als geschaetzt.
  int get differenceCents => actualCents - estimatedCents;
}
