import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/clock.dart';
import '../../data/local/database.dart';
import '../../domain/inventory/label_dates.dart';
import '../../domain/products/packaging.dart';
import '../common/quantity_dialog.dart';
import 'product_form_page.dart';

class StockEntryArgs {
  const StockEntryArgs({required this.product, required this.ean});
  final Product product;
  final String ean;
}

String _formatDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

const _dateKinds = [('best_before', 'Mindestens haltbar bis'), ('use_by', 'Zu verbrauchen bis')];
const _locations = [('pantry', 'Vorrat'), ('fridge', 'Kühlschrank'), ('freezer', 'Tiefkühl'), ('other', 'Sonstiges')];

/// Nach dem Barcode-Scan eines bekannten Produkts: MHD/Verbrauchsdatum, Lagerort, Menge erfassen und als
/// Bestand speichern (Doku 06 §3.5). Ist bereits Bestand vorhanden, bietet die Seite oben die Schnellaktionen
/// **Öffnen** und **Aufgebraucht** fuer den juengsten aktiven Eintrag an.
class StockEntryPage extends ConsumerStatefulWidget {
  const StockEntryPage({super.key, required this.product, required this.ean, this.labelScanAvailable = !kIsWeb});

  final Product product;
  final String ean;

  /// Das MHD-Foto (Texterkennung auf dem Geraet) gibt es nicht im Browser. Als Parameter statt einer festverdrahteten `kIsWeb`-Abfrage,
  /// damit beide Faelle testbar sind.
  final bool labelScanAvailable;

  @override
  ConsumerState<StockEntryPage> createState() => _StockEntryPageState();
}

class _StockEntryPageState extends ConsumerState<StockEntryPage> {
  DateTime? _date;
  late String _dateKind = widget.product.defaultDateKind;
  late String _location = widget.product.defaultLocation;
  late final Packaging _packaging = packagingOf(widget.product, widget.product.baseUnit);

  /// Was man eingeben kann: passend zum Produkt, danach die uebrigen Einheiten, falls das Produkt bisher falsch angelegt ist ("Für dieses Produkt
  /// merken"). Vorbelegt ist eine Packung, das ist fast immer, was gerade in der Hand liegt.
  late final List<QuantityOption> _options = [
    ..._packaging.options,
    for (final o in QuantityOption.free)
      if (!_packaging.options.any((p) => p.label == o.label)) o,
  ];
  late QuantityOption _option = _options.first;
  late final _quantity = TextEditingController(text: '1');
  var _rememberUnit = false;
  String? _quantityError;
  var _saving = false;
  var _scanning = false;

