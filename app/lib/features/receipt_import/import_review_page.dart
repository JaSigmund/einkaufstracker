import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../domain/receipt/parsed_receipt.dart';
import 'receipt_import_service.dart';

/// Prueferansicht vor dem Speichern (Doku 02 UC-01, Schritt 7): zeigt, was gelesen wurde, und ob die
/// Pruefungen (Summe, Zwischensumme, Steuerblock) bestehen.
class ImportReviewPage extends ConsumerStatefulWidget {
  const ImportReviewPage({super.key, required this.preview});

  final ImportPreview preview;

  @override
  ConsumerState<ImportReviewPage> createState() => _ImportReviewPageState();
}

class _ImportReviewPageState extends ConsumerState<ImportReviewPage> {
  bool _saving = false;
  late ImportPreview _preview = widget.preview;

  ImportPreview get p => _preview;

  /// Oeffnet den Editor. Bei einem nicht lesbaren Bon startet er leer (manuelle Eingabe).
  Future<void> _edit() async {
    final start = p.error == null
        ? p
        : ImportPreview(receipt: ParsedReceipt.manual(purchasedAtUtc: DateTime.now().toUtc()), source: p.source, note: p.note);
    final edited = await context.push<ImportPreview>('/import-edit', extra: start);
    if (edited == null || !mounted) return;
    final checked = await ref.read(receiptImportServiceProvider).recheckDuplicate(edited);
    if (mounted) setState(() => _preview = checked);
  }

  Future<void> _save() async {
    final trustworthy = p.receipt.isTrustworthy;
    if (!trustworthy) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Trotzdem speichern?'),
          content: const Text(
              'Die Prüfungen sind nicht alle bestanden. Der Bon wird mit einer Markierung gespeichert und kann später korrigiert werden.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Trotzdem speichern')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(receiptImportServiceProvider).save(p);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bon gespeichert')));
      context.go('/');
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Speichern nicht möglich: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bon prüfen'),
        actions: [
          // Codereview-Fund 2026-10-01: ein Duplikat-Verdacht (gleiche Summe, Uhrzeit auf 2 Minuten genau)
          // kann ein Fehlalarm sein, z.B. zwei getrennte, zufaellig gleich teure Einkaeufe kurz
          // hintereinander. Bearbeiten (Uhrzeit/Summe korrigieren) loest per `recheckDuplicate` erneut aus
          // und ist bisher der einzige Weg, so einen Fehlalarm aufzuloesen -- ohne diesen Button war der
          // zweite, echte Einkauf schlicht nicht speicherbar.
          if (p.error == null)
            IconButton(key: const Key('review-edit'), tooltip: 'Bearbeiten', icon: const Icon(Icons.edit_outlined), onPressed: _saving ? null : _edit),
        ],
      ),
      body: _body(context),
      bottomNavigationBar: p.canImport
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => context.pop(),
                      child: const Text('Verwerfen'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(p.receipt.isTrustworthy ? 'Speichern' : 'Trotzdem speichern'),
                    ),
                  ),
                ]),
              ),
            )
          : null,
    );
  }

  Widget _body(BuildContext context) {
    final t = Theme.of(context);
    if (p.error != null) {
      return _Message(
        icon: Icons.error_outline,
        color: t.colorScheme.error,
        title: 'Der Bon konnte nicht gelesen werden',
        text: p.error!,
        extra: p.source == ReceiptSources.pdfText
            ? null
            : OutlinedButton.icon(
                key: const Key('review-manual'),
                onPressed: _edit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Manuell eingeben'),
              ),
      );
    }
    if (p.isDuplicate) {
      return _Message(
        icon: Icons.copy_all_outlined,
        color: t.colorScheme.tertiary,
        title: 'Dieser Bon ist schon gespeichert',
        text: 'Derselbe Einkauf (gleiche Rechnungsnummer, oder gleiche Summe und Uhrzeit auf 2 Minuten genau) ist '
            'bereits vorhanden. Es wird nichts doppelt angelegt. War das ein eigener, nur zufällig gleich teurer '
            'Einkauf? Über "Bearbeiten" oben rechts lässt sich Uhrzeit oder Summe korrigieren.',
        extra: OutlinedButton.icon(
          key: const Key('review-duplicate-edit'),
          onPressed: _edit,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Bearbeiten'),
        ),
      );
    }

    final r = p.receipt;
    final c = r.checks!;
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        ListTile(
          leading: const Icon(Icons.store_outlined),
          title: Text('${r.chain}${r.branchCode == null ? '' : ', Filiale ${r.branchCode}'}'),
          subtitle: Text([
            if (r.purchasedAtUtc != null) formatViennaDateTime(r.purchasedAtUtc!),
            ReceiptSources.label(p.source),
            if (p.edited) 'von dir bearbeitet',
          ].join(' · ')),
          trailing: Text(formatEuro(r.totalCents!), style: t.textTheme.titleMedium),
        ),
        if (p.note != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(p.note!, key: const Key('review-note'), style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ),
        _CheckBanner(checks: c),
        const Divider(height: 1),
        for (final i in r.items) _ItemTile(item: i),
        for (final d in r.bonDiscounts)
          ListTile(
            dense: true,
            leading: const Icon(Icons.local_offer_outlined, size: 20),
            title: Text(d.percent == null ? d.name : '${d.name} ${d.percent}%'),
            subtitle: const Text('Rabatt auf den ganzen Bon'),
            trailing: Text(formatEuro(d.cents), style: TextStyle(color: t.colorScheme.primary)),
          ),
        const Divider(height: 1),
        ListTile(
          title: Text('Summe laut Bon', style: t.textTheme.titleSmall),
          trailing: Text(formatEuro(r.totalCents!), style: t.textTheme.titleMedium),
        ),
        if (r.warnings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('Nicht erkannte Zeilen: ${r.warnings.join('; ')}', style: TextStyle(color: t.colorScheme.error)),
          ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.color, required this.title, required this.text, this.extra});
  final Widget? extra;
  final IconData icon;
  final Color color;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            if (extra != null) ...[extra!, const SizedBox(height: 12)],
            FilledButton(onPressed: () => context.pop(), child: const Text('Zurück')),
          ]),
        ),
      );
}

