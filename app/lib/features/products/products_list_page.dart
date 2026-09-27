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
                        trailing: const Icon(Icons.chevron_right),
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
