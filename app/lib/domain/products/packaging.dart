import '../receipt/unit_price.dart';
import '../shopping_list/list_quantity.dart';

/// Mengenkonzept der App (ADR-045). Es gibt drei Ebenen, und jede beantwortet eine andere Frage:
///
/// - **Packung:** was auf dem Bon steht und auf die Einkaufsliste kommt.
/// - **Stueck:** was man einzeln entnimmt, das Flaeschchen aus dem Sechserpack.
/// - **Menge** in kg, l oder Stueck: worin Bestand, Ledger, Grundpreis und Naehrwerte rechnen, immer die Grundeinheit des Produkts.
///
/// Gespeichert wird im Bestand nur die Menge. Packung und Stueck sind Umrechnungen aus den Produktdaten, damit sich der Bestand nicht aendert,
/// wenn jemand den Inhalt einer Packung korrigiert. Das ergibt fuenf Arten von Produkten:
///
/// | Art             | Beispiel        | base_unit | pack_size | pieces_per_pack |
/// | Lose, gewogen   | Aepfel          | kg        | -         | -               |
/// | Einzelstueck    | Kuerbis         | piece     | -         | -               |
/// | Zaehlpackung    | 10 Eier         | piece     | 10        | -               |
/// | Packung         | 500 g Nudeln    | kg        | 0,5       | -               |
/// | Mehrfachpackung | 6 × 65 ml Yakult| l         | 0,39      | 6               |
class Packaging {
  const Packaging({required this.baseUnit, this.rawPackSize, this.rawPiecesPerPack, this.pieceLabel});

  /// 'kg' | 'l' | 'piece'
  final String baseUnit;

  /// Die Produktdaten, wie sie gespeichert sind. Gelesen wird ueber [contentPerPack] und [piecesPerPack], die Unsinn aussortieren.
  final double? rawPackSize;
  final int? rawPiecesPerPack;
  final String? pieceLabel;

  /// Inhalt einer Packung in [baseUnit], `null` wenn unbekannt. Bei `piece` nur ganze Zahlen: aeltere Eintraege haben dort "0,39" fuer 390 ml
  /// stehen, das waeren 0,39 Stueck und wird nicht geglaubt.
  double? get contentPerPack {
    final size = rawPackSize;
    if (size == null || size <= 0) return null;
    if (baseUnit == 'piece' && size != size.roundToDouble()) return null;
    return size;
  }

  /// Stueck je Packung, `null` wenn sich die Packung nicht in zaehlbare Stuecke teilt.
  int? get piecesPerPack {
    final content = contentPerPack;
    if (content == null) return null;
    if (baseUnit == 'piece') return content > 1 ? content.round() : null;
    final pieces = rawPiecesPerPack;
    return pieces != null && pieces >= 2 ? pieces : null;
  }

  /// Menge eines Stuecks in [baseUnit], `null` wenn es keine Stuecke gibt. Bei `piece` immer 1.
  double? get contentPerPiece {
    if (baseUnit == 'piece') return 1;
    final pieces = piecesPerPack;
    return pieces == null ? null : contentPerPack! / pieces;
  }

  /// Name der Stuecke in der Mehrzahl, ohne Angabe "Stk".
  String get pieceName {
    final label = pieceLabel?.trim();
    return label == null || label.isEmpty ? 'Stk' : label;
  }

  /// Mehrfachpackung: der Bestand steht in kg oder l, gezaehlt wird in Stueck.
  bool get isMultipack => baseUnit != 'piece' && piecesPerPack != null;

  /// Einzeln verpackt: ein entnommenes Stueck oeffnet den Rest nicht, die Haltbarkeit bleibt.
  bool get isIndividuallyPacked => baseUnit == 'piece' || isMultipack;

  /// Was man hier eingeben kann, das Naheliegende zuerst. Mehr als das Produkt hergibt, wird nicht angeboten.
  List<QuantityOption> get options {
    final content = contentPerPack;
    final piece = contentPerPiece;
    return [
      if (content != null && !(baseUnit == 'piece' && content == 1)) QuantityOption.pack(packDescription!, content, baseUnit),
      if (isMultipack) QuantityOption.piece(pieceName, piece!, baseUnit),
      ...switch (baseUnit) {
        'kg' => const [QuantityOption.g, QuantityOption.kg],
        'l' => const [QuantityOption.ml, QuantityOption.l],
        _ => [QuantityOption.piece(pieceName, 1, 'piece')],
      },
    ];
  }

  /// Der Inhalt einer Packung als Text: "6 × 65 ml", "500 g", "10 Stk"; `null` wenn unbekannt.
  String? get packDescription {
    final content = contentPerPack;
    if (content == null) return null;
    if (baseUnit == 'piece') return '${content.round()} $pieceName';
    if (isMultipack) return '${piecesPerPack!} × ${formatListAmount(contentPerPiece!, baseUnit)}';
    return formatListAmount(content, baseUnit);
  }

