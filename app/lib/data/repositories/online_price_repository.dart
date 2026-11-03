import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/clock.dart';
import '../../domain/online_prices/online_price.dart';
import '../local/database.dart';
import '../online_prices/online_price_remote.dart';
import '../sync/mappers.dart';

/// Online-Preise zu eigenen Produkten (ADR-019): die vom Nutzer bestaetigten Verknuepfungen (offline-first ueber die
/// Outbox, wie die uebrigen Repositories) und ein lokaler Zwischenspeicher der zuletzt geholten Preise.
class OnlinePriceRepository {
  OnlinePriceRepository(this._db, this._remote, {required this.householdId, this.onChanged, DateTime Function()? now, Uuid? uuid})
      : _now = now ?? DateTime.now,
        _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final OnlinePriceRemote _remote;
  final Future<String> Function() householdId;
  final void Function()? onChanged;
  final DateTime Function() _now;
  final Uuid _uuid;

  /// Wie oft die Preise hoechstens automatisch neu geholt werden. Der Server aktualisiert sie nur einmal am Tag.
  static const refreshInterval = Duration(hours: 6);
  static const _refreshedAtKey = 'online_prices_refreshed_at';

  /// Aktive Verknuepfungen eines Produkts.
  Stream<List<ProductOnlineLink>> watchLinksFor(String productId) =>
      (_db.select(_db.productOnlineLinks)..where((l) => l.productId.equals(productId) & l.deletedAt.isNull())).watch();

  /// Alle aktiven Verknuepfungen, fuer die Produktliste.
  Stream<List<ProductOnlineLink>> watchActiveLinks() => (_db.select(_db.productOnlineLinks)..where((l) => l.deletedAt.isNull())).watch();

  /// Alle aktiven Verknuepfungen (fuer den Abruf).
  Future<List<ProductOnlineLink>> activeLinks() => (_db.select(_db.productOnlineLinks)..where((l) => l.deletedAt.isNull())).get();

  /// Zwischengespeicherte Preise aller verknuepften Artikel.
  Stream<List<OnlinePriceCacheRow>> watchCache() => _db.select(_db.onlinePriceCache).watch();

  /// Aehnliche Artikel zum Namen, Basiseinheit des Produkts bevorzugt. Wirft [OnlinePricesUnavailable] ohne Netz.
  Future<List<OnlineArticle>> search(String query, {List<String> stores = const ['billa', 'spar'], String? productBaseUnit}) =>
      _remote.search(query, stores: stores, preferBase: productBaseUnit == null ? null : onlineBaseUnitOf(productBaseUnit));

  /// Verknuepft [productId] mit [article]. Ein Produkt kann beliebig viele Online-Artikel haben, auch mehrere beim selben
  /// Haendler (Bio-Paprika und normale Paprika sind bei Billa zwei Artikel, fuer den Einkauf aber dasselbe Produkt). Derselbe
  /// Artikel wird nur einmal je Produkt gefuehrt: ein zweites Verknuepfen aendert nichts. Der Preis des Artikels wird gleich
  /// zwischengespeichert, damit er sofort sichtbar ist.
  Future<void> link(String productId, OnlineArticle article) => linkAll(productId, [article]);

  /// Wie [link] fuer mehrere Artikel auf einmal (eine Transaktion, ein Sync-Anstoss).
  Future<void> linkAll(String productId, Iterable<OnlineArticle> articles) async {
    final hid = await householdId();
    final now = _now().toUtc();
    var changed = false;
    await _db.transaction(() async {
      for (final article in articles) {
        final existing = await (_db.select(_db.productOnlineLinks)
              ..where((l) =>
                  l.productId.equals(productId) & l.store.equals(article.store) & l.externalId.equals(article.externalId) & l.deletedAt.isNull()))
            .getSingleOrNull();
        if (existing == null) {
          final row = ProductOnlineLink(
            id: _uuid.v4(),
            householdId: hid,
            productId: productId,
            store: article.store,
            externalId: article.externalId,
            linkedName: article.name,
            updatedAt: now,
            deletedAt: null,
          );
          await _db.into(_db.productOnlineLinks).insertOnConflictUpdate(row.toCompanion(false));
          await _enqueue(row);
          await _db.into(_db.onlinePriceCache).insertOnConflictUpdate(
                _cacheRow(article, available: true, feedUpdatedAt: null, fetchedAt: now),
              );
          changed = true;
        }
      }
    });
    if (changed) onChanged?.call();
  }

