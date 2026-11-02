import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../domain/inventory/usage_forecast.dart';
import '../../domain/products/packaging.dart';
import '../../domain/receipt/price_history.dart';
import '../../domain/shopping_list/aisle_order.dart';
import '../../domain/shopping_list/list_price_estimate.dart';
import '../../domain/shopping_list/list_quantity.dart';
import '../common/quantity_dialog.dart';
import 'aisle_order_page.dart' show storeLabel;

/// KV-Schluessel: Markt, nach dessen Regal-Reihenfolge die Einkaufsliste sortiert wird (leer = alphabetisch).
const _sortStoreKey = 'shopping_sort_store';

String _sourceLabel(String source) => switch (source) {
      'depleted' => 'Aufgebraucht',
      'expiring' => 'Läuft bald ab',
      'recurring' => 'Regelmäßig gekauft',
      _ => 'Vorschlag',
    };

/// Einkaufsliste (Doku 06 §6/§7, Doku 08 §3.6, Lastenheft LH-SHO-01/02, Roadmap Phase 3): manuell pflegen,
/// im Markt ohne Netz abhaken, dazu Vorschlaege aus dem Inventar ("Leer"/"Ablauf") zur Bestaetigung oben.
/// Gruppiert nach Kategorie, abgehakte Artikel wandern nach unten in "Erledigt". Jeder Eintrag zeigt die
/// Menge nach dem Konzept in `list_quantity.dart`: "2 × 290 ml" bei Produkten mit Inhalt, sonst z.B. "250 g".
class ShoppingListPage extends ConsumerStatefulWidget {
  const ShoppingListPage({super.key});

  @override
  ConsumerState<ShoppingListPage> createState() => _ShoppingListPageState();
}

class _ShoppingListPageState extends ConsumerState<ShoppingListPage> {
  final _input = TextEditingController();
  List<Product> _matches = const [];
  var _addQuantity = 1.0;

  /// Markt, nach dessen Regal-Reihenfolge sortiert wird (Ausbau 1.14), `null` = alphabetisch. Nur auf diesem Geraet gemerkt.
  String? _sortStoreId;

  /// Hinweis auf Wischen und langes Druecken, bis er einmal weggeklickt wurde (Codereview 2026-10-16, X4). Bis die
  /// Ablage gelesen ist gilt er als gesehen, damit er nicht kurz aufblitzt.
  var _gestureHintSeen = true;
  static const _gestureHintKey = 'shopping_gesture_hint_seen';

  @override
  void initState() {
    super.initState();
    _loadSort();
    _loadGestureHint();
  }

  Future<void> _loadGestureHint() async {
    try {
      final seen = await ref.read(databaseProvider).getKv(_gestureHintKey) != null;
      if (mounted && !seen) setState(() => _gestureHintSeen = false);
    } catch (_) {
      // ohne lesbare Ablage kein Hinweis
    }
  }

  Future<void> _dismissGestureHint() async {
    setState(() => _gestureHintSeen = true);
    try {
      await ref.read(databaseProvider).setKv(_gestureHintKey, '1');
    } catch (_) {
      // nur eine Komfortfunktion
    }
  }

  Future<void> _loadSort() async {
    try {
      final id = await ref.read(databaseProvider).getKv(_sortStoreKey);
      if (mounted && id != _sortStoreId) setState(() => _sortStoreId = id);
    } catch (_) {
      // ohne lesbare Ablage bleibt es alphabetisch
    }
  }

  Future<void> _setSort(String? storeId) async {
    setState(() => _sortStoreId = storeId);
    try {
      await ref.read(databaseProvider).setKv(_sortStoreKey, storeId ?? '');
    } catch (_) {
      // nur eine Komfortfunktion
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final results = query.trim().isEmpty ? const <Product>[] : await ref.read(productRepositoryProvider).search(query);
    if (mounted) setState(() => _matches = results);
  }

  Future<void> _addProduct(Product product) async {
    await ref.read(shoppingListRepositoryProvider).addManual(productId: product.id, quantity: _addQuantity, unit: product.baseUnit, listId: ref.read(selectedShoppingListProvider));
    _input.clear();
    if (mounted) {
      setState(() {
        _matches = const [];
        _addQuantity = 1;
      });
    }
  }

  Future<void> _addFreeText() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    await ref.read(shoppingListRepositoryProvider).addManual(freeText: text, quantity: _addQuantity, listId: ref.read(selectedShoppingListProvider));
    _input.clear();
    if (mounted) {
      setState(() {
        _matches = const [];
        _addQuantity = 1;
      });
    }
  }

