import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../domain/nutrition/drink_mix.dart';
import '../../domain/nutrition/ingredient_nutrition.dart';
import '../../domain/products/packaging.dart';
import 'ingredient_picker.dart';

/// Was das Fenster liefert: das Getraenk und, falls angegeben, das Volumen von 1 Stueck, das sich die App fuer dieses Produkt merkt.
typedef DrinkSheetResult = ({DrinkDraft drink, double? pieceMl});

/// Menge und Mischverhaeltnis (Doku 26 §2.3). [drink] ist die Vorbelegung. [unknownPiece] ist ein Produkt in Stueck ohne bekanntes Volumen: Dann
/// fragt das Fenster einmal danach, und das Getraenk beginnt mit 1 Stueck.
Future<DrinkSheetResult?> showDrinkSheet(BuildContext context, {required DrinkDraft drink, Product? unknownPiece, Map<String, Product> products = const {}}) =>
    showModalBottomSheet<DrinkSheetResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DrinkSheet(drink: drink, unknownPiece: unknownPiece, products: products),
    );

/// Das Getraenk zu einer Auswahl aus der Zutatensuche, noch ohne Pruefung des Volumens.
DrinkPart drinkPartFromPicked(PickedIngredient picked, {double ml = drinkGlassMl}) {
  final product = picked.product;
  if (product != null) return DrinkPart(name: product.name, amount: ml, productId: product.id);
  final bls = picked.bls;
  if (bls != null) return DrinkPart(name: bls.nameDe, amount: ml, blsCode: bls.code, per100: bls.per100, microsPer100: bls.micros, nutrientBasis: 'bls_exact');
  return DrinkPart(name: picked.freeText!, amount: ml);
}

String _ratioLabel(int n) => n == 0 ? 'Pur' : '1:$n';

class _DrinkSheet extends StatefulWidget {
  const _DrinkSheet({required this.drink, this.unknownPiece, this.products = const {}});

  final DrinkDraft drink;
  final Product? unknownPiece;
  final Map<String, Product> products;

  @override
  State<_DrinkSheet> createState() => _DrinkSheetState();
}

class _DrinkSheetState extends State<_DrinkSheet> {
  late DrinkDraft _drink = widget.drink;
  late final _title = TextEditingController(text: widget.drink.title);
  final _pieceMl = TextEditingController();

  /// Eigene Felder je Teil. Sie werden neu aufgebaut, wenn Menge oder Verhaeltnis die Teile aendern.
  List<TextEditingController> _amounts = [];

  @override
  void initState() {
    super.initState();
    _syncAmounts();
  }

  void _syncAmounts() {
    for (final c in _amounts) {
      c.dispose();
    }
    _amounts = [for (final p in _drink.parts) TextEditingController(text: p.amount > 0 ? formatQuantity(p.amount) : '')];
  }

  @override
  void dispose() {
    _title.dispose();
    _pieceMl.dispose();
    for (final c in _amounts) {
      c.dispose();
    }
    super.dispose();
  }

  double? _parse(String text) {
    final v = double.tryParse(text.replaceAll(',', '.').trim());
    return v == null || v <= 0 ? null : v;
  }

  /// Bei einem Produkt in Stueck ohne Volumen ist das Volumen die Menge.
  bool get _needsPieceMl => widget.unknownPiece != null && _parse(_pieceMl.text) == null;

  /// Ueberschreibt die Teile, wie Menge oder Verhaeltnis sie vorgeben. Ein Titel, den der Nutzer getippt hat, bleibt.
  void _replace(DrinkDraft next) => setState(() {
        final typedTitle = _title.text;
        _drink = DrinkDraft(title: typedTitle == _drink.title ? next.title : typedTitle, parts: next.parts);
        _title.text = _drink.title;
        _syncAmounts();
      });

  void _mix(int n) {
    _commitTyped();
    _replace(_drink.mixedAt(n));
  }

  void _size(double ml) {
    _commitTyped();
    _replace(_drink.scaledTo(ml));
  }

  /// Uebernimmt, was in den Mengenfeldern steht.
  void _commitTyped() {
    final parts = [
      for (var i = 0; i < _drink.parts.length; i++) _drink.parts[i].withAmount(_parse(_amounts[i].text) ?? 0),
    ];
    _drink = DrinkDraft(title: _drink.title, parts: parts);
  }

  Future<void> _addPart() async {
    final picked = await showIngredientPicker(context);
    if (picked == null || !mounted) return;
    _commitTyped();
    setState(() {
      _drink = DrinkDraft(title: _drink.title, parts: [..._drink.parts, drinkPartFromPicked(picked, ml: 0)]);
      _syncAmounts();
    });
  }

