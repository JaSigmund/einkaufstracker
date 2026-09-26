import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../domain/receipt/month_report.dart';
import '../../domain/receipt/vienna_time.dart';

const _monthNames = [
  'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
];

/// Inhalt des Tabs "Auswertung": Ausgaben eines Monats nach Kategorie, Tippen auf den Namen zeigt die
/// Einzelartikel, Tippen auf den Betrag erklaert ihn samt Verweisen auf die Bons.
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

  /// Bon-Titel fuer die Erklaerung, z.B. "Billa, Filiale 0643".
  String _receiptTitle(String id, List<Receipt> receipts, List<Store> stores) {
    final r = receipts.where((x) => x.id == id).firstOrNull;
    final s = r == null ? null : stores.where((x) => x.id == r.storeId).firstOrNull;
    if (s == null) return 'Einkauf';
    return '${s.chain}${s.branch == null ? '' : ', Filiale ${s.branch}'}';
  }

  void _explain({
    required String title,
    required List<ReportLine> lines,
    required List<Receipt> receipts,
    required List<Store> stores,
    List<({String label, int cents})> extraSummary = const [],
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _ExplanationSheet(
        title: title,
        lines: lines,
        receiptTitle: (id) => _receiptTitle(id, receipts, stores),
        extraSummary: extraSummary,
        onOpenReceipt: (id) {
          Navigator.pop(ctx);
          context.push('/receipt/$id');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final receipts = ref.watch(receiptsStreamProvider);
    final items = ref.watch(allItemsStreamProvider);
    final categories = ref.watch(categoriesStreamProvider).value ?? const <Category>[];
    final stores = ref.watch(storesStreamProvider).value ?? const <Store>[];
    final t = Theme.of(context);

    if (receipts.isLoading || items.isLoading) return const Center(child: CircularProgressIndicator());
    if (receipts.hasError || items.hasError) return Center(child: Text('Fehler: ${receipts.error ?? items.error}'));

    final receiptList = receipts.value!;
    final report = buildMonthReport(
      [for (final r in receiptList) (id: r.id, purchasedAtUtc: r.purchasedAt)],
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
    String nameFor(CategoryTotal c) => c.categoryId == unassignedKey
        ? 'Nicht zugeordnet'
        : c.isBillDiscount
            ? billDiscountLabel
            : nameOf[c.categoryId] ?? 'Unbekannte Kategorie';
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
        InkWell(
          key: const Key('report-total-tap'),
          onTap: report.categories.isEmpty
              ? null
              : () => _explain(
                    title: 'Ausgaben ${_monthNames[_month - 1]} $_year',
                    lines: [for (final c in report.categories) ...c.lines],
                    receipts: receiptList,
                    stores: stores,
                    extraSummary: [for (final c in report.categories) (label: nameFor(c), cents: c.totalCents)],
                  ),
          child: Column(children: [
            Center(child: Text(formatEuro(total), key: const Key('report-total'), style: t.textTheme.headlineMedium)),
            Center(
              child: Text(
                report.receiptCount == 1 ? '1 Einkauf' : '${report.receiptCount} Einkäufe',
                style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline),
              ),
            ),
          ]),
        ),
        if (report.savedCents > 0)
          Card(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: ListTile(
              key: const Key('saved-card'),
              leading: Icon(Icons.savings_outlined, color: t.colorScheme.primary),
              title: const Text('Durch Rabatte gespart'),
              subtitle: const Text('Rabatte auf Artikel und auf den ganzen Bon'),
              trailing: Text(formatEuro(report.savedCents), key: const Key('saved-total'), style: t.textTheme.titleMedium?.copyWith(color: t.colorScheme.primary)),
              onTap: () => _explain(
                title: 'Durch Rabatte gespart',
                lines: report.discountLines,
                receipts: receiptList,
                stores: stores,
              ),
            ),
          ),
        const SizedBox(height: 8),
        if (report.categories.isEmpty)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Keine Einkäufe in diesem Monat')))
        else
          for (final c in report.categories) ...[
            ListTile(
              key: Key('cat-${c.categoryId}'),
              title: Text(nameFor(c), style: c.isBillDiscount ? TextStyle(color: t.colorScheme.primary) : null),
              subtitle: c.isBillDiscount
                  ? const Text('Nicht auf Kategorien verteilt')
                  : Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: LinearProgressIndicator(value: positive == 0 || c.totalCents <= 0 ? 0 : c.totalCents / positive, minHeight: 6),
                    ),
              trailing: TextButton(
                key: Key('amount-${c.categoryId}'),
                onPressed: () => _explain(
                  title: nameFor(c),
                  lines: c.lines,
                  receipts: receiptList,
                  stores: stores,
                ),
                child: Text(formatEuro(c.totalCents), style: t.textTheme.titleSmall?.copyWith(decoration: TextDecoration.underline)),
              ),
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

/// "Wie setzt sich dieser Betrag zusammen": Berechnung oben, darunter die Zeilen je Bon. Ein Tipp auf den
/// Bon oeffnet ihn.
class _ExplanationSheet extends StatelessWidget {
  const _ExplanationSheet({
    required this.title,
    required this.lines,
    required this.receiptTitle,
    required this.onOpenReceipt,
    required this.extraSummary,
  });

  final String title;
  final List<ReportLine> lines;
  final String Function(String receiptId) receiptTitle;
  final void Function(String receiptId) onOpenReceipt;
  final List<({String label, int cents})> extraSummary;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final total = lines.fold<int>(0, (s, l) => s + l.cents);
    int sumOf(bool Function(ReportLine) test) => lines.where(test).fold<int>(0, (s, l) => s + l.cents);
    final articles = sumOf((l) => l.kind == 'article');
    final deposits = sumOf((l) => l.kind == 'deposit');
    final discounts = sumOf((l) => l.kind == 'discount' || l.kind == 'bill_discount');

    // Zeilen je Bon in der Reihenfolge des ersten Auftretens (bereits nach Datum sortiert)
    final byReceipt = <String, List<ReportLine>>{};
    for (final l in lines) {
      byReceipt.putIfAbsent(l.receiptId, () => []).add(l);
    }

    Widget row(String label, int cents, {bool bold = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Row(children: [
            Expanded(child: Text(label, style: bold ? t.textTheme.titleSmall : null)),
            Text(formatEuro(cents), style: (bold ? t.textTheme.titleSmall : t.textTheme.bodyMedium)?.copyWith(color: color)),
          ]),
        );

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        key: const Key('explanation-sheet'),
        controller: controller,
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text(title, style: t.textTheme.titleLarge)),
          if (extraSummary.isNotEmpty) ...[
            for (final e in extraSummary) row(e.label, e.cents, color: e.cents < 0 ? t.colorScheme.primary : null),
          ] else ...[
            if (articles != 0) row('Artikel', articles),
            if (deposits != 0) row('Pfand', deposits),
            if (discounts != 0) row('Rabatte', discounts, color: t.colorScheme.primary),
          ],
          const Divider(indent: 16, endIndent: 16),
          row('Summe', total, bold: true),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Aus diesen Bons', style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.outline)),
          ),
          for (final e in byReceipt.entries) ...[
            ListTile(
              key: Key('receipt-link-${e.key}'),
              dense: true,
              title: Text(receiptTitle(e.key), style: t.textTheme.titleSmall),
              subtitle: Text(formatViennaDateTime(e.value.first.purchasedAtUtc)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(formatEuro(e.value.fold<int>(0, (s, l) => s + l.cents)), style: t.textTheme.titleSmall),
                const Icon(Icons.chevron_right),
              ]),
              onTap: () => onOpenReceipt(e.key),
            ),
            for (final l in e.value)
              Padding(
                padding: const EdgeInsets.only(left: 32, right: 16, bottom: 2),
                child: Row(children: [
                  Expanded(child: Text(l.label, style: t.textTheme.bodySmall)),
                  Text(formatEuro(l.cents), style: t.textTheme.bodySmall?.copyWith(color: l.cents < 0 ? t.colorScheme.primary : null)),
                ]),
              ),
          ],
        ],
      ),
    );
  }
}
