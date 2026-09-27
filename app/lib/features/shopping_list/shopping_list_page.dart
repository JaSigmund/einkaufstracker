import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';

String _sourceLabel(String source) => switch (source) {
      'depleted' => 'Aufgebraucht',
      'expiring' => 'Läuft bald ab',
      'recurring' => 'Regelmäßig gekauft',
      _ => 'Vorschlag',
    };

/// Gesamtmenge (Anzahl × Inhalt je Packung, `products.pack_size`) als Text, z.B. "4 Stück" oder "300 g".
/// `null`, wenn das Produkt keinen Inhalt hinterlegt hat oder es sich um einen frei getippten Eintrag
/// handelt — dann ist die Anzahl selbst schon die ganze Information (Wunsch "Inhalt je Produkt", 2026-09-28).
String? _totalContentLabel(ShoppingListItem item, Product? product) {
  final packSize = product?.packSize;
  if (packSize == null) return null;
  return '${formatQuantity(item.quantity * packSize)} ${product!.baseUnit}';
}

/// Einkaufsliste (Doku 06 §6/§7, Doku 08 §3.6, Lastenheft LH-SHO-01/02, Roadmap Phase 3): manuell pflegen,
/// im Markt ohne Netz abhaken, dazu Vorschlaege aus dem Inventar ("Leer"/"Ablauf") zur Bestaetigung oben.
/// Gruppiert nach Kategorie, abgehakte Artikel wandern nach unten in "Erledigt". Jeder Eintrag zeigt die
/// Anzahl (wie viele Packungen/Stueck) und, wenn das Produkt einen Inhalt hinterlegt hat, zusaetzlich die
/// Gesamtmenge — wichtig, wenn mal ein anderes Packungsformat gekauft wird.
class ShoppingListPage extends ConsumerStatefulWidget {
  const ShoppingListPage({super.key});

  @override
  ConsumerState<ShoppingListPage> createState() => _ShoppingListPageState();
}