  void _removePart(int i) {
    _commitTyped();
    setState(() {
      _drink = DrinkDraft(title: _drink.title, parts: [..._drink.parts]..removeAt(i));
      _syncAmounts();
    });
  }

  void _submit() {
    _commitTyped();
    final piece = _parse(_pieceMl.text);
    var parts = _drink.parts;
    if (widget.unknownPiece != null && piece != null) {
      // Das eingegebene Volumen ist ein Stueck des Produkts, ausser die Menge wurde selbst eingetragen
      parts = [for (final p in parts) p.productId == widget.unknownPiece!.id && p.amount <= 0 ? p.withAmount(piece) : p];
    }
    final drink = DrinkDraft(title: _title.text.trim(), parts: parts);
    if (!drink.isBookable) return setState(() {});
    Navigator.pop(context, (drink: drink, pieceMl: piece));
  }

  /// Glas und, wenn die Basis eine Packung hat, Flasche oder Dose.
  List<(String, double)> get _sizes {
    final packMl = _packMl;
    return [
      ('¼ Glas', drinkGlassMl / 4),
      ('½ Glas', drinkGlassMl / 2),
      ('1 Glas', drinkGlassMl),
      if (packMl != null) ('1 Flasche', packMl),
    ];
  }

  double? get _packMl {
    final id = _drink.base?.productId;
    final p = id == null ? null : widget.products[id];
    if (p == null || p.baseUnit != 'l') return null;
    final packaging = Packaging(baseUnit: 'l', rawPackSize: p.packSize, rawPiecesPerPack: p.piecesPerPack, pieceLabel: p.pieceLabel);
    final content = packaging.isMultipack ? packaging.contentPerPiece : packaging.contentPerPack;
    return content == null ? null : (content * 1000).roundToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final ratio = _drink.ratio;
    final sizes = _drink.parts.any((p) => p.unit == EntryUnit.ml) ? _sizes : const <(String, double)>[];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(key: const Key('drink-name'), controller: _title, maxLength: 200, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Name', counterText: '')),
            if (widget.unknownPiece != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  key: const Key('drink-piece-ml'),
                  controller: _pieceMl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Wie viel ml hat 1 Stück ${widget.unknownPiece!.name}?', helperText: 'Das merke ich mir für dieses Produkt.', suffixText: 'ml'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            if (sizes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Menge', style: t.textTheme.titleSmall),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final (label, ml) in sizes)
                  ActionChip(key: Key('drink-size-${ml.round()}'), label: Text('$label · ${formatQuantity(ml)} ml'), onPressed: () => _size(ml)),
              ]),
            ],
            if (_drink.canMix) ...[
              const SizedBox(height: 12),
              Text('Mit Wasser', style: t.textTheme.titleSmall),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final n in drinkRatios)
                  ChoiceChip(key: Key('drink-ratio-$n'), label: Text(_ratioLabel(n)), selected: ratio == n, onSelected: (_) => _mix(n)),
              ]),
            ],
            const SizedBox(height: 12),
            Text('Teile', style: t.textTheme.titleSmall),
            for (var i = 0; i < _drink.parts.length; i++)
              Padding(
                key: Key('drink-part-$i'),
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  Expanded(child: Text(_drink.parts[i].name, maxLines: 2, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 96,
                    child: TextField(
                      key: Key('drink-part-amount-$i'),
                      controller: _amounts[i],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(isDense: true, suffixText: _drink.parts[i].unit.label),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  IconButton(
                    key: Key('drink-part-remove-$i'),
                    tooltip: 'Entfernen',
                    icon: const Icon(Icons.close),
                    onPressed: _drink.parts.length > 1 ? () => _removePart(i) : null,
                  ),
                ]),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(key: const Key('drink-add-part'), onPressed: _addPart, icon: const Icon(Icons.add), label: const Text('Zutat dazu')),
            ),
            FilledButton(
              key: const Key('drink-book'),
              onPressed: _isReady ? _submit : null,
              child: const Text('Eintragen'),
            ),
          ]),
        ),
      ),
    );
  }

  bool get _isReady {
    if (_title.text.trim().isEmpty) return false;
    if (widget.unknownPiece != null && _needsPieceMl) return false;
    for (var i = 0; i < _drink.parts.length; i++) {
      final isTheUnknownPiece = widget.unknownPiece != null && _drink.parts[i].productId == widget.unknownPiece!.id;
      if (!isTheUnknownPiece && _parse(_amounts[i].text) == null) return false;
    }
    return true;
  }
}
