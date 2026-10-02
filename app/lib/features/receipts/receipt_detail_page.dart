import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../receipt_import/receipt_import_service.dart';

/// Einzelner gespeicherter Bon mit allen Positionen. Loeschen ueber das Menue oben rechts.
class ReceiptDetailPage extends ConsumerWidget {
  const ReceiptDetailPage({super.key, required this.receiptId});

  final String receiptId;

  Future<void> _delete(BuildContext context, WidgetRef ref, List<ReceiptItem> items) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bon löschen?'),
        content: const Text('Der Bon und seine Positionen werden entfernt und fließen nicht mehr in die Auswertung ein. Ein erneuter Import ist möglich.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true) return;

    final inventoryRepo = ref.read(inventoryRepositoryProvider);
    final itemIds = items.map((i) => i.id);
    // Rueckfrage nur, wenn tatsaechlich bestaetigter Bestand zugeordnet ist (Fehlerbericht "Bon löschen
    // verwirft keine Zuordnung", 2026-09-28): der Bestand bleibt beim Loeschen ohnehin erhalten und wird beim
    // erneuten Scan desselben Bons automatisch wieder verknuepft, soll aber auf Wunsch auch entkoppelt werden
    // koennen.
    final linked = await inventoryRepo.confirmedItemsLinkedTo(itemIds);
    var clearLinks = false;
    if (linked.isNotEmpty && context.mounted) {
      clearLinks = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Zuordnung entfernen?'),
              content: Text(linked.length == 1
                  ? 'Ein Inventar-Eintrag ist diesem Bon zugeordnet und bleibt erhalten. Soll die Zuordnung zum Bon ebenfalls entfernt werden? Sie wird sonst beim erneuten Scannen desselben Bons automatisch wiederhergestellt.'
                  : '${linked.length} Inventar-Einträge sind diesem Bon zugeordnet und bleiben erhalten. Soll die Zuordnung zum Bon ebenfalls entfernt werden? Sie wird sonst beim erneuten Scannen desselben Bons automatisch wiederhergestellt.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Zuordnung behalten')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Zuordnung entfernen')),
              ],
            ),
          ) ??
          false;
    }

    final repo = ref.read(receiptRepositoryProvider);
    final files = await repo.filesOf(receiptId);
    await repo.softDelete(receiptId);
    if (clearLinks) await inventoryRepo.clearReceiptLinksFor(itemIds);
    // Originalbelege mitloeschen (lokal und, soweit online, im Storage)
    await ref.read(receiptFileServiceProvider).purge(files);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bon gelöscht')));
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipt = ref.watch(receiptProvider(receiptId)).value;
    final items = ref.watch(receiptItemsProvider(receiptId)).value ?? const <ReceiptItem>[];
    final stores = ref.watch(storesStreamProvider).value ?? const <Store>[];
    final files = ref.watch(receiptFilesStreamProvider(receiptId)).value ?? const <ReceiptFile>[];
    final categories = (ref.watch(categoriesStreamProvider).value ?? const <Category>[]).where((c) => c.deletedAt == null).toList();
    final categoryName = {for (final c in categories) c.id: c.name};
    final t = Theme.of(context);

    if (receipt == null || receipt.deletedAt != null) {
      return Scaffold(appBar: AppBar(title: const Text('Bon')), body: const Center(child: Text('Dieser Bon ist nicht mehr vorhanden.')));
    }
    final store = stores.where((s) => s.id == receipt.storeId).firstOrNull;
    final title = store == null ? 'Einkauf' : '${store.chain}${store.branch == null ? '' : ', Filiale ${store.branch}'}';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'delete') _delete(context, ref, items);
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Löschen'))],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          ListTile(
            title: Text(formatViennaDateTime(receipt.purchasedAt)),
            subtitle: Text(ReceiptSources.label(receipt.source)),
            trailing: Text(formatEuro(receipt.totalCents), style: t.textTheme.titleLarge, key: const Key('receipt-total')),
          ),
          if (receipt.sumMismatch)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: t.colorScheme.errorContainer, borderRadius: BorderRadius.circular(12)),
              child: Text(
                'Beim Import stimmten nicht alle Prüfungen. Die Positionen sollten mit dem Original verglichen werden.',
                style: TextStyle(color: t.colorScheme.onErrorContainer),
              ),
            ),
          for (final f in files)
            ListTile(
              key: Key('file-${f.pageNo}-${f.kind}'),
              leading: Icon(f.kind == 'pdf' ? Icons.picture_as_pdf_outlined : Icons.photo_outlined),
              title: Text(f.kind == 'pdf' ? 'Originalbeleg ansehen (PDF)' : 'Originalbeleg ansehen (Foto, Seite ${f.pageNo})'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/receipt-file', extra: f),
            ),
          const Divider(height: 1),
          for (final i in items)
            ListTile(
              key: Key('item-${i.id}'),
              dense: true,
              // Ausgeschlossene Positionen (ADR-020) bleiben sichtbar, aber durchgestrichen und grau: der
              // Nutzer soll weiterhin sehen, was auf dem Bon stand.
              title: Text(i.rawText, style: i.excluded ? _excludedStyle(t) : null),
              subtitle: _sub(i, categoryName) == null ? null : Text(_sub(i, categoryName)!),
              // Rabatte auf Bon-Ebene haben keine Kategorie und werden anteilig verrechnet
              onTap: i.kind == 'bill_discount' || (i.kind == 'discount' && i.categoryId == null) ? null : () => _pickCategory(context, ref, i, categories),
              trailing: Text(
                formatEuro(i.lineTotalCents),
                style: i.excluded ? _excludedStyle(t) : TextStyle(color: i.lineTotalCents < 0 ? t.colorScheme.primary : null),
              ),
            ),
          const Divider(height: 1),
          ListTile(
            title: Text('Summe', style: t.textTheme.titleSmall),
            trailing: Text(formatEuro(items.fold<int>(0, (s, i) => s + i.lineTotalCents)), key: const Key('items-sum')),
          ),
          if (items.any((i) => i.excluded))
            ListTile(
              dense: true,
              title: const Text('davon von anderen bezahlt'),
              subtitle: const Text('zählt nicht zu deinen Ausgaben'),
              trailing: Text(
                formatEuro(items.where((i) => i.excluded).fold<int>(0, (s, i) => s + i.lineTotalCents)),
                key: const Key('items-excluded-sum'),
              ),
            ),
        ],
      ),
    );
  }

  TextStyle _excludedStyle(ThemeData t) => TextStyle(decoration: TextDecoration.lineThrough, color: t.colorScheme.outline);

  /// Schalter "Von jemand anderem bezahlt" (ADR-020): wirkt nur auf diese Position (und bei einem Artikel auf
  /// die Rabatte direkt darunter), nicht auf gleiche Artikel anderer Bons.
  Future<void> _toggleExcluded(BuildContext context, WidgetRef ref, ReceiptItem item, bool excluded) async {
    await ref.read(receiptRepositoryProvider).setItemExcluded(item.id, excluded);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(excluded ? 'Ausgeschlossen: zählt nicht zu deinen Ausgaben' : 'Zählt wieder zu deinen Ausgaben'),
      ));
    }
  }

  Future<void> _pickCategory(BuildContext context, WidgetRef ref, ReceiptItem item, List<Category> categories) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
          child: ListView(
            shrinkWrap: true,
            children: [
              SwitchListTile(
                key: const Key('item-excluded-switch'),
                value: item.excluded,
                title: const Text('Von jemand anderem bezahlt'),
                subtitle: const Text('Zählt nicht zu deinen Ausgaben, bleibt aber auf dem Bon und im Inventar.'),
                onChanged: (v) {
                  Navigator.pop(ctx);
                  _toggleExcluded(context, ref, item, v);
                },
              ),
              const Divider(height: 1),
              ListTile(title: Text(item.rawText, style: Theme.of(ctx).textTheme.titleMedium), subtitle: const Text('Kategorie wählen. Die App merkt sich die Zuordnung für gleiche Artikel.')),
              for (final c in categories)
                ListTile(
                  key: Key('pick-${c.name}'),
                  title: Text(c.name),
                  trailing: c.id == item.categoryId ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(ctx, c.id),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    final n = await ref.read(receiptRepositoryProvider).setItemCategory(item.id, picked);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(n > 1 ? 'Zugeordnet, $n gleiche Artikel aktualisiert' : 'Zugeordnet')));
    }
  }

  String? _sub(ReceiptItem i, Map<String, String> categoryName) {
    final parts = <String>[
      if (i.kind == 'article') categoryName[i.categoryId] ?? 'Nicht zugeordnet',
      if (i.quantity != 1 && i.unitPriceCents != null)
        '${formatQuantity(i.quantity)}${i.quantityUnit == 'piece' ? ' ×' : ' ${i.quantityUnit} ×'} ${formatEuro(i.unitPriceCents!)}',
      if (i.kind == 'discount') 'Rabatt',
      if (i.kind == 'bill_discount') 'Rabatt auf den ganzen Bon',
      if (i.kind == 'deposit') 'Pfand',
      if (i.excluded) 'von anderem bezahlt',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}
