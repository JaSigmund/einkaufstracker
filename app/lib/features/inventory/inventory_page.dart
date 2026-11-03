import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/clock.dart';
import '../../data/local/database.dart';
import '../../domain/inventory/expiry.dart';
import '../../domain/inventory/inventory_grouping.dart';
import '../../domain/inventory/usage_forecast.dart';
import '../common/quantity_dialog.dart';
import '../products/barcode_flow.dart';
import '../products/products_list_page.dart';
import '../products/stock_entry_page.dart';
import 'inventory_item_detail_page.dart';

const _locationLabels = {'pantry': 'Vorrat', 'fridge': 'Kühlschrank', 'freezer': 'Tiefkühl', 'other': 'Sonstiges'};
const _locationOrder = ['fridge', 'freezer', 'pantry', 'other'];

const _groupTitles = {
  ExpiryLevel.expired: 'Abgelaufen',
  ExpiryLevel.soon: 'Läuft bald ab',
  ExpiryLevel.ok: 'Gut',
  ExpiryLevel.unknown: 'Ohne Ablaufdatum',
};
// Reihenfolge der Gruppen: das Dringende zuerst, wie in der Uebersicht (Doku 08 §3.1 "Bald ablaufend").
const _groupOrder = [ExpiryLevel.expired, ExpiryLevel.soon, ExpiryLevel.ok, ExpiryLevel.unknown];

Color _dotColor(ExpiryLevel level, ColorScheme cs) => switch (level) {
      ExpiryLevel.expired => cs.error,
      ExpiryLevel.soon => Colors.amber.shade700,
      ExpiryLevel.ok => Colors.green.shade600,
      ExpiryLevel.unknown => cs.outlineVariant,
    };

String _expiryText(InventoryItem item, ExpiryLevel level, DateTime today) {
  if (item.expiresOn == null) return 'Kein Ablaufdatum';
  final days = item.expiresOn!.difference(DateTime.utc(today.year, today.month, today.day)).inDays;
  final label = item.dateKind == 'use_by' ? 'Zu verbrauchen bis' : 'MHD';
  if (days == 0) return '$label: heute';
  if (days == 1) return '$label: morgen';
  if (days > 1) return '$label: in $days Tagen';
  final overdue = -days;
  return '$label: seit $overdue Tag${overdue == 1 ? '' : 'en'} abgelaufen';
}

/// Geraete-Einstellungen der Inventar-Ansicht (lokaler KV-Speicher, nicht im Haushalt geteilt: jeder sortiert fuer sich).
const inventoryViewKey = 'inventory_view';
const inventoryOpenCategoriesKey = 'inventory_open_categories';

/// Ansicht des Inventars: nach Produktkategorie (Standard seit 1.22) oder nach Dringlichkeit (bisherige Liste).
enum InventoryView { categories, expiry }

