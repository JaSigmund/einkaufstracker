import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../data/nutrition/bls_food_search.dart';
import '../../domain/nutrition/food_unit.dart';
import '../../domain/nutrition/ingredient_nutrition.dart';
import '../../domain/nutrition/nutrient_scaling.dart';

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
///
/// Haushaltseinheiten (Stueck, Scheibe, EL ...) kommen als [EntryUnit.piece] mit dem Namen in [unitKey] und dem Gewicht einer
/// Einheit in [unitWeightG] (Phase N2, ADR-033): in der Datenbank steht die Menge in Einheiten, die Rechnung laeuft ueber das Gewicht.
class IngredientQuantity {
  const IngredientQuantity(this.quantity, this.unit, this.deduct, {this.unitKey, this.unitWeightG, this.learnWeight = false});
  final double quantity;
  final EntryUnit unit;
  final bool deduct;

  /// Welche Haushaltseinheit gemeint ist, `null` bei Gramm und Milliliter (und bei "Stk" ohne Angabe).
  final FoodUnitKey? unitKey;

  /// Gewicht von 1 [unitKey] in g, `null` wenn die Einheit Gramm/Milliliter ist oder das Gewicht unbekannt blieb.
  final double? unitWeightG;

  /// Der Nutzer hat das Stueckgewicht selbst eingetragen: die App merkt es sich fuer dieses Lebensmittel.
  final bool learnWeight;
}

/// [initialQuery] fuellt das Suchfeld vor und startet die Suche sofort, z.B. mit dem Namen einer Zutat, die die
/// Foto-Analyse ohne Naehrwerte erkannt hat.
Future<PickedIngredient?> showIngredientPicker(BuildContext context, {String initialQuery = ''}) =>
    showModalBottomSheet<PickedIngredient>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _IngredientPickerSheet(initialQuery: initialQuery),
    );

