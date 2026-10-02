import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../data/nutrition/bls_food_search.dart';
import '../../domain/nutrition/ingredient_nutrition.dart';

/// Was der Nutzer als Zutat ausgewaehlt hat: ein Produkt aus dem Haushalt, ein Lebensmittel aus der BLS oder ein
/// frei getippter Text ohne Naehrwerte.
class PickedIngredient {
  const PickedIngredient.product(Product this.product)
      : bls = null,
        freeText = null;
  const PickedIngredient.bls(BlsFood this.bls)
      : product = null,
        freeText = null;
  const PickedIngredient.freeText(String this.freeText)
      : product = null,
        bls = null;

  final Product? product;
  final BlsFood? bls;
  final String? freeText;
}

/// Menge, Einheit und Abzugswunsch, wie sie der Mengendialog liefert.
class IngredientQuantity {
  const IngredientQuantity(this.quantity, this.unit, this.deduct);
  final double quantity;
  final EntryUnit unit;
  final bool deduct;
}

Future<PickedIngredient?> showIngredientPicker(BuildContext context) => showModalBottomSheet<PickedIngredient>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _IngredientPickerSheet(),
    );

/// Fragt Menge und Einheit einer Zutat ab. [canDeduct] blendet "Vom Bestand abziehen" ein (nur bei Produkten),
/// [stockHint] zeigt den aktuellen Bestand daneben.
Future<IngredientQuantity?> askIngredientQuantity(
  BuildContext context, {
  required String label,
  required EntryUnit initialUnit,
  double? initialQuantity,
  bool canDeduct = false,
  bool initialDeduct = true,
  String? stockHint,
}) =>
    showDialog<IngredientQuantity>(
      context: context,
      builder: (_) => _QuantityDialog(
        label: label,
        initialUnit: initialUnit,
        initialQuantity: initialQuantity,
        canDeduct: canDeduct,
        initialDeduct: initialDeduct,
        stockHint: stockHint,
      ),
    );

class _QuantityDialog extends StatefulWidget {
  const _QuantityDialog({
    required this.label,
    required this.initialUnit,
    this.initialQuantity,
    required this.canDeduct,
    required this.initialDeduct,
    this.stockHint,
  });

  final String label;
  final EntryUnit initialUnit;
  final double? initialQuantity;
  final bool canDeduct;
  final bool initialDeduct;
  final String? stockHint;

  @override
  State<_QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<_QuantityDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialQuantity == null ? '' : formatQuantity(widget.initialQuantity!));
  late EntryUnit _unit = widget.initialUnit;
  late bool _deduct = widget.initialDeduct;

  double? get _value {
    final v = double.tryParse(_controller.text.replaceAll(',', '.').trim());
    return (v == null || v <= 0) ? null : v;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.label),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          key: const Key('ingredient-quantity'),
          controller: _controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Menge'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        SegmentedButton<EntryUnit>(
          key: const Key('ingredient-unit'),
          showSelectedIcon: false,
          segments: [
            for (final u in const [EntryUnit.g, EntryUnit.ml, EntryUnit.piece]) ButtonSegment(value: u, label: Text(u.label)),
          ],
          selected: {_unit},
          onSelectionChanged: (s) => setState(() => _unit = s.first),
        ),
        if (widget.stockHint != null)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(widget.stockHint!, style: Theme.of(context).textTheme.bodySmall)),
        if (widget.canDeduct)
          SwitchListTile(
            key: const Key('ingredient-deduct'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Vom Bestand abziehen'),
            value: _deduct,
            onChanged: (v) => setState(() => _deduct = v),
          ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(
          key: const Key('ingredient-quantity-ok'),
          onPressed: _value == null ? null : () => Navigator.pop(context, IngredientQuantity(_value!, _unit, widget.canDeduct && _deduct)),
          child: const Text('Übernehmen'),
        ),
      ],
    );
  }
}

class _IngredientPickerSheet extends ConsumerStatefulWidget {
  const _IngredientPickerSheet();

  @override
  ConsumerState<_IngredientPickerSheet> createState() => _IngredientPickerSheetState();
}

