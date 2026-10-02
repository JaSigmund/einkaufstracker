import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/online_prices/online_price_remote.dart';
import '../../domain/online_prices/online_price.dart';

/// Kurzform der Basiseinheit eines Online-Artikels fuer den Grundpreis ("je kg").
String onlineBaseUnitLabel(String baseUnit) => baseUnit == 'stk' ? 'Stk' : baseUnit;

/// Preis und Grundpreis eines Online-Artikels in einer Zeile: "500 g · 6,65 €/kg".
String onlineArticleDetail(OnlineArticle a) {
  final parts = [
    formatOnlineQuantity(a.quantity, a.unit),
    if (a.unitPriceNormCents != null && a.baseUnit != null) '${formatEuro(a.unitPriceNormCents!)}/${onlineBaseUnitLabel(a.baseUnit!)}',
  ].where((p) => p.isNotEmpty);
  return parts.join(' · ');
}

/// Sucht zu einem Produkt passende Online-Artikel eines Haendlers (ADR-019). Der Nutzer bestaetigt selbst: der Feed hat keine
/// EAN, ein automatisches Zuordnen waere unzuverlaessig und wuerde falsche Preise als Vergleich zeigen. Es lassen sich mehrere
/// Artikel auf einmal waehlen (Bio-Paprika und normale Paprika sind dasselbe Produkt), schon zugeordnete sind markiert.
/// Liefert die gewaehlten neuen Artikel oder `null`, wenn nichts gewaehlt wurde.
Future<List<OnlineArticle>?> showOnlineArticleSearch(
  BuildContext context, {
  required String store,
  required String initialQuery,
  required String productBaseUnit,
  Set<String> alreadyLinked = const {},
}) =>
    showModalBottomSheet<List<OnlineArticle>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _OnlineArticleSearch(store: store, initialQuery: initialQuery, productBaseUnit: productBaseUnit, alreadyLinked: alreadyLinked),
    );

class _OnlineArticleSearch extends ConsumerStatefulWidget {
  const _OnlineArticleSearch({required this.store, required this.initialQuery, required this.productBaseUnit, required this.alreadyLinked});

  final String store;
  final String initialQuery;
  final String productBaseUnit;

  /// `externalId`s, die dieses Produkt bei diesem Haendler schon hat.
  final Set<String> alreadyLinked;

  @override
  ConsumerState<_OnlineArticleSearch> createState() => _OnlineArticleSearchState();
}

class _OnlineArticleSearchState extends ConsumerState<_OnlineArticleSearch> {
  late final _controller = TextEditingController(text: widget.initialQuery);
  Timer? _debounce;
  List<OnlineArticle> _results = const [];
  final _selected = <String, OnlineArticle>{};
  var _loading = false;
  var _failed = false;
  var _token = 0;

  @override
  void initState() {
    super.initState();
    _search(widget.initialQuery);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(text));
  }

  Future<void> _search(String query) async {
    final token = ++_token;
    if (query.trim().length < 2) {
      setState(() {
        _results = const [];
        _loading = false;
        _failed = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final results = await ref.read(onlinePriceRepositoryProvider).search(query, stores: [widget.store], productBaseUnit: widget.productBaseUnit);
      if (!mounted || token != _token) return;
      setState(() {
        _results = results;
        _loading = false;
        _failed = false;
      });
    } on OnlinePricesUnavailable {
      if (!mounted || token != _token) return;
      setState(() {
        _results = const [];
        _loading = false;
        _failed = true;
      });
    }
  }

  void _toggle(OnlineArticle a, bool selected) => setState(() {
        if (selected) {
          _selected[a.externalId] = a;
        } else {
          _selected.remove(a.externalId);
        }
      });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final label = onlineStoreLabel(widget.store);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              key: const Key('online-search-field'),
              controller: _controller,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              decoration: InputDecoration(labelText: 'Artikel bei $label suchen', prefixIcon: const Icon(Icons.search)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Wähle alle Artikel, die für dich dasselbe Produkt sind (z. B. Bio und normal). Nur du bestätigst die Zuordnung.',
                style: t.textTheme.bodySmall,
              ),
            ),
          ),
          Expanded(child: _body(t, label)),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('online-search-done'),
                  onPressed: () => Navigator.pop(context, _selected.isEmpty ? null : _selected.values.toList()),
                  child: Text(_selected.isEmpty ? 'Schließen' : 'Hinzufügen (${_selected.length})'),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _body(ThemeData t, String label) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_failed) {
      return const Padding(padding: EdgeInsets.all(16), child: Text('Die Online-Preise sind gerade nicht erreichbar.', key: Key('online-search-error')));
    }
    if (_results.isEmpty) {
      return Padding(padding: const EdgeInsets.all(16), child: Text('Keine Treffer bei $label.', key: const Key('online-search-empty')));
    }
    return ListView(children: [
      for (final a in _results)
        CheckboxListTile(
          key: Key('online-result-${a.store}-${a.externalId}'),
          value: widget.alreadyLinked.contains(a.externalId) || _selected.containsKey(a.externalId),
          onChanged: widget.alreadyLinked.contains(a.externalId) ? null : (v) => _toggle(a, v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(a.name),
          subtitle: Text([
            onlineArticleDetail(a),
            if (widget.alreadyLinked.contains(a.externalId)) 'schon zugeordnet',
          ].where((p) => p.isNotEmpty).join(' · ')),
          secondary: Text(formatEuro(a.priceCents), style: t.textTheme.titleSmall),
        ),
    ]);
  }
}