/// Inhalt des Tabs "Inventar" (Doku 06, 08 §3.4). Zwei Ansichten:
/// - **Kategorien** (Standard): einklappbare Abschnitte je Produktkategorie, die Kopfzeile zaehlt Abgelaufenes und bald Faelliges, damit
///   nichts Dringendes in einem zugeklappten Abschnitt verschwindet. Oben ein Hinweis "Zuerst verbrauchen", der zur Ablauf-Ansicht fuehrt.
///   Welche Abschnitte offen sind, merkt sich das Geraet.
/// - **Ablauf**: der Bestand nach Dringlichkeit gruppiert (abgelaufen/bald faellig zuerst, wie auf der Uebersicht).
/// Fuer beide gelten die Suche (Name, Marke, Kategorie) und der Filter nach Lagerort; die Vorschlaege aus Bons stehen einklappbar oben.
/// Der FAB startet direkt den Barcode-Scan, ohne Umweg ueber die Seite "Scannen". Der zweite Reiter ist die Produktliste, der eine Ort
/// fuer alle Zuordnungen (Doku 27, Q-36): der Bestand sagt, was da ist, die Produkte, was die App darueber weiss.
class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key, this.now});

  final DateTime? now;

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> {
  String? _location; // null = alle
  var _suggestionsOpen = true;
  var _showProducts = false;

  /// Erst beim ersten Oeffnen aufbauen, danach behaelt die Produktliste Filter und Scrollposition.
  var _productsVisited = false;
  var _view = InventoryView.categories;
  var _open = <String>{};
  var _query = '';
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    try {
      final db = ref.read(databaseProvider);
      final view = await db.getKv(inventoryViewKey);
      final open = await db.getKv(inventoryOpenCategoriesKey);
      if (!mounted) return;
      setState(() {
        if (view == InventoryView.expiry.name) _view = InventoryView.expiry;
        if (open != null) _open = {for (final k in jsonDecode(open) as List) k as String};
      });
    } catch (_) {
      // ohne lesbare Ablage gilt die Standardansicht
    }
  }

  Future<void> _savePref(String key, String value) async {
    try {
      await ref.read(databaseProvider).setKv(key, value);
    } catch (_) {
      // nur eine Komfortfunktion
    }
  }

  void _setView(InventoryView v) {
    setState(() => _view = v);
    _savePref(inventoryViewKey, v.name);
  }

  void _setOpen(Set<String> open) {
    setState(() => _open = open);
    _savePref(inventoryOpenCategoriesKey, jsonEncode(open.toList()..sort()));
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeInventoryStreamProvider);
    final suggestions = ref.watch(inventorySuggestionsStreamProvider).value ?? const <InventoryItem>[];
    final products = {for (final p in ref.watch(productsStreamProvider).value ?? const <Product>[]) p.id: p};
    final categories = ref.watch(categoriesStreamProvider).value ?? const <Category>[];
    final categoryNames = {for (final c in categories) c.id: c.name};
    final today = widget.now ?? appClock.now();
    final t = Theme.of(context);
    final forecasts = ref.watch(usageForecastProvider);
    final openAssignments = ref.watch(openAssignmentCountProvider);

    return active.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (all) {
        final locations = {for (final i in all) i.location}.toList()..sort((a, b) => _locationOrder.indexOf(a).compareTo(_locationOrder.indexOf(b)));
        final shown = [
          for (final i in all)
            if ((_location == null || i.location == _location) &&
                matchesInventorySearch(
                  _query,
                  name: products[i.productId]?.name ?? '',
                  brand: products[i.productId]?.brand,
                  category: categoryNames[products[i.productId]?.categoryId],
                ))
              i,
        ];
        ExpiryLevel levelOf(InventoryItem item) => expiryLevel(expiresOn: item.expiresOn, dateKind: item.dateKind, today: today);
        final groups = <ExpiryLevel, List<InventoryItem>>{};
        for (final item in shown) {
          groups.putIfAbsent(levelOf(item), () => []).add(item);
        }
        final byCategory = groupByCategory<InventoryItem>(
          [
            for (final i in shown)
              (item: i, categoryId: products[i.productId]?.categoryId, name: products[i.productId]?.name ?? '', level: levelOf(i), expiresOn: i.expiresOn),
          ],
          [for (final c in categories) (id: c.id, name: c.name)],
        );
        final searching = _query.trim().isNotEmpty;
        // dringend zaehlt ueber den ganzen Bestand, nicht nur ueber die Auswahl: der Hinweis soll nichts verschweigen
        final expiredAll = all.where((i) => levelOf(i) == ExpiryLevel.expired).length;
        final soonAll = all.where((i) => levelOf(i) == ExpiryLevel.soon).length;

        return Scaffold(
          floatingActionButton: _showProducts ? null : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
            FloatingActionButton.extended(
              key: const Key('inventory-manual-fab'),
              heroTag: 'inventory-manual-fab',
              onPressed: () => context.push('/stock-manual'),
              icon: const Icon(Icons.edit_note),
              label: const Text('Ohne Barcode'),
            ),
            const SizedBox(height: 12),
            FloatingActionButton.extended(
              key: const Key('inventory-scan-fab'),
              heroTag: 'inventory-scan-fab',
              onPressed: () => startBarcodeScan(context, ref),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scannen'),
            ),
          ]),
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  key: const Key('inventory-sections'),
                  showSelectedIcon: false,
                  segments: [
                    const ButtonSegment(value: false, label: Text('Bestand', key: Key('inventory-section-stock'))),
                    ButtonSegment(
                      value: true,
                      label: Badge.count(
                        key: const Key('inventory-products-badge'),
                        count: openAssignments,
                        isLabelVisible: openAssignments > 0,
                        offset: const Offset(18, -6),
                        child: const Text('Produkte', key: Key('inventory-section-products')),
                      ),
                    ),
                  ],
                  selected: {_showProducts},
                  onSelectionChanged: (s) => setState(() {
                    _showProducts = s.first;
                    _productsVisited = _productsVisited || _showProducts;
                  }),
                ),
              ),
            ),
            Expanded(
              child: IndexedStack(index: _showProducts ? 1 : 0, children: [
                _stockList(t, all, shown, locations, groups, suggestions, products, today, forecasts,
                    byCategory: byCategory, searching: searching, expiredAll: expiredAll, soonAll: soonAll),
                if (_productsVisited) const ProductsView() else const SizedBox.shrink(),
              ]),
            ),
          ]),
        );
      },
    );
  }

  Widget _stockList(
    ThemeData t,
    List<InventoryItem> all,
    List<InventoryItem> shown,
    List<String> locations,
    Map<ExpiryLevel, List<InventoryItem>> groups,
    List<InventoryItem> suggestions,
    Map<String, Product> products,
    DateTime today,
    Map<String, UsageForecast> forecasts, {
    required List<InventoryCategoryGroup<InventoryItem>> byCategory,
    required bool searching,
    required int expiredAll,
    required int soonAll,
  }) =>
      ListView(
            padding: const EdgeInsets.only(bottom: 168),
            children: [
              if (suggestions.isNotEmpty)
                Card(
                  margin: const EdgeInsets.all(16),
                  child: Column(children: [
                    ListTile(
                      key: const Key('suggestions-toggle'),
                      leading: const Icon(Icons.inbox_outlined),
                      title: Text('Noch nicht gescannt (${suggestions.length})'),
                      subtitle: const Text('Aus Bons vorgeschlagen. Antippen übernimmt auch ohne Barcode.'),
                      trailing: Icon(_suggestionsOpen ? Icons.expand_less : Icons.expand_more),
                      onTap: () => setState(() => _suggestionsOpen = !_suggestionsOpen),
                    ),
                    if (_suggestionsOpen)
                      for (final s in suggestions)
                        ListTile(
                          dense: true,
                          title: Text(products[s.productId]?.name ?? 'Unbekanntes Produkt'),
                          subtitle: Text(describeStock(s.quantity, s.unit, products[s.productId])),
                          // Lose Ware wie Bananen hat keinen Strichcode, ein Scan koennte den Vorschlag nie bestaetigen
                          onTap: products[s.productId] == null ? null : () => context.push('/stock-entry', extra: StockEntryArgs(product: products[s.productId]!, suggestion: s)),
                          trailing: TextButton(
                            key: Key('discard-suggestion-${s.id}'),
                            onPressed: () => ref.read(inventoryRepositoryProvider).discardSuggestion(s.id),
                            child: const Text('Verwerfen'),
                          ),
                        ),
                  ]),
                ),
              if (all.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: SegmentedButton<InventoryView>(
                    key: const Key('inventory-view'),
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: InventoryView.categories, label: Text('Kategorien'), icon: Icon(Icons.category_outlined)),
                      ButtonSegment(value: InventoryView.expiry, label: Text('Ablauf'), icon: Icon(Icons.schedule)),
                    ],
                    selected: {_view},
                    onSelectionChanged: (s) => _setView(s.first),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: TextField(
                    key: const Key('inventory-search'),
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      isDense: true,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Im Bestand suchen',
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              key: const Key('inventory-search-clear'),
                              tooltip: 'Suche löschen',
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(() {
                                _search.clear();
                                _query = '';
                              }),
                            ),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
              ],
              if (locations.length > 1)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(spacing: 8, children: [
                    ChoiceChip(label: const Text('Alle'), selected: _location == null, onSelected: (_) => setState(() => _location = null)),
                    for (final l in locations)
                      ChoiceChip(
                        key: Key('filter-location-$l'),
                        label: Text(_locationLabels[l] ?? l),
                        selected: _location == l,
                        onSelected: (_) => setState(() => _location = _location == l ? null : l),
                      ),
                  ]),
                ),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      all.isEmpty
                          ? 'Noch kein Bestand. Tippe unten auf „Scannen“, um den ersten Artikel zu erfassen.'
                          : searching
                              ? 'Nichts im Bestand passt zu „${_query.trim()}“'
                              : 'Keine Einträge für diese Auswahl',
                      key: const Key('inventory-empty'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else if (_view == InventoryView.categories) ...[
                if (expiredAll + soonAll > 0 && !searching)
                  Card(
                    key: const Key('inventory-urgent'),
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    color: (expiredAll > 0 ? t.colorScheme.errorContainer : t.colorScheme.secondaryContainer),
                    child: ListTile(
                      leading: Icon(Icons.priority_high, color: expiredAll > 0 ? t.colorScheme.onErrorContainer : null),
                      title: const Text('Zuerst verbrauchen'),
                      subtitle: Text([
                        if (expiredAll > 0) '$expiredAll abgelaufen',
                        if (soonAll > 0) '$soonAll ${soonAll == 1 ? 'läuft' : 'laufen'} bald ab',
                      ].join(', ')),
                      trailing: const Text('Anzeigen'),
                      onTap: () => _setView(InventoryView.expiry),
                    ),
                  ),
                if (!searching && byCategory.length > 1)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: TextButton(
                        key: const Key('inventory-toggle-all'),
                        onPressed: () => _setOpen(byCategory.every((g) => _open.contains(g.key)) ? {} : {for (final g in byCategory) g.key}),
                        child: Text(byCategory.every((g) => _open.contains(g.key)) ? 'Alle zuklappen' : 'Alle aufklappen'),
                      ),
                    ),
                  ),
                for (final g in byCategory) ...[
                  _CategoryHeader(
                    group: g,
                    // beim Suchen ist jeder Abschnitt mit Treffern offen
                    open: searching || _open.contains(g.key),
                    onTap: searching ? null : () => _setOpen(_open.contains(g.key) ? ({..._open}..remove(g.key)) : {..._open, g.key}),
                  ),
                  if (searching || _open.contains(g.key))
                    for (final i in g.items)
                      _InventoryTile(item: i.item, product: products[i.item.productId], level: i.level, today: today, forecast: forecasts[i.item.productId]),
                ],
              ] else
                for (final level in _groupOrder)
                  if (groups[level] case final items? when items.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Row(children: [
                        Container(width: 10, height: 10, margin: const EdgeInsets.only(right: 8), decoration: BoxDecoration(color: _dotColor(level, t.colorScheme), shape: BoxShape.circle)),
                        Text('${_groupTitles[level]} (${items.length})', style: t.textTheme.titleSmall),
                      ]),
                    ),
                    for (final item in items) _InventoryTile(item: item, product: products[item.productId], level: level, today: today, forecast: forecasts[item.productId]),
                  ],
            ],
          );
}