class _ShoppingListPageState extends ConsumerState<ShoppingListPage> {
  final _input = TextEditingController();
  List<Product> _matches = const [];
  var _addQuantity = 1.0;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final results = query.trim().isEmpty ? const <Product>[] : await ref.read(productRepositoryProvider).search(query);
    if (mounted) setState(() => _matches = results);
  }

  Future<void> _addProduct(Product product) async {
    await ref.read(shoppingListRepositoryProvider).addManual(productId: product.id, quantity: _addQuantity, unit: product.baseUnit);
    _input.clear();
    if (mounted) {
      setState(() {
        _matches = const [];
        _addQuantity = 1;
      });
    }
  }

  Future<void> _addFreeText() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    await ref.read(shoppingListRepositoryProvider).addManual(freeText: text, quantity: _addQuantity);
    _input.clear();
    if (mounted) {
      setState(() {
        _matches = const [];
        _addQuantity = 1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final items = ref.watch(shoppingListItemsStreamProvider).value ?? const <ShoppingListItem>[];
    final products = {for (final p in ref.watch(productsStreamProvider).value ?? const <Product>[]) p.id: p};
    final categoryNames = {for (final c in ref.watch(categoriesStreamProvider).value ?? const <Category>[]) c.id: c.name};

    String labelOf(ShoppingListItem i) => i.freeText ?? products[i.productId]?.name ?? 'Unbekanntes Produkt';
    String categoryOf(ShoppingListItem i) {
      final categoryId = i.productId == null ? null : products[i.productId]?.categoryId;
      return categoryId == null ? 'Ohne Kategorie' : (categoryNames[categoryId] ?? 'Ohne Kategorie');
    }

    final suggestions = items.where((i) => i.isSuggestion && !i.checked).toList();
    final active = items.where((i) => !i.isSuggestion && !i.checked).toList();
    final done = items.where((i) => i.checked).toList()..sort((a, b) => labelOf(a).toLowerCase().compareTo(labelOf(b).toLowerCase()));

    final grouped = <String, List<ShoppingListItem>>{};
    for (final i in active) {
      grouped.putIfAbsent(categoryOf(i), () => []).add(i);
    }
    for (final list in grouped.values) {
      list.sort((a, b) => labelOf(a).toLowerCase().compareTo(labelOf(b).toLowerCase()));
    }
    final groupNames = grouped.keys.toList()
      ..sort((a, b) {
        if (a == 'Ohne Kategorie') return 1;
        if (b == 'Ohne Kategorie') return -1;
        return a.compareTo(b);
      });

    return Scaffold(
      body: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 8),
            children: [
              if (suggestions.isNotEmpty) ...[
                Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text('Vorschläge', style: t.textTheme.titleSmall)),
                for (final s in suggestions)
                  Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: ListTile(
                      key: Key('suggestion-${s.id}'),
                      title: Text(labelOf(s)),
                      subtitle: Text(_sourceLabel(s.source)),
                      trailing: Wrap(spacing: 4, children: [
                        TextButton(
                          key: Key('suggestion-add-${s.id}'),
                          onPressed: () => ref.read(shoppingListRepositoryProvider).confirmSuggestion(s.id),
                          child: const Text('Hinzufügen'),
                        ),
                        TextButton(
                          key: Key('suggestion-dismiss-${s.id}'),
                          onPressed: () => ref.read(shoppingListRepositoryProvider).delete(s.id),
                          child: const Text('Verwerfen'),
                        ),
                      ]),
                    ),
                  ),
                const Divider(height: 24),
              ],
              if (active.isEmpty && done.isEmpty && suggestions.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(child: Text('Die Liste ist leer', key: const Key('shopping-list-empty'))),
                ),
              for (final group in groupNames) ...[
                Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text(group, style: t.textTheme.titleSmall)),
                for (final i in grouped[group]!) _ItemTile(item: i, label: labelOf(i), product: i.productId == null ? null : products[i.productId]),
              ],
              if (done.isNotEmpty) ...[
                Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text('Erledigt (${done.length})', style: t.textTheme.titleSmall)),
                for (final i in done) _ItemTile(item: i, label: labelOf(i), product: i.productId == null ? null : products[i.productId]),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_matches.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final p in _matches) ListTile(dense: true, key: Key('add-match-${p.id}'), title: Text(p.name), onTap: () => _addProduct(p)),
                    ],
                  ),
                ),
              Row(children: [
                // Anzahl vor dem Hinzufuegen anpassen, ohne den Eintrag danach extra oeffnen zu muessen
                // (Wunsch "auch die Menge angeben koennen", 2026-09-28).
                IconButton(
                  key: const Key('add-quantity-minus'),
                  onPressed: _addQuantity > 1 ? () => setState(() => _addQuantity -= 1) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                SizedBox(width: 28, child: Text(formatQuantity(_addQuantity), textAlign: TextAlign.center, key: const Key('add-quantity-value'))),
                IconButton(
                  key: const Key('add-quantity-plus'),
                  onPressed: () => setState(() => _addQuantity += 1),
                  icon: const Icon(Icons.add_circle_outline),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const Key('shopping-list-input'),
                    controller: _input,
                    decoration: const InputDecoration(labelText: 'Artikel hinzufügen'),
                    onChanged: _search,
                    onSubmitted: (_) => _addFreeText(),
                  ),
                ),
                IconButton(key: const Key('shopping-list-add'), icon: const Icon(Icons.add), onPressed: _addFreeText),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _ItemTile extends ConsumerWidget {
  const _ItemTile({required this.item, required this.label, required this.product});
  final ShoppingListItem item;
  final String label;
  final Product? product;

  Future<void> _editQuantity(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(text: formatQuantity(item.quantity));
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Anzahl'),
        content: TextField(
          key: const Key('shopping-item-quantity-input'),
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(suffixText: item.unit),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.replaceAll(',', '.').trim())),
            child: const Text('Übernehmen'),
          ),
        ],
      ),
    );
    if (value != null && value > 0) {
      await ref.read(shoppingListRepositoryProvider).setQuantity(item.id, value);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalContent = _totalContentLabel(item, product);
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline),
      ),
      onDismissed: (_) => ref.read(shoppingListRepositoryProvider).delete(item.id),
      child: CheckboxListTile(
        key: Key('shopping-item-${item.id}'),
        controlAffinity: ListTileControlAffinity.leading,
        value: item.checked,
        onChanged: (v) => ref.read(shoppingListRepositoryProvider).setChecked(item.id, v ?? false),
        title: Text(label, style: item.checked ? const TextStyle(decoration: TextDecoration.lineThrough) : null),
        subtitle: totalContent == null ? null : Text('insgesamt $totalContent', key: Key('shopping-item-total-${item.id}')),
        secondary: InkWell(
          key: Key('shopping-item-quantity-${item.id}'),
          onTap: () => _editQuantity(context, ref),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('${formatQuantity(item.quantity)} ${item.unit}', style: Theme.of(context).textTheme.bodyMedium),
          ),
        ),
      ),
    );
  }
}
