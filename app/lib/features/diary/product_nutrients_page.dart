import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../data/nutrition/bls_food_search.dart';
import '../../domain/nutrition/food_match.dart';
import 'ingredient_picker.dart';

/// KV-Schluessel: Produkte, bei denen der Nutzer "Ueberspringen" gewaehlt hat (JSON-Liste der IDs).
const productsNutrientsSkippedKey = 'products_nutrients_skipped';

/// Produkte ohne Naehrwerte (Phase N1, ADR-031): Produkte, die vom Bon kommen, haben keinen Barcode und deshalb kein Profil
/// aus Open Food Facts. Hier schlaegt die App je Produkt einen Eintrag der Lebensmitteldatenbank vor, der Nutzer uebernimmt,
/// aendert oder ueberspringt ihn. Das Profil wird als Snapshot ins Produkt kopiert (Produkt-Zutaten haben danach Naehrwerte),
/// und der Name wird im Gedaechtnis des Haushalts vermerkt (beim Foto-Vorschlag heisst "Milch" dann dasselbe).
class ProductNutrientsPage extends ConsumerStatefulWidget {
  const ProductNutrientsPage({super.key});

  @override
  ConsumerState<ProductNutrientsPage> createState() => _ProductNutrientsPageState();
}

class _ProductNutrientsPageState extends ConsumerState<ProductNutrientsPage> {
  /// Vorschlag je Produkt, einmal geholt und gemerkt (kein erneuter Abruf bei jedem Neuzeichnen).
  final _suggestions = <String, Future<List<BlsFood>>>{};
  final _done = <String>{};
  Set<String> _skipped = {};
  var _skippedLoaded = false;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _loadSkipped();
  }

  Future<void> _loadSkipped() async {
    var ids = <String>{};
    try {
      final raw = await ref.read(databaseProvider).getKv(productsNutrientsSkippedKey);
      if (raw != null) ids = {for (final x in jsonDecode(raw) as List) x as String};
    } catch (_) {
      // unlesbare Ablage: dann ist nichts uebersprungen
    }
    if (mounted) {
      setState(() {
        _skipped = ids;
        _skippedLoaded = true;
      });
    }
  }

  Future<void> _skip(Product p) async {
    setState(() => _skipped = {..._skipped, p.id});
    try {
      await ref.read(databaseProvider).setKv(productsNutrientsSkippedKey, jsonEncode(_skipped.toList()));
    } catch (_) {
      // nur eine Komfortfunktion
    }
  }

  Future<List<BlsFood>> _suggestionFor(Product p) => _suggestions.putIfAbsent(p.id, () async {
        try {
          return await ref.read(blsFoodSearchProvider).resolve(p.name);
        } on BlsSearchUnavailable {
          return const [];
        }
      });

  Future<void> _apply(Product p, BlsFood food) async {
    final updated = await ref.read(productRepositoryProvider).setBlsProfile(p.id, food);
    if (updated != null) {
      try {
        await ref.read(foodLinkRepositoryProvider).learn(p.name, food.code);
      } catch (_) {
        // das Gedaechtnis ist eine Zugabe
      }
    }
    if (mounted) setState(() => _done.add(p.id));
  }

  Future<void> _change(Product p) async {
    final picked = await showIngredientPicker(context, initialQuery: p.name);
    final bls = picked?.bls;
    if (bls == null || !mounted) return;
    await _apply(p, bls);
  }

  Future<void> _applyAll(List<(Product, BlsFood)> items) async {
    setState(() => _busy = true);
    for (final (p, food) in items) {
      await _apply(p, food);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final products = ref.watch(productsStreamProvider).value ?? const <Product>[];
    final open = [
      for (final p in products)
        if (p.deletedAt == null && p.nutrientsPer100 == null && !_done.contains(p.id) && !_skipped.contains(p.id)) p,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Scaffold(
      appBar: AppBar(title: const Text('Nährwerte zuordnen')),
      body: !_skippedLoaded
          ? const Center(child: CircularProgressIndicator())
          : open.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      _done.isEmpty ? 'Alle Produkte haben Nährwerte oder wurden übersprungen.' : '${_done.length} Produkte zugeordnet. Alle anderen haben schon Nährwerte.',
                      key: const Key('nutrients-empty'),
                      textAlign: TextAlign.center,
                      style: t.textTheme.bodyLarge,
                    ),
                  ),
                )
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Text(
                    'Produkte vom Bon haben keinen Barcode und deshalb keine Nährwerte. Die App schlägt je Produkt einen Eintrag der '
                    'Lebensmitteldatenbank (BLS) vor. Mit „Übernehmen“ rechnet das Tagebuch künftig mit diesen Werten, wenn du das Produkt als Zutat wählst.',
                    style: t.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  _ApplyAll(open: open, suggestionFor: _suggestionFor, busy: _busy, onApply: _applyAll),
                  const SizedBox(height: 8),
                  for (final p in open)
                    _ProductRow(
                      key: Key('nutrients-row-${p.id}'),
                      product: p,
                      future: _suggestionFor(p),
                      onApply: (food) => _apply(p, food),
                      onChange: () => _change(p),
                      onSkip: () => _skip(p),
                    ),
                ]),
    );
  }
}

