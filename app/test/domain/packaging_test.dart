import 'package:einkaufstracker/domain/products/packaging.dart';
import 'package:einkaufstracker/domain/receipt/unit_price.dart';
import 'package:einkaufstracker/domain/shopping_list/list_quantity.dart';
import 'package:flutter_test/flutter_test.dart';

/// Die Faelle des Mengenkonzepts (ADR-045). Der Anlass: eine Packung Yakult ist eine Bon-Position, aber 6 Flaeschchen zu je 65 ml.
void main() {
  const yakult = Packaging(baseUnit: 'l', rawPackSize: 0.39, rawPiecesPerPack: 6, pieceLabel: 'Fläschchen');
  const nudeln = Packaging(baseUnit: 'kg', rawPackSize: 0.5);
  const eier = Packaging(baseUnit: 'piece', rawPackSize: 10);
  const aepfel = Packaging(baseUnit: 'kg');
  const kuerbis = Packaging(baseUnit: 'piece');

  group('Arten', () {
    test('werden aus den Produktdaten erkannt', () {
      expect(PackagingKind.of(yakult), PackagingKind.multipack);
      expect(PackagingKind.of(nudeln), PackagingKind.contentPack);
      expect(PackagingKind.of(eier), PackagingKind.countPack);
      expect(PackagingKind.of(aepfel), PackagingKind.loose);
      expect(PackagingKind.of(kuerbis), PackagingKind.single);
    });

    test('Altlast: 0,39 "Stück" je Packung ist kein Inhalt, Yakult zeigt nie "0,4 Stk"', () {
      const legacy = Packaging(baseUnit: 'piece', rawPackSize: 0.39);
      expect(legacy.contentPerPack, isNull);
      expect(PackagingKind.of(legacy), PackagingKind.single);
      expect(legacy.describe(6), '6 Stk');
      expect(describeListQuantity(quantity: 1, unit: 'piece', packSize: 0.39, productBaseUnit: 'piece').primary, '1 Stk');
    });

    test('Stueck je Packung ohne Inhalt oder unter 2 zaehlen nicht als Mehrfachpackung', () {
      expect(const Packaging(baseUnit: 'l', rawPiecesPerPack: 6).isMultipack, isFalse);
      expect(const Packaging(baseUnit: 'l', rawPackSize: 0.39, rawPiecesPerPack: 1).isMultipack, isFalse);
      expect(const Packaging(baseUnit: 'piece', rawPackSize: 1).piecesPerPack, isNull);
    });
  });

  group('Mehrfachpackung', () {
    test('kennt Packung, Stueck und Menge', () {
      expect(yakult.contentPerPiece, closeTo(0.065, 1e-9));
      expect(yakult.packDescription, '6 × 65 ml');
      expect(yakult.options.map((o) => o.label), ['Packung à 6 × 65 ml', 'Fläschchen', 'ml', 'l']);
      expect(yakult.isIndividuallyPacked, isTrue);
    });

    test('Bestand nennt Stuecke und Menge, Minus nimmt ein Flaeschchen', () {
      expect(yakult.describe(0.39), '6 Fläschchen · 390 ml');
      expect(yakult.describe(0.325), '5 Fläschchen · 325 ml');
      expect(yakult.describe(0.065), '1 Fläschchen · 65 ml');
      expect(yakult.step.amount, closeTo(0.065, 1e-9));
      expect(yakult.step.label, '1 Fläschchen');
    });

    test('was nicht aufgeht, bleibt eine Menge, Rundungsreste zaehlen als ganz', () {
      expect(yakult.describe(0.1), '100 ml');
      expect(const Packaging(baseUnit: 'l', rawPackSize: 1, rawPiecesPerPack: 3).describe(0.333), '1 Stk · 333 ml');
    });

    test('ohne Namen heissen die Stuecke Stk', () {
      expect(const Packaging(baseUnit: 'kg', rawPackSize: 0.5, rawPiecesPerPack: 4).describe(0.25), '2 Stk · 250 g');
    });

    test('Einkaufsliste zaehlt Packungen', () {
      String primary(double q) => describeListQuantity(quantity: q, unit: 'l', packSize: 0.39, productBaseUnit: 'l', piecesPerPack: 6, pieceLabel: 'Fläschchen').primary;
      String? total(double q) => describeListQuantity(quantity: q, unit: 'l', packSize: 0.39, productBaseUnit: 'l', piecesPerPack: 6, pieceLabel: 'Fläschchen').total;
      expect(primary(1), '1 Packung (6 × 65 ml)');
      expect(total(1), '390 ml');
      expect(primary(2), '2 Packungen (6 × 65 ml)');
      expect(total(2), '12 Fläschchen · 780 ml');
      expect(primary(0.333), '2 Fläschchen', reason: '2 von 6, in der Datenbank gerundet');
      expect(primary(0.25), '98 ml', reason: 'anderthalb Flaeschchen gehen nicht auf');
    });
  });

  group('andere Arten', () {
    test('Packung: ganze Packungen als solche, sonst die Menge', () {
      expect(nudeln.describe(0.5), '500 g');
      expect(nudeln.describe(1.5), '3 × 500 g · 1,5 kg');
      expect(nudeln.describe(0.3), '300 g');
      expect(nudeln.step.label, '500 g');
      expect(nudeln.isIndividuallyPacked, isFalse, reason: 'angebrochen heisst geoeffnet');
    });

    test('Zaehlpackung: gezaehlt wird einzeln, eingegeben auch als Packung', () {
      expect(eier.describe(14), '14 Stk');
      expect(eier.step.amount, 1);
      expect(eier.options.map((o) => o.label), ['Packung à 10 Stk', 'Stk']);
      expect(const Packaging(baseUnit: 'piece', rawPackSize: 20, pieceLabel: 'Beutel').describe(20), '20 Beutel');
    });

    test('Lose: Minus nimmt 100 g statt eines ganzen Kilos', () {
      expect(aepfel.describe(1.2), '1,2 kg');
      expect(aepfel.step.amount, 0.1);
      expect(aepfel.step.label, '100 g');
      expect(aepfel.options.map((o) => o.label), ['g', 'kg']);
    });

    test('Einzelstueck: nur Stueck', () {
      expect(kuerbis.describe(2), '2 Stk');
      expect(kuerbis.options.single.label, 'Stk');
    });

    test('Bestand in anderer Einheit als das Produkt: die Packungsdaten gelten nicht', () {
      expect(nudeln.forStockUnit('piece').describe(2), '2 Stk');
      expect(nudeln.forStockUnit('kg').describe(1.5), '3 × 500 g · 1,5 kg');
    });
  });

  group('Vorbelegung des Dialogs', () {
    test('ganze Packungen, dann ganze Stuecke, sonst die handlichste Menge', () {
      expect(yakult.bestOption(0.78).kind, QuantityKind.pack);
      expect(yakult.bestOption(0.26).label, 'Fläschchen');
      expect(yakult.bestOption(0.1).label, 'ml');
      expect(nudeln.bestOption(0.3).label, 'g');
      expect(nudeln.bestOption(1.5).kind, QuantityKind.pack);
      expect(eier.bestOption(14).label, 'Stk');
      expect(aepfel.bestOption(1.2).label, 'kg');
      expect(aepfel.bestOption(0).label, 'g', reason: 'Bestand 0 darf nicht abstuerzen');
    });
  });

  group('Bon wird zu Bestand', () {
    test('Packungen werden zur Menge', () {
      expect(yakult.stockFromPurchase(quantity: 1, quantityUnit: 'piece', rawText: 'Yakult Drink'), (quantity: 0.39, unit: 'l'));
      expect(nudeln.stockFromPurchase(quantity: 2, quantityUnit: 'piece', rawText: 'Bandnudeln'), (quantity: 1.0, unit: 'kg'));
      expect(eier.stockFromPurchase(quantity: 1, quantityUnit: 'piece', rawText: 'Eier BH 10er'), (quantity: 10.0, unit: 'piece'));
    });

    test('der Bon-Text geht vor: dasselbe Produkt in anderer Groesse', () {
      const zwiebeln = Packaging(baseUnit: 'kg', rawPackSize: 1);
      expect(zwiebeln.stockFromPurchase(quantity: 1, quantityUnit: 'piece', rawText: 'Zwiebeln gelb 3kg'), (quantity: 3.0, unit: 'kg'));
    });

    test('Gewogenes steht schon in der Menge', () {
      expect(aepfel.stockFromPurchase(quantity: 1.234, quantityUnit: 'kg', rawText: 'Äpfel'), (quantity: 1.234, unit: 'kg'));
    });

    test('ohne bekannten Inhalt bleibt es bei den Packungen, statt eine Menge zu raten', () {
      expect(aepfel.stockFromPurchase(quantity: 2, quantityUnit: 'piece', rawText: 'Äpfel Tasse'), (quantity: 2.0, unit: 'piece'));
      expect(kuerbis.stockFromPurchase(quantity: 2, quantityUnit: 'piece', rawText: 'Kürbis'), (quantity: 2.0, unit: 'piece'));
    });
  });

  group('Bestand umrechnen', () {
    test('Stueck auf einem Mengen-Produkt: Bon-Vorschlag zaehlt Packungen, bestaetigter Bestand Stuecke', () {
      expect(yakult.stockConversionFactor('piece', isSuggestion: true), 0.39);
      expect(yakult.stockConversionFactor('piece', isSuggestion: false), closeTo(0.065, 1e-9));
      expect(nudeln.stockConversionFactor('piece', isSuggestion: false), 0.5);
    });

    test('was nicht eindeutig geht, bleibt', () {
      expect(aepfel.stockConversionFactor('piece', isSuggestion: true), isNull);
      expect(nudeln.stockConversionFactor('kg', isSuggestion: false), isNull);
      expect(nudeln.stockConversionFactor('l', isSuggestion: false), isNull);
    });
  });

  group('Text lesen', () {
    test('Mehrfachpackungen aus Bon und Open Food Facts', () {
      expect(parsePackagingFromText('6 x 65 ml'), (amount: 0.39, unit: 'l', pieces: 6));
      expect(parsePackagingFromText('Tyrolini mild 4x40g'), (amount: 0.16, unit: 'kg', pieces: 4));
      expect(parsePackagingFromText('BM GUACAMOLE 150 G'), (amount: 0.15, unit: 'kg', pieces: null));
      expect(parsePackagingFromText('Eier BH 10er'), isNull);
    });
  });

  group('Produktformular', () {
    ResolvedPackaging resolve(PackagingKind kind, {String count = '', String amount = '', QuantityOption unit = QuantityOption.g, String label = '', String loose = 'kg'}) =>
        resolvePackaging(kind: kind, looseUnit: loose, count: count, amount: amount, amountUnit: unit, label: label);

    test('Mehrfachpackung: 6 × 65 ml', () {
      final r = resolve(PackagingKind.multipack, count: '6', amount: '65', unit: QuantityOption.ml, label: ' Fläschchen ');
      expect(r.error, isNull);
      expect(r.baseUnit, 'l');
      expect(r.packSize, 0.39);
      expect(r.piecesPerPack, 6);
      expect(r.pieceLabel, 'Fläschchen');
      expect(r.pieceWeightG, closeTo(65, 1e-9));
    });

    test('Packung nimmt die Einheit der Eingabe, Komma geht', () {
      final r = resolve(PackagingKind.contentPack, amount: '1,5', unit: QuantityOption.kg);
      expect((r.baseUnit, r.packSize), ('kg', 1.5));
    });

    test('Reste einer anderen Art zaehlen nicht', () {
      final single = resolve(PackagingKind.single, count: '6', amount: '65');
      expect((single.baseUnit, single.packSize, single.piecesPerPack), ('piece', null, null));
      final loose = resolve(PackagingKind.loose, count: '6', amount: '65', loose: 'l');
      expect((loose.baseUnit, loose.packSize, loose.pieceLabel), ('l', null, null));
    });

    test('Fehlendes und Unsinn werden abgelehnt', () {
      expect(resolve(PackagingKind.multipack, amount: '65').error, isNotNull);
      expect(resolve(PackagingKind.multipack, count: '1', amount: '65').error, isNotNull);
      expect(resolve(PackagingKind.multipack, count: '2,5', amount: '65').error, isNotNull);
      expect(resolve(PackagingKind.multipack, count: '6').error, isNotNull);
      expect(resolve(PackagingKind.contentPack, amount: '0').error, isNotNull);
      expect(resolve(PackagingKind.contentPack, amount: '-5').error, isNotNull);
      expect(resolve(PackagingKind.contentPack, amount: 'abc').error, isNotNull);
      expect(resolve(PackagingKind.contentPack, amount: '0,1').error, isNotNull, reason: '0,1 g waere in kg gerundet 0');
      expect(resolve(PackagingKind.countPack, count: '0').error, isNotNull);
      expect(resolve(PackagingKind.countPack, count: '10', label: 'x' * 31).error, isNotNull);
    });
  });

  group('Eingabe lesen', () {
    test('Komma, Punkt und Leerzeichen, sonst nichts', () {
      expect(parseQuantityInput(' 1,5 '), 1.5);
      expect(parseQuantityInput('2.5'), 2.5);
      for (final bad in ['', 'x', '1,2,3', 'NaN', 'Infinity']) {
        expect(parseQuantityInput(bad), isNull, reason: bad);
      }
    });

    test('Eingabefeld zeigt drei Stellen, ohne Reste', () {
      expect(formatListNumberExact(0.065), '0,065');
      expect(formatListNumberExact(0.1 + 0.2), '0,3');
      expect(formatListNumberExact(6), '6');
    });
  });
}
