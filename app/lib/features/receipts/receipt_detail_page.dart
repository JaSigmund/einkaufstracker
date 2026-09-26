import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';

/// Einzelner gespeicherter Bon mit allen Positionen. Loeschen ueber das Menue oben rechts.
class ReceiptDetailPage extends ConsumerWidget {
  const ReceiptDetailPage({super.key, required this.receiptId});

  final String receiptId;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bon löschen?'),
        content: const Text('Der Bon und seine Positionen werden entfernt und fließen nicht mehr in die Auswertung ein. Ein erneuter Import ist möglich.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(receiptRepositoryProvider).softDelete(receiptId);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bon gelöscht')));
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipt = ref.watch(receiptProvider(receiptId)).value;
    final items = ref.watch(receiptItemsProvider(receiptId)).value ?? const <ReceiptItem>[];
    final stores = ref.watch(storesStreamProvider).value ?? const <Store>[];
    final t = Theme.of(context);

    if (receipt == null || receipt.deletedAt != null) {
      return Scaffold(appBar: AppBar(title: const Text('Bon')), body: const Center(child: Text('Dieser Bon ist nicht mehr vorhanden.')));
    }
    final store = stores.where((s) => s.id == receipt.storeId).firstOrNull;
    final title = store == null ? 'Einkauf' : '${store.chain}${store.branch == null ? '' : ', Filiale ${store.branch}'}';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'delete') _delete(context, ref);
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Löschen'))],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          ListTile(
            title: Text(formatViennaDateTime(receipt.purchasedAt)),
            subtitle: Text(receipt.source == 'pdf_text' ? 'Digitaler Bon (PDF)' : 'Quelle: ${receipt.source}'),
            trailing: Text(formatEuro(receipt.totalCents), style: t.textTheme.titleLarge, key: const Key('receipt-total')),
          ),
          if (receipt.sumMismatch)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: t.colorScheme.errorContainer, borderRadius: BorderRadius.circular(12)),
              child: Text(
                'Beim Import stimmten nicht alle Prüfungen. Die Positionen sollten mit dem Original verglichen werden.',
                style: TextStyle(color: t.colorScheme.onErrorContainer),
              ),
            ),
          const Divider(height: 1),
          for (final i in items)
            ListTile(
              dense: true,
              title: Text(i.rawText),
              subtitle: _sub(i) == null ? null : Text(_sub(i)!),
              trailing: Text(formatEuro(i.lineTotalCents), style: TextStyle(color: i.lineTotalCents < 0 ? t.colorScheme.primary : null)),
            ),
          const Divider(height: 1),
          ListTile(
            title: Text('Summe', style: t.textTheme.titleSmall),
            trailing: Text(formatEuro(items.fold<int>(0, (s, i) => s + i.lineTotalCents)), key: const Key('items-sum')),
          ),
        ],
      ),
    );
  }

  String? _sub(ReceiptItem i) {
    final parts = <String>[
      if (i.quantity != 1 && i.unitPriceCents != null)
        '${formatQuantity(i.quantity)}${i.quantityUnit == 'piece' ? ' ×' : ' ${i.quantityUnit} ×'} ${formatEuro(i.unitPriceCents!)}',
      if (i.kind == 'discount') 'Rabatt',
      if (i.kind == 'deposit') 'Pfand',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}
