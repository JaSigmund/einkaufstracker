import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../domain/receipt/vienna_time.dart';

const _monthNames = [
  'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
];

/// Monat als Schluessel year*100+month, [allMonths] fuer "alle Monate".
const allMonths = 0;

int _monthKey(DateTime utc) {
  final l = utcToViennaLocal(utc);
  return l.year * 100 + l.month;
}

String _monthLabel(int key) => key == allMonths ? 'Alle Monate' : '${_monthNames[key % 100 - 1]} ${key ~/ 100}';

/// Inhalt des Tabs "Uebersicht": Summe und Liste der gespeicherten Bons, filterbar nach Monat (Wiener Zeit)
/// und Markt. Vorbelegt ist der aktuelle Monat, alle Markte.
class ReceiptsOverview extends ConsumerStatefulWidget {
  const ReceiptsOverview({super.key, this.now});

  /// Aktueller Zeitpunkt (UTC). Austauschbar fuer Tests.
  final DateTime? now;

  @override
  ConsumerState<ReceiptsOverview> createState() => _ReceiptsOverviewState();
}

class _ReceiptsOverviewState extends ConsumerState<ReceiptsOverview> {
  late int _month = _monthKey(widget.now ?? DateTime.now().toUtc());
  String? _chain; // null = alle Maerkte

  @override
  Widget build(BuildContext context) {
    final receipts = ref.watch(receiptsStreamProvider);
    final stores = ref.watch(storesStreamProvider).value ?? const <Store>[];
    final t = Theme.of(context);

    return receipts.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (list) {
        final storeById = {for (final s in stores) s.id: s};
        String chainOf(Receipt r) => storeById[r.storeId]?.chain ?? 'Unbekannt';

        // Auswahl: alle Monate mit Bons plus der aktuelle; alle Maerkte mit Bons
        final currentKey = _monthKey(widget.now ?? DateTime.now().toUtc());
        final monthKeys = {currentKey, _month, for (final r in list) _monthKey(r.purchasedAt)}..remove(allMonths);
        final months = monthKeys.toList()..sort((a, b) => b.compareTo(a));
        final chains = {for (final r in list) chainOf(r)}.toList()..sort();

        final shown = [
          for (final r in list)
            if ((_month == allMonths || _monthKey(r.purchasedAt) == _month) && (_chain == null || chainOf(r) == _chain)) r,
        ];
        final total = shown.fold<int>(0, (s, r) => s + r.totalCents);

        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Card(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    [_monthLabel(_month), ?_chain].join(' · '),
                    key: const Key('period-label'),
                    style: t.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(formatEuro(total), key: const Key('month-total'), style: t.textTheme.headlineMedium),
                  const SizedBox(height: 2),
                  Text(
                    shown.length == 1 ? '1 Einkauf' : '${shown.length} Einkäufe',
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline),
                  ),
                ]),
              ),
            ),
            if (list.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  DropdownButton<int>(
                    key: const Key('filter-month'),
                    value: _month,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem(value: allMonths, child: Text('Alle Monate')),
                      for (final m in months) DropdownMenuItem(value: m, child: Text(_monthLabel(m))),
                    ],
                    onChanged: (v) => setState(() => _month = v ?? _month),
                  ),
                  Wrap(spacing: 8, children: [
                    ChoiceChip(
                      key: const Key('filter-chain-all'),
                      label: const Text('Alle Märkte'),
                      selected: _chain == null,
                      onSelected: (_) => setState(() => _chain = null),
                    ),
                    for (final c in chains)
                      ChoiceChip(
                        key: Key('filter-chain-$c'),
                        label: Text(c),
                        selected: _chain == c,
                        onSelected: (_) => setState(() => _chain = _chain == c ? null : c),
                      ),
                  ]),
                ]),
              ),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  Icon(Icons.receipt_long_outlined, size: 48, color: t.colorScheme.outline),
                  const SizedBox(height: 12),
                  Text('Noch keine Bons', style: t.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  const Text('Importiere im Tab „Scan“ deinen ersten digitalen Bon.', textAlign: TextAlign.center),
                ]),
              )
            else if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text('Keine Bons für diese Auswahl', key: const Key('no-match'), style: t.textTheme.bodyMedium)),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('Bons', style: t.textTheme.titleSmall),
              ),
              for (final r in shown) _ReceiptTile(receipt: r, store: storeById[r.storeId]),
            ],
          ],
        );
      },
    );
  }
}

class _ReceiptTile extends StatelessWidget {
  const _ReceiptTile({required this.receipt, this.store});
  final Receipt receipt;
  final Store? store;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final title = store == null ? 'Einkauf' : '${store!.chain}${store!.branch == null ? '' : ', Filiale ${store!.branch}'}';
    return ListTile(
      leading: const Icon(Icons.receipt_long_outlined),
      title: Text(title),
      subtitle: Text(formatViennaDateTime(receipt.purchasedAt)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (receipt.sumMismatch) Icon(Icons.warning_amber_rounded, size: 18, color: t.colorScheme.error),
        const SizedBox(width: 4),
        Text(formatEuro(receipt.totalCents), style: t.textTheme.titleSmall),
      ]),
      onTap: () => context.push('/receipt/${receipt.id}'),
    );
  }
}
