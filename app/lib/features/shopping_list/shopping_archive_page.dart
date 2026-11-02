import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../domain/shopping_list/list_archive.dart';
import '../../domain/shopping_list/list_quantity.dart';

/// Abgeschlossene Einkaeufe (ADR-043), der neueste zuerst. Ein Einkauf laesst sich zurueck auf die Liste holen, falls er versehentlich
/// abgeschlossen wurde; seine Eintraege stehen dann wieder unter "Erledigt".
class ShoppingArchivePage extends ConsumerWidget {
  const ShoppingArchivePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final items = ref.watch(archivedShoppingItemsStreamProvider).value ?? const <ShoppingListItem>[];
    final products = {for (final p in ref.watch(productsStreamProvider).value ?? const <Product>[]) p.id: p};
    final listNames = {for (final l in ref.watch(shoppingListsStreamProvider).value ?? const <ShoppingList>[]) l.id: l.name};
    final purchases = groupArchivedPurchases(items, archivedAt: (ShoppingListItem i) => i.archivedAt!, listId: (ShoppingListItem i) => i.listId);

    return Scaffold(
      appBar: AppBar(title: const Text('Abgeschlossene Einkäufe')),
      body: purchases.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Noch nichts archiviert. Abgehakte Einträge kommen mit „Einkauf abschließen“ hierher.', key: Key('shopping-archive-empty'), textAlign: TextAlign.center),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(8),
              children: [
                for (final p in purchases)
                  Card(
                    key: Key('archive-${p.archivedAt.toIso8601String()}'),
                    child: ExpansionTile(
                      title: Text(formatViennaDateTime(p.archivedAt)),
                      subtitle: Text('${listNames[p.listId] ?? 'Einkaufsliste'} · ${p.items.length == 1 ? '1 Eintrag' : '${p.items.length} Einträge'}'),
                      children: [
                        for (final i in p.items)
                          ListTile(
                            dense: true,
                            title: Text(i.freeText ?? products[i.productId]?.name ?? 'Unbekanntes Produkt'),
                            trailing: Text(
                              describeListQuantity(quantity: i.quantity, unit: i.unit, packSize: products[i.productId]?.packSize, productBaseUnit: products[i.productId]?.baseUnit, piecesPerPack: products[i.productId]?.piecesPerPack, pieceLabel: products[i.productId]?.pieceLabel).primary,
                              style: t.textTheme.bodyMedium,
                            ),
                          ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            key: Key('archive-restore-${p.archivedAt.toIso8601String()}'),
                            onPressed: () => ref.read(shoppingListRepositoryProvider).unarchive([for (final i in p.items) i.id]),
                            icon: const Icon(Icons.unarchive_outlined),
                            label: const Text('Zurück auf die Liste'),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
