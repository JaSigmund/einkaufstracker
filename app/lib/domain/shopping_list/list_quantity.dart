/// Mengen auf der Einkaufsliste (ADR-040). Ein Eintrag speichert `quantity` und `unit`, und die Zahl meint je nach Produkt etwas anderes:
///
/// - Produkt mit Inhalt (`products.pack_size`): `quantity` zaehlt **Packungen**, der Inhalt kommt vom Produkt.
///   Die Einheit des Eintrags ist nur die Grundeinheit des Produkts, sie sagt nichts ueber die Menge.
/// - Sonst (frei getippt oder Produkt ohne Inhalt): `quantity` ist die **Menge** in `unit`.
///
/// Die fruehere Anzeige zeigte in beiden Faellen "`quantity` `unit`". So stand bei einer Packung Yakult mit 0,29 l Inhalt rechts "1 l"
/// und darunter "insgesamt 0,29 l". Dieses Modul ist die einzige Stelle, die das in Text und wieder zurueck uebersetzt.
library;

/// Einheiten, in denen man eine Menge eingeben kann. Gespeichert wird immer die Grundeinheit des Servers (`kg`, `l`, `piece`).
enum ListAmountUnit {
  piece('Stk', 'piece', 1),
  g('g', 'kg', 0.001),
  kg('kg', 'kg', 1),
  ml('ml', 'l', 0.001),
  l('l', 'l', 1);

  const ListAmountUnit(this.label, this.baseUnit, this.toBase);

  final String label;
  final String baseUnit;
  final double toBase;

  /// Was zu einer Grundeinheit passt; ohne Grundeinheit (frei getippter Eintrag) ist alles erlaubt.
  static List<ListAmountUnit> forBaseUnit(String? baseUnit) => switch (baseUnit) {
        null => ListAmountUnit.values,
        'kg' => const [g, kg],
        'l' => const [ml, l],
        _ => const [piece],
      };

  /// Die handlichste Einheit fuer einen Wert: unter 1 kg in Gramm, unter 1 l in Milliliter.
  static ListAmountUnit bestFor(double baseQuantity, String baseUnit) => switch (baseUnit) {
        'kg' => baseQuantity.abs() < 1 ? g : kg,
        'l' => baseQuantity.abs() < 1 ? ml : l,
        _ => piece,
      };
}

double _round3(double v) => (v * 1000).roundToDouble() / 1000;

/// Eine Zahl mit hoechstens einer Nachkommastelle und deutschem Komma.
String formatListNumber(double v) {
  final rounded = (v * 10).roundToDouble() / 10;
  final s = rounded == rounded.roundToDouble() ? rounded.toInt().toString() : rounded.toString();
  return s.replaceAll('.', ',');
}

/// Eine Menge in Grundeinheit als Text: 0.29 l -> "290 ml", 1.5 kg -> "1,5 kg", 3 piece -> "3 Stk".
/// Eine Zahl, wie sie in ein Eingabefeld gehoert: bis zu drei Nachkommastellen, nichts wird weggerundet ("0,065"), mit deutschem Komma.
String formatListNumberExact(double v) {
  final rounded = _round3(v);
  final s = rounded == rounded.roundToDouble() ? rounded.toInt().toString() : rounded.toString();
  return s.replaceAll('.', ',');
}

String formatListAmount(double baseQuantity, String baseUnit) {
  final unit = ListAmountUnit.bestFor(baseQuantity, baseUnit);
  return '${formatListNumber(_round3(baseQuantity) / unit.toBase)} ${unit.label}';
}

/// Was die Zeile eines Eintrags anzeigt: rechts [primary], darunter [total], wenn sich die Gesamtmenge nicht von selbst ergibt.
typedef ListQuantityText = ({String primary, String? total});

/// Der Text zu einem Eintrag. [packSize] und [productBaseUnit] kommen vom Produkt, beide `null` bei frei getippten Eintraegen.
///
/// Mehrfachpackung ([piecesPerPack], ADR-045): ganze Packungen als "2 Packungen (6 × 65 ml)", darunter die Stuecke und die Menge. Ein Teil einer
/// Packung, der aufgeht, heisst "2 Fläschchen", alles andere ist eine Menge.
ListQuantityText describeListQuantity({required double quantity, required String unit, double? packSize, String? productBaseUnit, int? piecesPerPack, String? pieceLabel}) {
  final baseUnit = productBaseUnit ?? unit;
  // Aeltere Produkte haben "0,39 Stueck" je Packung stehen, siehe Packaging.contentPerPack
  if (packSize == null || packSize <= 0 || (baseUnit == 'piece' && packSize != packSize.roundToDouble())) return (primary: formatListAmount(quantity, unit), total: null);
  final total = formatListAmount(quantity * packSize, baseUnit);
  if (baseUnit != 'piece' && piecesPerPack != null && piecesPerPack >= 2) {
    final label = pieceLabel == null || pieceLabel.trim().isEmpty ? 'Stk' : pieceLabel.trim();
    final pieces = quantity * piecesPerPack;
    final wholePieces = pieces.roundToDouble();
    final goesUp = wholePieces >= 1 && (pieces - wholePieces).abs() < 0.02;
    if (quantity == quantity.roundToDouble()) {
      final contents = '$piecesPerPack × ${formatListAmount(packSize / piecesPerPack, baseUnit)}';
      return (primary: '${quantity.toInt()} ${quantity == 1 ? 'Packung' : 'Packungen'} ($contents)', total: quantity == 1 ? total : '${wholePieces.toInt()} $label · $total');
    }
    return goesUp ? (primary: '${wholePieces.toInt()} $label', total: total) : (primary: total, total: null);
  }
  // Ein Stueck je Packung: "3 Stk" sagt alles
  if (baseUnit == 'piece' && packSize == 1) return (primary: total, total: null);
  // Ein Bruchteil einer Packung ("0,3 × 500 g") liest niemand gern, also gleich die Menge
  if (quantity != quantity.roundToDouble()) return (primary: total, total: null);
  return (primary: '${quantity.toInt()} × ${formatListAmount(packSize, baseUnit)}', total: quantity == 1 ? null : total);
}

/// Rechnet eine eingegebene Menge in das um, was der Eintrag speichert: Packungen, wenn das Produkt einen Inhalt hat, sonst die Menge in
/// Grundeinheit. `null`, wenn die Eingabe nicht positiv ist oder nach dem Runden auf drei Stellen (`numeric(10,3)`) nichts uebrig bleibt.
({double quantity, String unit})? listQuantityFromAmount(double amount, ListAmountUnit amountUnit, {double? packSize}) {
  if (!amount.isFinite || amount <= 0) return null;
  final base = amount * amountUnit.toBase;
  final quantity = _round3(packSize != null && packSize > 0 ? base / packSize : base);
  if (quantity <= 0) return null;
  return (quantity: quantity, unit: amountUnit.baseUnit);
}
