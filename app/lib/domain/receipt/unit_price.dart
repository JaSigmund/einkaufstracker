/// Grundpreis eines Bon-Artikels in Cent je Basiseinheit des Produkts (Doku 07 §3.1): macht Preise über
/// Händler und Packungsgrößen hinweg vergleichbar (€/kg, €/l, €/Stk statt Packungspreis).
///
/// - Wiegeware (Bon-Menge steht schon in der Basiseinheit, z.B. `quantityUnit == baseUnit == 'kg'`):
///   die Bon-Menge ist bereits die Menge in Basiseinheit.
/// - Packware mit bekanntem Inhalt (Bon-Menge in Stück = Anzahl gekaufter Packungen): `packSize`
///   (Inhalt je Packung, siehe [[04 Datenmodell]] `products.pack_size`) multipliziert die Menge auf die
///   Basiseinheit hoch. Das gilt **auch wenn die Basiseinheit selbst 'piece' ist** (Fehlerbericht "Preis
///   wird nicht auf Einheit heruntergerechnet", 2026-09-28): eine 4er-Packung Paprika Tricolore hat
///   `baseUnit: 'piece'` (Grundpreis je einzelner Paprika) und `packSize: 4`, die Bon-Menge zählt aber
///   gekaufte Packungen, nicht einzelne Paprika.
/// - Stückware ohne Packungsinhalt (Bon-Menge in Stück = Basiseinheit direkt, z.B. einzeln gezählte
///   Artikel): kein Packungsinhalt nötig, die Bon-Menge ist bereits die Menge in Basiseinheit.
/// - Fehlt der Packungsinhalt bei abweichender Einheit, ist kein Grundpreis berechenbar (`null`): die
///   Position nimmt dann am Preisvergleich nicht teil, statt einen falschen Wert zu zeigen.
///
/// Der Inhalt je Packung kommt zuerst aus dem Bon-Text [rawText], siehe [parsePackSizeFromReceiptText]: ein
/// Produkt kann in mehreren Packungsgrößen gekauft werden (Zwiebeln 1 kg und 3 kg), `packSize` kennt aber
/// nur eine davon. Passt die Einheit im Text nicht zur Basiseinheit des Produkts, gilt `packSize`.
int? computeUnitPriceNormCents({
  required int lineTotalCents,
  required double quantity,
  required String quantityUnit,
  required String productBaseUnit,
  double? packSize,
  String? rawText,
}) {
  final fromText = rawText == null ? null : parsePackSizeFromReceiptText(rawText);
  final contentPerPack = fromText != null && fromText.unit == productBaseUnit ? fromText.amount : packSize;
  final double baseUnitAmount;
  if (quantityUnit == 'piece' && contentPerPack != null && contentPerPack > 0) {
    baseUnitAmount = quantity * contentPerPack;
  } else if (quantityUnit == productBaseUnit) {
    baseUnitAmount = quantity;
  } else {
    return null;
  }
  if (baseUnitAmount <= 0) return null;
  return (lineTotalCents / baseUnitAmount).round();
}

/// Packungsinhalt aus einem Bon-Text, umgerechnet auf die Einheit `kg` bzw. `l`.
typedef ReceiptPackSize = ({double amount, String unit});

/// Faktor auf `kg` bzw. `l` je Schreibweise im Bon-Text.
const _packUnits = <String, ReceiptPackSize>{
  'kg': (amount: 1, unit: 'kg'),
  'dkg': (amount: 0.01, unit: 'kg'),
  'dag': (amount: 0.01, unit: 'kg'),
  'g': (amount: 0.001, unit: 'kg'),
  'gr': (amount: 0.001, unit: 'kg'),
  'l': (amount: 1, unit: 'l'),
  'ltr': (amount: 1, unit: 'l'),
  'cl': (amount: 0.01, unit: 'l'),
  'ml': (amount: 0.001, unit: 'l'),
};

/// Optional `4x`, dann Zahl und Einheit. Davor darf kein Buchstabe und keine Ziffer stehen, aber ein Punkt
/// ("CV FASCHIERTES GEM.500G"); danach kein Buchstabe und keine Ziffer ("3.Wahl", "1 Liebe").
final _packSizePattern = RegExp(
  r'(?<![\p{L}\d])(?:(\d+)\s*[x×*]\s*)?(\d+(?:[.,]\d+)?)\s*(kg|dkg|dag|gr|g|ltr|ml|cl|l)(?![\p{L}\d])',
  caseSensitive: false,
  unicode: true,
);

/// Liest den Packungsinhalt aus dem Bon-Text: "Zwiebeln gelb 3kg", "BM GUACAMOLE 150 G", "Tyrolini mild 4x40g".
/// `null` ohne Mengenangabe oder wenn mehrere verschiedene im Text stehen, weil dann unklar ist, welche gilt.
/// Stückzahlen ("Eier BH 10er") liest die Funktion bewusst nicht: ohne `packSize` zählt der Grundpreis solcher
/// Produkte Packungen, ein Wert aus dem Text würde den Preisverlauf sprunghaft ändern.
ReceiptPackSize? parsePackSizeFromReceiptText(String rawText) {
  ReceiptPackSize? found;
  for (final m in _packSizePattern.allMatches(rawText)) {
    final count = m.group(1) == null ? 1 : int.parse(m.group(1)!);
    final number = double.parse(m.group(2)!.replaceAll(',', '.'));
    final unit = _packUnits[m.group(3)!.toLowerCase()]!;
    final size = (amount: count * number * unit.amount, unit: unit.unit);
    if (found != null && (found.unit != size.unit || (found.amount - size.amount).abs() > 1e-9)) return null;
    found = size;
  }
  return found != null && found.amount > 0 ? found : null;
}

/// Wie [parsePackSizeFromReceiptText], dazu die Stueckzahl einer Mehrfachpackung: "6 x 65 ml" ergibt 0,39 l in 6 Stuecken.
({double amount, String unit, int? pieces})? parsePackagingFromText(String text) {
  final size = parsePackSizeFromReceiptText(text);
  if (size == null) return null;
  final count = int.tryParse(_packSizePattern.firstMatch(text)?.group(1) ?? '');
  return (amount: (size.amount * 1000).roundToDouble() / 1000, unit: size.unit, pieces: count != null && count >= 2 ? count : null);
}
