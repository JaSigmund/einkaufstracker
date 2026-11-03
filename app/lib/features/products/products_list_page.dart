import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../data/nutrition/bls_food_search.dart';
import '../../domain/categorization/name_similarity.dart';
import '../../domain/categorization/normalize_name.dart';
import '../../domain/nutrition/food_match.dart';
import '../../domain/online_prices/online_price.dart';
import '../../domain/products/product_assignment.dart';
import '../report/online_price_section.dart';
import 'nutrient_assignment.dart';
import 'product_actions.dart';

/// Die Produktliste als eigene Seite: Einstieg aus den Einstellungen und aus der Hinweiskarte im Tagebuch.
class ProductsListPage extends StatelessWidget {
  const ProductsListPage({super.key, this.initialView = ProductView.all, this.initialOpenOnly = false});

  final ProductView initialView;
  final bool initialOpenOnly;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Meine Produkte')),
        body: ProductsView(initialView: initialView, initialOpenOnly: initialOpenOnly),
      );
}

/// Der eine Ort fuer die Massenarbeit (Doku 27, ADR-050): alle Produkte in einer Liste, die Ansicht bestimmt, was jede Zeile zeigt und was
/// ein Tipp macht. "Nur offene" macht aus der Gesamtuebersicht eine Arbeitsliste. Steht im Inventar und auf [ProductsListPage].
class ProductsView extends ConsumerStatefulWidget {
  const ProductsView({super.key, this.initialView = ProductView.all, this.initialOpenOnly = false});

  final ProductView initialView;
  final bool initialOpenOnly;

  @override
  ConsumerState<ProductsView> createState() => _ProductsViewState();
}

class _ProductsViewState extends ConsumerState<ProductsView> {
  final _search = TextEditingController();
  late var _view = widget.initialView;
  late var _openOnly = widget.initialOpenOnly;

  /// Vorschlag je Produkt, einmal geholt und gemerkt (kein erneuter Abruf bei jedem Neuzeichnen).
  final _suggestions = <String, Future<List<BlsFood>>>{};
  var _busy = false;

