import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../domain/receipt/month_summary.dart';
import '../../domain/receipt/vienna_time.dart';

const _monthNames = [
  'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
];

/// Inhalt des Tabs "Uebersicht": Summe des aktuellen Monats und die gespeicherten Bons.
class ReceiptsOverview extends ConsumerWidget {
  const ReceiptsOverview({super.key, this.now});

  /// Aktueller Zeitpunkt (UTC). Austauschbar fuer Tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipts = ref.watch(receiptsStreamProvider);
    final stores = ref.watch(storesStreamProvider).value ?? const <Store>[];
    final t = Theme.of(context);

    return receipts.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (list) {
        final local = utcToViennaLocal(now ?? DateTime.now().toUtc());
        final month = summarizeMonth(
          list.map((r) => (purchasedAtUtc: r.purchasedAt, totalCents: r.totalCents)),
          year: local.year,
          month: local.month,
        );
        final storeById = {for (final s in stores) s.id: s};

        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${_monthNames[local.month - 1]} ${local.year}', style: t.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Text(formatEuro(month.totalCents), key: const Key('month-total'), style: t.textTheme.headlineMedium),
                  const SizedBox(height: 2),
                  Text(
                    month.receiptCount == 1 ? '1 Einkauf' : '${month.receiptCount} Einkäufe',
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline),
                  ),
                ]),
              ),
            ),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  Icon(Icons.receipt_long_outlined, size: 48, color: t.colorScheme.outline),
                  const SizedBox(height: 12),
                  Text('Noch keine Bons', style: t.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  const Text('Importiere im Tab „Scan“ deinen ersten digitalen Bon.', textAlign: TextAlign.center),
                ]),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Text('Bons', style: t.textTheme.titleSmall),
              ),
              for (final r in list) _ReceiptTile(receipt: r, store: storeById[r.storeId]),
            ],
          ],
        );
      },
    );
  }
}

class _ReceiptTile extends StatelessWidget {
  const _ReceiptTile({required this.receipt, this.store});
  final Receipt receipt;
  final Store? store;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final title = store == null ? 'Einkauf' : '${store!.chain}${store!.branch == null ? '' : ', Filiale ${store!.branch}'}';
    return ListTile(
      leading: const Icon(Icons.receipt_long_outlined),
      title: Text(title),
      subtitle: Text(formatViennaDateTime(receipt.purchasedAt)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (receipt.sumMismatch) Icon(Icons.warning_amber_rounded, size: 18, color: t.colorScheme.error),
        const SizedBox(width: 4),
        Text(formatEuro(receipt.totalCents), style: t.textTheme.titleSmall),
      ]),
      onTap: () => context.push('/receipt/${receipt.id}'),
    );
  }
}