  /// "Noch zu kaufen: ca. 12,40 €" nach dem zuletzt bezahlten Preis. Eintraege ohne bekannten Preis (neues Produkt, frei
  /// getippt) zaehlen nicht mit und werden genannt, damit die Summe nie vollstaendiger wirkt, als sie ist.
  Widget _estimateCard(ThemeData t, ListTotalEstimate estimate) {
    return Card(
      key: const Key('shopping-estimate'),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Noch zu kaufen: ca. ${formatEuro(estimate.totalCents)}', key: const Key('shopping-estimate-total'), style: t.textTheme.titleMedium),
          Text('nach dem zuletzt bezahlten Preis', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          if (!estimate.isComplete)
            Text(
              estimate.itemsWithoutPrice == 1
                  ? '1 Artikel ohne bekannten Preis ist nicht eingerechnet.'
                  : '${estimate.itemsWithoutPrice} Artikel ohne bekannten Preis sind nicht eingerechnet.',
              key: const Key('shopping-estimate-missing'),
              style: t.textTheme.bodySmall,
            ),
        ]),
      ),
    );
  }

  /// Sortierung der Liste: alphabetisch oder nach der Regal-Reihenfolge eines Marktes (nur Maerkte, fuer die es eine gibt), dazu der Weg zur
  /// Pflege der Reihenfolgen.
  Widget _sortRow(ThemeData t, List<Store> orderedStores) {
    return SizedBox(
      height: 44,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: IconButton(
            key: const Key('aisle-settings'),
            tooltip: 'Regal-Reihenfolge je Markt',
            icon: const Icon(Icons.swap_vert),
            onPressed: () async {
              await context.push('/aisle-order', extra: _sortStoreId);
              ref.invalidate(householdPrefsOnceProvider);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: IconButton(
            key: const Key('open-shopping-archive'),
            tooltip: 'Abgeschlossene Einkäufe',
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: () => context.push('/shopping-archive'),
          ),
        ),
        if (orderedStores.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(key: const Key('sort-alpha'), label: const Text('A–Z'), selected: _sortStoreId == null, onSelected: (_) => _setSort(null)),
          ),
          for (final s in orderedStores)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(key: Key('sort-store-${s.id}'), label: Text(storeLabel(s)), selected: _sortStoreId == s.id, onSelected: (_) => _setSort(s.id)),
            ),
        ] else
          Padding(padding: const EdgeInsets.only(top: 12), child: Text('Reihenfolge je Markt festlegen', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant))),
      ]),
    );
  }

  /// Auswahl der Liste als Chip-Reihe. Langer Druck auf eine Liste: umbenennen oder (nicht die Standardliste) loeschen, die Eintraege
  /// wandern dann auf die Standardliste.
  Widget _listChips(ThemeData t, List<ShoppingList> lists, String? selectedId, List<ShoppingListItem> all) {
    int open(String id) => all.where((i) => i.listId == id && !i.checked && !i.isSuggestion).length;
    return SizedBox(
      // 48 dp Tippflaeche je Chip plus 4 dp Rand oben und unten (Codereview-Fund 2026-10-16: vorher 52 mit 8 dp Rand, das
      // stauchte die Chips auf 36 dp, unter das Android-Minimum von 48 dp).
      height: 56,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), children: [
        for (final l in lists)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            // Langes Druecken oeffnet das Listenmenue; fuer Screenreader als benannte Aktion statt als namenlose Geste
            // (Codereview-Fund 2026-10-16, labeledTapTargetGuideline in test/ui_accessibility_test.dart).
            child: Semantics(
              customSemanticsActions: {const CustomSemanticsAction(label: 'Liste bearbeiten'): () => _listMenu(l)},
              child: GestureDetector(
                excludeFromSemantics: true,
                onLongPress: () => _listMenu(l),
                child: ChoiceChip(
                  key: Key('list-chip-${l.id}'),
                  label: Text(open(l.id) > 0 ? '${l.name} (${open(l.id)})' : l.name),
                  selected: l.id == selectedId,
                  onSelected: (_) => ref.read(selectedShoppingListProvider.notifier).select(l.isDefault ? null : l.id),
                ),
              ),
            ),
          ),
        // Sichtbarer Weg zum Listenmenue, das sonst nur langes Druecken oeffnet (Codereview 2026-10-16, X4)
        if (lists.where((l) => l.id == selectedId).firstOrNull case final selected?)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              key: const Key('list-edit'),
              tooltip: 'Liste „${selected.name}“ bearbeiten',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _listMenu(selected),
            ),
          ),
        ActionChip(key: const Key('list-add'), avatar: const Icon(Icons.add, size: 18), label: const Text('Neue Liste'), onPressed: _createList),
      ]),
    );
  }

  Future<String?> _askName(String title, {String initial = ''}) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(key: const Key('list-name-field'), controller: ctrl, autofocus: true, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(key: const Key('list-name-ok'), onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _createList() async {
    final name = await _askName('Neue Liste');
    if (name == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    try {
      final list = await ref.read(shoppingListRepositoryProvider).createList(name);
      ref.read(selectedShoppingListProvider.notifier).select(list.id);
    } on ArgumentError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('${e.message}')));
    }
  }

  Future<void> _listMenu(ShoppingList list) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(key: const Key('list-rename'), leading: const Icon(Icons.edit_outlined), title: const Text('Umbenennen'), onTap: () => Navigator.pop(ctx, 'rename')),
          if (!list.isDefault)
            ListTile(
              key: const Key('list-delete'),
              leading: const Icon(Icons.delete_outline),
              title: const Text('Liste löschen'),
              subtitle: const Text('Die Einträge wandern auf die Standardliste'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
        ]),
      ),
    );
    if (action == null || !mounted) return;
    final repo = ref.read(shoppingListRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    if (action == 'rename') {
      final name = await _askName('Liste umbenennen', initial: list.name);
      if (name == null) return;
      try {
        await repo.renameList(list.id, name);
      } on ArgumentError catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('${e.message}')));
      }
    } else {
      if (ref.read(selectedShoppingListProvider) == list.id) ref.read(selectedShoppingListProvider.notifier).select(null);
      await repo.deleteList(list.id);
    }
  }

  /// "Einkauf abschließen" (ADR-043): nimmt das Abgehakte von der Liste, ins Archiv statt in den Papierkorb. Keine Rueckfrage, dafuer
  /// "Rückgängig" und im Archiv der Weg zurueck.
  Future<void> _finishPurchase(List<ShoppingListItem> done) async {
    final repo = ref.read(shoppingListRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final archived = await repo.archiveItems([for (final i in done) i.id]);
    if (archived.isEmpty) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        key: const Key('shopping-archived'),
        content: Text(archived.length == 1 ? 'Ein Eintrag archiviert' : '${archived.length} Einträge archiviert'),
        persist: false,
        action: SnackBarAction(label: 'Rückgängig', onPressed: () => repo.unarchive(archived)),
      ));
  }

  /// "Bald aufgebraucht": Produkte, die nach dem bisherigen Verbrauch in hoechstens drei Tagen leer sind und noch nirgends auf einer Liste
  /// stehen. Ein Tipp setzt sie auf die gewaehlte Liste. Nur ein Hinweis, nichts wird von selbst eingetragen.
  Widget _forecastCard(ThemeData t, List<({Product product, UsageForecast forecast})> due, String? selectedId) {
    return Card(
      key: const Key('shopping-forecast'),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Bald aufgebraucht', style: t.textTheme.titleSmall),
          Text('nach deinem Verbrauch der letzten Wochen, eine Schätzung', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          for (final d in due)
            ListTile(
              key: Key('forecast-${d.product.id}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(d.product.name),
              subtitle: Text(d.forecast.text ?? ''),
              trailing: TextButton(
                key: Key('forecast-add-${d.product.id}'),
                onPressed: () => ref.read(shoppingListRepositoryProvider).addManual(productId: d.product.id, unit: d.product.baseUnit, listId: selectedId),
                child: const Text('Auf die Liste'),
              ),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final allItems = ref.watch(shoppingListItemsStreamProvider).value ?? const <ShoppingListItem>[];
    final lists = ref.watch(shoppingListsStreamProvider).value ?? const <ShoppingList>[];
    final selectedState = ref.watch(selectedShoppingListProvider);
    final defaultId = lists.where((l) => l.isDefault).map((l) => l.id).firstOrNull;
    // Die Auswahl gilt nur, solange es die Liste gibt (sie kann auf einem anderen Geraet geloescht worden sein)
    final selectedId = (selectedState != null && lists.any((l) => l.id == selectedState)) ? selectedState : defaultId;
    // Solange es noch keine Standardliste gibt (vor dem ersten Eintrag), zeigt die Seite alle Eintraege wie bisher
    final items = selectedId == null ? allItems : allItems.where((i) => i.listId == selectedId).toList();
    final products = {for (final p in ref.watch(productsStreamProvider).value ?? const <Product>[]) p.id: p};
    final categoryNames = {for (final c in ref.watch(categoriesStreamProvider).value ?? const <Category>[]) c.id: c.name};
    final receiptItems = ref.watch(allItemsStreamProvider).value ?? const <ReceiptItem>[];
    final receipts = ref.watch(receiptsStreamProvider).value ?? const <Receipt>[];

    String labelOf(ShoppingListItem i) => i.freeText ?? products[i.productId]?.name ?? 'Unbekanntes Produkt';
    String categoryOf(ShoppingListItem i) {
      final categoryId = i.productId == null ? null : products[i.productId]?.categoryId;
      return categoryId == null ? 'Ohne Kategorie' : (categoryNames[categoryId] ?? 'Ohne Kategorie');
    }

    final suggestions = items.where((i) => i.isSuggestion && !i.checked).toList();
    final active = items.where((i) => !i.isSuggestion && !i.checked).toList();
    final done = items.where((i) => i.checked).toList()..sort((a, b) => labelOf(a).toLowerCase().compareTo(labelOf(b).toLowerCase()));

    final grouped = <String, List<ShoppingListItem>>{};
    for (final i in active) {
      grouped.putIfAbsent(categoryOf(i), () => []).add(i);
    }
    for (final list in grouped.values) {
      list.sort((a, b) => labelOf(a).toLowerCase().compareTo(labelOf(b).toLowerCase()));
    }
    // Summenschaetzung (ADR-030): offene Eintraege mit dem zuletzt bezahlten Grundpreis des Produkts
    final latestPrice = latestUnitPriceByProduct(
      items: [
        for (final i in receiptItems)
          (receiptId: i.receiptId, productId: i.productId, unitPriceNormCents: i.unitPriceNormCents, quantity: i.quantity, quantityUnit: i.quantityUnit),
      ],
      receipts: [for (final r in receipts) (id: r.id, storeId: r.storeId, purchasedAtUtc: r.purchasedAt)],
    );
    final estimate = estimateShoppingListTotal([
      for (final i in active)
        (
          quantity: i.quantity,
          packSize: i.productId == null ? null : products[i.productId]?.packSize,
          lastUnitPriceNormCents: i.productId == null ? null : latestPrice[i.productId],
        ),
    ]);
    // Regal-Reihenfolge (Ausbau 1.14): Maerkte mit gespeicherter Reihenfolge, gewaehlter Markt, Kategorie-ID je Gruppe
    final prefs = ref.watch(householdPrefsOnceProvider).value ?? const <String, Object?>{};
    final stores = ref.watch(storesStreamProvider).value ?? const <Store>[];
    final orderedStores = [
      for (final s in stores)
        if (s.deletedAt == null && parseAisleOrder(prefs[aislePrefFor(s.id)]) != null) s,
    ]..sort((a, b) => storeLabel(a).toLowerCase().compareTo(storeLabel(b).toLowerCase()));
    final activeStoreId = orderedStores.any((s) => s.id == _sortStoreId) ? _sortStoreId : null;
    final aisle = activeStoreId == null ? const <String>[] : (parseAisleOrder(prefs[aislePrefFor(activeStoreId)]) ?? const <String>[]);
    final idByName = {for (final e in categoryNames.entries) e.value: e.key};
    final groupNames = sortGroupsByAisle(
      grouped.keys,
      order: aisle,
      idOf: (name) => name == 'Ohne Kategorie' ? null : idByName[name],
      nameOf: (name) => name,
    );

    // Vorhersage: bald leer (hoechstens 3 Tage) und noch auf keiner Liste (unabgehakt)
    final listedProducts = {for (final i in allItems) if (!i.checked && i.productId != null) i.productId!};
    final forecastDue = <({Product product, UsageForecast forecast})>[
      for (final e in ref.watch(usageForecastProvider).entries)
        if (e.value.daysLeft <= 3 && e.value.text != null && !listedProducts.contains(e.key) && products[e.key] != null) (product: products[e.key]!, forecast: e.value),
    ]..sort((a, b) => a.forecast.daysLeft.compareTo(b.forecast.daysLeft));

    return Scaffold(
      body: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 8),
            children: [
              _listChips(t, lists, selectedId, allItems),
              _sortRow(t, orderedStores),
              if (forecastDue.isNotEmpty) _forecastCard(t, forecastDue, selectedId),
              if (estimate.itemsWithPrice > 0) _estimateCard(t, estimate),
              if (suggestions.isNotEmpty) ...[
                Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text('Vorschläge', style: t.textTheme.titleSmall)),
                for (final s in suggestions)
                  Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: ListTile(
                      key: Key('suggestion-${s.id}'),
                      title: Text(labelOf(s)),
                      subtitle: Text(_sourceLabel(s.source)),
                      trailing: Wrap(spacing: 4, children: [
                        TextButton(
                          key: Key('suggestion-add-${s.id}'),
                          onPressed: () => ref.read(shoppingListRepositoryProvider).confirmSuggestion(s.id),
                          child: const Text('Hinzufügen'),
                        ),
                        TextButton(
                          key: Key('suggestion-dismiss-${s.id}'),
                          onPressed: () => ref.read(shoppingListRepositoryProvider).delete(s.id),
                          child: const Text('Verwerfen'),
                        ),
                      ]),
                    ),
                  ),
                const Divider(height: 24),
              ],
              if (!_gestureHintSeen && active.isNotEmpty)
                Card(
                  key: const Key('shopping-gesture-hint'),
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: ListTile(
                    leading: const Icon(Icons.swipe_left_outlined),
                    title: Text(lists.length > 1
                        ? 'Nach links wischen löscht einen Eintrag, langes Drücken verschiebt ihn in eine andere Liste.'
                        : 'Nach links wischen löscht einen Eintrag.'),
                    trailing: IconButton(
                      key: const Key('shopping-gesture-hint-ok'),
                      tooltip: 'Hinweis ausblenden',
                      icon: const Icon(Icons.close),
                      onPressed: _dismissGestureHint,
                    ),
                  ),
                ),
              if (active.isEmpty && done.isEmpty && suggestions.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(child: Text('Die Liste ist leer', key: const Key('shopping-list-empty'))),
                ),
              for (final group in groupNames) ...[
                Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text(group, style: t.textTheme.titleSmall)),
                for (final i in grouped[group]!) _ItemTile(item: i, label: labelOf(i), product: i.productId == null ? null : products[i.productId]),
              ],
              if (done.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                  child: Row(children: [
                    Expanded(child: Text('Erledigt (${done.length})', style: t.textTheme.titleSmall)),
                    TextButton.icon(
                      key: const Key('finish-purchase'),
                      onPressed: () => _finishPurchase(done),
                      icon: const Icon(Icons.task_alt),
                      label: const Text('Einkauf abschließen'),
                    ),
                  ]),
                ),
                for (final i in done) _ItemTile(item: i, label: labelOf(i), product: i.productId == null ? null : products[i.productId]),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_matches.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final p in _matches) ListTile(dense: true, key: Key('add-match-${p.id}'), title: Text(p.name), onTap: () => _addProduct(p)),
                    ],
                  ),
                ),
              Row(children: [
                // Anzahl vor dem Hinzufuegen anpassen, ohne den Eintrag danach extra oeffnen zu muessen
                // (Wunsch "auch die Menge angeben koennen", 2026-09-28).
                IconButton(
                  key: const Key('add-quantity-minus'),
                  tooltip: 'Anzahl verringern',
                  onPressed: _addQuantity > 1 ? () => setState(() => _addQuantity -= 1) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                SizedBox(width: 28, child: Text(formatQuantity(_addQuantity), textAlign: TextAlign.center, key: const Key('add-quantity-value'))),
                IconButton(
                  key: const Key('add-quantity-plus'),
                  tooltip: 'Anzahl erhöhen',
                  onPressed: () => setState(() => _addQuantity += 1),
                  icon: const Icon(Icons.add_circle_outline),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const Key('shopping-list-input'),
                    controller: _input,
                    decoration: const InputDecoration(labelText: 'Artikel hinzufügen'),
                    onChanged: _search,
                    onSubmitted: (_) => _addFreeText(),
                  ),
                ),
                IconButton(key: const Key('shopping-list-add'), tooltip: 'Hinzufügen', icon: const Icon(Icons.add), onPressed: _addFreeText),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _ItemTile extends ConsumerWidget {
  const _ItemTile({required this.item, required this.label, required this.product});
  final ShoppingListItem item;
  final String label;
  final Product? product;

  /// Langer Druck: den Eintrag auf eine andere Liste verschieben (nur sinnvoll, wenn es mehrere gibt).
  Future<void> _move(BuildContext context, WidgetRef ref) async {
    final lists = ref.read(shoppingListsStreamProvider).value ?? const <ShoppingList>[];
    final others = [for (final l in lists) if (l.id != item.listId) l];
    if (others.isEmpty && item.productId == null) return;
    final target = await showModalBottomSheet<ShoppingList>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (item.productId != null)
            ListTile(
              key: Key('open-product-${item.id}'),
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('Produkt öffnen'),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/product/${item.productId}');
              },
            ),
          if (others.isNotEmpty) Padding(padding: const EdgeInsets.all(16), child: Text('„$label“ verschieben nach', style: Theme.of(ctx).textTheme.titleSmall)),
          for (final l in others) ListTile(key: Key('move-to-${l.id}'), leading: const Icon(Icons.drive_file_move_outline), title: Text(l.name), onTap: () => Navigator.pop(ctx, l)),
        ]),
      ),
    );
    if (target != null) await ref.read(shoppingListRepositoryProvider).moveItem(item.id, target.id);
  }

  /// Loeschen mit "Rückgängig" (Codereview 2026-10-16, X2). Messenger und Repository vorher holen: nach dem Wischen ist
  /// die Zeile schon aus dem Baum.
  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(shoppingListRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    await repo.delete(item.id);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        key: const Key('shopping-item-deleted'),
        content: Text('„$label“ gelöscht'),
        // mit Aktion bliebe die SnackBar sonst stehen, bis man sie wegwischt
        persist: false,
        action: SnackBarAction(label: 'Rückgängig', onPressed: () => repo.restore(item.id)),
      ));
  }

  /// Menge aendern (ADR-045). Bei Produkten mit Inhalt speichert der Eintrag Packungen, sonst die Menge; eingeben laesst sich beides.
  Future<void> _editQuantity(BuildContext context, WidgetRef ref) async {
    final packaging = packagingOf(product, item.unit);
    final pack = packaging.contentPerPack;
    final amount = item.quantity * (pack ?? 1);
    final result = await showQuantityDialog(
      context,
      keyPrefix: 'shopping-item-quantity',
      initialAmount: amount,
      initialOption: product == null ? _freeOption(amount, item.unit) : packaging.bestOption(amount),
      options: product == null ? QuantityOption.free : packaging.options,
      preview: (a, unit) => product == null ? packagingOf(null, unit).describe(a) : packaging.describe(a),
    );
    if (result == null) return;
    final quantity = pack == null ? result.amount : roundQuantity(result.amount / pack);
    if (quantity <= 0) return;
    // Packungen behalten die Einheit des Eintrags, die Zahl zaehlt ja nur Packungen
    await ref.read(shoppingListRepositoryProvider).setQuantity(item.id, quantity, unit: pack == null ? result.unit : item.unit);
  }

  static QuantityOption _freeOption(double amount, String unit) {
    final best = ListAmountUnit.bestFor(amount, unit);
    return QuantityOption.free.firstWhere((o) => o.label == best.label);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quantity = describeListQuantity(quantity: item.quantity, unit: item.unit, packSize: product?.packSize, productBaseUnit: product?.baseUnit, piecesPerPack: product?.piecesPerPack, pieceLabel: product?.pieceLabel);
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline),
      ),
      onDismissed: (_) => _delete(context, ref),
      // Wischen (Loeschen) und langes Druecken (Verschieben) sind fuer Screenreader zusaetzlich benannte Aktionen
      // (Codereview-Fund 2026-10-16).
      child: Semantics(
        customSemanticsActions: {
          const CustomSemanticsAction(label: 'In andere Liste verschieben'): () => _move(context, ref),
          const CustomSemanticsAction(label: 'Löschen'): () => _delete(context, ref),
        },
        child: GestureDetector(
        excludeFromSemantics: true,
        onLongPress: () => _move(context, ref),
        child: CheckboxListTile(
        key: Key('shopping-item-${item.id}'),
        controlAffinity: ListTileControlAffinity.leading,
        value: item.checked,
        onChanged: (v) => ref.read(shoppingListRepositoryProvider).setChecked(item.id, v ?? false),
        title: Text(label, style: item.checked ? const TextStyle(decoration: TextDecoration.lineThrough) : null),
        subtitle: quantity.total == null ? null : Text('insgesamt ${quantity.total}', key: Key('shopping-item-total-${item.id}')),
        secondary: InkWell(
          key: Key('shopping-item-quantity-${item.id}'),
          onTap: () => _editQuantity(context, ref),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(quantity.primary, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ),
      ),
      ),
      ),
    );
  }
}