/// "Alle übernehmen (n)": die Produkte, deren Vorschlag sicher oder automatisch ist.
class _ApplyAll extends StatelessWidget {
  const _ApplyAll({required this.open, required this.suggestionFor, required this.busy, required this.onApply});

  final List<Product> open;
  final Future<List<BlsFood>> Function(Product) suggestionFor;
  final bool busy;
  final Future<void> Function(List<(Product, BlsFood)>) onApply;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<(Product, BlsFood?)>>(
      future: Future.wait([for (final p in open) suggestionFor(p).then((r) => (p, r.isEmpty ? null : r.first))]),
      builder: (context, snap) {
        final items = [
          for (final (p, food) in snap.data ?? const <(Product, BlsFood?)>[])
            if (food != null && food.trust != MatchTrust.unknown) (p, food),
        ];
        if (items.isEmpty) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonal(
            key: const Key('nutrients-apply-all'),
            onPressed: busy ? null : () => onApply(items),
            child: Text(busy ? 'Übernehme…' : 'Alle sicheren und automatischen übernehmen (${items.length})'),
          ),
        );
      },
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({super.key, required this.product, required this.future, required this.onApply, required this.onChange, required this.onSkip});

  final Product product;
  final Future<List<BlsFood>> future;
  final void Function(BlsFood) onApply;
  final VoidCallback onChange;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(product.name, style: t.textTheme.titleSmall),
          const SizedBox(height: 4),
          FutureBuilder<List<BlsFood>>(
            future: future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: LinearProgressIndicator());
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
                  Text('Kein passender Eintrag gefunden.', key: Key('nutrients-none-${product.id}'), style: t.textTheme.bodySmall)
                else
                  Row(children: [
                    mark,
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${top.nameDe}${top.per100.kcal != null ? ' · ${formatKcal(top.per100.kcal!)} je 100 g' : ''}',
                        key: Key('nutrients-suggestion-${product.id}'),
                        style: t.textTheme.bodyMedium,
                      ),
                    ),
                  ]),
                if (top != null && top.trust == MatchTrust.unknown)
                  Text('Unsicher: bitte prüfen oder einen anderen Eintrag wählen.', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                Wrap(spacing: 4, children: [
                  if (top != null) TextButton(key: Key('nutrients-apply-${product.id}'), onPressed: () => onApply(top), child: const Text('Übernehmen')),
                  TextButton(key: Key('nutrients-change-${product.id}'), onPressed: onChange, child: const Text('Anderen wählen')),
                  TextButton(key: Key('nutrients-skip-${product.id}'), onPressed: onSkip, child: const Text('Überspringen')),
                ]),
              ]);
            },
          ),
        ]),
      ),
    );
  }
}