  /// MHD fotografieren (Ausbau 1.14): Text auf dem Geraet lesen, Datumsfunde zur Bestaetigung zeigen. Nichts wird ungesehen uebernommen,
  /// die Texterkennung kann sich irren.
  Future<void> _scanDate() async {
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    setState(() => _scanning = true);
    try {
      final bytes = await ref.read(labelPhotoPickerProvider)(camera: true);
      if (bytes == null) return;
      final text = await ref.read(labelTextReaderProvider).read(bytes);
      final found = extractLabelDates(text ?? '', today: appClock.now());
      // das Lesen ist fertig: der Fortschrittskreis darf nicht weiterlaufen, waehrend der Dialog auf die Auswahl wartet
      if (mounted) setState(() => _scanning = false);
      if (found.isEmpty) {
        messenger.showSnackBar(const SnackBar(content: Text('Kein Datum erkannt. Versuch es näher und gerade, oder tipp es ein.')));
        return;
      }
      if (!mounted) return;
      final choice = await showDialog<LabelDate>(context: context, builder: (ctx) => _ScanChoiceDialog(found: found));
      if (choice != null && mounted) {
        setState(() {
          _date = choice.date;
          if (choice.kind != null) _dateKind = choice.kind!;
        });
      }
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Das Foto konnte nicht gelesen werden. Tipp das Datum ein.')));
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _pickDate({int? addDays}) async {
    if (addDays != null) {
      setState(() => _date = appClock.now().add(Duration(days: addDays)));
      return;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? appClock.now(),
      firstDate: appClock.now().subtract(const Duration(days: 3650)),
      lastDate: appClock.now().add(const Duration(days: 3650)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final typed = parseQuantityInput(_quantity.text);
    final qty = typed == null ? 0.0 : roundQuantity(typed * _option.toBase);
    if (qty <= 0) {
      setState(() => _quantityError = 'Bitte eine Menge größer als 0 eingeben');
      return;
    }
    final unit = _option.baseUnit;
    setState(() {
      _quantityError = null;
      _saving = true;
    });
    try {
      if (_rememberUnit && unit != widget.product.baseUnit) {
        // Die Packungsdaten galten fuer die alte Einheit
        final updated = widget.product.copyWith(baseUnit: unit, packSize: const Value(null), piecesPerPack: const Value(null));
        await ref.read(productRepositoryProvider).update(updated);
        await ref.read(inventoryRepositoryProvider).normalizeStock(updated);
      }
      await ref.read(inventoryRepositoryProvider).recordFromScan(
            productId: widget.product.id,
            ean: widget.ean,
            quantity: qty,
            unit: unit,
            bestBefore: _date,
            dateKind: _dateKind,
            location: _location,
            openShelfLifeDays: widget.product.openedShelfLifeDays,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bestand gespeichert')));
        context.go('/inventory');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Speichern nicht möglich: $e')));
      }
    }
  }

  Future<void> _quickAction(Future<void> Function(String id) action, InventoryItem item) async {
    await action(item.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erledigt')));
      context.go('/inventory');
    }
  }

  /// Der Barcode wurde beim letzten Mal dem falschen Produkt zugeordnet: hier neu verknuepfen, ohne dass
  /// der Nutzer dazu erst woanders hinnavigieren muss (Fehlerbericht "Keine Bonzuordnung", 2026-09-28).
  Future<void> _reassign() async {
    final newProduct = await context.push<Product>('/product-form', extra: ProductFormArgs(ean: widget.ean));
    if (newProduct != null && mounted) {
      context.pushReplacement('/stock-entry', extra: StockEntryArgs(product: newProduct, ean: widget.ean));
    }
  }

  /// Was die Eingabe ergibt, nur wenn es mehr sagt als die Eingabe selbst.
  String? get _preview {
    final typed = parseQuantityInput(_quantity.text);
    if (typed == null || typed <= 0 || _option.kind == QuantityKind.amount) return null;
    return 'Das sind ${_packaging.describe(roundQuantity(typed * _option.toBase))}';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final active = ref.watch(activeInventoryStreamProvider).value ?? const <InventoryItem>[];
    final existing = active.where((i) => i.productId == widget.product.id).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.product.name),
        actions: [
          IconButton(
            key: const Key('stock-reassign'),
            tooltip: 'Falsches Produkt? Anderes verknüpfen',
            icon: const Icon(Icons.swap_horiz),
            onPressed: _reassign,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (existing.isNotEmpty) ...[
            Text('Bereits im Inventar', style: t.textTheme.titleSmall),
            for (final item in existing)
              Card(
                child: ListTile(
                  title: Text(describeStock(item.quantity, item.unit, widget.product)),
                  subtitle: Text(item.status == 'opened' ? 'Geöffnet' : 'Ungeöffnet'),
                  trailing: Wrap(spacing: 4, children: [
                    if (item.status == 'sealed')
                      OutlinedButton(
                        key: Key('quick-open-${item.id}'),
                        onPressed: () => _quickAction(
                          (id) => ref.read(inventoryRepositoryProvider).open(id, productDefaultOpenShelfLifeDays: widget.product.openedShelfLifeDays),
                          item,
                        ),
                        child: const Text('Öffnen'),
                      ),
                    OutlinedButton(
                      key: Key('quick-consumed-${item.id}'),
                      onPressed: () => _quickAction((id) => ref.read(inventoryRepositoryProvider).markConsumed(id), item),
                      child: const Text('Aufgebraucht'),
                    ),
                  ]),
                ),
              ),
            const Divider(height: 32),
            Text('Neu hinzufügen', style: t.textTheme.titleSmall),
            const SizedBox(height: 8),
          ],
          ListTile(
            key: const Key('stock-date'),
            leading: const Icon(Icons.event_outlined),
            title: Text(_date == null ? 'Kein Datum' : _formatDate(_date!)),
            subtitle: const Text('Antippen zum Ändern'),
            onTap: () => _pickDate(),
          ),
          Wrap(spacing: 8, children: [
            if (widget.labelScanAvailable)
              OutlinedButton.icon(
                key: const Key('stock-date-scan'),
                onPressed: _scanning ? null : _scanDate,
                icon: _scanning ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.photo_camera_outlined),
                label: Text(_scanning ? 'Lese Etikett …' : 'MHD fotografieren'),
              ),
            OutlinedButton(onPressed: () => _pickDate(addDays: 7), child: const Text('+7 Tage')),
            OutlinedButton(onPressed: () => _pickDate(addDays: 14), child: const Text('+14 Tage')),
            if (_date != null) TextButton(onPressed: () => setState(() => _date = null), child: const Text('Kein Datum')),
          ]),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: const Key('stock-date-kind'),
            initialValue: _dateKind,
            decoration: const InputDecoration(labelText: 'Art des Datums'),
            items: [for (final d in _dateKinds) DropdownMenuItem(value: d.$1, child: Text(d.$2))],
            onChanged: (v) => setState(() => _dateKind = v ?? _dateKind),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const Key('stock-location'),
            initialValue: _location,
            decoration: const InputDecoration(labelText: 'Lagerort'),
            items: [for (final l in _locations) DropdownMenuItem(value: l.$1, child: Text(l.$2))],
            onChanged: (v) => setState(() => _location = v ?? _location),
          ),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: TextField(
                key: const Key('stock-quantity'),
                controller: _quantity,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Menge', errorText: _quantityError),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<QuantityOption>(
                key: const Key('stock-unit'),
                isExpanded: true,
                initialValue: _option,
                decoration: const InputDecoration(labelText: 'Einheit'),
                items: [for (final o in _options) DropdownMenuItem(value: o, child: Text(o.label, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => _option = v ?? _option),
              ),
            ),
          ]),
          if (_preview case final text?) Padding(padding: const EdgeInsets.only(top: 4), child: Text(text, key: const Key('stock-preview'), style: t.textTheme.bodySmall)),
          if (_option.baseUnit != widget.product.baseUnit)
            CheckboxListTile(
              key: const Key('stock-remember-unit'),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text('Für dieses Produkt merken'),
              subtitle: const Text('Künftige Käufe schlagen dann gleich diese Einheit vor.'),
              value: _rememberUnit,
              onChanged: (v) => setState(() => _rememberUnit = v ?? false),
            ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('stock-save'),
            onPressed: _saving ? null : _save,
            child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Speichern'),
          ),
        ],
      ),
    );
  }
}

