import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/vienna_time.dart';
import 'balance_card.dart';

/// Verlauf der Verbrauchsbilanz, eine Karte je Woche (LH-MEAL-10).
class BalancePage extends ConsumerWidget {
  const BalancePage({super.key, this.now});

  /// Aktueller Zeitpunkt (UTC). Austauschbar fuer Tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weeks = weeklyBalanceOf(ref);
    final today = utcToViennaLocal(now ?? DateTime.now().toUtc());
    final t = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Bilanz')),
      body: weeks == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              Text(balanceLimitsText, key: const Key('balance-limits'), style: t.textTheme.bodySmall),
              const SizedBox(height: 8),
              if (weeks.where((w) => w.hasData).isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Center(child: Text('Noch keine Bestandsbewegungen in den letzten 12 Wochen.', key: Key('balance-none'))),
                ),
              for (final w in weeks.where((w) => w.hasData))
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(formatWeekRange(w.weekStart, today), style: t.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      ...WeekBalanceSummary(week: w).lines(context),
                    ]),
                  ),
                ),
            ]),
    );
  }
}
