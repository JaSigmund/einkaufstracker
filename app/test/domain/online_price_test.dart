import 'package:einkaufstracker/domain/online_prices/online_price.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('onlineArticleFromRow', () {
    Map<String, dynamic> row({Object? quantity = 1, Object? base = 'l', Object? unitPrice = 132}) => {
          'store': 'billa',
          'external_id': '00-1',
          'name': 'Clever Vollmilch',
          'price_cents': 132,
          'quantity': quantity,
          'unit': 'l',
          'base_unit': base,
          'unit_price_norm_cents': unitPrice,
        };

    test('liest eine vollstaendige Zeile', () {
      final a = onlineArticleFromRow(row())!;
      expect(a.store, 'billa');
      expect(a.externalId, '00-1');
      expect(a.priceCents, 132);
      expect(a.quantity, 1.0);
      expect(a.baseUnit, 'l');
      expect(a.unitPriceNormCents, 132);
    });

    test('numeric kommt je nach Server als Zahl oder als Text', () {
      expect(onlineArticleFromRow(row(quantity: '1.500'))!.quantity, 1.5);
      expect(onlineArticleFromRow(row(quantity: '1,5'))!.quantity, 1.5);
      expect(onlineArticleFromRow(row(quantity: null))!.quantity, isNull);
    });

    test('unbekannte Basiseinheit und fehlender Grundpreis bleiben null statt zu raten', () {
      final a = onlineArticleFromRow(row(base: 'wg', unitPrice: null))!;
      expect(a.baseUnit, isNull);
      expect(a.unitPriceNormCents, isNull);
      expect(onlineArticleFromRow(row(base: null))!.baseUnit, isNull);
    });

    test('Zeile ohne Pflichtfelder ergibt null', () {
      expect(onlineArticleFromRow({'store': 'billa'}), isNull);
      expect(onlineArticleFromRow({...row(), 'price_cents': 'teuer'}), isNull);
      expect(onlineArticleFromRow({...row(), 'name': null}), isNull);
    });
  });

  test('Basiseinheit des Produkts in der Schreibweise des Feeds', () {
    expect(onlineBaseUnitOf('piece'), 'stk');
    expect(onlineBaseUnitOf('kg'), 'kg');
    expect(onlineBaseUnitOf('l'), 'l');
  });

  test('Grundpreise sind nur bei gleicher Basiseinheit vergleichbar', () {
    expect(onlineUnitsComparable('l', 'l'), isTrue);
    expect(onlineUnitsComparable('piece', 'stk'), isTrue);
    expect(onlineUnitsComparable('kg', 'l'), isFalse);
    expect(onlineUnitsComparable('kg', null), isFalse);
  });

  test('Menge und Einheit fuer die Anzeige', () {
    expect(formatOnlineQuantity(500, 'g'), '500 g');
    expect(formatOnlineQuantity(1.5, 'l'), '1,5 l');
    expect(formatOnlineQuantity(6, 'stk'), '6 Stk');
    expect(formatOnlineQuantity(6, 'Stück'), '6 Stk');
    expect(formatOnlineQuantity(19, 'wg'), '19 wg');
    expect(formatOnlineQuantity(3, null), '3');
    expect(formatOnlineQuantity(null, 'g'), '');
    expect(formatOnlineQuantity(0, 'g'), '');
  });

  test('Haendlernamen', () {
    expect(onlineStoreLabel('billa'), 'Billa');
    expect(onlineStoreLabel('spar'), 'Spar');
    expect(onlineStoreLabel('hofer'), 'hofer', reason: 'unbekannte Haendler erscheinen unveraendert');
    expect(onlineStores.keys, ['billa', 'spar']);
  });

  group('onlinePriceFreshness', () {
    final now = DateTime.utc(2026, 10, 10, 12);

    test('Feed hoechstens 7 Tage alt und verfuegbar: aktuell', () {
      expect(onlinePriceFreshness(available: true, feedUpdatedAt: DateTime.utc(2026, 10, 10, 5), now: now), OnlinePriceFreshness.fresh);
      expect(onlinePriceFreshness(available: true, feedUpdatedAt: now.subtract(onlinePriceStaleAfter), now: now), OnlinePriceFreshness.fresh,
          reason: 'genau 7 Tage zaehlt noch als aktuell');
    });

    test('Feed aelter als 7 Tage: zuletzt bekannt', () {
      final old = now.subtract(onlinePriceStaleAfter + const Duration(minutes: 1));
      expect(onlinePriceFreshness(available: true, feedUpdatedAt: old, now: now), OnlinePriceFreshness.stale);
    });

    test('Stand unbekannt gilt nicht als aktuell', () {
      expect(onlinePriceFreshness(available: true, feedUpdatedAt: null, now: now), OnlinePriceFreshness.stale);
    });

    test('aus dem Sortiment verschwunden hat Vorrang, auch bei frischem Feed', () {
      expect(onlinePriceFreshness(available: false, feedUpdatedAt: now, now: now), OnlinePriceFreshness.discontinued);
      expect(onlinePriceFreshness(available: false, feedUpdatedAt: null, now: now), OnlinePriceFreshness.discontinued);
    });
  });
}
