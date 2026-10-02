import 'package:flutter/material.dart';

import '../../domain/nutrition/nutrient_scaling.dart';

/// Ergebnis des Dialogs "Nährwerte eintragen": Bezeichnung und die absoluten Werte der ganzen Portion.
class ManualNutrientEntry {
  const ManualNutrientEntry(this.name, this.nutrients);
  final String name;
  final NutrientAmounts nutrients;
}

/// Handeingabe der Naehrwerte fuer Essen ohne Zutatenliste, z.B. im Restaurant (Doku 15 §3.3): Bezeichnung, kcal und
/// optional Eiweiss, Fett und Kohlenhydrate fuer die ganze Portion. Ein Wert, den man nicht kennt, bleibt leer und
/// zaehlt dann als "nicht bekannt", nicht als 0.
Future<ManualNutrientEntry?> askManualNutrients(
  BuildContext context, {
  required String initialName,
  NutrientAmounts? initial,
}) =>
    showDialog<ManualNutrientEntry>(
      context: context,
      builder: (_) => _ManualNutrientsDialog(initialName: initialName, initial: initial),
    );

class _ManualNutrientsDialog extends StatefulWidget {
  const _ManualNutrientsDialog({required this.initialName, this.initial});

  final String initialName;
  final NutrientAmounts? initial;

  @override
  State<_ManualNutrientsDialog> createState() => _ManualNutrientsDialogState();
}

class _ManualNutrientsDialogState extends State<_ManualNutrientsDialog> {
  late final _name = TextEditingController(text: widget.initialName);
  late final _kcal = TextEditingController(text: _show(widget.initial?.kcal));
  late final _protein = TextEditingController(text: _show(widget.initial?.proteinG));
  late final _fat = TextEditingController(text: _show(widget.initial?.fatG));
  late final _carbs = TextEditingController(text: _show(widget.initial?.carbsG));
  String? _error;

  static String _show(double? v) => v == null ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString()).replaceAll('.', ',');

  @override
  void dispose() {
    for (final c in [_name, _kcal, _protein, _fat, _carbs]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Leer = nicht bekannt (`null`), sonst eine Zahl ab 0. `ok` false bei Unlesbarem.
  ({double? value, bool ok}) _parse(String text) {
    final t = text.replaceAll(',', '.').trim();
    if (t.isEmpty) return (value: null, ok: true);
    final v = double.tryParse(t);
    return (v == null || !v.isFinite || v < 0) ? (value: null, ok: false) : (value: v, ok: true);
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return setState(() => _error = 'Bitte eine Bezeichnung eingeben.');
    final kcal = _parse(_kcal.text), protein = _parse(_protein.text), fat = _parse(_fat.text), carbs = _parse(_carbs.text);
    if (![kcal, protein, fat, carbs].every((p) => p.ok)) return setState(() => _error = 'Bitte nur Zahlen ab 0 eingeben.');
    if (kcal.value == null && protein.value == null && fat.value == null && carbs.value == null) {
      return setState(() => _error = 'Bitte mindestens einen Wert eintragen.');
    }
    Navigator.pop(
      context,
      ManualNutrientEntry(name, NutrientAmounts(kcal: kcal.value, proteinG: protein.value, fatG: fat.value, carbsG: carbs.value)),
    );
  }

  Widget _field(Key key, TextEditingController c, String label, {String? suffix}) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextField(
          key: key,
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, suffixText: suffix, border: const OutlineInputBorder()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nährwerte eintragen'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Für die ganze Portion, z.B. aus der Speisekarte oder geschätzt. Unbekanntes bleibt leer.'),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, key: const Key('manual-error'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextField(
              key: const Key('manual-name'),
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Bezeichnung', border: OutlineInputBorder()),
            ),
          ),
          _field(const Key('manual-kcal'), _kcal, 'Energie', suffix: 'kcal'),
          _field(const Key('manual-protein'), _protein, 'Eiweiß', suffix: 'g'),
          _field(const Key('manual-fat'), _fat, 'Fett', suffix: 'g'),
          _field(const Key('manual-carbs'), _carbs, 'Kohlenhydrate', suffix: 'g'),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(key: const Key('manual-ok'), onPressed: _submit, child: const Text('Übernehmen')),
      ],
    );
  }
}
