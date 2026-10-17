import 'package:flutter/material.dart';

import '../../domain/notifications/expiry_stages.dart';

String _stageLabel(int days) => switch (days) {
      0 => 'Am Tag selbst',
      1 => '1 Tag vorher',
      _ => '$days Tage vorher',
    };

/// Waehlt die Stufen der Ablauf-Erinnerung (Ausbau 1.14): mehrere Zeitpunkte vor dem Ablauf, hoechstens [maxExpiryStages].
///
/// Ergebnis: die gewaehlten Stufen (mindestens eine), eine **leere Liste** bei "Wie Standard" (nur mit [allowInherit]), `null` beim
/// Abbrechen.
Future<List<int>?> showExpiryStagesDialog(
  BuildContext context, {
  required List<int> initial,
  required String title,
  String? helper,
  bool allowInherit = false,
}) {
  return showDialog<List<int>>(
    context: context,
    builder: (ctx) => _ExpiryStagesDialog(initial: initial, title: title, helper: helper, allowInherit: allowInherit),
  );
}

class _ExpiryStagesDialog extends StatefulWidget {
  const _ExpiryStagesDialog({required this.initial, required this.title, required this.helper, required this.allowInherit});
  final List<int> initial;
  final String title;
  final String? helper;
  final bool allowInherit;

  @override
  State<_ExpiryStagesDialog> createState() => _ExpiryStagesDialogState();
}

class _ExpiryStagesDialogState extends State<_ExpiryStagesDialog> {
  late final Set<int> _chosen = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final full = _chosen.length >= maxExpiryStages;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.helper != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(widget.helper!, style: t.textTheme.bodySmall)),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final s in selectableExpiryStages)
              FilterChip(
                key: Key('stage-chip-$s'),
                label: Text(_stageLabel(s)),
                selected: _chosen.contains(s),
                // bei vollen Stufen laesst sich nur noch abwaehlen
                onSelected: !_chosen.contains(s) && full
                    ? null
                    : (on) => setState(() {
                          if (on) {
                            _chosen.add(s);
                          } else {
                            _chosen.remove(s);
                          }
                        }),
              ),
          ]),
          const SizedBox(height: 8),
          Text(
            _chosen.isEmpty ? 'Wähle mindestens einen Zeitpunkt.' : describeExpiryStages(_chosen.toList()),
            key: const Key('stage-summary'),
            style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
          ),
          Text('Höchstens $maxExpiryStages Zeitpunkte. Bei einem Verbrauchsdatum kommt die Erinnerung nie früher als einen Tag vorher.', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        if (widget.allowInherit) TextButton(key: const Key('stage-inherit'), onPressed: () => Navigator.pop(context, const <int>[]), child: const Text('Wie Standard')),
        FilledButton(
          key: const Key('stage-ok'),
          onPressed: _chosen.isEmpty ? null : () => Navigator.pop(context, (_chosen.toList()..sort((a, b) => b.compareTo(a)))),
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}
