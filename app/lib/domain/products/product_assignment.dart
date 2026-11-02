/// Was einem Produkt zugeordnet ist (Doku 27, ADR-050). Die Produktliste zeigt je Ansicht eine dieser Zuordnungen und was daran offen ist.
enum ProductView {
  all('Alle'),
  nutrients('Nährwerte'),
  barcode('Barcode'),
  receiptText('Bon-Text'),
  online('Online'),
  category('Kategorie'),
  duplicates('Duplikate');

  const ProductView(this.label);
  final String label;

  /// Aus dem Adress-Parameter `view`, unbekannt heisst [all].
  static ProductView fromParam(String? param) => values.firstWhere((v) => v.name == param, orElse: () => all);
}

/// Schluessel der gemeinsamen Einstellung "dieses Produkt braucht keine Naehrwerte" (Muellbeutel, CO2-Zylinder). Je Produkt eine
/// Zeile wie bei den Erinnerungsstufen, damit zwei Geraete sich nicht gegenseitig ueberschreiben.
String noNutrientsPrefFor(String productId) => 'no_nutrients:$productId';

bool nutrientsNotNeeded(Map<String, Object?> prefs, String productId) => prefs[noNutrientsPrefFor(productId)] == true;

class ProductAssignment {
  const ProductAssignment({
    required this.hasNutrients,
    required this.nutrientsNotNeeded,
    required this.hasCategory,
    required this.isLoose,
    this.barcodes = const [],
    this.receiptTexts = const [],
    this.onlineArticles = const [],
  });

  final bool hasNutrients;

  /// Nur wirksam, solange das Produkt kein Profil hat.
  final bool nutrientsNotNeeded;
  final bool hasCategory;

  /// Lose Ware (Bananen, Kaese am Stueck) hat keinen Strichcode, ein fehlender Barcode ist dort nichts Offenes.
  final bool isLoose;
  final List<String> barcodes;
  final List<String> receiptTexts;
  final List<String> onlineArticles;

  bool get nutrientsOpen => !hasNutrients && !nutrientsNotNeeded;
  bool get categoryOpen => !hasCategory;
  bool get barcodeOpen => barcodes.isEmpty && !isLoose;
  bool get receiptTextOpen => receiptTexts.isEmpty;
  bool get onlineOpen => onlineArticles.isEmpty;

  /// Barcode, Bon-Text und Online-Artikel sind freiwillig: "Alle" zaehlt nur, was fuer Tagebuch und Auswertung wirklich fehlt.
  bool isOpen(ProductView view) => switch (view) {
        ProductView.all => nutrientsOpen || categoryOpen,
        ProductView.nutrients => nutrientsOpen,
        ProductView.barcode => barcodeOpen,
        ProductView.receiptText => receiptTextOpen,
        ProductView.online => onlineOpen,
        ProductView.category => categoryOpen,
        ProductView.duplicates => false,
      };
}

/// Lose Ware: in kg oder l gezaehlt und ohne feste Packungsgroesse.
bool isLooseProduct({required String baseUnit, double? packSize}) => baseUnit != 'piece' && packSize == null;
