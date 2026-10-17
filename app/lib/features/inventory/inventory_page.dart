import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/clock.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../domain/inventory/expiry.dart';
import '../../domain/inventory/usage_forecast.dart';
import '../products/barcode_flow.dart';
import 'inventory_item_detail_page.dart';

const _locationLabels = {'pantry': 'Vorrat', 'fridge': 'Kühlschrank', 'freezer': 'Tiefkühl', 'other': 'Sonstiges'};
const _locationOrder = ['fridge', 'freezer', 'pantry', 'other'];

const _groupTitles = {
  ExpiryLevel.expired: 'Abgelaufen',
  ExpiryLevel.soon: 'Läuft bald ab',
  ExpiryLevel.ok: 'Gut',
  ExpiryLevel.unknown: 'Ohne Ablaufdatum',
};
// Reihenfolge der Gruppen: das Dringende zuerst, wie in der Uebersicht (Doku 08 §3.1 "Bald ablaufend").
const _groupOrder = [ExpiryLevel.expired, ExpiryLevel.soon, ExpiryLevel.ok, ExpiryLevel.unknown];

Color _dotColor(ExpiryLevel level, ColorScheme cs) => switch (level) {
      ExpiryLevel.expired => cs.error,
      ExpiryLevel.soon => Colors.amber.shade700,
      ExpiryLevel.ok => Colors.green.shade600,
      ExpiryLevel.unknown => cs.outlineVariant,
    };

String _expiryText(InventoryItem item, ExpiryLevel level, DateTime today) {
  if (item.expiresOn == null) return 'Kein Ablaufdatum';
  final days = item.expiresOn!.difference(DateTime.utc(today.year, today.month, today.day)).inDays;
  final label = item.dateKind == 'use_by' ? 'Zu verbrauchen bis' : 'MHD';
  if (days == 0) return '$label: heute';
  if (days == 1) return '$label: morgen';
  if (days > 1) return '$label: in $days Tagen';
  final overdue = -days;
  return '$label: seit $overdue Tag${overdue == 1 ? '' : 'en'} abgelaufen';
}

/// Inhalt des Tabs "Inventar" (Doku 06, 08 §3.4): aktiver Bestand nach Dringlichkeit gruppiert (abgelaufen/
/// bald faellig zuerst, wie auf der Uebersicht), Filter nach Lagerort, Vorschlaege aus Bons einklappbar oben.
/// Der FAB startet direkt den Barcode-Scan, ohne Umweg ueber die Seite "Scannen".
class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key, this.now});

  final DateTime? now;

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
    final today = widget.now ?? appClock.now();
    final t = Theme.of(context);
    final forecasts = ref.watch(usageForecastProvider);

    return active.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (all) {
        final locations = {for (final i in all) i.location}.toList()..sort((a, b) => _locationOrder.indexOf(a).compareTo(_locationOrder.indexOf(b)));
        final shown = _location == null ? all : all.where((i) => i.location == _location).toList();
        final groups = <ExpiryLevel, List<InventoryItem>>{};
        for (final item in shown) {
          groups.putIfAbsent(expiryLevel(expiresOn: item.expiresOn, dateKind: item.dateKind, today: today), () => []).add(item);
        }

        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            key: const Key('inventory-scan-fab'),
            onPressed: () => startBarcodeScan(context, ref),
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
                      all.isEmpty ? 'Noch kein Bestand. Tippe unten auf „Scannen“, um den ersten Artikel zu erfassen.' : 'Keine Einträge für diese Auswahl',
                      key: const Key('inventory-empty'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                for (final level in _groupOrder)
                  if (groups[level] case final items? when items.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Row(children: [
                        Container(width: 10, height: 10, margin: const EdgeInsets.only(right: 8), decoration: BoxDecoration(color: _dotColor(level, t.colorScheme), shape: BoxShape.circle)),
                        Text('${_groupTitles[level]} (${items.length})', style: t.textTheme.titleSmall),
                      ]),
                    ),
                    for (final item in items) _InventoryTile(item: item, product: products[item.productId], level: level, today: today, forecast: forecasts[item.productId]),
                  ],
            ],
          ),
        );
      },
    );
  }
}

/// Bis zu dieser Reichweite (Tage) zeigt die Bestandsliste die Vorhersage.
const forecastShowDays = 14;

class _InventoryTile extends ConsumerWidget {
  const _InventoryTile({required this.item, required this.product, required this.level, required this.today, this.forecast});
  final InventoryItem item;

  /// Vorhersage der Reichweite des Gesamtbestands dieses Produkts (Ausbau 1.14), `null` ohne ausreichende Daten.
  final UsageForecast? forecast;
  final Product? product;
  final ExpiryLevel level;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
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
        final consumed = direction == DismissDirection.startToEnd;
        if (consumed) {
          await repo.markConsumed(item.id);
        } else {
          await repo.markDiscarded(item.id);
        }
        // Sofortiger Rueckweg fuer einen verwischten Wisch (Fehlerbericht "Rueckgaengigmachen von
        // aufgebrauchten Artikeln", 2026-09-28), statt den Eintrag erst wiederfinden zu muessen.
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(consumed ? 'Als aufgebraucht markiert' : 'Als weggeworfen markiert'),
            action: SnackBarAction(label: 'Rückgängig', onPressed: () => repo.reopen(item.id)),
          ));
        }
        return false; // die Liste aktualisiert sich ueber den Stream, kein manuelles Entfernen noetig
      },
      child: ListTile(
        key: Key('inventory-item-${item.id}'),
        leading: Container(width: 12, height: 12, decoration: BoxDecoration(color: _dotColor(level, t.colorScheme), shape: BoxShape.circle)),
        title: Text(product?.name ?? 'Unbekanntes Produkt'),
        subtitle: Text([
          _expiryText(item, level, today),
          if (item.status == 'opened') 'geöffnet',
          '${formatQuantity(item.quantity)} ${item.unit}',
          // nur wenn es bald knapp wird: sonst waere die Zeile bei jedem Artikel voll von Prognosen
          if (forecast != null && forecast!.daysLeft <= forecastShowDays && forecast!.text != null) forecast!.text!,
        ].join(' · ')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/inventory-item', extra: InventoryItemArgs(item: item, product: product)),
      ),
    );
  }
}
