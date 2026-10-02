import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../domain/online_prices/online_price.dart';
import 'online_article_search.dart';

/// Online-Preise zu einem Produkt (ADR-019): getrennt von der Kaufhistorie, nie in Grundpreis-Statistik oder
/// Haendlervergleich gemischt. Zeigt je Haendler den zugeordneten Artikel mit Preis, Grundpreis und "Stand vom ...",
/// oder "zuletzt bekannt", wenn der Feed nicht mehr gepflegt wird. Faellt der Abruf aus, bleibt der letzte Preis stehen.
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

  Future<void> _pick(String store) async {
    final article = await showOnlineArticleSearch(
      context,
      store: store,
      initialQuery: widget.product.name,
      productBaseUnit: widget.product.baseUnit,
    );
    if (article == null || !mounted) return;
    await ref.read(onlinePriceRepositoryProvider).link(widget.product.id, article);
    unawaited(_refresh(force: true));
  }

  Future<void> _unlink(ProductOnlineLink link) => ref.read(onlinePriceRepositoryProvider).unlink(link.id);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final links = ref.watch(onlineLinksStreamProvider(widget.product.id)).value ?? const <ProductOnlineLink>[];
    final cache = ref.watch(onlinePriceCacheStreamProvider).value ?? const <OnlinePriceCacheRow>[];
    final now = (widget.now ?? DateTime.now)().toUtc();

    return Column(
      key: const Key('online-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Online-Preise', style: t.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Regalpreise aus dem Webshop (heisse-preise.io), getrennt von deinen Käufen.',
          style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline),
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(children: [
            for (final store in onlineStores.keys)
              _storeRow(
                t,
                store,
                links.where((l) => l.store == store).firstOrNull,
                cache,
                now,
              ),
          ]),
        ),
      ],
    );
  }

  Widget _storeRow(ThemeData t, String store, ProductOnlineLink? link, List<OnlinePriceCacheRow> cache, DateTime now) {
    final label = onlineStoreLabel(store);
    if (link == null) {
      return ListTile(
        key: Key('online-row-$store'),
        title: Text(label),
        subtitle: const Text('Noch kein Artikel zugeordnet'),
        trailing: TextButton(key: Key('online-link-$store'), onPressed: () => _pick(store), child: const Text('Zuordnen')),
      );
    }

    final cached = cache.where((c) => c.store == link.store && c.externalId == link.externalId).firstOrNull;
    final freshness = cached == null
        ? OnlinePriceFreshness.stale
        : onlinePriceFreshness(available: cached.available, feedUpdatedAt: cached.feedUpdatedAt?.toUtc(), now: now);
    final dim = freshness != OnlinePriceFreshness.fresh;
    final muted = t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline);
    final name = cached?.name ?? link.linkedName;

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
      key: Key('online-row-$store'),
      isThreeLine: true,
      title: Text('$label · $name'),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (detail.isNotEmpty) Text(detail, key: Key('online-detail-$store')),
        Text(status, key: Key('online-status-$store'), style: dim ? muted : t.textTheme.bodySmall),
        if (mismatch != null) Text(mismatch, key: Key('online-mismatch-$store'), style: muted),
      ]),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(
          cached?.priceCents == null ? '–' : formatEuro(cached!.priceCents!),
          key: Key('online-price-$store'),
          style: t.textTheme.titleSmall?.copyWith(color: dim ? t.colorScheme.outline : null),
        ),
        PopupMenuButton<String>(
          key: Key('online-menu-$store'),
          onSelected: (v) => v == 'change' ? _pick(store) : _unlink(link),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'change', child: Text('Anderen Artikel wählen')),
            PopupMenuItem(value: 'unlink', child: Text('Zuordnung lösen')),
          ],
        ),
      ]),
    );
  }
}
