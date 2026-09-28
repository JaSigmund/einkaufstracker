import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/local/database.dart';
import 'product_form_page.dart';

/// Alle Produkte des Haushalts, durchsuchbar, zum Bearbeiten (Fehlerbericht "Alias ändern", 2026-09-27):
/// bisher gab es keinen Weg, ein Produkt ausserhalb des Barcode-Flows zu oeffnen.
class ProductsListPage extends ConsumerStatefulWidget {
  const ProductsListPage({super.key});

  @override
  ConsumerState<ProductsListPage> createState() => _ProductsListPageState();
}

class _ProductsListPageState extends ConsumerState<ProductsListPage> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<bool> _confirmDelete(Product product) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Produkt löschen?'),
        content: Text('„${product.name}“ wird aus der Liste entfernt. Bereits erfasste Bons und Inventar-Einträge bleiben erhalten.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok == true) await ref.read(productRepositoryProvider).softDelete(product.id);
    return ok ?? false;
  }

  /// Duplikate zusammenfuehren (Doku 07 §4.3): [source] bleibt als sichtbares Produkt bestehen, alle
  /// Kaeufe/Inventar/Einkaufsliste des ausgewaehlten anderen Produkts wandern zu [source], das andere
  /// verschwindet danach aus der Liste. So laesst sich z.B. ein versehentlich doppelt angelegtes Produkt
  /// wieder mit dem urspruenglichen vereinen, ohne die Kaufhistorie zu verlieren.
  Future<void> _mergeDialog(Product source) async {
    final all = ref.read(productsStreamProvider).value ?? const <Product>[];
    final candidates = all.where((p) => p.id != source.id).toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final search = TextEditingController();
    final target = await showDialog<Product>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        final q = search.text.trim().toLowerCase();
        final shown = q.isEmpty ? candidates : candidates.where((p) => p.name.toLowerCase().contains(q)).toList();
        return AlertDialog(
          title: Text('„${source.name}“ zusammenführen mit…'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: Column(children: [
              TextField(
                controller: search,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Anderes Produkt suchen', prefixIcon: Icon(Icons.search)),
                onChanged: (_) => setDialogState(() {}),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: shown.isEmpty
                    ? const Center(child: Text('Keine Produkte gefunden'))
                    : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (ctx, i) {
                          final p = shown[i];
                          return ListTile(
                            key: Key('merge-target-${p.id}'),
                            title: Text(p.name),
                            subtitle: p.brand == null ? null : Text(p.brand!),
                            onTap: () => Navigator.pop(ctx, p),
                          );
                        },
                      ),
              ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen'))],
        );
      }),
    );
    if (target == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Produkte zusammenführen?'),
        content: Text(
            '„${target.name}“ wird in „${source.name}“ zusammengeführt. Bons, Inventar und Einkaufsliste von „${target.name}“ gehören danach zu „${source.name}“; „${target.name}“ verschwindet aus der Liste.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Zusammenführen')),
        ],
      ),
    );
    if (confirmed == true) await ref.read(productRepositoryProvider).mergeInto(target.id, source.id);
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsStreamProvider).value ?? const <Product>[];
    final query = _search.text.trim().toLowerCase();
    final filtered = (query.isEmpty ? products : products.where((p) => p.name.toLowerCase().contains(query))).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Scaffold(
      appBar: AppBar(title: const Text('Meine Produkte')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            key: const Key('products-search'),
            controller: _search,
            decoration: const InputDecoration(labelText: 'Suchen', prefixIcon: Icon(Icons.search)),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('Keine Produkte gefunden'))
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final p = filtered[i];
                    return Dismissible(
                      key: ValueKey(p.id),
                      direction: DismissDirection.endToStart,
                      confirmDismiss: (_) => _confirmDelete(p),
                      background: Container(
                        color: Theme.of(context).colorScheme.errorContainer,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: const Icon(Icons.delete_outline),
                      ),
                      child: ListTile(
                        key: Key('product-${p.id}'),
                        title: Text(p.name),
                        subtitle: p.brand == null ? null : Text(p.brand!),
                        trailing: PopupMenuButton<String>(
                          key: Key('product-menu-${p.id}'),
                          onSelected: (v) {
                            if (v == 'merge') _mergeDialog(p);
                          },
                          itemBuilder: (ctx) => const [
                            PopupMenuItem(value: 'merge', child: Text('Mit anderem Produkt zusammenführen')),
                          ],
                        ),
                        onTap: () => context.push('/product-form', extra: ProductFormArgs(existing: p)),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
