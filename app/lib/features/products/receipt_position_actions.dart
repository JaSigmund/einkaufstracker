import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../data/repositories/inventory_repository.dart';
import 'product_form_page.dart';

String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

/// Produkt waehlen, zu dem eine Bon-Position gehoert (Doku 27 Etappe E3): Suche ueber die Produkte des Haushalts oder neu anlegen.
Future<Product?> pickProductFor(BuildContext context, WidgetRef ref, {required String initialQuery, String? currentProductId}) async {
  final products = [...(ref.read(productsStreamProvider).value ?? const <Product>[])]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  final search = TextEditingController(text: initialQuery);
  final picked = await showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setSheetState) {
      final q = search.text.trim().toLowerCase();
      final shown = q.isEmpty ? products : products.where((p) => p.name.toLowerCase().contains(q)).toList();
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.8,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                key: const Key('pick-product-search'),
                controller: search,
                decoration: const InputDecoration(labelText: 'Produkt suchen', prefixIcon: Icon(Icons.search)),
                onChanged: (_) => setSheetState(() {}),
              ),
            ),
            ListTile(
              key: const Key('pick-product-new'),
              leading: const Icon(Icons.add),
              title: Text(search.text.trim().isEmpty ? 'Neues Produkt anlegen' : '„${search.text.trim()}“ neu anlegen'),
              onTap: () => Navigator.pop(ctx, 'new'),
            ),
            const Divider(height: 1),
            Expanded(
              child: shown.isEmpty
                  ? const Center(child: Text('Keine Produkte gefunden'))
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (ctx, i) {
                        final p = shown[i];
                        return ListTile(
                          key: Key('pick-product-${p.id}'),
                          title: Text(p.name),
                          subtitle: p.brand == null ? null : Text(p.brand!),
                          trailing: p.id == currentProductId ? const Icon(Icons.check) : null,
                          onTap: () => Navigator.pop(ctx, p),
                        );
                      },
                    ),
            ),
          ]),
        ),
      );
    }),
  );
  if (picked is Product) return picked;
  if (picked == 'new' && context.mounted) {
    final created = await context.push<Product>('/product-form', extra: ProductFormArgs(initialName: search.text.trim().isEmpty ? null : search.text.trim()));
    return created;
  }
  return null;
}

/// Eine Bon-Position einem anderen Produkt zuordnen, aus dem Bon-Detail. Andere Bons mit demselben Text bleiben, wie sie sind (ADR-048).
Future<void> moveReceiptPosition(BuildContext context, WidgetRef ref, ReceiptItem item) async {
  final product = await pickProductFor(context, ref, initialQuery: '', currentProductId: item.productId);
  if (product == null || product.id == item.productId || !context.mounted) return;
  await ref.read(inventoryRepositoryProvider).moveReceiptItemTo(item.id, product.id);
  if (context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('„${item.rawText}“ gehört jetzt zu „${product.name}“')));
  }
}

/// Von der Produktseite aus eine Bon-Position zuordnen: alle freien Artikel-Positionen mit Suche, samt "bisher bei …".
Future<void> addReceiptPositionTo(BuildContext context, WidgetRef ref, Product product) async {
  final repo = ref.read(inventoryRepositoryProvider);
  final candidates = await repo.otherReceiptLinksFor(product.id);
  if (!context.mounted) return;
  var query = '';
  final picked = await showModalBottomSheet<ReceiptLink>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setSheetState) {
      final q = query.trim().toLowerCase();
      final shown = q.isEmpty ? candidates : candidates.where((c) => c.rawText.toLowerCase().contains(q) || (c.productName?.toLowerCase().contains(q) ?? false)).toList();
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.8,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                key: const Key('receipt-position-search'),
                decoration: const InputDecoration(labelText: 'Bon-Positionen durchsuchen', prefixIcon: Icon(Icons.search)),
                onChanged: (v) => setSheetState(() => query = v),
              ),
            ),
            Expanded(
              child: shown.isEmpty
                  ? const Center(child: Text('Keine passenden Bon-Positionen'))
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (ctx, i) {
                        final c = shown[i];
                        return ListTile(
                          key: Key('receipt-position-${c.receiptItemId}'),
                          leading: const Icon(Icons.receipt_long_outlined),
                          title: Text('„${c.rawText}“'),
                          subtitle: Text([
                            '${c.storeChain ?? 'Bon'} · ${_date(c.purchasedAt)}',
                            if (c.productName != null) 'bisher bei ${c.productName}',
                          ].join('\n')),
                          trailing: c.lineTotalCents == null ? null : Text(formatEuro(c.lineTotalCents!)),
                          onTap: () => Navigator.pop(ctx, c),
                        );
                      },
                    ),
            ),
          ]),
        ),
      );
    }),
  );
  if (picked == null) return;
  await repo.moveReceiptItemTo(picked.receiptItemId, product.id);
}
