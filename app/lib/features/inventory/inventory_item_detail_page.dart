import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../domain/inventory/expiry.dart';
import '../../data/repositories/inventory_repository.dart';

const _locationLabels = {'pantry': 'Vorrat', 'fridge': 'Kühlschrank', 'freezer': 'Tiefkühl', 'other': 'Sonstiges'};
const _locationIcons = {
  'pantry': Icons.kitchen_outlined,
  'fridge': Icons.ac_unit_outlined,
  'freezer': Icons.severe_cold_outlined,
  'other': Icons.inventory_2_outlined,
};
const _dateKindLabels = {'best_before': 'Mindestens haltbar bis', 'use_by': 'Zu verbrauchen bis'};
const _movementLabels = {
  'purchase': 'Zugang',
  'consumed': 'Aufgebraucht',
  'discarded': 'Weggeworfen',
  'adjustment': 'Korrektur',
  'meal': 'Verbraucht',
};

String _formatDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

/// Argumente fuer /inventory-item.
class InventoryItemArgs {
  const InventoryItemArgs({required this.item, this.product});
  final InventoryItem item;
  final Product? product;
}

/// Ansicht **und** Bearbeitung eines Vorratseintrags an einem Ort (Doku 06 §1, §3, §9): Menge, Ablaufdatum,
/// Lagerort direkt antippbar, dazu die Statusaktionen und der Bewegungsverlauf. Ersetzt das fruehere, rein
/// lesende Bottom Sheet, damit sich ein falsch erfasster Wert korrigieren laesst, ohne den Eintrag neu anzulegen.
class InventoryItemDetailPage extends ConsumerStatefulWidget {
  const InventoryItemDetailPage({super.key, required this.item, this.product});

  final InventoryItem item;
  final Product? product;

  @override
  ConsumerState<InventoryItemDetailPage> createState() => _InventoryItemDetailPageState();
}

class _InventoryItemDetailPageState extends ConsumerState<InventoryItemDetailPage> {
  late InventoryItem _item = widget.item;

  InventoryRepository get _repo => ref.read(inventoryRepositoryProvider);

  Future<void> _refresh() async {
    final fresh = await (ref.read(databaseProvider).select(ref.read(databaseProvider).inventoryItems)
          ..where((i) => i.id.equals(_item.id)))
        .getSingleOrNull();
    if (fresh != null && mounted) setState(() => _item = fresh);
  }

  Future<void> _changeQuantity(double delta) async {
    final next = (_item.quantity + delta).clamp(0, 999999).toDouble();
    if (next == _item.quantity) return;
    await _repo.adjustQuantity(_item.id, next);
    await _refresh();
  }

