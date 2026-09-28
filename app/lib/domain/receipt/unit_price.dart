/// Grundpreis eines Bon-Artikels in Cent je Basiseinheit des Produkts (Doku 07 §3.1): macht Preise über
/// Händler und Packungsgrößen hinweg vergleichbar (€/kg, €/l, €/Stk statt Packungspreis).
///
/// - Wiegeware (Bon-Menge steht schon in der Basiseinheit, z.B. `quantityUnit == baseUnit == 'kg'`):
///   die Bon-Menge ist bereits die Menge in Basiseinheit.
/// - Stückware (`baseUnit == 'piece'`, Bon-Menge in Stück): ebenso, kein Packungsinhalt nötig.
/// - Packware mit bekanntem Inhalt (Bon-Menge in Stück, aber `baseUnit` ist kg/l): die Bon-Menge sind
///   gekaufte Packungen, `packSize` (Inhalt je Packung, siehe [[04 Datenmodell]] `products.pack_size`)
///   multipliziert die Menge auf die Basiseinheit hoch.
/// - Fehlt der Packungsinhalt in diesem Fall, ist kein Grundpreis berechenbar (`null`): die Position
///   nimmt dann am Preisvergleich nicht teil, statt einen falschen Wert zu zeigen.
int? computeUnitPriceNormCents({
  required int lineTotalCents,
  required double quantity,
  required String quantityUnit,
  required String productBaseUnit,
  double? packSize,
}) {
  final double baseUnitAmount;
  if (quantityUnit == productBaseUnit) {
    baseUnitAmount = quantity;
  } else if (quantityUnit == 'piece' && packSize != null && packSize > 0) {
    baseUnitAmount = quantity * packSize;
  } else {
    return null;
  }
  if (baseUnitAmount <= 0) return null;
  return (lineTotalCents / baseUnitAmount).round();
}