  /// Wie viele ganze Stuecke [amount] sind, `null` wenn es keine ganze Zahl ist. Drei Nachkommastellen in der Datenbank machen aus einem
  /// Drittel Packung Rundungsreste, die niemand sehen soll.
  int? wholePieces(double amount) {
    final piece = contentPerPiece;
    if (piece == null || piece <= 0) return null;
    final count = amount / piece;
    final rounded = count.roundToDouble();
    return rounded >= 1 && (count - rounded).abs() < 0.02 ? rounded.toInt() : null;
  }

  /// Ein Bestand als Text: "4 Fläschchen · 260 ml", "3 × 500 g · 1,5 kg", "300 g", "14 Stk".
  String describe(double amount) {
    if (isMultipack) {
      final pieces = wholePieces(amount);
      final total = formatListAmount(amount, baseUnit);
      return pieces == null ? total : '$pieces $pieceName · $total';
    }
    if (baseUnit == 'piece') {
      return '${formatListNumber(amount)} $pieceName';
    }
    final content = contentPerPack;
    if (content != null) {
      final packs = amount / content;
      final rounded = packs.roundToDouble();
      if (rounded >= 2 && (packs - rounded).abs() < 0.001) return '${rounded.toInt()} × ${formatListAmount(content, baseUnit)} · ${formatListAmount(amount, baseUnit)}';
    }
    return formatListAmount(amount, baseUnit);
  }

  /// Was ein Tipp auf Plus oder Minus bewegt: ein Stueck, eine Packung, sonst 100 g oder 100 ml statt eines ganzen Kilos.
  QuantityStep get step {
    final piece = contentPerPiece;
    if (piece != null) return (amount: piece, label: '1 $pieceName');
    final content = contentPerPack;
    if (content != null) return (amount: content, label: formatListAmount(content, baseUnit));
    return (amount: 0.1, label: formatListAmount(0.1, baseUnit));
  }

  /// Die Eingabe, in der [amount] am natuerlichsten aussieht: ganze Packungen, ganze Stuecke, sonst die handlichste Menge.
  QuantityOption bestOption(double amount) {
    final all = options;
    if (amount > 0) {
      for (final o in all) {
        final count = amount / o.toBase;
        final whole = (count - count.roundToDouble()).abs() < 0.02 && count.round() >= 1;
        if (whole && (o.kind == QuantityKind.pack || o.kind == QuantityKind.piece)) return o;
      }
    }
    final best = ListAmountUnit.bestFor(amount, baseUnit);
    return all.firstWhere((o) => o.label == best.label, orElse: () => all.last);
  }

  /// Was ein gekaufter Bon-Artikel im Bestand bedeutet. Eine Bon-Menge in Stueck zaehlt Packungen und wird zur Menge in Grundeinheit, der
  /// Inhalt aus dem Bon-Text geht vor (ein Produkt gibt es in mehreren Groessen). Ohne bekannten Inhalt bleibt es bei den Packungen als Stueck:
  /// das ist ehrlicher als eine geratene Menge, und [stockConversionFactor] holt es nach, sobald der Inhalt bekannt ist.
  ({double quantity, String unit}) stockFromPurchase({required double quantity, required String quantityUnit, required String rawText}) {
    if (quantityUnit != 'piece') return (quantity: quantity, unit: quantityUnit);
    final fromText = parsePackSizeFromReceiptText(rawText);
    final content = fromText != null && fromText.unit == baseUnit ? fromText.amount : contentPerPack;
    if (content == null) return (quantity: quantity, unit: 'piece');
    return (quantity: roundQuantity(quantity * content), unit: baseUnit);
  }

  /// Faktor, mit dem ein Bestand in [itemUnit] zur Grundeinheit wird, `null` wenn das nicht eindeutig geht. Stueck auf einem Produkt in kg oder
  /// l sind bei einem Bon-Vorschlag Packungen (der Bon zaehlt Packungen), sonst Stuecke, soweit es welche gibt.
  double? stockConversionFactor(String itemUnit, {required bool isSuggestion}) {
    if (itemUnit == baseUnit || itemUnit != 'piece') return null;
    if (!isSuggestion && isMultipack) return contentPerPiece;
    return contentPerPack;
  }

  /// Fuer einen Bestand, dessen Einheit nicht zum Produkt passt, gelten die Packungsdaten des Produkts nicht.
  Packaging forStockUnit(String itemUnit) => itemUnit == baseUnit ? this : Packaging(baseUnit: itemUnit);
}

/// Die fuenf Arten aus [Packaging], wie sie das Produktformular anbietet.
enum PackagingKind {
  single('Einzelstück', 'z. B. ein Kürbis'),
  loose('Lose oder gewogen', 'z. B. Äpfel nach Gewicht'),
  contentPack('Packung', 'z. B. 500 g Nudeln, 1 l Milch'),
  countPack('Packung mit Stückzahl', 'z. B. 10 Eier, 20 Teebeutel'),
  multipack('Mehrfachpackung', 'z. B. 6 × 65 ml Yakult, 4 × 125 g Joghurt');

  const PackagingKind(this.label, this.example);
  final String label;
  final String example;

  static PackagingKind of(Packaging p) {
    if (p.isMultipack) return multipack;
    if (p.baseUnit == 'piece') return p.piecesPerPack != null ? countPack : single;
    return p.contentPerPack != null ? contentPack : loose;
  }
}

