import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/clock.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../domain/inventory/expiry.dart';
import '../../domain/notifications/expiry_stages.dart';
import '../../domain/products/packaging.dart';
import '../../domain/shopping_list/list_quantity.dart';
import '../../data/repositories/inventory_repository.dart';
import '../common/quantity_dialog.dart';
import '../products/product_form_page.dart';
import '../settings/expiry_stages_dialog.dart';

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

/// Rueckgabewert des Bonzuordnung-Bottom-Sheets: `receiptItemId` null bedeutet "loesen".
class _ReceiptLinkChoice {
  const _ReceiptLinkChoice(this.receiptItemId);
  final String? receiptItemId;
}

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
  late Product? _product = widget.product;
  ReceiptLink? _receiptLink;

  InventoryRepository get _repo => ref.read(inventoryRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _loadReceiptLink();
  }

  Future<void> _loadReceiptLink() async {
    final link = await _repo.receiptLinkFor(_item.receiptItemId);
    if (mounted) setState(() => _receiptLink = link);
  }

  Future<void> _refresh() async {
    final fresh = await (ref.read(databaseProvider).select(ref.read(databaseProvider).inventoryItems)
          ..where((i) => i.id.equals(_item.id)))
        .getSingleOrNull();
    if (fresh != null && mounted) setState(() => _item = fresh);
  }

  Packaging get _packaging => packagingOf(_product, _item.unit).forStockUnit(_item.unit);

  /// Plus ist eine Korrektur (es ist mehr da als gedacht), Minus ein Verbrauch (ADR-045). Der letzte Rest macht den Eintrag zu "Aufgebraucht".
  Future<void> _addStep() async {
    await _repo.adjustQuantity(_item.id, roundQuantity(_item.quantity + _packaging.step.amount));
    await _refresh();
  }

  Future<void> _consumeStep() async {
    final emptied = await _repo.consumePart(
      _item.id,
      _packaging.step.amount,
      opens: !_packaging.isIndividuallyPacked,
      openedShelfLifeDays: _product?.openedShelfLifeDays,
    );
    if (emptied) {
      _leaveEmptied();
    } else {
      await _refresh();
    }
  }

  void _leaveEmptied() {
    if (!mounted) return;
    final repo = _repo;
    final id = _item.id;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        key: const Key('item-emptied'),
        content: const Text('Als aufgebraucht markiert'),
        persist: false,
        action: SnackBarAction(label: 'Rückgängig', onPressed: () => repo.reopen(id)),
      ));
    context.pop();
  }

  /// Die Menge eintippen ist eine Inventur, keine Entnahme. 0 heisst aufgebraucht: ein aktiver Eintrag ohne Menge hilft niemandem.
  Future<void> _enterQuantity() async {
    final packaging = _packaging;
    final result = await showQuantityDialog(
      context,
      keyPrefix: 'quantity',
      initialAmount: _item.quantity,
      initialOption: packaging.bestOption(_item.quantity),
      options: packaging.options,
      preview: (amount, _) => packaging.describe(amount),
      allowZero: true,
    );
    if (result == null) return;
    if (result.amount == 0) {
      await _repo.markConsumed(_item.id);
      _leaveEmptied();
      return;
    }
    await _repo.adjustQuantity(_item.id, result.amount);
    await _refresh();
  }

  Future<void> _changeDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _item.bestBefore ?? appClock.now(),
      firstDate: appClock.now().subtract(const Duration(days: 3650)),
      lastDate: appClock.now().add(const Duration(days: 3650)),
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
    await _repo.open(_item.id, productDefaultOpenShelfLifeDays: _product?.openedShelfLifeDays);
    await _refresh();
  }

  /// Produktname direkt hier umbenennen, ohne den Umweg ueber Einstellungen -> Meine Produkte (Wunsch
  /// "intuitiver", 2026-09-28): betrifft alle Kaeufe dieses Produkts, das ist so gewollt.
  Future<void> _renameProduct() async {
    final product = _product;
    if (product == null) return;
    final ctrl = TextEditingController(text: product.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Produktname'),
        content: TextField(key: const Key('product-name-input'), controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Übernehmen')),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == product.name) return;
    final updated = product.copyWith(name: name);
    await ref.read(productRepositoryProvider).update(updated);
    if (mounted) setState(() => _product = updated);
  }

  /// Fuer seltenere Aenderungen (Kategorie, Einheit, Haltbarkeit, Aliase) weiterhin das volle Formular.
  Future<void> _editProduct() async {
    final product = _product;
    if (product == null) return;
    final updated = await context.push<Product>('/product-form', extra: ProductFormArgs(existing: product));
    if (updated != null && mounted) {
      setState(() => _product = updated);
      await _refresh(); // das Formular kann den Bestand auf eine neue Einheit umgerechnet haben
    }
  }

  /// Bonzuordnung loesen oder neu setzen (Fehlerbericht "Bonzuordnung anzeigen", erweitert 2026-09-28: soll
  /// auch aenderbar sein, nicht nur anzeigbar).
  Future<void> _changeReceiptLink() async {
    final candidates = await _repo.candidateReceiptLinksFor(_item.productId);
    final others = await _repo.otherReceiptLinksFor(_item.productId);
    if (!mounted) return;
    var query = '';
    final choice = await showModalBottomSheet<_ReceiptLinkChoice>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheetState) {
        final q = query.trim().toLowerCase();
        final shown = q.isEmpty ? others : others.where((c) => c.rawText.toLowerCase().contains(q) || (c.productName?.toLowerCase().contains(q) ?? false)).toList();
        Widget tile(ReceiptLink c) => ListTile(
              key: Key('receipt-link-candidate-${c.receiptItemId}'),
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text(c.storeChain ?? 'Bon'),
              subtitle: Text([
                '${_formatDate(c.purchasedAt)} · „${c.rawText}“',
                if (c.productName != null && c.productName != _product?.name) 'bisher bei ${c.productName}',
              ].join('\n')),
              trailing: c.lineTotalCents == null ? null : Text(formatEuro(c.lineTotalCents!)),
              onTap: () => Navigator.pop(ctx, _ReceiptLinkChoice(c.receiptItemId)),
            );
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (_receiptLink != null)
                    ListTile(
                      key: const Key('receipt-link-remove'),
                      leading: const Icon(Icons.link_off),
                      title: const Text('Zuordnung lösen'),
                      subtitle: const Text('Wird zu einem reinen Scan ohne Bon-Herkunft'),
                      onTap: () => Navigator.pop(ctx, const _ReceiptLinkChoice(null)),
                    ),
                  if (candidates.isEmpty && others.isEmpty && _receiptLink == null)
                    const Padding(padding: EdgeInsets.all(16), child: Text('Keine passenden Bon-Positionen gefunden.')),
                  for (final c in candidates) tile(c),
                  if (others.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: TextField(
                        key: const Key('receipt-link-search'),
                        decoration: const InputDecoration(labelText: 'Andere Bon-Positionen durchsuchen', prefixIcon: Icon(Icons.search)),
                        onChanged: (v) => setSheetState(() => query = v),
                      ),
                    ),
                    for (final c in shown) tile(c),
                    if (shown.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Nichts gefunden.')),
                  ],
                ],
              ),
            ),
          ),
        );
      }),
    );
    if (choice == null) return;
    await _repo.setReceiptLink(_item.id, choice.receiptItemId);
    await _refresh();
    await _loadReceiptLink();
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

  /// Eigene Erinnerungsstufen fuer dieses Produkt (Ausbau 1.14). "Wie Standard" entfernt sie wieder (leere Liste).
  Future<void> _editStages(List<int> standard, List<int>? own) async {
    final picked = await showExpiryStagesDialog(
      context,
      initial: own ?? standard,
      title: 'Erinnerungen für dieses Produkt',
      helper: 'Gilt für alle Packungen dieses Produkts. „Wie Standard“ nimmt die Zeitpunkte aus den Einstellungen.',
      allowInherit: true,
    );
    if (picked == null) return;
    try {
      await ref.read(householdPrefsRepositoryProvider).set(expiryStagesPrefFor(_item.productId), picked);
      ref.invalidate(householdPrefsOnceProvider);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Speichern nicht möglich.')));
      return;
    }
    // sofort neu planen; scheitert das, gilt es beim naechsten App-Start
    try {
      await rescheduleExpiryReminders(ref);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final today = appClock.now();
    final prefs = ref.watch(householdPrefsOnceProvider).value ?? const <String, Object?>{};
    final ownStages = parseExpiryStages(prefs[expiryStagesPrefFor(_item.productId)]);
    final standardStages = parseExpiryStages(prefs[expiryStagesPref]) ?? const [1];
    final level = expiryLevel(expiresOn: _item.expiresOn, dateKind: _item.dateKind, today: today);
    final color = switch (level) {
      ExpiryLevel.expired => t.colorScheme.error,
      ExpiryLevel.soon => Colors.amber.shade800,
      ExpiryLevel.ok => Colors.green.shade700,
      ExpiryLevel.unknown => t.colorScheme.onSurfaceVariant,
    };
    final movements = ref.watch(inventoryMovementsStreamProvider(_item.productId)).value ?? const <InventoryMovement>[];
    final ownMovements = movements.where((m) => m.inventoryItemId == _item.id).toList();

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          key: const Key('product-name-tap'),
          onTap: _product == null ? null : _renameProduct,
          child: Text(_product?.name ?? 'Unbekanntes Produkt'),
        ),
        actions: [
          if (_product != null)
            IconButton(
              key: const Key('action-edit-product'),
              tooltip: 'Weitere Produktdetails bearbeiten',
              icon: const Icon(Icons.tune),
              onPressed: _editProduct,
            ),
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
                IconButton(key: const Key('quantity-minus'), tooltip: '${_packaging.step.label} verbraucht', iconSize: 32, onPressed: _consumeStep, icon: const Icon(Icons.remove_circle_outline)),
                Expanded(
                  child: InkWell(
                    key: const Key('quantity-tap'),
                    onTap: _enterQuantity,
                    child: Column(children: [
                      Text(describeStock(_item.quantity, _item.unit, _product), key: const Key('quantity-text'), style: t.textTheme.headlineSmall, textAlign: TextAlign.center),
                      Text('Minus: ${_packaging.step.label} verbraucht · antippen: genaue Menge', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
                    ]),
                  ),
                ),
                IconButton(key: const Key('quantity-plus'), tooltip: '${_packaging.step.label} mehr', iconSize: 32, onPressed: _addStep, icon: const Icon(Icons.add_circle_outline)),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _receiptLink != null
                ? ListTile(
                    key: const Key('receipt-link'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: Text(_receiptLink!.storeChain ?? 'Bon', style: t.textTheme.bodyMedium),
                    subtitle: Text('${_formatDate(_receiptLink!.purchasedAt)} · „${_receiptLink!.rawText}“'),
                    trailing: _receiptLink!.lineTotalCents == null ? null : Text(formatEuro(_receiptLink!.lineTotalCents!)),
                    onTap: _changeReceiptLink,
                  )
                : TextButton.icon(
                    key: const Key('receipt-link-add'),
                    onPressed: _changeReceiptLink,
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: const Text('Bon zuordnen'),
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
              trailing: _item.bestBefore == null ? null : IconButton(key: const Key('date-clear'), tooltip: 'Datum entfernen', icon: const Icon(Icons.close), onPressed: _clearDate),
              onTap: _changeDate,
            ),
          ),
          if (_item.bestBefore == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(spacing: 8, children: [
                OutlinedButton(
                  onPressed: () async {
                    await _repo.updateDetails(_item.id, bestBefore: appClock.now().add(const Duration(days: 7)).toUtc());
                    await _refresh();
                  },
                  child: const Text('+7 Tage'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    await _repo.updateDetails(_item.id, bestBefore: appClock.now().add(const Duration(days: 14)).toUtc());
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
          const SizedBox(height: 8),
          ListTile(
            key: const Key('item-reminder-stages'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.alarm_outlined),
            title: const Text('Erinnerungen'),
            subtitle: Text(ownStages == null ? 'Wie Standard (${describeExpiryStages(standardStages)})' : describeExpiryStages(ownStages)),
            onTap: () => _editStages(standardStages, ownStages),
          ),
          if (ownMovements.isNotEmpty) ...[
            const Divider(height: 32),
            Text('Verlauf', style: t.textTheme.titleSmall),
            for (final m in ownMovements)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(_movementLabels[m.type] ?? m.type),
                subtitle: Text(_formatDate(m.occurredAt)),
                trailing: Text('${m.quantityDelta > 0 ? '+' : '−'}${formatListAmount(m.quantityDelta.abs(), m.unit)}'),
              ),
          ],
        ],
      ),
    );
  }
}