  Future<void> _enterQuantity() async {
    final ctrl = TextEditingController(text: formatQuantity(_item.quantity));
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Menge'),
        content: TextField(
          key: const Key('quantity-input'),
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(suffixText: _item.unit),
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
    if (value != null && value >= 0) {
      await _repo.adjustQuantity(_item.id, value);
      await _refresh();
    }
  }

  Future<void> _changeDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _item.bestBefore ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked == null) return;
    await _repo.updateDetails(_item.id, bestBefore: DateTime.utc(picked.year, picked.month, picked.day));
    await _refresh();
  }

  Future<void> _clearDate() async {
    await _repo.updateDetails(_item.id, clearBestBefore: true);
    await _refresh();
  }

  Future<void> _changeDateKind(String kind) async {
    await _repo.updateDetails(_item.id, dateKind: kind);
    await _refresh();
  }

  Future<void> _changeLocation(String location) async {
    await _repo.updateDetails(_item.id, location: location);
    await _refresh();
  }

  Future<void> _open() async {
    await _repo.open(_item.id, productDefaultOpenShelfLifeDays: widget.product?.openedShelfLifeDays);
    await _refresh();
  }

  Future<void> _consumed() async {
    await _repo.markConsumed(_item.id);
    if (mounted) context.pop();
  }

  Future<void> _discarded() async {
    await _repo.markDiscarded(_item.id);
    if (mounted) context.pop();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eintrag löschen?'),
        content: const Text('Der Eintrag und seine Kaufbewegung werden entfernt, so als wäre er nie erfasst worden. Anders als "Aufgebraucht" oder "Weggeworfen".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true) return;
    await _repo.deleteItem(_item.id);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final today = DateTime.now();
    final level = expiryLevel(expiresOn: _item.expiresOn, dateKind: _item.dateKind, today: today);
    final color = switch (level) {
      ExpiryLevel.expired => t.colorScheme.error,
      ExpiryLevel.soon => Colors.amber.shade800,
      ExpiryLevel.ok => Colors.green.shade700,
      ExpiryLevel.unknown => t.colorScheme.outline,
    };
    final movements = ref.watch(inventoryMovementsStreamProvider(_item.productId)).value ?? const <InventoryMovement>[];
    final ownMovements = movements.where((m) => m.inventoryItemId == _item.id).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.product?.name ?? 'Unbekanntes Produkt'),
        actions: [
          IconButton(
            key: const Key('action-delete'),
            tooltip: 'Löschen (falsch erfasst)',
            icon: const Icon(Icons.delete_forever_outlined),
            onPressed: _delete,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Menge: gross und direkt bedienbar, das war vorher gar nicht moeglich
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(key: const Key('quantity-minus'), iconSize: 32, onPressed: () => _changeQuantity(-1), icon: const Icon(Icons.remove_circle_outline)),
                Expanded(
                  child: InkWell(
                    key: const Key('quantity-tap'),
                    onTap: _enterQuantity,
                    child: Column(children: [
                      Text('${formatQuantity(_item.quantity)} ${_item.unit}', style: t.textTheme.headlineSmall, textAlign: TextAlign.center),
                      Text('Menge antippen zum Eingeben', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
                    ]),
                  ),
                ),
                IconButton(key: const Key('quantity-plus'), iconSize: 32, onPressed: () => _changeQuantity(1), icon: const Icon(Icons.add_circle_outline)),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          // Ablaufdatum: Ampelfarbe und Datum an einem Ort, direkt antippbar
          Card(
            color: color.withValues(alpha: 0.12),
            child: ListTile(
              key: const Key('date-tap'),
              leading: Icon(Icons.event_outlined, color: color),
              title: Text(_item.bestBefore == null ? 'Kein Datum hinterlegt' : _formatDate(_item.bestBefore!), style: TextStyle(color: color, fontWeight: FontWeight.bold)),
              subtitle: Text(_dateKindLabels[_item.dateKind]!),
              trailing: _item.bestBefore == null ? null : IconButton(key: const Key('date-clear'), icon: const Icon(Icons.close), onPressed: _clearDate),
              onTap: _changeDate,
            ),
          ),
          if (_item.bestBefore == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(spacing: 8, children: [
                OutlinedButton(
                  onPressed: () async {
                    await _repo.updateDetails(_item.id, bestBefore: DateTime.now().add(const Duration(days: 7)).toUtc());
                    await _refresh();
                  },
                  child: const Text('+7 Tage'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    await _repo.updateDetails(_item.id, bestBefore: DateTime.now().add(const Duration(days: 14)).toUtc());
                    await _refresh();
                  },
                  child: const Text('+14 Tage'),
                ),
              ]),
            ),
          const SizedBox(height: 4),
          SegmentedButton<String>(
            key: const Key('date-kind-picker'),
            segments: const [
              ButtonSegment(value: 'best_before', label: Text('MHD')),
              ButtonSegment(value: 'use_by', label: Text('Verbrauchsdatum')),
            ],
            selected: {_item.dateKind},
            onSelectionChanged: (s) => _changeDateKind(s.first),
          ),
          const SizedBox(height: 16),
          Text('Lagerort', style: t.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final l in _locationLabels.keys)
              ChoiceChip(
                key: Key('location-$l'),
                avatar: Icon(_locationIcons[l], size: 18),
                label: Text(_locationLabels[l]!),
                selected: _item.location == l,
                onSelected: (_) => _changeLocation(l),
              ),
          ]),
          const SizedBox(height: 20),
          if (_item.status == 'sealed')
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(key: const Key('action-open'), onPressed: _open, icon: const Icon(Icons.kitchen_outlined), label: const Text('Geöffnet')),
            ),
          if (_item.status == 'opened')
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Geöffnet seit ${_item.openedOn == null ? '-' : _formatDate(_item.openedOn!)}', style: t.textTheme.bodyMedium),
            ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(key: const Key('action-consumed'), onPressed: _consumed, icon: const Icon(Icons.check_circle_outline), label: const Text('Aufgebraucht')),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('action-discarded'),
                onPressed: _discarded,
                icon: Icon(Icons.delete_outline, color: t.colorScheme.error),
                label: Text('Weggeworfen', style: TextStyle(color: t.colorScheme.error)),
                style: OutlinedButton.styleFrom(side: BorderSide(color: t.colorScheme.error)),
              ),
            ),
          ]),
          if (ownMovements.isNotEmpty) ...[
            const Divider(height: 32),
            Text('Verlauf', style: t.textTheme.titleSmall),
            for (final m in ownMovements)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(_movementLabels[m.type] ?? m.type),
                subtitle: Text(_formatDate(m.occurredAt)),
                trailing: Text('${m.quantityDelta > 0 ? '+' : ''}${formatQuantity(m.quantityDelta)} ${m.unit}'),
              ),
          ],
        ],
      ),
    );
  }
}