  /// Loest die Verknuepfung (Soft-Delete, damit der Sync sie auf andere Geraete bringt).
  Future<void> unlink(String linkId) async {
    final link = await (_db.select(_db.productOnlineLinks)..where((l) => l.id.equals(linkId))).getSingleOrNull();
    if (link == null) return;
    final row = link.copyWith(deletedAt: Value(_now().toUtc()), updatedAt: _now().toUtc());
    await _db.transaction(() async {
      await _db.into(_db.productOnlineLinks).insertOnConflictUpdate(row.toCompanion(false));
      await _enqueue(row);
    });
    onChanged?.call();
  }

  /// Holt den aktuellen Stand aller verknuepften Artikel und aktualisiert den Zwischenspeicher. Ohne [force] hoechstens alle
  /// [refreshInterval] und nur, wenn es Verknuepfungen gibt. Ein Fehler (kein Netz) laesst den Zwischenspeicher unveraendert und
  /// wird nicht geworfen: die App zeigt dann den zuletzt bekannten Preis. Liefert `true`, wenn neue Daten geholt wurden.
  Future<bool> refresh({bool force = false}) async {
    final links = await activeLinks();
    if (links.isEmpty) return false;
    final now = _now().toUtc();
    if (!force) {
      final last = DateTime.tryParse(await _db.getKv(_refreshedAtKey) ?? '');
      if (last != null && now.difference(last) < refreshInterval) return false;
    }

    final OnlineFetchResult result;
    try {
      result = await _remote.fetch([for (final l in links) (store: l.store, externalId: l.externalId)]);
    } on OnlinePricesUnavailable {
      return false;
    }

    await _db.transaction(() async {
      for (final l in links) {
        final key = onlineKey(l.store, l.externalId);
        final article = result.found[key];
        if (article != null) {
          await _db.into(_db.onlinePriceCache).insertOnConflictUpdate(
                _cacheRow(article, available: true, feedUpdatedAt: onlineArticleUpdatedAt(article.seenAt, result.feedLastModified), fetchedAt: now),
              );
          continue;
        }
        // Nicht mehr im Feed: letzten bekannten Preis behalten, nur als nicht verfuegbar markieren
        final cached = await (_db.select(_db.onlinePriceCache)..where((c) => c.store.equals(l.store) & c.externalId.equals(l.externalId))).getSingleOrNull();
        await _db.into(_db.onlinePriceCache).insertOnConflictUpdate(
              (cached ?? OnlinePriceCacheRow(store: l.store, externalId: l.externalId, name: l.linkedName, available: false, fetchedAt: now))
                  .copyWith(available: false, feedUpdatedAt: Value(cached?.feedUpdatedAt ?? result.feedLastModified), fetchedAt: now)
                  .toCompanion(false),
            );
      }
      await _db.setKv(_refreshedAtKey, now.toIso8601String());
    });
    return true;
  }

  OnlinePriceCacheCompanion _cacheRow(OnlineArticle a, {required bool available, required DateTime? feedUpdatedAt, required DateTime fetchedAt}) =>
      OnlinePriceCacheCompanion(
        store: Value(a.store),
        externalId: Value(a.externalId),
        name: Value(a.name),
        priceCents: Value(a.priceCents),
        quantity: Value(a.quantity),
        unit: Value(a.unit),
        baseUnit: Value(a.baseUnit),
        unitPriceNormCents: Value(a.unitPriceNormCents),
        available: Value(available),
        feedUpdatedAt: Value(feedUpdatedAt),
        fetchedAt: Value(fetchedAt),
      );

  Future<void> _enqueue(ProductOnlineLink row) => _db.into(_db.outbox).insert(OutboxCompanion.insert(
        remoteTable: 'product_online_links',
        rowId: row.id,
        payload: jsonEncode(productOnlineLinkToRemote(row)),
        createdAt: appClock.now().toUtc(),
      ));
}
