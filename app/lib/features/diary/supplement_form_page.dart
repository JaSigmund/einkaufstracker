import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/local/database.dart';
import '../../domain/nutrition/micros.dart';
import '../../domain/nutrition/nutrient_registry.dart';
import '../../domain/nutrition/supplements.dart';

/// Einheiten, die man mit einem Tipp waehlen kann (frei ueberschreibbar).
const supplementUnits = ['Tablette', 'Kapsel', 'Messlöffel', 'Tropfen', 'Portion'];

/// Ergaenzung anlegen oder bearbeiten (Phase N4, ADR-035): Name, Einheit und die Mengen je Einheit laut Packung.
class SupplementFormPage extends ConsumerStatefulWidget {
  const SupplementFormPage({super.key, this.existing});

  final Supplement? existing;

  @override
  ConsumerState<SupplementFormPage> createState() => _SupplementFormPageState();
}

class _SupplementFormPageState extends ConsumerState<SupplementFormPage> {
  late final TextEditingController _name;
  late final TextEditingController _unit;

  /// Gewaehlte Naehrstoffe in der Reihenfolge des Hinzufuegens, je mit eigenem Eingabefeld.
  final _amounts = <String, TextEditingController>{};
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    _name = TextEditingController(text: s?.name ?? '');
    _unit = TextEditingController(text: s?.servingLabel ?? supplementUnits.first);
    final micros = s == null ? null : parseMicros(s.micros);
    if (micros != null) {
      for (final d in nutrientRegistry) {
        final v = micros[d.key];
        if (v != null) _amounts[d.key] = TextEditingController(text: _show(v));
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    for (final c in _amounts.values) {
      c.dispose();
    }
    super.dispose();
  }

  static String _show(double v) => (v == v.roundToDouble() ? v.toInt().toString() : v.toString()).replaceAll('.', ',');

  Future<void> _addNutrient() async {
    final def = await showDialog<NutrientDef>(
      context: context,
      builder: (ctx) => _NutrientPicker(taken: _amounts.keys.toSet()),
    );
    if (def != null) setState(() => _amounts.putIfAbsent(def.key, () => TextEditingController()));
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    final micros = <String, double>{};
    for (final e in _amounts.entries) {
      final v = parseAmount(e.value.text);
      if (v != null && v > 0) micros[e.key] = v;
    }
    if (_name.text.trim().isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Gib einen Namen ein.')));
      return;
    }
    if (_unit.text.trim().isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Gib an, was eine Einheit ist, zum Beispiel Tablette.')));
      return;
    }
    if (micros.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Füge mindestens einen Wert mit einer Menge über 0 hinzu.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(supplementRepositoryProvider).save(id: widget.existing?.id, name: _name.text, servingLabel: _unit.text, micros: micros);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Speichern nicht möglich.')));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Ergänzung anlegen' : 'Ergänzung bearbeiten'),
        actions: [TextButton(key: const Key('supp-save'), onPressed: _saving ? null : _save, child: const Text('Speichern'))],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        TextField(key: const Key('supp-name'), controller: _name, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Name', hintText: 'z. B. Vitamin D3')),
        const SizedBox(height: 12),
        TextField(key: const Key('supp-unit'), controller: _unit, decoration: const InputDecoration(labelText: 'Eine Einheit ist', helperText: 'Die Mengen unten gelten je Einheit')),
        Wrap(spacing: 8, children: [
          for (var i = 0; i < supplementUnits.length; i++)
            ActionChip(key: Key('supp-unit-chip-$i'), label: Text(supplementUnits[i]), onPressed: () => setState(() => _unit.text = supplementUnits[i])),
        ]),
        const SizedBox(height: 16),
        Text('Inhalt je Einheit laut Packung', style: t.textTheme.titleSmall),
        for (final e in _amounts.entries) _row(e.key, e.value),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(key: const Key('supp-add-nutrient'), onPressed: _addNutrient, icon: const Icon(Icons.add), label: const Text('Wert hinzufügen')),
        ),
      ]),
    );
  }

  Widget _row(String key, TextEditingController c) {
    final def = nutrientDef(key)!;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        Expanded(child: Text(def.label)),
        const SizedBox(width: 8),
        SizedBox(
          width: 120,
          child: TextField(
            key: Key('supp-amount-$key'),
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.end,
            decoration: InputDecoration(isDense: true, suffixText: def.unit),
          ),
        ),
        IconButton(
          key: Key('supp-remove-$key'),
          tooltip: 'Entfernen',
          icon: const Icon(Icons.close),
          onPressed: () => setState(() => _amounts.remove(key)?.dispose()),
        ),
      ]),
    );
  }
}

/// Auswahl eines Naehrstoffs aus dem Register mit Filter. Bereits gewaehlte fehlen.
class _NutrientPicker extends StatefulWidget {
  const _NutrientPicker({required this.taken});
  final Set<String> taken;

  @override
  State<_NutrientPicker> createState() => _NutrientPickerState();
}

class _NutrientPickerState extends State<_NutrientPicker> {
  var _filter = '';

  @override
  Widget build(BuildContext context) {
    final q = _filter.trim().toLowerCase();
    final defs = [
      for (final d in nutrientRegistry)
        if (!widget.taken.contains(d.key) && (q.isEmpty || d.label.toLowerCase().contains(q))) d,
    ];
    return AlertDialog(
      title: const Text('Welcher Wert?'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(key: const Key('supp-picker-filter'), autofocus: true, decoration: const InputDecoration(hintText: 'Suchen', prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() => _filter = v)),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final d in defs)
                ListTile(key: Key('supp-pick-${d.key}'), dense: true, title: Text(d.label), trailing: Text(d.unit), onTap: () => Navigator.pop(context, d)),
              if (defs.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Nichts gefunden.')),
            ]),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen'))],
    );
  }
}
