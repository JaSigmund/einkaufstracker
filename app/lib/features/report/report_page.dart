import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../domain/receipt/month_report.dart';
import '../../domain/receipt/vienna_time.dart';

const _monthNames = [
  'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
];

/// Inhalt des Tabs "Auswertung": Ausgaben eines Monats nach Kategorie, Tippen zeigt die Einzelartikel.
class ReportPage extends ConsumerStatefulWidget {
  const ReportPage({super.key, this.now});

  /// Aktueller Zeitpunkt (UTC). Austauschbar fuer Tests.
  final DateTime? now;

  @override
  ConsumerState<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends ConsumerState<ReportPage> {
  late int _year;
  late int _month;
  String? _open; // aufgeklappte Kategorie

  @override
  void initState() {
    super.initState();
    final local = utcToViennaLocal(widget.now ?? DateTime.now().toUtc());
    _year = local.year;
    _month = local.month;
  }

  void _shift(int delta) => setState(() {
        final m = _month - 1 + delta;
        _year += (m / 12).floor();
        _month = m % 12 + 1;
        _open = null;
      });

  @override
  Widget build(BuildContext context) {
    final receipts = ref.watch(receiptsStreamProvider);
    final items = ref.watch(allItemsStreamProvider);
    final categories = ref.watch(categoriesStreamProvider).value ?? const <Category>[];
    final t = Theme.of(context);

    if (receipts.isLoading || items.isLoading) return const Center(child: CircularProgressIndicator());
    if (receipts.hasError || items.hasError) return Center(child: Text('Fehler: ${receipts.error ?? items.error}'));

    final report = buildMonthReport(
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
      year: _year,
      month: _month,
    );
    final nameOf = {for (final c in categories) c.id: c.name};
    final total = report.totalCents;
    final positive = report.categories.where((c) => c.totalCents > 0).fold<int>(0, (s, c) => s + c.totalCents);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(key: const Key('month-prev'), tooltip: 'Vormonat', icon: const Icon(Icons.chevron_left), onPressed: () => _shift(-1)),
            Text('${_monthNames[_month - 1]} $_year', style: t.textTheme.titleMedium),
            IconButton(key: const Key('month-next'), tooltip: 'Folgemonat', icon: const Icon(Icons.chevron_right), onPressed: () => _shift(1)),
          ],
        ),
        Center(child: Text(formatEuro(total), key: const Key('report-total'), style: t.textTheme.headlineMedium)),
        Center(
          child: Text(
            report.receiptCount == 1 ? '1 Einkauf' : '${report.receiptCount} Einkäufe',
            style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline),
          ),
        ),
        const SizedBox(height: 8),
        if (report.categories.isEmpty)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Keine Einkäufe in diesem Monat')))
        else
          for (final c in report.categories) ...[
            ListTile(
              key: Key('cat-${c.categoryId}'),
              title: Text(c.categoryId == unassignedKey ? 'Nicht zugeordnet' : nameOf[c.categoryId] ?? 'Unbekannte Kategorie'),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: LinearProgressIndicator(value: positive == 0 || c.totalCents <= 0 ? 0 : c.totalCents / positive, minHeight: 6),
              ),
              trailing: Text(formatEuro(c.totalCents), style: t.textTheme.titleSmall),
              onTap: () => setState(() => _open = _open == c.categoryId ? null : c.categoryId),
            ),
            if (_open == c.categoryId)
              for (final a in c.items)
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.only(left: 32, right: 16),
                  title: Text(a.label),
                  subtitle: a.purchases == 0 ? null : Text('${a.purchases}× gekauft'),
                  trailing: Text(formatEuro(a.totalCents), style: TextStyle(color: a.totalCents < 0 ? t.colorScheme.primary : null)),
                ),
          ],
      ],
    );
  }
}
