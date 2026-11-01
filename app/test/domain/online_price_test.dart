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

  group('cheapestOnlinePrice', () {
    LinkedOnlinePrice item(String id, {int? unit = 200, int? price = 200, String? base = 'kg', OnlinePriceFreshness f = OnlinePriceFreshness.fresh, String store = 'billa'}) =>
        LinkedOnlinePrice(store: store, externalId: id, name: 'Artikel $id', priceCents: price, baseUnit: base, unitPriceNormCents: unit, freshness: f);

    test('der niedrigste Grundpreis gewinnt, auch ueber Haendler hinweg', () {
      final best = cheapestOnlinePrice([item('a', unit: 398), item('b', unit: 249, store: 'spar'), item('c', unit: 299)], 'kg');
      expect(best?.externalId, 'b');
      expect(best?.store, 'spar');
    });

    test('bei gleichem Grundpreis gewinnt der niedrigere Preis, dann der erste', () {
      expect(cheapestOnlinePrice([item('a', unit: 300, price: 300), item('b', unit: 300, price: 150)], 'kg')?.externalId, 'b');
      expect(cheapestOnlinePrice([item('a', unit: 300), item('b', unit: 300)], 'kg')?.externalId, 'a');
    });

    test('nur vergleichbare Artikel: gleiche Basiseinheit wie das Produkt', () {
      final items = [item('a', unit: 100, base: 'l'), item('b', unit: 500, base: 'kg')];
      expect(cheapestOnlinePrice(items, 'kg')?.externalId, 'b');
      expect(cheapestOnlinePrice(items, 'l')?.externalId, 'a');
      expect(cheapestOnlinePrice(items, 'piece'), isNull);
    });

    test('ohne Grundpreis oder aus dem Sortiment verschwunden zaehlt nicht', () {
      expect(cheapestOnlinePrice([item('a', unit: null), item('b', f: OnlinePriceFreshness.discontinued, unit: 50)], 'kg'), isNull);
      expect(cheapestOnlinePrice([item('a', unit: null), item('b', unit: 400)], 'kg')?.externalId, 'b');
    });

    test('ein zuletzt bekannter Preis (alter Feed) zaehlt weiter mit', () {
      expect(cheapestOnlinePrice([item('a', unit: 100, f: OnlinePriceFreshness.stale), item('b', unit: 400)], 'kg')?.externalId, 'a');
    });

    test('leere Liste ergibt null', () {
      expect(cheapestOnlinePrice(const [], 'kg'), isNull);
    });
  });

  group('onlineArticleUpdatedAt', () {
    final feed = DateTime.utc(2026, 11, 1, 5, 2);

    test('Artikel im letzten Lauf gesehen: es gilt der Feed-Stand', () {
      expect(onlineArticleUpdatedAt(DateTime.utc(2026, 11, 1, 6), feed), feed);
    });

    test('Haendler in der Quelle ausgefallen: es gilt der letzte Lauf, der den Artikel gesehen hat', () {
      final seen = DateTime.utc(2026, 10, 29, 6);
      expect(onlineArticleUpdatedAt(seen, feed), seen);
    });

    test('ohne Feed-Stand bleibt der Stand unbekannt, ohne seen_at gilt der Feed-Stand', () {
      expect(onlineArticleUpdatedAt(DateTime.utc(2026, 11, 1, 6), null), isNull);
      expect(onlineArticleUpdatedAt(null, feed), feed);
    });

    test('seen_at wird aus der Zeile gelesen', () {
      final row = {'store': 'spar', 'external_id': '1', 'name': 'A', 'price_cents': 100, 'seen_at': '2026-10-29T06:00:03.015+00:00'};
      expect(onlineArticleFromRow(row)!.seenAt, DateTime.utc(2026, 10, 29, 6, 0, 3, 15));
      expect(onlineArticleFromRow({...row, 'seen_at': null})!.seenAt, isNull);
    });
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
