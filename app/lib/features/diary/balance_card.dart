import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../domain/nutrition/consumption_balance.dart';
import '../../core/vienna_time.dart';

/// Wochen der Verbrauchsbilanz aus den Ledger-Bewegungen der letzten 12 Wochen, neueste zuerst. `null` solange die
/// Daten noch laden.
List<WeekBalance>? weeklyBalanceOf(WidgetRef ref) {
  final movements = ref.watch(balanceMovementsProvider).value;
  if (movements == null) return null;
  final products = ref.watch(productsStreamProvider).value ?? const <Product>[];
  return buildWeeklyBalance(
    [
      for (final m in movements)
        (productId: m.productId, occurredAtUtc: m.occurredAt, type: m.type, quantityDelta: m.quantityDelta, unit: m.unit, mealId: m.mealId),
    ],
    unitWeightG: {for (final p in products) if (p.unitWeightG != null) p.id: p.unitWeightG!},
  );
}

/// Erklaerung der Grenzen der Bilanz (Doku 15 §4.1): sie ist eine Plausibilitaetspruefung, keine exakte Zahl.
const balanceLimitsText =
    'Die Bilanz zählt den ganzen Haushalt, nicht nur dich. Der Deckungsgrad sagt, welcher Anteil dessen, was aus dem '
    'Bestand abgegangen ist, durch Mahlzeiten im Tagebuch erklärt ist. Ein niedriger Wert heißt: Es fehlen Einträge, oder '
    'es wurde verbraucht, ohne es einzutragen. Nicht erfasst sind Käufe ohne Bon, Restaurant und Arbeit sowie Schalen, '
    'Kerne und Abfall, den du nicht als weggeworfen gebucht hast. Mengen in Litern zählen wie Kilogramm, Stückware nur, '
    'wenn das Stückgewicht des Produkts bekannt ist.';

Future<void> showBalanceInfo(BuildContext context) => showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wie die Bilanz rechnet'),
        content: const Text(balanceLimitsText),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );

/// Karte "Bilanz diese Woche" im Tagebuch (LH-MEAL-10).
class BalanceCard extends ConsumerWidget {
  const BalanceCard({super.key, this.now});

  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weeks = weeklyBalanceOf(ref);
    if (weeks == null) return const SizedBox.shrink();
    final today = utcToViennaLocal(now ?? DateTime.now().toUtc());
    final monday = DateTime(today.year, today.month, today.day - (today.weekday - 1));
    final week = weeks.where((w) => w.weekStart == monday).firstOrNull;
    final t = Theme.of(context);

    return Card(
      key: const Key('diary-balance'),
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Bilanz diese Woche', style: t.textTheme.titleSmall)),
            IconButton(
              key: const Key('balance-info'),
              tooltip: 'Wie die Bilanz rechnet',
              icon: const Icon(Icons.info_outline, size: 20),
              visualDensity: VisualDensity.compact,
              onPressed: () => showBalanceInfo(context),
            ),
          ]),
          if (week == null || !week.hasData)
            Text('Diese Woche gibt es noch keine Bestandsbewegung.', key: const Key('balance-empty'), style: t.textTheme.bodyMedium)
          else
            ...WeekBalanceSummary(week: week).lines(context),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(key: const Key('balance-history'), onPressed: () => context.push('/balance'), child: const Text('Verlauf')),
          ),
        ]),
      ),
    );
  }
}

/// Textzeilen einer Wochenbilanz, gemeinsam fuer Karte und Verlaufsseite.
class WeekBalanceSummary {
  const WeekBalanceSummary({required this.week});

  final WeekBalance week;

  List<Widget> lines(BuildContext context) {
    final t = Theme.of(context);
    final coverage = week.coverage;
    final out = <Widget>[];
    if (coverage == null) {
      out.add(Text('Kein Bestandsabgang in dieser Woche.', key: Key('balance-coverage-${_id(week)}'), style: t.textTheme.bodyMedium));
    } else {
      out.add(Text('Deckungsgrad ${(coverage * 100).round()} %', key: Key('balance-coverage-${_id(week)}'), style: t.textTheme.titleLarge));
      out.add(Text(
        'Vom Bestand sind ${formatMassG(week.expectedG)} abgegangen, ${formatMassG(week.eatenG < 0 ? 0 : week.eatenG)} davon durch Mahlzeiten erklärt.',
        style: t.textTheme.bodySmall,
      ));
      out.add(const SizedBox(height: 6));
      out.add(LinearProgressIndicator(value: coverage.clamp(0.0, 1.0), minHeight: 4, backgroundColor: t.colorScheme.surfaceContainerHighest));
    }
    out.add(const SizedBox(height: 6));
    out.add(Text(
      'Eingekauft ${formatMassG(week.purchasedG)} · weggeworfen ${formatMassG(week.discardedG)}',
      key: Key('balance-flow-${_id(week)}'),
      style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
    ));
    if (week.skipped > 0) {
      out.add(Text(
        week.skipped == 1
            ? '1 Buchung in Stück ohne bekanntes Gewicht ist nicht eingerechnet.'
            : '${week.skipped} Buchungen in Stück ohne bekanntes Gewicht sind nicht eingerechnet.',
        key: Key('balance-skipped-${_id(week)}'),
        style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
      ));
    }
    return out;
  }

  static String _id(WeekBalance w) => '${w.weekStart.year}-${w.weekStart.month}-${w.weekStart.day}';
}