/// Kopfzeile eines Kategorie-Abschnitts: Name, Anzahl und, auch zugeklappt, die abgelaufenen und bald faelligen Positionen als Punkte.
class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.group, required this.open, this.onTap});

  final InventoryCategoryGroup<InventoryItem> group;
  final bool open;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    Widget badge(int n, ExpiryLevel level, String what) => Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Tooltip(
            message: '$n $what',
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 4), decoration: BoxDecoration(color: _dotColor(level, t.colorScheme), shape: BoxShape.circle)),
              Text('$n', style: t.textTheme.labelMedium),
            ]),
          ),
        );
    return ListTile(
      key: Key('inventory-category-${group.key}'),
      dense: true,
      title: Text(group.name, style: t.textTheme.titleSmall),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (group.expired > 0) badge(group.expired, ExpiryLevel.expired, 'abgelaufen'),
        if (group.soon > 0) badge(group.soon, ExpiryLevel.soon, 'bald fällig'),
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Text('${group.items.length}', key: Key('inventory-category-count-${group.key}'), style: t.textTheme.labelLarge),
        ),
        if (onTap != null) Icon(open ? Icons.expand_less : Icons.expand_more),
      ]),
      onTap: onTap,
    );
  }
}

/// Bis zu dieser Reichweite (Tage) zeigt die Bestandsliste die Vorhersage.
const forecastShowDays = 14;