  @override
  void initState() {
    super.initState();
    // Die fruehere, nur lokale Liste "Ueberspringen" wird zur gemeinsamen Einstellung
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ref.read(householdPrefsRepositoryProvider).adoptLocalNutrientSkips();
      } catch (_) {
        // beim naechsten Oeffnen wieder
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _select(ProductView view) {
    setState(() => _view = view);
    if (view == ProductView.online) unawaited(_refreshPrices());
  }

  /// Hoechstens alle 6 Stunden, nur mit Verknuepfungen, ohne Netz still (siehe OnlinePriceRepository.refresh).
  Future<void> _refreshPrices() async {
    try {
      await ref.read(onlinePriceRepositoryProvider).refresh();
    } catch (_) {
      // Die Preise sind eine Zugabe
    }
  }

  Future<List<BlsFood>> _suggestionFor(Product p) => _suggestions.putIfAbsent(p.id, () async {
        try {
          return await ref.read(blsFoodSearchProvider).resolve(p.name);
        } on BlsSearchUnavailable {
          return const [];
        }
      });

  /// Mehrere auf einmal uebernehmen. Gelernt wird nur mit [learn], siehe [applyNutrients].
  Future<void> _applyAll(List<(Product, BlsFood)> items, {required bool learn}) async {
    setState(() => _busy = true);
    for (final (p, food) in items) {
      await applyNutrients(ref, p, food, learn: learn);
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Paare, deren normalisierte Namen knapp ausserhalb der automatischen Bon-Zuordnungs-Toleranz liegen
  /// (ADR-023) -- zu unsicher fuer eine stille Automatik, aber nah genug fuer einen Hinweis hier. Wird bei
  /// jedem Aufbau neu berechnet statt gespeichert, damit nichts veraltet nachhaengt.
  List<(Product, Product)> _likelyDuplicates(List<Product> products) {
    final keys = products.map((p) => normalizeItemName(p.name)).toList();
    return [for (final (i, j) in likelyDuplicatePairs(keys)) (products[i], products[j])];
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final products = ref.watch(productsStreamProvider).value ?? const <Product>[];
    final assignments = ref.watch(productAssignmentsProvider);
    final categoryNames = {for (final c in ref.watch(categoriesStreamProvider).value ?? const <Category>[]) c.id: c.name};
    final links = ref.watch(allOnlineLinksStreamProvider).value ?? const <ProductOnlineLink>[];
    final duplicates = _likelyDuplicates(products);

    final query = _search.text.trim().toLowerCase();
    bool matches(Product p) => query.isEmpty || p.name.toLowerCase().contains(query);
    ProductAssignment? of(Product p) => assignments[p.id];
    final filtered = products.where((p) => matches(p) && (!_openOnly || (of(p)?.isOpen(_view) ?? false))).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final open = [for (final p in products) if (of(p)?.nutrientsOpen ?? false) p];

    int? count(ProductView v) => switch (v) {
          ProductView.nutrients => assignments.values.where((a) => a.nutrientsOpen).length,
          ProductView.category => assignments.values.where((a) => a.categoryOpen).length,
          ProductView.duplicates => duplicates.length,
          _ => null,
        };

    final Map<String, String> blsNames = _view == ProductView.nutrients
        ? ref.watch(blsNamesProvider(({for (final p in products) ?p.blsCode}.toList()..sort()).join(','))).value ?? const {}
        : const {};

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: TextField(
          key: const Key('products-search'),
          controller: _search,
          decoration: const InputDecoration(labelText: 'Suchen', prefixIcon: Icon(Icons.search)),
          onChanged: (_) => setState(() {}),
        ),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          for (final v in ProductView.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: Key('product-view-${v.name}'),
                label: Text(switch (count(v)) { final n? when n > 0 => '${v.label} $n', _ => v.label }),
                selected: _view == v,
                onSelected: (_) => _select(v),
              ),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
        child: Row(children: [
          if (_view != ProductView.duplicates)
            FilterChip(
              key: const Key('products-open-only'),
              label: const Text('Nur offene'),
              selected: _openOnly,
              onSelected: (v) => setState(() => _openOnly = v),
            ),
          const Spacer(),
          TextButton.icon(
            key: const Key('products-learned'),
            onPressed: () => context.push('/learned-terms'),
            icon: const Icon(Icons.psychology_outlined, size: 18),
            label: const Text('Gelernte Begriffe'),
          ),
        ]),
      ),
      Expanded(
        child: _view == ProductView.duplicates
            ? _duplicatesList(t, duplicates.where((d) => matches(d.$1) || matches(d.$2)).toList())
            : ListView.builder(
                padding: const EdgeInsets.only(top: 4, bottom: 32),
                // Vorne die Knoepfe fuer alle offenen, in den uebrigen Ansichten nichts
                itemCount: filtered.isEmpty ? 2 : filtered.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) return _view == ProductView.nutrients && open.isNotEmpty ? _bulkButtons(open) : const SizedBox.shrink();
                  if (filtered.isEmpty) return _emptyHint(t, query.isNotEmpty);
                  final p = filtered[i - 1];
                  final a = of(p) ?? const ProductAssignment(hasNutrients: false, nutrientsNotNeeded: false, hasCategory: false, isLoose: false);
                  return switch (_view) {
                    ProductView.nutrients => _nutrientsRow(t, p, a, blsNames),
                    ProductView.barcode => _textRow(p, 'product-barcode', a.barcodes.isNotEmpty ? a.barcodes.join(', ') : (a.isLoose ? 'Lose Ware, kein Barcode nötig' : 'Kein Barcode')),
                    ProductView.receiptText => _textRow(p, 'product-receipt-text', a.receiptTexts.isNotEmpty ? a.receiptTexts.join(', ') : 'Kein Bon-Text'),
                    ProductView.online => _onlineRow(t, p, a, links),
                    ProductView.category => _categoryRow(p, categoryNames),
                    _ => _allRow(t, p, a),
                  };
                },
              ),
      ),
    ]);
  }

  Widget _emptyHint(ThemeData t, bool searching) {
    final isNutrients = _view == ProductView.nutrients && _openOnly && !searching;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Text(
          isNutrients ? 'Alle Produkte haben Nährwerte oder sind als „nicht nötig“ markiert.' : (_openOnly && !searching ? 'Hier ist nichts offen.' : 'Keine Produkte gefunden'),
          key: Key(isNutrients ? 'nutrients-empty' : 'products-empty'),
          textAlign: TextAlign.center,
          style: isNutrients ? t.textTheme.bodyLarge : null,
        ),
      ),
    );
  }

  void _open(Product p) => context.push('/product/${p.id}');

  Widget _allRow(ThemeData t, Product p, ProductAssignment a) {
    Widget mark(IconData icon, bool set, String what) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Icon(icon, size: 16, color: set ? t.colorScheme.primary : t.colorScheme.outlineVariant, semanticLabel: '$what ${set ? 'zugeordnet' : 'fehlt'}'),
        );
    return Dismissible(
      key: ValueKey(p.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => confirmDeleteProduct(context, ref, p),
      background: Container(
        color: t.colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline),
      ),
      child: ListTile(
        key: Key('product-${p.id}'),
        title: Text(p.name),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (p.brand != null) Text(p.brand!),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(key: Key('product-status-${p.id}'), children: [
              mark(Icons.local_dining_outlined, a.hasNutrients || a.nutrientsNotNeeded, 'Nährwerte'),
              mark(Icons.qr_code_2, a.barcodes.isNotEmpty || a.isLoose, 'Barcode'),
              mark(Icons.receipt_long_outlined, a.receiptTexts.isNotEmpty, 'Bon-Text'),
              mark(Icons.storefront_outlined, a.onlineArticles.isNotEmpty, 'Online-Artikel'),
              mark(Icons.category_outlined, a.hasCategory, 'Kategorie'),
            ]),
          ),
        ]),
        trailing: PopupMenuButton<String>(
          key: Key('product-menu-${p.id}'),
          onSelected: (v) {
            if (v == 'merge') showProductMergeDialog(context, ref, p);
          },
          itemBuilder: (ctx) => const [PopupMenuItem(value: 'merge', child: Text('Mit anderem Produkt zusammenführen'))],
        ),
        onTap: () => _open(p),
      ),
    );
  }

  Widget _textRow(Product p, String keyPrefix, String text) => ListTile(
        key: Key('$keyPrefix-${p.id}'),
        title: Text(p.name),
        subtitle: Text(text),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _open(p),
      );

  Widget _categoryRow(Product p, Map<String, String> names) => ListTile(
        key: Key('product-category-${p.id}'),
        title: Text(p.name),
        subtitle: Text(names[p.categoryId] ?? 'Keine Kategorie'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => pickProductCategory(context, ref, p),
      );

  Widget _onlineRow(ThemeData t, Product p, ProductAssignment a, List<ProductOnlineLink> links) => Card(
        key: Key('product-online-${p.id}'),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            InkWell(onTap: () => _open(p), child: Text(p.name, style: t.textTheme.titleSmall)),
            const SizedBox(height: 2),
            Text(a.onlineArticles.isEmpty ? 'Noch kein Artikel zugeordnet' : a.onlineArticles.join(', '), style: t.textTheme.bodySmall),
            Wrap(spacing: 4, children: [
              for (final store in onlineStores.keys)
                TextButton.icon(
                  key: Key('online-link-$store-${p.id}'),
                  onPressed: () => linkOnlineArticles(context, ref, p, store, [for (final l in links) if (l.productId == p.id) l]),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(onlineStoreLabel(store)),
                ),
            ]),
          ]),
        ),
      );

  /// "Alle sicheren übernehmen" und, als eigener Schritt, die automatischen: die liegen oft daneben (Doku 25).
  Widget _bulkButtons(List<Product> open) => FutureBuilder<List<(Product, BlsFood?)>>(
        future: Future.wait([for (final p in open) _suggestionFor(p).then((r) => (p, r.isEmpty ? null : r.first))]),
        builder: (context, snap) {
          final data = snap.data ?? const <(Product, BlsFood?)>[];
          final stillOpen = {for (final p in open) p.id};
          final sure = [for (final (p, f) in data) if (f != null && f.trust == MatchTrust.sure && stillOpen.contains(p.id)) (p, f)];
          final auto = [for (final (p, f) in data) if (f != null && f.trust == MatchTrust.auto && stillOpen.contains(p.id)) (p, f)];
          if (sure.isEmpty && auto.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Wrap(spacing: 8, runSpacing: 4, children: [
              if (sure.isNotEmpty)
                FilledButton.tonal(
                  key: const Key('nutrients-apply-all'),
                  onPressed: _busy ? null : () => _applyAll(sure, learn: true),
                  child: Text('Alle sicheren übernehmen (${sure.length})'),
                ),
              if (auto.isNotEmpty)
                OutlinedButton(
                  key: const Key('nutrients-apply-auto'),
                  onPressed: _busy ? null : () => _applyAll(auto, learn: false),
                  child: Text('Auch automatische übernehmen (${auto.length})'),
                ),
            ]),
          );
        },
      );

  Widget _nutrientsRow(ThemeData t, Product p, ProductAssignment a, Map<String, String> blsNames) {
    final muted = t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant);
    final List<Widget> body;
    if (a.hasNutrients) {
      final kcal = nutrientsOf(p)?.kcal;
      body = [
        Text(
          '${blsNames[p.blsCode] ?? nutrientSourceLabel(p.nutrientsSource)}${kcal != null ? ' · ${formatKcal(kcal)} je 100 ${p.nutrientsBasis ?? 'g'}' : ''}',
          key: Key('nutrients-current-${p.id}'),
          style: t.textTheme.bodyMedium,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(key: Key('nutrients-change-${p.id}'), onPressed: () => changeNutrients(context, ref, p), child: const Text('Ändern')),
        ),
      ];
    } else if (a.nutrientsNotNeeded) {
      body = [
        Text('Nicht nötig', key: Key('nutrients-not-needed-${p.id}'), style: muted),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: Key('nutrients-undo-${p.id}'),
            onPressed: () => ref.read(householdPrefsRepositoryProvider).setNutrientsNotNeeded(p.id, false),
            child: const Text('Zurücknehmen'),
          ),
        ),
      ];
    } else {
      body = [_openNutrients(t, p, muted)];
    }
    return Card(
      key: Key('nutrients-row-${p.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(key: Key('nutrients-open-${p.id}'), onTap: () => _open(p), child: Text(p.name, style: t.textTheme.titleSmall)),
          const SizedBox(height: 4),
          ...body,
        ]),
      ),
    );
  }

  Widget _openNutrients(ThemeData t, Product p, TextStyle? muted) => FutureBuilder<List<BlsFood>>(
        future: _suggestionFor(p),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator());
          }
          final foods = snap.data ?? const <BlsFood>[];
          final top = foods.isEmpty ? null : foods.first;
          final mark = switch (top?.trust) {
            MatchTrust.sure => Icon(Icons.check_circle_outline, size: 18, color: t.colorScheme.primary),
            MatchTrust.auto => Icon(Icons.change_circle_outlined, size: 18, color: t.colorScheme.tertiary),
            _ => Icon(Icons.help_outline, size: 18, color: t.colorScheme.outline),
          };
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (top == null)
              Text('Kein passender Eintrag gefunden.', key: Key('nutrients-none-${p.id}'), style: t.textTheme.bodySmall)
            else
              Row(children: [
                mark,
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${top.nameDe}${top.per100.kcal != null ? ' · ${formatKcal(top.per100.kcal!)} je 100 g' : ''}',
                    key: Key('nutrients-suggestion-${p.id}'),
                    style: t.textTheme.bodyMedium,
                  ),
                ),
              ]),
            if (top != null && top.trust == MatchTrust.unknown) Text('Unsicher: bitte prüfen oder einen anderen Eintrag wählen.', style: muted),
            Wrap(spacing: 4, children: [
              if (top != null)
                TextButton(key: Key('nutrients-apply-${p.id}'), onPressed: () => applyNutrients(ref, p, top, learn: top.trust == MatchTrust.sure), child: const Text('Übernehmen')),
              TextButton(key: Key('nutrients-change-${p.id}'), onPressed: () => changeNutrients(context, ref, p), child: const Text('Anderen wählen')),
              TextButton(key: Key('nutrients-skip-${p.id}'), onPressed: () => markNutrientsNotNeeded(context, ref, p), child: const Text('Nicht nötig')),
            ]),
          ]);
        },
      );

  Widget _duplicatesList(ThemeData t, List<(Product, Product)> pairs) {
    if (pairs.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(32), child: Text('Keine möglichen Duplikate', key: const Key('duplicates-empty'), style: t.textTheme.bodyLarge)));
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
      Card(
        key: const Key('duplicate-suggestions'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Mögliche Duplikate', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          for (final (a, b) in pairs)
            ListTile(
              key: Key('duplicate-${a.id}-${b.id}'),
              dense: true,
              title: Text('„${a.name}“ ≈ „${b.name}“'),
              trailing: TextButton(
                key: Key('duplicate-merge-${a.id}-${b.id}'),
                onPressed: () => confirmProductMerge(context, ref, keep: a, drop: b),
                child: const Text('Zusammenführen'),
              ),
            ),
        ]),
      ),
    ]);
  }
}
