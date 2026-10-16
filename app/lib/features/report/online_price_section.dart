import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../domain/online_prices/online_price.dart';
import 'online_article_search.dart';

/// Online-Preise zu einem Produkt (ADR-019): getrennt von der Kaufhistorie, nie in Grundpreis-Statistik oder
/// Haendlervergleich gemischt. Je Haendler lassen sich mehrere Artikel zuordnen (Bio-Paprika und normale Paprika sind bei Billa
/// zwei Artikel, fuer den Einkauf aber dasselbe Produkt). Jeder zeigt Preis, Grundpreis und "Stand vom ...", oder "zuletzt
/// bekannt", wenn der Feed nicht mehr gepflegt wird. Der guenstigste Artikel nach Grundpreis ist markiert. Faellt der Abruf
/// aus, bleibt der letzte Preis stehen.
class OnlinePriceSection extends ConsumerStatefulWidget {
  const OnlinePriceSection({super.key, required this.product, this.now});

  final Product product;

  /// Uhr, nur fuer Tests.
  final DateTime Function()? now;

  @override
  ConsumerState<OnlinePriceSection> createState() => _OnlinePriceSectionState();
}

class _OnlinePriceSectionState extends ConsumerState<OnlinePriceSection> {
  @override
  void initState() {
    super.initState();
    // Hoechstens alle 6 Stunden, nur mit Verknuepfungen, ohne Netz still (siehe OnlinePriceRepository.refresh)
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_refresh()));
  }

  Future<void> _refresh({bool force = false}) async {
    try {
      await ref.read(onlinePriceRepositoryProvider).refresh(force: force);
    } catch (_) {
      // Die Preise sind eine Zugabe: kein Haushalt, kein Netz oder ein Serverfehler darf die Seite nie stoeren.
    }
  }

  Future<void> _add(String store, List<ProductOnlineLink> links) async {
    final articles = await showOnlineArticleSearch(
      context,
      store: store,
      initialQuery: widget.product.name,
      productBaseUnit: widget.product.baseUnit,
      alreadyLinked: {for (final l in links.where((l) => l.store == store)) l.externalId},
    );
    if (articles == null || articles.isEmpty || !mounted) return;
    await ref.read(onlinePriceRepositoryProvider).linkAll(widget.product.id, articles);
    unawaited(_refresh(force: true));
  }

  Future<void> _unlink(ProductOnlineLink link) => ref.read(onlinePriceRepositoryProvider).unlink(link.id);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final links = ref.watch(onlineLinksStreamProvider(widget.product.id)).value ?? const <ProductOnlineLink>[];
    final cache = ref.watch(onlinePriceCacheStreamProvider).value ?? const <OnlinePriceCacheRow>[];
    final now = (widget.now ?? DateTime.now)().toUtc();

    // Preise aller zugeordneten Artikel, fuer die Markierung des guenstigsten
    final priced = [
      for (final l in links) _pricedOf(l, cache, now),
    ];
    final cheapest = priced.length >= 2 ? cheapestOnlinePrice(priced, widget.product.baseUnit) : null;

    return Column(
      key: const Key('online-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Online-Preise', style: t.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Regalpreise aus dem Webshop (heisse-preise.io), getrennt von deinen Käufen. Ordne alle Artikel zu, die für dich dasselbe Produkt sind.',
          style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(children: [
            for (final store in onlineStores.keys) _storeBlock(t, store, links, cache, now, cheapest),
          ]),
        ),
        if (cheapest != null) ...[
          const SizedBox(height: 8),
          Text(
            'Günstigster Online-Preis: ${cheapest.name} (${onlineStoreLabel(cheapest.store)}), '
            '${formatEuro(cheapest.unitPriceNormCents!)}/${onlineBaseUnitLabel(cheapest.baseUnit!)}',
            key: const Key('online-cheapest'),
            style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.primary),
          ),
        ],
      ],
    );
  }

  LinkedOnlinePrice _pricedOf(ProductOnlineLink link, List<OnlinePriceCacheRow> cache, DateTime now) {
    final c = cache.where((c) => c.store == link.store && c.externalId == link.externalId).firstOrNull;
    return LinkedOnlinePrice(
      store: link.store,
      externalId: link.externalId,
      name: c?.name ?? link.linkedName,
      priceCents: c?.priceCents,
      baseUnit: c?.baseUnit,
      unitPriceNormCents: c?.unitPriceNormCents,
      freshness: c == null ? OnlinePriceFreshness.stale : onlinePriceFreshness(available: c.available, feedUpdatedAt: c.feedUpdatedAt?.toUtc(), now: now),
    );
  }

  Widget _storeBlock(ThemeData t, String store, List<ProductOnlineLink> allLinks, List<OnlinePriceCacheRow> cache, DateTime now, LinkedOnlinePrice? cheapest) {
    final label = onlineStoreLabel(store);
    final links = allLinks.where((l) => l.store == store).toList();
    return Column(
      key: Key('online-store-$store'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(children: [
            Expanded(child: Text(label, style: t.textTheme.titleSmall)),
            TextButton.icon(
              key: Key('online-link-$store'),
              onPressed: () => _add(store, allLinks),
              icon: const Icon(Icons.add, size: 18),
              label: Text(links.isEmpty ? 'Zuordnen' : 'Artikel hinzufügen'),
            ),
          ]),
        ),
        if (links.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text('Noch kein Artikel zugeordnet', key: Key('online-empty-$store'), style: t.textTheme.bodyMedium),
          )
        else
          for (final link in links) _articleTile(t, link, cache, now, cheapest),
      ],
    );
  }

  Widget _articleTile(ThemeData t, ProductOnlineLink link, List<OnlinePriceCacheRow> cache, DateTime now, LinkedOnlinePrice? cheapest) {
    final k = '${link.store}-${link.externalId}';
    final cached = cache.where((c) => c.store == link.store && c.externalId == link.externalId).firstOrNull;
    final freshness = cached == null
        ? OnlinePriceFreshness.stale
        : onlinePriceFreshness(available: cached.available, feedUpdatedAt: cached.feedUpdatedAt?.toUtc(), now: now);
    final dim = freshness != OnlinePriceFreshness.fresh;
    final muted = t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant);
    final name = cached?.name ?? link.linkedName;
    final isCheapest = cheapest != null && cheapest.store == link.store && cheapest.externalId == link.externalId;

    final detail = cached == null
        ? ''
        : onlineArticleDetail(OnlineArticle(
            store: cached.store,
            externalId: cached.externalId,
            name: cached.name,
            priceCents: cached.priceCents ?? 0,
            quantity: cached.quantity,
            unit: cached.unit,
            baseUnit: cached.baseUnit,
            unitPriceNormCents: cached.unitPriceNormCents,
          ));
    final status = switch (freshness) {
      OnlinePriceFreshness.fresh => 'Stand vom ${formatViennaDate(cached!.feedUpdatedAt!)}',
      OnlinePriceFreshness.stale when cached?.feedUpdatedAt != null => 'zuletzt bekannt, Stand vom ${formatViennaDate(cached!.feedUpdatedAt!)}',
      OnlinePriceFreshness.stale => 'Stand unbekannt',
      OnlinePriceFreshness.discontinued => 'nicht mehr im Online-Sortiment, zuletzt bekannt',
    };
    final mismatch = cached != null && cached.baseUnit != null && !onlineUnitsComparable(widget.product.baseUnit, cached.baseUnit)
        ? 'Der Grundpreis gilt je ${onlineBaseUnitLabel(cached.baseUnit!)}, dein Produkt zählt anders.'
        : null;

    return ListTile(
      key: Key('online-row-$k'),
      dense: true,
      isThreeLine: true,
      leading: isCheapest ? Icon(Icons.star, key: Key('online-star-$k'), color: t.colorScheme.primary) : const SizedBox(width: 24),
      title: Text(name),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (detail.isNotEmpty) Text(detail, key: Key('online-detail-$k')),
        Text(status, key: Key('online-status-$k'), style: dim ? muted : t.textTheme.bodySmall),
        if (mismatch != null) Text(mismatch, key: Key('online-mismatch-$k'), style: muted),
      ]),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(
          cached?.priceCents == null ? '–' : formatEuro(cached!.priceCents!),
          key: Key('online-price-$k'),
          style: t.textTheme.titleSmall?.copyWith(color: dim ? t.colorScheme.onSurfaceVariant : null),
        ),
        PopupMenuButton<String>(
          key: Key('online-menu-$k'),
          onSelected: (_) => _unlink(link),
          itemBuilder: (_) => const [PopupMenuItem(value: 'unlink', child: Text('Zuordnung lösen'))],
        ),
      ]),
    );
  }
}
