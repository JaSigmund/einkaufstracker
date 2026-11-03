import 'package:einkaufstracker/domain/products/product_assignment.dart';
import 'package:flutter_test/flutter_test.dart';

ProductAssignment _a({
  bool hasNutrients = true,
  bool notNeeded = false,
  bool hasCategory = true,
  bool isLoose = false,
  List<String> barcodes = const ['9001'],
  List<String> texts = const ['MILCH'],
  List<String> online = const ['Vollmilch'],
}) =>
    ProductAssignment(
      hasNutrients: hasNutrients,
      nutrientsNotNeeded: notNeeded,
      hasCategory: hasCategory,
      isLoose: isLoose,
      barcodes: barcodes,
      receiptTexts: texts,
      onlineArticles: online,
    );

void main() {
  test('alles zugeordnet: in keiner Ansicht offen', () {
    for (final v in ProductView.values) {
      expect(_a().isOpen(v), isFalse, reason: v.name);
    }
  });

  test('jede Ansicht schaut nur auf ihre eigene Zuordnung', () {
    expect(_a(hasNutrients: false).isOpen(ProductView.nutrients), isTrue);
    expect(_a(hasNutrients: false).isOpen(ProductView.barcode), isFalse);
    expect(_a(barcodes: const []).isOpen(ProductView.barcode), isTrue);
    expect(_a(texts: const []).isOpen(ProductView.receiptText), isTrue);
    expect(_a(online: const []).isOpen(ProductView.online), isTrue);
    expect(_a(hasCategory: false).isOpen(ProductView.category), isTrue);
  });

  test('"Nicht nötig" schliesst die Naehrwerte, ein Profil gewinnt', () {
    expect(_a(hasNutrients: false, notNeeded: true).nutrientsOpen, isFalse);
    expect(_a(notNeeded: true).nutrientsOpen, isFalse);
  });

  test('lose Ware vermisst keinen Barcode', () {
    expect(_a(barcodes: const [], isLoose: true).barcodeOpen, isFalse);
    expect(isLooseProduct(baseUnit: 'kg'), isTrue);
    expect(isLooseProduct(baseUnit: 'kg', packSize: 0.5), isFalse);
    expect(isLooseProduct(baseUnit: 'piece'), isFalse);
  });

  test('"Alle" zaehlt nur Naehrwerte und Kategorie: Barcode und Online sind freiwillig', () {
    expect(_a(barcodes: const [], online: const [], texts: const []).isOpen(ProductView.all), isFalse);
    expect(_a(hasNutrients: false).isOpen(ProductView.all), isTrue);
    expect(_a(hasCategory: false).isOpen(ProductView.all), isTrue);
  });

  test('Adress-Parameter: bekannt oder Alle', () {
    expect(ProductView.fromParam('nutrients'), ProductView.nutrients);
    expect(ProductView.fromParam('quatsch'), ProductView.all);
    expect(ProductView.fromParam(null), ProductView.all);
  });

  test('Einstellung liest nur ein echtes true', () {
    expect(nutrientsNotNeeded({noNutrientsPrefFor('p1'): true}, 'p1'), isTrue);
    expect(nutrientsNotNeeded({noNutrientsPrefFor('p1'): false}, 'p1'), isFalse);
    expect(nutrientsNotNeeded(const {}, 'p1'), isFalse);
    expect(noNutrientsPrefFor('00000000-0000-0000-0000-000000000000').length, lessThanOrEqualTo(64));
  });
}