class _CheckBanner extends StatelessWidget {
  const _CheckBanner({required this.checks});
  final ReceiptChecks checks;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final ok = checks.allOk;
    final lines = <String>[];
    if (!checks.totalMatches) {
      final d = checks.differenceCents;
      lines.add('Die Positionen ergeben ${formatEuro(checks.itemsSumCents + checks.bonDiscountSumCents)}, der Bon nennt ${formatEuro(checks.totalCents ?? 0)}'
          '${d == null ? '' : ' (Differenz ${formatEuro(d)})'}.');
    }
    if (checks.subtotalMatches == false) {
      lines.add('Die Zwischensumme ${formatEuro(checks.subtotalCents!)} passt nicht zu den Positionen (${formatEuro(checks.itemsSumCents)}).');
    }
    if (!checks.taxMatches) {
      if (checks.missingTaxClasses.isNotEmpty) lines.add('Steuerklasse ${checks.missingTaxClasses.join(', ')} fehlt im Steuerblock.');
      checks.classDifferences.forEach((code, diff) => lines.add('Steuerklasse $code weicht um ${formatEuro(diff)} vom Steuerblock ab.'));
      if (checks.unlabeledItems > 0 && checks.missingTaxClasses.isEmpty && checks.classDifferences.isEmpty) {
        lines.add(checks.taxBlockGrossSumCents == 0
            ? 'Der Steuerblock wurde nicht gelesen, die Steuerprüfung ist nicht möglich.'
            : 'Der Steuerblock ergibt ${formatEuro(checks.taxBlockGrossSumCents)}, der Bon nennt ${formatEuro(checks.totalCents ?? 0)}.');
      }
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ok ? t.colorScheme.primaryContainer : t.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(ok ? Icons.check_circle_outline : Icons.warning_amber_rounded,
            color: ok ? t.colorScheme.onPrimaryContainer : t.colorScheme.onErrorContainer),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            ok
                ? (checks.taxBlockGrossSumCents == 0
                    ? 'Die Summe der Positionen entspricht der Bon-Summe.'
                    : 'Alles stimmig: Die Summe der Positionen entspricht der Bon-Summe, und der Steuerblock geht auf.')
                : lines.join('\n'),
            key: const Key('check-text'),
            style: TextStyle(color: ok ? t.colorScheme.onPrimaryContainer : t.colorScheme.onErrorContainer),
          ),
        ),
      ]),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item});
  final ParsedItem item;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final isDiscount = item.kind == ReceiptItemKind.discount;
    final isDeposit = item.kind == ReceiptItemKind.deposit;
    final extra = <String>[
      if (item.quantity != 1 && item.unitPriceCents != null)
        '${formatQuantity(item.quantity)}${item.quantityUnit == 'piece' ? ' ×' : ' ${item.quantityUnit} ×'} ${formatEuro(item.unitPriceCents!)}',
      if (isDiscount) 'Rabatt',
      if (isDeposit) 'Pfand',
    ];
    return ListTile(
      dense: true,
      title: Text(item.rawText),
      subtitle: extra.isEmpty ? null : Text(extra.join(' · ')),
      trailing: Text(
        formatEuro(item.lineTotalCents),
        style: TextStyle(color: item.lineTotalCents < 0 ? t.colorScheme.primary : null),
      ),
    );
  }
}
