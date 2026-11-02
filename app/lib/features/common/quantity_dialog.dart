import 'package:flutter/material.dart';

import '../../data/local/database.dart';
import '../../domain/products/packaging.dart';
import '../../domain/shopping_list/list_quantity.dart';

/// Die Packungsdaten eines Produkts; ohne Produkt nur die Einheit des Eintrags.
Packaging packagingOf(Product? p, String unit) =>
    p == null ? Packaging(baseUnit: unit) : Packaging(baseUnit: p.baseUnit, rawPackSize: p.packSize, rawPiecesPerPack: p.piecesPerPack, pieceLabel: p.pieceLabel);

/// Ein Bestand als Text, in seiner eigenen Einheit, wenn sie nicht zum Produkt passt (dann gelten dessen Packungsdaten nicht).
String describeStock(double amount, String unit, Product? product) => packagingOf(product, unit).forStockUnit(unit).describe(amount);

/// Ergebnis des Mengendialogs: die Menge in Grundeinheit und die Einheit, in der sie steht.
typedef QuantityResult = ({double amount, String unit});

/// Der eine Mengendialog der App (ADR-045): Zahl, Einheit passend zum Produkt und darunter in Worten, was das ergibt. [options] und [preview]
/// kommen von [Packaging]; ohne Produkt (frei getippter Eintrag) stehen alle Einheiten zur Wahl.
Future<QuantityResult?> showQuantityDialog(
  BuildContext context, {
  required String keyPrefix,
  required double initialAmount,
  required QuantityOption initialOption,
  required List<QuantityOption> options,
  required String Function(double amount, String unit) preview,
  bool allowZero = false,
  String? hint,
}) =>
    showDialog<QuantityResult>(
      context: context,
      builder: (_) => _QuantityDialog(
        keyPrefix: keyPrefix,
        initialAmount: initialAmount,
        initialOption: initialOption,
        options: options,
        preview: preview,
        allowZero: allowZero,
        hint: hint,
      ),
    );

class _QuantityDialog extends StatefulWidget {
  const _QuantityDialog({
    required this.keyPrefix,
    required this.initialAmount,
    required this.initialOption,
    required this.options,
    required this.preview,
    required this.allowZero,
    this.hint,
  });

  final String keyPrefix;
  final double initialAmount;
  final QuantityOption initialOption;
  final List<QuantityOption> options;
  final String Function(double amount, String unit) preview;
  final bool allowZero;
  final String? hint;

  @override
  State<_QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<_QuantityDialog> {
  late QuantityOption _option = widget.initialOption;
  late final _ctrl = TextEditingController(text: formatListNumberExact(widget.initialAmount / widget.initialOption.toBase));
  var _showError = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Die Eingabe in Grundeinheit, `null` wenn sie ungueltig ist oder nach dem Runden nichts uebrig bleibt.
  double? get _amount {
    final v = parseQuantityInput(_ctrl.text);
    if (v == null || v < 0) return null;
    final amount = roundQuantity(v * _option.toBase);
    if (amount > 999999) return null;
    if (amount == 0) return widget.allowZero && v == 0 ? 0 : null;
    return amount;
  }

  /// Wechselt die Einheit, die eingegebene Menge bleibt dieselbe: aus "1 Packung" werden "6 Fläschchen", nicht "1 Fläschchen".
  void _changeOption(QuantityOption next) {
    final amount = _amount;
    setState(() {
      _option = next;
      if (amount != null) _ctrl.text = formatListNumberExact(amount / next.toBase);
    });
  }

  void _submit() {
    final amount = _amount;
    if (amount == null) {
      setState(() => _showError = true);
      return;
    }
    Navigator.pop(context, (amount: amount, unit: _option.baseUnit));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final amount = _amount;
    return AlertDialog(
      title: const Text('Menge'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          key: Key('${widget.keyPrefix}-input'),
          controller: _ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Menge', errorText: _showError && amount == null ? 'Bitte eine Menge ${widget.allowZero ? 'ab 0' : 'größer als 0'} eingeben' : null),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 8),
        DropdownButton<QuantityOption>(
          key: Key('${widget.keyPrefix}-unit'),
          isExpanded: true,
          value: _option,
          items: [for (final o in widget.options) DropdownMenuItem(value: o, child: Text(o.label, overflow: TextOverflow.ellipsis))],
          onChanged: widget.options.length < 2 ? null : (o) => _changeOption(o ?? _option),
        ),
        const SizedBox(height: 8),
        if (amount != null && amount > 0)
          Text('Das sind ${widget.preview(amount, _option.baseUnit)}', key: Key('${widget.keyPrefix}-preview'), style: t.textTheme.bodySmall)
        else if (amount == 0)
          Text('Der Eintrag gilt dann als aufgebraucht', key: Key('${widget.keyPrefix}-preview'), style: t.textTheme.bodySmall),
        if (widget.hint != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(widget.hint!, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(key: Key('${widget.keyPrefix}-ok'), onPressed: _submit, child: const Text('Übernehmen')),
      ],
    );
  }
}