/// Die erkannten Daten zur Auswahl: das beste ist vorgewaehlt, "Uebernehmen" setzt Datum und (falls erkannt) Art.
class _ScanChoiceDialog extends StatefulWidget {
  const _ScanChoiceDialog({required this.found});
  final List<LabelDate> found;

  @override
  State<_ScanChoiceDialog> createState() => _ScanChoiceDialogState();
}

class _ScanChoiceDialogState extends State<_ScanChoiceDialog> {
  late LabelDate _selected = widget.found.first;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return AlertDialog(
      title: const Text('Erkanntes Datum'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Prüf das Datum, die Texterkennung kann sich irren.', style: t.textTheme.bodySmall),
          RadioGroup<LabelDate>(
            groupValue: _selected,
            onChanged: (v) => setState(() => _selected = v ?? _selected),
            child: Column(children: [
              for (var i = 0; i < widget.found.length; i++)
                RadioListTile<LabelDate>(
                  key: Key('scan-candidate-$i'),
                  contentPadding: EdgeInsets.zero,
                  value: widget.found[i],
                  title: Text(_formatDate(widget.found[i].date)),
                  subtitle: Text([
                    switch (widget.found[i].kind) { 'best_before' => 'Mindestens haltbar bis', 'use_by' => 'Zu verbrauchen bis', _ => 'Art nicht erkannt' },
                    '„${widget.found[i].source}“',
                  ].join(' · ')),
                ),
            ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(key: const Key('scan-accept'), onPressed: () => Navigator.pop(context, _selected), child: const Text('Übernehmen')),
      ],
    );
  }
}
