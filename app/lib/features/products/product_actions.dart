import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/local/database.dart';

/// Was Produktliste und Produktseite gemeinsam anbieten (Doku 27): Loeschen, Zusammenfuehren und die Kategorie.
Future<bool> confirmDeleteProduct(BuildContext context, WidgetRef ref, Product product) async {
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
Future<void> showProductMergeDialog(BuildContext context, WidgetRef ref, Product source) async {
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
  if (target == null || !context.mounted) return;
  await confirmProductMerge(context, ref, keep: source, drop: target);
}

/// Letzter Schritt beider Zusammenfuehren-Wege (manuell gesucht oder als Duplikat-Vorschlag
/// angetippt): [drop] verschwindet aus der Liste, seine Historie wandert zu [keep].
Future<void> confirmProductMerge(BuildContext context, WidgetRef ref, {required Product keep, required Product drop}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Produkte zusammenführen?'),
      content: Text(
          '„${drop.name}“ wird in „${keep.name}“ zusammengeführt. Bons, Inventar und Einkaufsliste von „${drop.name}“ gehören danach zu „${keep.name}“; „${drop.name}“ verschwindet aus der Liste.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Zusammenführen')),
      ],
    ),
  );
  if (confirmed == true) await ref.read(productRepositoryProvider).mergeInto(drop.id, keep.id);
}

/// Kategorie eines Produkts waehlen. Das Produkt fuehrt (Q-37, ADR-052): seine Bon-Positionen ziehen nach, mit "Rückgängig".
Future<void> pickProductCategory(BuildContext context, WidgetRef ref, Product product) async {
  final categories = (ref.read(categoriesStreamProvider).value ?? const <Category>[]).where((c) => c.deletedAt == null).toList();
  final messenger = ScaffoldMessenger.maybeOf(context);
  final picked = await showModalBottomSheet<({String? id})>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
        child: ListView(shrinkWrap: true, children: [
          ListTile(title: Text(product.name, style: Theme.of(ctx).textTheme.titleMedium), subtitle: const Text('Kategorie wählen')),
          ListTile(
            key: const Key('pick-category-none'),
            title: const Text('Keine'),
            trailing: product.categoryId == null ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(ctx, (id: null)),
          ),
          for (final c in categories)
            ListTile(
              key: Key('pick-category-${c.id}'),
              title: Text(c.name),
              trailing: c.id == product.categoryId ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(ctx, (id: c.id)),
            ),
        ]),
      ),
    ),
  );
  if (picked == null || picked.id == product.categoryId) return;
  final products = ref.read(productRepositoryProvider);
  final receipts = ref.read(receiptRepositoryProvider);
  await products.update(product.copyWith(categoryId: Value(picked.id)));
  final previous = await receipts.setProductItemsCategory(product.id, picked.id);
  if (previous.isEmpty || messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      key: const Key('category-items-changed'),
      content: Text(previous.length == 1 ? 'Auch 1 Bon-Position geändert' : 'Auch ${previous.length} Bon-Positionen geändert'),
      persist: false,
      action: SnackBarAction(
        label: 'Rückgängig',
        onPressed: () async {
          await products.update(product.copyWith(categoryId: Value(product.categoryId)));
          await receipts.restoreItemCategories(previous);
        },
      ),
    ));
}
