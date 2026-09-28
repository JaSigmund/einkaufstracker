import 'package:einkaufstracker/domain/receipt/price_history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final stores = [(id: 's-billa', chain: 'Billa', branch: null), (id: 's-hofer', chain: 'Hofer', branch: null)];

  group('buildPriceHistory (Doku 07 §2 "Artikel-Detail: Preisverlauf")', () {
    test('nur Positionen des gefragten Produkts mit Grundpreis, chronologisch aufsteigend', () {
      final receipts = [
        (id: 'r1', storeId: 's-billa', purchasedAtUtc: DateTime.utc(2026, 8, 1)),
        (id: 'r2', storeId: 's-billa', purchasedAtUtc: DateTime.utc(2026, 7, 1)),
      ];
      final items = [
        (receiptId: 'r1', productId: 'p1', unitPriceNormCents: 129, quantity: 1.0, quantityUnit: 'piece'),
        (receiptId: 'r2', productId: 'p1', unitPriceNormCents: 119, quantity: 1.0, quantityUnit: 'piece'),
        (receiptId: 'r1', productId: 'p2', unitPriceNormCents: 999, quantity: 1.0, quantityUnit: 'piece'), // anderes Produkt
        (receiptId: 'r1', productId: 'p1', unitPriceNormCents: null, quantity: 1.0, quantityUnit: 'piece'), // kein Grundpreis
      ];
      final history = buildPriceHistory(productId: 'p1', items: items, receipts: receipts, stores: stores);
      expect(history.map((p) => p.unitPriceNormCents), [119, 129]); // Juli vor August
      expect(history.every((p) => p.storeChain == 'Billa'), isTrue);
    });
  });

  group('buildStoreComparison (Doku 07 §3.2)', () {
    final now = DateTime.utc(2026, 9, 28);

    test('weniger als 2 Haendler mit je 2 Kaeufen: nicht aussagekraeftig', () {
      final receipts = [
        (id: 'r1', storeId: 's-billa', purchasedAtUtc: DateTime.utc(2026, 9, 1)),
        (id: 'r2', storeId: 's-hofer', purchasedAtUtc: DateTime.utc(2026, 9, 2)),
      ];
      final items = [
        (receiptId: 'r1', productId: 'p1', unitPriceNormCents: 129, quantity: 1.0, quantityUnit: 'piece'),
        (receiptId: 'r2', productId: 'p1', unitPriceNormCents: 109, quantity: 1.0, quantityUnit: 'piece'),
      ];
      final cmp = buildStoreComparison(productId: 'p1', items: items, receipts: receipts, stores: stores, now: now);
      expect(cmp.isMeaningful, isFalse);
      expect(cmp.cheapest, isNull);
    });

    test('2 Haendler mit je mind. 2 Kaeufen: aussagekraeftig, guenstigster und Ersparnis berechnet', () {
      final receipts = [
        (id: 'r1', storeId: 's-billa', purchasedAtUtc: DateTime.utc(2026, 9, 1)),
        (id: 'r2', storeId: 's-billa', purchasedAtUtc: DateTime.utc(2026, 8, 1)),
        (id: 'r3', storeId: 's-hofer', purchasedAtUtc: DateTime.utc(2026, 9, 5)),
        (id: 'r4', storeId: 's-hofer', purchasedAtUtc: DateTime.utc(2026, 8, 5)),
      ];
      final items = [
        (receiptId: 'r1', productId: 'p1', unitPriceNormCents: 200, quantity: 1.0, quantityUnit: 'piece'),
        (receiptId: 'r2', productId: 'p1', unitPriceNormCents: 220, quantity: 1.0, quantityUnit: 'piece'),
        (receiptId: 'r3', productId: 'p1', unitPriceNormCents: 150, quantity: 1.0, quantityUnit: 'piece'),
        (receiptId: 'r4', productId: 'p1', unitPriceNormCents: 160, quantity: 1.0, quantityUnit: 'piece'),
      ];
      final cmp = buildStoreComparison(productId: 'p1', items: items, receipts: receipts, stores: stores, now: now);
      expect(cmp.isMeaningful, isTrue);
      expect(cmp.cheapest!.chain, 'Hofer');
      expect(cmp.cheapest!.avgCents, 155); // (150+160)/2
      expect(cmp.savingsPerPurchaseCents, 55); // 210 (Billa-Schnitt) - 155
    });

    test('Kaeufe aelter als 180 Tage zaehlen nicht mit', () {
      final receipts = [
        (id: 'r1', storeId: 's-billa', purchasedAtUtc: DateTime.utc(2025, 1, 1)),
        (id: 'r2', storeId: 's-billa', purchasedAtUtc: DateTime.utc(2025, 1, 2)),
      ];
      final items = [
        (receiptId: 'r1', productId: 'p1', unitPriceNormCents: 200, quantity: 1.0, quantityUnit: 'piece'),
        (receiptId: 'r2', productId: 'p1', unitPriceNormCents: 200, quantity: 1.0, quantityUnit: 'piece'),
      ];
      final cmp = buildStoreComparison(productId: 'p1', items: items, receipts: receipts, stores: stores, now: now);
      expect(cmp.stores, isEmpty);
    });
  });
}