/// Fragt Menge und Einheit einer Zutat ab. [canDeduct] blendet "Vom Bestand abziehen" ein (nur bei Produkten),
/// [stockHint] zeigt den aktuellen Bestand daneben.
///
/// Phase N2 (ADR-033): [units] sind die fuer dieses Lebensmittel bekannten Haushaltsmasse (Tabelle `food_units`), [pieceWeightG]
/// das schon bekannte Gewicht von 1 Stueck (eigenes Gewicht des Haushalts oder des Produkts). Der Dialog zeigt nur Einheiten,
/// die er umrechnen kann; waehlt jemand "Stk" ohne bekanntes Gewicht, fragt er einmal danach. Mit [per100] steht die Umrechnung
/// sofort da ("1 Stk ≈ 118 g · 97 kcal"). [initialUnitKey] und [initialUnitWeightG] stellen eine gespeicherte Zeile wieder her.
Future<IngredientQuantity?> askIngredientQuantity(
  BuildContext context, {
  required String label,
  required EntryUnit initialUnit,
  double? initialQuantity,
  bool canDeduct = false,
  bool initialDeduct = true,
  String? stockHint,
  List<FoodUnit> units = const [],
  double? pieceWeightG,
  String pieceWeightSource = 'household',
  NutrientsPer100? per100,
  FoodUnitKey? initialUnitKey,
  double? initialUnitWeightG,
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
        units: units,
        pieceWeightG: pieceWeightG,
        pieceWeightSource: pieceWeightSource,
        per100: per100,
        initialUnitKey: initialUnitKey,
        initialUnitWeightG: initialUnitWeightG,
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
    this.units = const [],
    this.pieceWeightG,
    this.pieceWeightSource = 'household',
    this.per100,
    this.initialUnitKey,
    this.initialUnitWeightG,
  });

  final String label;
  final EntryUnit initialUnit;
  final double? initialQuantity;
  final bool canDeduct;
  final bool initialDeduct;
  final String? stockHint;
  final List<FoodUnit> units;
  final double? pieceWeightG;
  final String pieceWeightSource;
  final NutrientsPer100? per100;
  final FoodUnitKey? initialUnitKey;
  final double? initialUnitWeightG;

  @override
  State<_QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<_QuantityDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialQuantity == null ? '' : formatQuantity(widget.initialQuantity!));
  final _weightController = TextEditingController();
  late EntryUnit _unit = widget.initialUnit;

  /// Welche Haushaltseinheit gewaehlt ist; nur bei [EntryUnit.piece] gesetzt ("Stk" ist [FoodUnitKey.piece]).
  late FoodUnitKey? _key = widget.initialUnit == EntryUnit.piece ? (widget.initialUnitKey ?? FoodUnitKey.piece) : null;

  /// Eine Groesse der Tabelle, die der Nutzer gewaehlt hat (je Einheit), und ob er das Gewicht selbst aendern will.
  final _picked = <FoodUnitKey, FoodUnit>{};
  late var _editWeight = false;
  late bool _deduct = widget.initialDeduct;

  double? get _value {
    final v = double.tryParse(_controller.text.replaceAll(',', '.').trim());
    return (v == null || v <= 0) ? null : v;
  }

  double? get _typedWeight {
    final v = double.tryParse(_weightController.text.replaceAll(',', '.').trim());
    return (v == null || v <= 0 || v > 5000) ? null : v;
  }

  /// Gewicht und Herkunft von 1 [key], in der Reihenfolge: selbst eingetragen, gewaehlte Groesse, bekanntes Stueckgewicht
  /// (Haushalt/Produkt), Tabellenwert.
  ({double grams, String source})? _weightOf(FoodUnitKey key) {
    if (key == _key && _typedWeight != null) return (grams: _typedWeight!, source: 'own');
    final chosen = _picked[key];
    if (chosen != null) return (grams: chosen.gramsEdible, source: chosen.source);
    // Eine gespeicherte Zeile bringt ihr Gewicht mit: es gilt, bis jemand etwas anderes waehlt (und wird nicht "gelernt")
    final saved = widget.initialUnitWeightG;
    if (saved != null && saved > 0 && widget.initialUnit == EntryUnit.piece && key == (widget.initialUnitKey ?? FoodUnitKey.piece)) {
      return (grams: saved, source: 'saved');
    }
    if (key == FoodUnitKey.piece && widget.pieceWeightG != null) return (grams: widget.pieceWeightG!, source: widget.pieceWeightSource);
    final table = defaultUnit(widget.units, key);
    return table == null ? null : (grams: table.gramsEdible, source: table.source);
  }

  /// Einheiten zur Auswahl: Gramm, Milliliter, Stueck immer (ohne bekanntes Gewicht fragt der Dialog danach), dazu alles, was die
  /// Tabelle fuer dieses Lebensmittel kennt.
  List<FoodUnitKey> get _keys => [FoodUnitKey.piece, ...unitKeysOf(widget.units).where((k) => k != FoodUnitKey.piece)];

  void _selectKey(FoodUnitKey k) => setState(() {
        _unit = EntryUnit.piece;
        _key = k;
        _editWeight = false;
      });

  String _sourceText(String source) => switch (source) {
        'own' || 'household' => 'dein Gewicht',
        'saved' => 'wie gespeichert',
        'product' => 'vom Produkt',
        'off' => 'Packungsangabe',
        'llm_estimate' => 'geschätzt',
        _ => 'Richtwert',
      };

  @override
  void dispose() {
    _controller.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Widget _unitChips() {
    return Wrap(key: const Key('ingredient-unit'), spacing: 8, runSpacing: 4, children: [
      for (final u in const [EntryUnit.g, EntryUnit.ml])
        ChoiceChip(
          key: Key('ingredient-unit-${u.name}'),
          label: Text(u.label),
          selected: _unit == u,
          onSelected: (_) => setState(() {
            _unit = u;
            _key = null;
          }),
        ),
      for (final k in _keys)
        ChoiceChip(
          key: Key('ingredient-unit-${k.db}'),
          label: Text(k.singular),
          selected: _key == k,
          onSelected: (_) => _selectKey(k),
        ),
    ]);
  }

  Widget _sizeChips(FoodUnitKey key) {
    final sizes = sizesOf(widget.units, key).where((u) => u.size != UnitSize.none).toList();
    if (sizes.length < 2) return const SizedBox.shrink();
    final current = _weightOf(key)?.grams;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(key: const Key('ingredient-sizes'), spacing: 8, runSpacing: 4, children: [
        for (final u in sizes)
          ChoiceChip(
            key: Key('ingredient-size-${u.size.db}'),
            label: Text('${u.size.label} · ${formatQuantity(u.gramsEdible)} g'),
            selected: _picked[key] == u || (_picked[key] == null && current == u.gramsEdible && _typedWeight == null),
            onSelected: (_) => setState(() {
              _picked[key] = u;
              _weightController.clear();
              _editWeight = false;
            }),
          ),
      ]),
    );
  }

  Widget _fractions() {
    const fractions = [0.25, 0.5, 1.0, 1.5, 2.0];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(key: const Key('ingredient-fractions'), spacing: 8, runSpacing: 4, children: [
        for (var i = 0; i < fractions.length; i++)
          ActionChip(
            key: Key('ingredient-frac-$i'),
            label: Text(const ['¼', '½', '1', '1½', '2'][i]),
            onPressed: () => setState(() => _controller.text = formatQuantity(fractions[i])),
          ),
      ]),
    );
  }

  /// "1 Scheibe ≈ 28 g (Richtwert)" und, wenn die Naehrwerte bekannt sind, die ganze Menge: "2 Scheiben = 56 g · 130 kcal".
  List<Widget> _preview(BuildContext context) {
    final t = Theme.of(context).textTheme.bodySmall;
    final lines = <Widget>[];
    final key = _key;
    final q = _value;
    double? grams;
    if (key != null) {
      final w = _weightOf(key);
      if (w != null) {
        lines.add(Text('1 ${key.singular} ≈ ${formatQuantity(w.grams)} g (${_sourceText(w.source)})', key: const Key('ingredient-unit-info'), style: t));
        if (q != null) grams = q * w.grams;
      }
    } else if (q != null) {
      grams = _unit == EntryUnit.kg || _unit == EntryUnit.l ? q * 1000 : q;
    }
    if (grams != null && widget.per100 != null) {
      final n = scaleNutrients(per100: widget.per100!, amountG: grams);
      final amount = key == null ? '' : '${formatQuantity(q!)} ${key.labelFor(q)} = ${formatQuantity(grams)} g';
      final kcal = n.kcal == null ? null : formatKcal(n.kcal!);
      final text = [if (amount.isNotEmpty) amount, ?kcal].join(' · ');
      if (text.isNotEmpty) lines.add(Text(text, key: const Key('ingredient-preview'), style: t));
    }
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    final key = _key;
    final known = key == null ? null : _weightOf(key);
    // Ohne bekanntes Stueckgewicht fragt der Dialog einmal danach; mit bekanntem nur auf Wunsch
    final askWeight = key == FoodUnitKey.piece && (known == null || _editWeight);
    final foodName = widget.label;
    return AlertDialog(
      title: Text(widget.label),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            key: const Key('ingredient-quantity'),
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Menge'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          _unitChips(),
          if (key != null) ...[_fractions(), _sizeChips(key)],
          if (askWeight)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                key: const Key('ingredient-unit-weight'),
                controller: _weightController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Gewicht von 1 Stück in g',
                  helperText: known == null
                      ? 'Wie viel wiegt 1 Stück $foodName (ohne Schale)? Das merke ich mir. Ohne Gewicht zählt die Zutat nicht in den Nährwerten.'
                      : 'Dein Gewicht ersetzt den Richtwert und gilt künftig überall.',
                  helperMaxLines: 3,
                  suffixText: 'g',
                ),
                onChanged: (_) => setState(() {}),
              ),
            )
          else if (key == FoodUnitKey.piece && known != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('ingredient-unit-weight-edit'),
                onPressed: () => setState(() {
                  _editWeight = true;
                  _weightController.text = formatQuantity(known.grams);
                }),
                child: const Text('Gewicht ändern'),
              ),
            ),
          ..._preview(context).map((w) => Padding(padding: const EdgeInsets.only(top: 6), child: w)),
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
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(
          key: const Key('ingredient-quantity-ok'),
          onPressed: _value == null ? null : _submit,
          child: const Text('Übernehmen'),
        ),
      ],
    );
  }

  void _submit() {
    final key = _key;
    final w = key == null ? null : _weightOf(key);
    Navigator.pop(
      context,
      IngredientQuantity(
        _value!,
        _unit,
        widget.canDeduct && _deduct,
        unitKey: key,
        unitWeightG: w?.grams,
        // Nur ein selbst eingetragenes oder geaendertes Stueckgewicht wird gemerkt, nie ein Tabellenwert
        learnWeight: key == FoodUnitKey.piece && w != null && w.source == 'own',
      ),
    );
  }
}

class _IngredientPickerSheet extends ConsumerStatefulWidget {
  const _IngredientPickerSheet({this.initialQuery = ''});

  final String initialQuery;

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
  void initState() {
    super.initState();
    final q = widget.initialQuery.trim();
    if (q.isEmpty) return;
    _search.text = q;
    _query = q;
    if (q.length >= blsSearchMinChars) {
      _blsLoading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchBls(q);
      });
    }
  }

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
