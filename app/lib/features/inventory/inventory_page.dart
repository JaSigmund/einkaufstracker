import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../domain/inventory/expiry.dart';

const _locationLabels = {'pantry': 'Vorrat', 'fridge': 'Kühlschrank', 'freezer': 'Tiefkühl', 'other': 'Sonstiges'};
const _locationOrder = ['fridge', 'freezer', 'pantry', 'other'];

Color _dotColor(ExpiryLevel level, ColorScheme cs) => switch (level) {
      ExpiryLevel.expired => cs.error,
      ExpiryLevel.soon => Colors.amber.shade700,
      ExpiryLevel.ok => Colors.green.shade600,
      ExpiryLevel.unknown => cs.outlineVariant,
    };

String _expiryText(InventoryItem item, ExpiryLevel level) {
  if (item.expiresOn == null) return 'Kein Ablaufdatum';
  final days = item.expiresOn!.difference(DateTime.utc(DateTime.now().year, DateTime.now().month, DateTime.now().day)).inDays;
  final label = item.dateKind == 'use_by' ? 'Zu verbrauchen bis' : 'MHD';
  if (days == 0) return '$label: heute';
  if (days == 1) return '$label: morgen';
  if (days > 1) return '$label: in $days Tagen';
  final overdue = -days;
  return '$label: seit $overdue Tag${overdue == 1 ? '' : 'en'} abgelaufen';
}

/// Inhalt des Tabs "Inventar" (Doku 06, 08 §3.4): aktiver Bestand mit Ampel, sortiert nach Ablauf, Filter nach
/// Lagerort, Vorschlaege aus Bons einklappbar oben, FAB fuehrt zum Barcode-Scan.
class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key, this.now, this.onScan});

  final DateTime? now;

  /// Wechselt zum Scan-Tab (der Barcode-Ablauf lebt dort, siehe Doku 08 §3.2).
  final VoidCallback? onScan;

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> {
  String? _location; // null = alle
  var _suggestionsOpen = true;

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeInventoryStreamProvider);
    final suggestions = ref.watch(inventorySuggestionsStreamProvider).value ?? const <InventoryItem>[];
    final products = {for (final p in ref.watch(productsStreamProvider).value ?? const <Product>[]) p.id: p};
    final today = widget.now ?? DateTime.now();

    return active.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (all) {
        final locations = {for (final i in all) i.location}.toList()..sort((a, b) => _locationOrder.indexOf(a).compareTo(_locationOrder.indexOf(b)));
        final shown = _location == null ? all : all.where((i) => i.location == _location).toList();

        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            key: const Key('inventory-scan-fab'),
            onPressed: widget.onScan,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scannen'),
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              if (suggestions.isNotEmpty)
                Card(
                  margin: const EdgeInsets.all(16),
                  child: Column(children: [
                    ListTile(
                      key: const Key('suggestions-toggle'),
                      leading: const Icon(Icons.inbox_outlined),
                      title: Text('Noch nicht gescannt (${suggestions.length})'),
                      subtitle: const Text('Aus Bons vorgeschlagen'),
                      trailing: Icon(_suggestionsOpen ? Icons.expand_less : Icons.expand_more),
                      onTap: () => setState(() => _suggestionsOpen = !_suggestionsOpen),
                    ),
                    if (_suggestionsOpen)
                      for (final s in suggestions)
                        ListTile(
                          dense: true,
                          title: Text(products[s.productId]?.name ?? 'Unbekanntes Produkt'),
                          subtitle: Text('${formatQuantity(s.quantity)} ${s.unit}'),
                          trailing: TextButton(
                            key: Key('discard-suggestion-${s.id}'),
                            onPressed: () => ref.read(inventoryRepositoryProvider).discardSuggestion(s.id),
                            child: const Text('Verwerfen'),
                          ),
                        ),
                  ]),
                ),
              if (locations.length > 1)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(spacing: 8, children: [
                    ChoiceChip(label: const Text('Alle'), selected: _location == null, onSelected: (_) => setState(() => _location = null)),
                    for (final l in locations)
                      ChoiceChip(
                        key: Key('filter-location-$l'),
                        label: Text(_locationLabels[l] ?? l),
                        selected: _location == l,
                        onSelected: (_) => setState(() => _location = _location == l ? null : l),
                      ),
                  ]),
                ),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      all.isEmpty ? 'Noch kein Bestand. Scanne einen Barcode im Tab „Scan".' : 'Keine Einträge für diese Auswahl',
                      key: const Key('inventory-empty'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                for (final item in shown) _InventoryTile(item: item, product: products[item.productId], today: today),
            ],
          ),
        );
      },
    );
  }
}

class _InventoryTile extends ConsumerWidget {
  const _InventoryTile({required this.item, required this.product, required this.today});
  final InventoryItem item;
  final Product? product;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final level = expiryLevel(expiresOn: item.expiresOn, dateKind: item.dateKind, today: today);
    return Dismissible(
      key: ValueKey(item.id),
      background: Container(
        color: t.colorScheme.primaryContainer,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Icon(Icons.check_circle_outline),
      ),
      secondaryBackground: Container(
        color: t.colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline),
      ),
      confirmDismiss: (direction) async {
        final repo = ref.read(inventoryRepositoryProvider);
        if (direction == DismissDirection.startToEnd) {
          await repo.markConsumed(item.id);
        } else {
          await repo.markDiscarded(item.id);
        }
        return false; // die Liste aktualisiert sich ueber den Stream, kein manuelles Entfernen noetig
      },
      child: ListTile(
        key: Key('inventory-item-${item.id}'),
        leading: Container(width: 12, height: 12, decoration: BoxDecoration(color: _dotColor(level, t.colorScheme), shape: BoxShape.circle)),
        title: Text(product?.name ?? 'Unbekanntes Produkt'),
        subtitle: Text([
          _expiryText(item, level),
          if (item.status == 'opened') 'geöffnet',
          '${formatQuantity(item.quantity)} ${item.unit}',
        ].join(' · ')),
        onTap: () => _openDetail(context, ref),
      ),
    );
  }

  void _openDetail(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(product?.name ?? 'Unbekanntes Produkt'), subtitle: Text(_locationLabels[item.location] ?? item.location)),
          if (item.status == 'sealed')
            ListTile(
              key: const Key('detail-open'),
              leading: const Icon(Icons.kitchen_outlined),
              title: const Text('Geöffnet'),
              onTap: () {
                ref.read(inventoryRepositoryProvider).open(item.id, productDefaultOpenShelfLifeDays: product?.openedShelfLifeDays);
                Navigator.pop(ctx);
              },
            ),
          ListTile(
            key: const Key('detail-consumed'),
            leading: const Icon(Icons.check_circle_outline),
            title: const Text('Aufgebraucht'),
            onTap: () {
              ref.read(inventoryRepositoryProvider).markConsumed(item.id);
              Navigator.pop(ctx);
            },
          ),
          ListTile(
            key: const Key('detail-discarded'),
            leading: const Icon(Icons.delete_outline),
            title: const Text('Weggeworfen'),
            onTap: () {
              ref.read(inventoryRepositoryProvider).markDiscarded(item.id);
              Navigator.pop(ctx);
            },
          ),
        ]),
      ),
    );
  }
}
