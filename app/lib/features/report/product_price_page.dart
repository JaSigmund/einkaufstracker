import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../domain/receipt/price_history.dart';
import 'online_price_section.dart';

const _baseUnitLabels = {'piece': 'Stk', 'kg': 'kg', 'l': 'l'};

String priceBaseUnitLabel(String baseUnit) => _baseUnitLabels[baseUnit] ?? baseUnit;

/// Artikel-Detail (Doku 07 §2): Preisverlauf und Haendlervergleich eines einzelnen Produkts, auf Basis
/// des am jeweiligen Bon-Artikel berechneten Grundpreises (Doku 07 §3.1).
class ProductPricePage extends ConsumerWidget {
  const ProductPricePage({super.key, required this.product, this.now});

  final Product product;

  /// Stichtag fuer das 180-Tage-Fenster des Haendlervergleichs; ohne Angabe die App-Uhr. Fuer Tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(allItemsStreamProvider).value ?? const <ReceiptItem>[];
    final receipts = ref.watch(receiptsStreamProvider).value ?? const <Receipt>[];
    final stores = ref.watch(storesStreamProvider).value ?? const <Store>[];
    final t = Theme.of(context);
    final unitLabel = priceBaseUnitLabel(product.baseUnit);

    final historyItems = [
      for (final i in items) (receiptId: i.receiptId, productId: i.productId, unitPriceNormCents: i.unitPriceNormCents, quantity: i.quantity, quantityUnit: i.quantityUnit),
    ];
    final historyReceipts = [for (final r in receipts) (id: r.id, storeId: r.storeId, purchasedAtUtc: r.purchasedAt)];
    final historyStores = [for (final s in stores) (id: s.id, chain: s.chain, branch: s.branch)];

    final history = buildPriceHistory(productId: product.id, items: historyItems, receipts: historyReceipts, stores: historyStores).reversed.toList();
    final comparison = buildStoreComparison(productId: product.id, items: historyItems, receipts: historyReceipts, stores: historyStores, now: now);

    return Scaffold(
      appBar: AppBar(title: Text(product.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Händlervergleich', style: t.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (comparison.stores.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Noch keine Käufe mit Grundpreis in den letzten 180 Tagen'))
          else if (!comparison.isMeaningful)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Zu wenig Daten für einen Vergleich (mindestens 2 Käufe je Händler in den letzten 180 Tagen nötig)',
                key: const Key('comparison-insufficient'),
                style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
              ),
            )
          else
            Card(
              key: const Key('comparison-card'),
              child: Column(children: [
                for (final s in comparison.stores)
                  ListTile(
                    dense: true,
                    leading: s.chain == comparison.cheapest?.chain ? Icon(Icons.star, color: t.colorScheme.primary) : const SizedBox(width: 24),
                    title: Text(s.chain),
                    subtitle: Text('${s.purchaseCount}× gekauft · ${formatEuro(s.minCents!)}–${formatEuro(s.maxCents!)}/$unitLabel'),
                    trailing: Text('⌀ ${formatEuro(s.avgCents)}/$unitLabel', style: t.textTheme.titleSmall),
                  ),
                if (comparison.savingsPerPurchaseCents != null && comparison.savingsPerPurchaseCents! > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      '${comparison.cheapest!.chain} spart ${formatEuro(comparison.savingsPerPurchaseCents!)}/$unitLabel gegenüber dem teuersten Händler',
                      style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.primary),
                    ),
                  ),
              ]),
            ),
          const SizedBox(height: 24),
          OnlinePriceSection(product: product),
          const SizedBox(height: 24),
          Text('Preisverlauf', style: t.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (history.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Noch kein Grundpreis berechenbar'))
          else
            for (final p in history)
              ListTile(
                key: Key('price-point-${p.purchasedAtUtc.toIso8601String()}'),
                dense: true,
                title: Text('${formatEuro(p.unitPriceNormCents)}/$unitLabel'),
                subtitle: Text('${p.storeChain} · ${formatQuantity(p.quantity)} ${p.quantityUnit == 'piece' ? 'Stk' : p.quantityUnit}'),
                trailing: Text(formatViennaDateTime(p.purchasedAtUtc), style: t.textTheme.bodySmall),
              ),
        ],
      ),
    );
  }
}
