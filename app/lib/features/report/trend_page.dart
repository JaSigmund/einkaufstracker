import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../domain/receipt/month_report.dart';
import '../../domain/receipt/vienna_time.dart';

const _monthNamesShort = ['Jän', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'];

/// "Trend" (Doku 07 §2): Ausgaben je Monat und Kategorie über 6 oder 12 Monate, damit sich Ausreißer und
/// saisonale Muster erkennen lassen statt nur den einen ausgewählten Monat der Monatsauswertung zu sehen.
class TrendPage extends ConsumerStatefulWidget {
  const TrendPage({super.key, this.now});

  /// Aktueller Zeitpunkt (UTC). Austauschbar für Tests.
  final DateTime? now;

  @override
  ConsumerState<TrendPage> createState() => _TrendPageState();
}

class _TrendPageState extends ConsumerState<TrendPage> {
  int _months = 6;
  int? _openIndex;

  @override
  Widget build(BuildContext context) {
    final receipts = ref.watch(receiptsStreamProvider);
    final items = ref.watch(allItemsStreamProvider);
    final categories = ref.watch(categoriesStreamProvider).value ?? const <Category>[];
    final t = Theme.of(context);

    if (receipts.isLoading || items.isLoading) return const Center(child: CircularProgressIndicator());
    if (receipts.hasError || items.hasError) return Center(child: Text('Fehler: ${receipts.error ?? items.error}'));

    final local = utcToViennaLocal(widget.now ?? DateTime.now().toUtc());
    final trend = buildTrend(
      [for (final r in receipts.value!) (id: r.id, purchasedAtUtc: r.purchasedAt)],
      [
        for (final i in items.value!)
          (
            receiptId: i.receiptId,
            lineNo: i.lineNo,
            kind: i.kind,
            rawText: i.rawText,
            categoryId: i.categoryId,
            quantity: i.quantity,
            lineTotalCents: i.lineTotalCents,
          ),
      ],
      endYear: local.year,
      endMonth: local.month,
      months: _months,
    );
    final nameOf = {for (final c in categories) c.id: c.name};
    String nameFor(CategoryTotal c) => c.categoryId == unassignedKey
        ? 'Nicht zugeordnet'
        : c.isBillDiscount
            ? billDiscountLabel
            : nameOf[c.categoryId] ?? 'Unbekannte Kategorie';
    final maxTotal = trend.fold<int>(0, (m, r) => r.totalCents > m ? r.totalCents : m);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trend'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: SegmentedButton<int>(
                key: const Key('trend-range'),
                segments: const [ButtonSegment(value: 6, label: Text('6 M.')), ButtonSegment(value: 12, label: Text('12 M.'))],
                selected: {_months},
                onSelectionChanged: (s) => setState(() {
                  _months = s.first;
                  _openIndex = null;
                }),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final (i, r) in trend.indexed) ...[
            InkWell(
              key: Key('trend-month-$i'),
              onTap: r.categories.isEmpty ? null : () => setState(() => _openIndex = _openIndex == i ? null : i),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  SizedBox(width: 56, child: Text('${_monthNamesShort[r.month - 1]} ${r.year}', style: t.textTheme.bodySmall)),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: LinearProgressIndicator(value: maxTotal == 0 ? 0 : r.totalCents / maxTotal, minHeight: 16),
                    ),
                  ),
                  SizedBox(width: 72, child: Text(formatEuro(r.totalCents), textAlign: TextAlign.end, style: t.textTheme.bodySmall)),
                ]),
              ),
            ),
            if (_openIndex == i)
              Padding(
                padding: const EdgeInsets.only(left: 56, bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final c in r.categories.where((c) => c.totalCents > 0))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(children: [
                          Expanded(child: Text(nameFor(c), style: t.textTheme.bodySmall)),
                          Text(formatEuro(c.totalCents), style: t.textTheme.bodySmall),
                        ]),
                      ),
                  ],
                ),
              ),
          ],
          if (trend.every((r) => r.categories.isEmpty))
            const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Keine Einkäufe in diesem Zeitraum'))),
        ],
      ),
    );
  }
}
