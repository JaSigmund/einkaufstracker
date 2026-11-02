import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../domain/nutrition/nutrition_targets.dart';
import 'fluid_settings.dart';

/// Richtwerte fuer die Naehrwerte festlegen (LH-MEAL-09). Die App gibt keine Werte vor und bewertet nichts
/// (Doku 15 §2): leere Felder heissen "kein Richtwert".
class TargetsPage extends ConsumerStatefulWidget {
  const TargetsPage({super.key});

  @override
  ConsumerState<TargetsPage> createState() => _TargetsPageState();
}

class _TargetsPageState extends ConsumerState<TargetsPage> {
  final _min = {for (final k in NutrientKey.values) k: TextEditingController()};
  final _max = {for (final k in NutrientKey.values) k: TextEditingController()};
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [..._min.values, ..._max.values]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(NutritionTargets t) {
    for (final k in NutrientKey.values) {
      final target = t[k];
      _min[k]!.text = target?.min == null ? '' : _show(target!.min!);
      _max[k]!.text = target?.max == null ? '' : _show(target!.max!);
    }
    _loaded = true;
  }

  String _show(double v) => (v == v.roundToDouble() ? v.toInt().toString() : v.toString()).replaceAll('.', ',');

  /// Leer = kein Wert, sonst eine Zahl >= 0. `null` mit Fehler, wenn nicht lesbar.
  ({double? value, bool ok}) _parse(String text) {
    final t = text.replaceAll(',', '.').trim();
    if (t.isEmpty) return (value: null, ok: true);
    final v = double.tryParse(t);
    if (v == null || !v.isFinite || v < 0) return (value: null, ok: false);
    return (value: v, ok: true);
  }

  Future<void> _save() async {
    var targets = const NutritionTargets();
    for (final k in NutrientKey.values) {
      final min = _parse(_min[k]!.text);
      final max = _parse(_max[k]!.text);
      if (!min.ok || !max.ok) {
        setState(() => _error = '${k.label}: Bitte eine Zahl ab 0 eingeben oder das Feld leer lassen.');
        return;
      }
      final t = NutrientTarget(min: min.value, max: max.value);
      if (!t.isConsistent) {
        setState(() => _error = '${k.label}: Die Untergrenze liegt über der Obergrenze.');
        return;
      }
      targets = targets.withTarget(k, t);
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    await ref.read(nutritionTargetsRepositoryProvider).save(targets);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(nutritionTargetsProvider);
    if (!_loaded && current.hasValue) _fill(current.value!);
    final t = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Richtwerte'),
        actions: [
          TextButton(key: const Key('targets-save'), onPressed: _saving || !_loaded ? null : _save, child: const Text('Speichern')),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!, key: const Key('targets-error'), style: TextStyle(color: t.colorScheme.error)),
                ),
              Text(
                'Richtwerte setzt du selbst, die App schlägt keine vor und bewertet nichts. '
                'Sie zeigt nur, wo ein Tag oder eine Woche im Vergleich zu deinen Werten liegt. '
                'Jedes Feld ist optional: nur eine Untergrenze („mindestens“), nur eine Obergrenze („höchstens“) oder beides.',
                style: t.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              for (final k in NutrientKey.values) _row(k),
              ListTile(
                key: const Key('targets-fluid'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.local_drink_outlined),
                title: const Text('Trinkmenge'),
                subtitle: const Text('Ziel und Erinnerung'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showFluidSettings(context),
              ),
            ]),
    );
  }

  Widget _row(NutrientKey k) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: TextField(
              key: Key('target-min-${k.jsonKey}'),
              controller: _min[k],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: '${k.label} mindestens', suffixText: k.unit, border: const OutlineInputBorder()),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              key: Key('target-max-${k.jsonKey}'),
              controller: _max[k],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: '${k.label} höchstens', suffixText: k.unit, border: const OutlineInputBorder()),
            ),
          ),
        ]),
      );
}