class _InventoryTile extends ConsumerWidget {
  const _InventoryTile({required this.item, required this.product, required this.level, required this.today, this.forecast});
  final InventoryItem item;

  /// Vorhersage der Reichweite des Gesamtbestands dieses Produkts (Ausbau 1.14), `null` ohne ausreichende Daten.
  final UsageForecast? forecast;
  final Product? product;
  final ExpiryLevel level;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    return Dismissible(
      key: ValueKey(item.id),
      background: Container(
        color: t.colorScheme.primaryContainer,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Icon(Icons.check_circle_outline),
      ),
      secondaryBackground: Container(
        color: t.colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline),
      ),
      confirmDismiss: (direction) async {
        final repo = ref.read(inventoryRepositoryProvider);
        final consumed = direction == DismissDirection.startToEnd;
        if (consumed) {
          await repo.markConsumed(item.id);
        } else {
          await repo.markDiscarded(item.id);
        }
        // Sofortiger Rueckweg fuer einen verwischten Wisch (Fehlerbericht "Rueckgaengigmachen von
        // aufgebrauchten Artikeln", 2026-09-28), statt den Eintrag erst wiederfinden zu muessen.
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(consumed ? 'Als aufgebraucht markiert' : 'Als weggeworfen markiert'),
            // mit Aktion bliebe die SnackBar sonst stehen, bis man sie wegwischt
            persist: false,
            action: SnackBarAction(label: 'Rückgängig', onPressed: () => repo.reopen(item.id)),
          ));
        }
        return false; // die Liste aktualisiert sich ueber den Stream, kein manuelles Entfernen noetig
      },
      child: ListTile(
        key: Key('inventory-item-${item.id}'),
        leading: Container(width: 12, height: 12, decoration: BoxDecoration(color: _dotColor(level, t.colorScheme), shape: BoxShape.circle)),
        title: Text(product?.name ?? 'Unbekanntes Produkt'),
        subtitle: Text([
          _expiryText(item, level, today),
          if (item.status == 'opened') 'geöffnet',
          describeStock(item.quantity, item.unit, product),
          // nur wenn es bald knapp wird: sonst waere die Zeile bei jedem Artikel voll von Prognosen
          if (forecast != null && forecast!.daysLeft <= forecastShowDays && forecast!.text != null) forecast!.text!,
        ].join(' · ')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/inventory-item', extra: InventoryItemArgs(item: item, product: product)),
      ),
    );
  }
}
