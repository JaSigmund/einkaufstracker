import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../domain/nutrition/daily_nutrition.dart';
import '../../domain/nutrition/nutrition_targets.dart';

/// Zeilen "Eiweiß 48 g von mindestens 60 g" mit Fortschrittsbalken, nur fuer Naehrwerte mit Richtwert.
///
/// Neutral gestaltet (Doku 15 §2): Der Balken faerbt sich nicht rot oder gruen, das Ueberschreiten einer Obergrenze
/// und das Unterschreiten einer Untergrenze werden nur benannt. [partial] kennzeichnet Werte, die wegen fehlender
/// Naehrwerte einzelner Zutaten zu niedrig sein koennen ("mindestens").
class TargetRows extends StatelessWidget {
  const TargetRows({super.key, required this.totals, required this.targets, required this.keyPrefix, this.partial = false});

  final NutrientTotals totals;
  final NutritionTargets targets;

  /// Praefix der Widget-Keys, z.B. `day-2026-10-2` oder `week`.
  final String keyPrefix;
  final bool partial;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final rows = <Widget>[];
    for (final k in NutrientKey.values) {
      final target = targets[k];
      if (target == null) continue;
      final value = totals.valueOf(k);
      final check = checkTarget(value, target);
      final note = switch (check.status) {
        TargetStatus.below => 'darunter',
        TargetStatus.above => 'darüber',
        _ => null,
      };
      final color = check.status == TargetStatus.within ? t.colorScheme.primary : t.colorScheme.tertiary;
      rows.add(Padding(
        key: Key('target-row-$keyPrefix-${k.jsonKey}'),
        padding: const EdgeInsets.only(top: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            '${k.label} ${partial ? 'mindestens ' : ''}${formatNutrient(k, value)} · ${formatTarget(k, target)}${note == null ? '' : ' ($note)'}',
            style: t.textTheme.bodySmall,
          ),
          const SizedBox(height: 2),
          LinearProgressIndicator(
            value: (check.fraction ?? 0).clamp(0.0, 1.0),
            minHeight: 4,
            color: color,
            backgroundColor: t.colorScheme.surfaceContainerHighest,
          ),
        ]),
      ));
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }
}