class _IngredientPickerSheetState extends ConsumerState<_IngredientPickerSheet> {
  final _search = TextEditingController();
  Timer? _debounce;
  var _query = '';
  List<BlsFood> _bls = const [];
  var _blsLoading = false;
  String? _blsError;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    setState(() => _query = text.trim());
    _debounce?.cancel();
    if (_query.length < blsSearchMinChars) {
      setState(() {
        _bls = const [];
        _blsLoading = false;
        _blsError = null;
      });
      return;
    }
    setState(() => _blsLoading = true);
    _debounce = Timer(const Duration(milliseconds: 350), () => _searchBls(_query));
  }

  Future<void> _searchBls(String query) async {
    try {
      final results = await ref.read(blsFoodSearchProvider).search(query);
      if (!mounted || query != _query) return;
      setState(() {
        _bls = results;
        _blsLoading = false;
        _blsError = null;
      });
    } on BlsSearchUnavailable {
      if (!mounted || query != _query) return;
      setState(() {
        _bls = const [];
        _blsLoading = false;
        _blsError = 'Die Lebensmitteldatenbank ist gerade nicht erreichbar.';
      });
    }
  }

  String _stockText(Product p, List<InventoryItem> active) {
    final total = active.where((i) => i.productId == p.id).fold<double>(0, (s, i) => s + i.quantity);
    return total <= 0 ? 'nicht im Bestand' : 'Bestand: ${formatQuantity(total)} ${p.baseUnit}';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final products = ref.watch(productsStreamProvider).value ?? const <Product>[];
    final active = ref.watch(activeInventoryStreamProvider).value ?? const <InventoryItem>[];
    final q = _query.toLowerCase();
    final matches = q.isEmpty ? const <Product>[] : products.where((p) => p.deletedAt == null && p.name.toLowerCase().contains(q)).take(20).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              key: const Key('picker-search'),
              controller: _search,
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Zutat suchen'),
              onChanged: _onChanged,
            ),
          ),
          Expanded(
            child: ListView(children: [
              if (_query.isEmpty)
                const Padding(padding: EdgeInsets.all(16), child: Text('Tippe den Namen einer Zutat, z.B. "Reis" oder "Paprika".')),
              if (matches.isNotEmpty) ...[
                Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: Text('Aus deinen Produkten', style: t.textTheme.titleSmall)),
                for (final p in matches)
                  ListTile(
                    key: Key('pick-product-${p.id}'),
                    leading: const Icon(Icons.kitchen_outlined),
                    title: Text(p.name),
                    subtitle: Text('${_stockText(p, active)}${p.nutrientsPer100 == null ? ' · ohne Nährwerte' : ''}'),
                    onTap: () => Navigator.pop(context, PickedIngredient.product(p)),
                  ),
              ],
              if (_query.length >= blsSearchMinChars) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text('Lebensmitteldatenbank (BLS)', style: t.textTheme.titleSmall),
                ),
                if (_blsLoading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
                else if (_blsError != null)
                  Padding(padding: const EdgeInsets.all(16), child: Text(_blsError!, key: const Key('picker-bls-error')))
                else if (_bls.isEmpty)
                  const Padding(padding: EdgeInsets.all(16), child: Text('Keine Treffer in der Datenbank.', key: Key('picker-bls-empty')))
                else
                  for (final f in _bls)
                    ListTile(
                      key: Key('pick-bls-${f.code}'),
                      leading: const Icon(Icons.eco_outlined),
                      title: Text(f.nameDe),
                      subtitle: Text(f.per100.kcal == null ? 'ohne Energieangabe' : '${formatKcal(f.per100.kcal!)} je 100 g'),
                      onTap: () => Navigator.pop(context, PickedIngredient.bls(f)),
                    ),
              ],
              if (_query.isNotEmpty)
                ListTile(
                  key: const Key('pick-freetext'),
                  leading: const Icon(Icons.edit_outlined),
                  title: Text('"$_query" als Freitext hinzufügen'),
                  subtitle: const Text('ohne Nährwerte, zählt in der Auswertung als nicht erfasst'),
                  onTap: () => Navigator.pop(context, PickedIngredient.freeText(_query)),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
