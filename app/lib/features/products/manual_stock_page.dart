import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/local/database.dart';
import 'product_form_page.dart';
import 'stock_entry_page.dart';

/// Bestand ohne Barcode erfassen (Fehlerbericht "Produkte ohne Barcode", 2026-11-02): lose Ware wie Bananen hat keinen
/// Strichcode, bisher fuehrte aber jeder Weg ins Inventar ueber den Scanner. Produkt suchen oder neu anlegen, danach weiter
/// wie nach einem Scan.
class ManualStockPage extends ConsumerStatefulWidget {
  const ManualStockPage({super.key});

  @override
  ConsumerState<ManualStockPage> createState() => _ManualStockPageState();
}

class _ManualStockPageState extends ConsumerState<ManualStockPage> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _createProduct() async {
    final name = _search.text.trim();
    final created = await context.push<Product>('/product-form', extra: ProductFormArgs(initialName: name.isEmpty ? null : name));
    if (created != null && mounted) await context.push('/stock-entry', extra: StockEntryArgs(product: created));
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsStreamProvider).value ?? const <Product>[];
    final query = _search.text.trim().toLowerCase();
    final shown = (query.isEmpty ? products : products.where((p) => p.name.toLowerCase().contains(query))).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Scaffold(
      appBar: AppBar(title: const Text('Ohne Barcode erfassen')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            key: const Key('manual-stock-search'),
            controller: _search,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Produkt suchen', prefixIcon: Icon(Icons.search)),
            onChanged: (_) => setState(() {}),
          ),
        ),
        ListTile(
          key: const Key('manual-stock-new'),
          leading: const Icon(Icons.add),
          title: Text(query.isEmpty ? 'Neues Produkt anlegen' : '„${_search.text.trim()}“ neu anlegen'),
          onTap: _createProduct,
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: shown.length,
            itemBuilder: (context, i) {
              final p = shown[i];
              return ListTile(
                key: Key('manual-stock-product-${p.id}'),
                title: Text(p.name),
                subtitle: p.brand == null ? null : Text(p.brand!),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/stock-entry', extra: StockEntryArgs(product: p)),
              );
            },
          ),
        ),
      ]),
    );
  }
}