/// Was das Produktformular speichert, oder was daran noch fehlt.
typedef ResolvedPackaging = ({String baseUnit, double? packSize, int? piecesPerPack, String? pieceLabel, double? pieceWeightG, String? error});

/// Uebersetzt die Eingaben des Formulars in die Produktdaten. [count] und [amount] sind die getippten Texte; welche gelten, haengt von [kind] ab,
/// damit Reste einer vorher gewaehlten Art nichts anrichten. Eine Mehrfachpackung bekommt ihr Stueckgewicht gleich mit, dann versteht auch das
/// Tagebuch "1 Fläschchen" (Milliliter gelten dort als Gramm, Doku 15 §5.3).
ResolvedPackaging resolvePackaging({required PackagingKind kind, required String looseUnit, required String count, required String amount, required QuantityOption amountUnit, required String label}) {
  ResolvedPackaging failed(String error) => (baseUnit: looseUnit, packSize: null, piecesPerPack: null, pieceLabel: null, pieceWeightG: null, error: error);
  final name = label.trim().isEmpty ? null : label.trim();
  if (name != null && name.length > 30) return failed('Der Name der Stücke ist zu lang');
  final pieces = int.tryParse(count.trim());
  final size = parseQuantityInput(amount);
  final content = size == null || size <= 0 ? null : size * amountUnit.toBase;
  switch (kind) {
    case PackagingKind.single:
      return (baseUnit: 'piece', packSize: null, piecesPerPack: null, pieceLabel: name, pieceWeightG: null, error: null);
    case PackagingKind.loose:
      return (baseUnit: looseUnit, packSize: null, piecesPerPack: null, pieceLabel: null, pieceWeightG: null, error: null);
    case PackagingKind.contentPack:
      if (content == null || roundQuantity(content) <= 0) return failed('Bitte den Inhalt der Packung angeben');
      return (baseUnit: amountUnit.baseUnit, packSize: roundQuantity(content), piecesPerPack: null, pieceLabel: null, pieceWeightG: null, error: null);
    case PackagingKind.countPack:
      if (pieces == null || pieces < 2) return failed('Bitte angeben, wie viele Stück in einer Packung sind (mindestens 2)');
      return (baseUnit: 'piece', packSize: pieces.toDouble(), piecesPerPack: null, pieceLabel: name, pieceWeightG: null, error: null);
    case PackagingKind.multipack:
      if (pieces == null || pieces < 2) return failed('Bitte angeben, wie viele Stück in einer Packung sind (mindestens 2)');
      if (content == null || roundQuantity(content) <= 0) return failed('Bitte den Inhalt eines Stücks angeben');
      return (baseUnit: amountUnit.baseUnit, packSize: roundQuantity(content * pieces), piecesPerPack: pieces, pieceLabel: name, pieceWeightG: content * 1000, error: null);
  }
}

/// Schritt der Plus- und Minus-Knoepfe.
typedef QuantityStep = ({double amount, String label});

enum QuantityKind { pack, piece, amount }

/// Eine Einheit, in der man eine Menge eingeben kann, und wie viel davon eine Einheit in Grundeinheit ist.
class QuantityOption {
  const QuantityOption(this.kind, this.label, this.toBase, this.baseUnit);

  const QuantityOption.piece(String name, double content, String base) : this(QuantityKind.piece, name, content, base);

  factory QuantityOption.pack(String description, double content, String base) => QuantityOption(QuantityKind.pack, 'Packung à $description', content, base);

  static const g = QuantityOption(QuantityKind.amount, 'g', 0.001, 'kg');
  static const kg = QuantityOption(QuantityKind.amount, 'kg', 1, 'kg');
  static const ml = QuantityOption(QuantityKind.amount, 'ml', 0.001, 'l');
  static const l = QuantityOption(QuantityKind.amount, 'l', 1, 'l');
  static const stk = QuantityOption(QuantityKind.amount, 'Stk', 1, 'piece');

  /// Alles, was ohne Produkt moeglich ist (frei getippter Eintrag).
  static const free = [stk, g, kg, ml, l];

  final QuantityKind kind;
  final String label;
  final double toBase;
  final String baseUnit;

  // Als Wert vergleichen: [Packaging.options] baut die Liste bei jedem Aufruf neu, ein Dropdown muss die Auswahl darin wiederfinden.
  @override
  bool operator ==(Object other) => other is QuantityOption && other.kind == kind && other.label == label && other.toBase == toBase && other.baseUnit == baseUnit;

  @override
  int get hashCode => Object.hash(kind, label, toBase, baseUnit);
}

/// Liest eine Zahl mit Komma oder Punkt, `null` bei allem anderen (auch NaN und Unendlich).
double? parseQuantityInput(String text) {
  final v = double.tryParse(text.replaceAll(',', '.').trim());
  return v == null || !v.isFinite ? null : v;
}

/// Auf die drei Stellen der Datenbank (`numeric(10,3)`).
double roundQuantity(double v) => (v * 1000).roundToDouble() / 1000;
