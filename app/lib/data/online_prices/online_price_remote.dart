import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/online_prices/online_price.dart';

/// Die Online-Preise sind gerade nicht erreichbar (kein Netz, Serverfehler). Nichts in der App haengt davon ab: der
/// zuletzt bekannte Preis bleibt lokal sichtbar (ADR-019).
class OnlinePricesUnavailable implements Exception {
  const OnlinePricesUnavailable([this.message = 'nicht erreichbar']);
  final String message;
  @override
  String toString() => message;
}

/// Ergebnis eines Abrufs der verknuepften Artikel.
class OnlineFetchResult {
  const OnlineFetchResult({required this.found, this.feedLastModified});

  /// Artikel, die es im Feed noch gibt, nach `store/externalId`.
  final Map<String, OnlineArticle> found;

  /// Stand des Feeds selbst (`online_feed_status.feed_last_modified`), `null`, wenn der Server noch nie erfolgreich war.
  final DateTime? feedLastModified;
}

String onlineKey(String store, String externalId) => '$store/$externalId';

/// Zugriff auf `online_prices` (nur lesbar fuer angemeldete Nutzer, Migration 0018). Als Schnittstelle, damit Repository
/// und Oberflaeche ohne Netz getestet werden koennen.
abstract class OnlinePriceRemote {
  /// Aehnliche Artikel zu [query] bei [stores], hoechstens [perStore] je Haendler. [preferBase] (`kg`, `l`, `stk`) stellt
  /// Artikel mit derselben Basiseinheit wie das eigene Produkt bei gleicher Treffergenauigkeit nach vorn.
  Future<List<OnlineArticle>> search(String query, {List<String> stores = const ['billa', 'spar'], int perStore = 8, String? preferBase});

  /// Aktueller Stand der Artikel mit diesen Schluesseln (`store`, `externalId`).
  Future<OnlineFetchResult> fetch(List<({String store, String externalId})> links);
}

class SupabaseOnlinePriceRemote implements OnlinePriceRemote {
  SupabaseOnlinePriceRemote(this._client);
  final SupabaseClient _client;

  static const _timeout = Duration(seconds: 15);
  static const _columns = 'store,external_id,name,price_cents,quantity,unit,base_unit,unit_price_norm_cents';

  @override
  Future<List<OnlineArticle>> search(String query, {List<String> stores = const ['billa', 'spar'], int perStore = 8, String? preferBase}) async {
    if (query.trim().length < 2) return const [];
    try {
      final rows = await _client
          .rpc('search_online_prices', params: {'q': query.trim(), 'wanted_stores': stores, 'per_store': perStore, 'prefer_base': preferBase})
          .timeout(_timeout);
      return [for (final r in rows as List) onlineArticleFromRow(Map<String, dynamic>.from(r as Map))].whereType<OnlineArticle>().toList();
    } catch (e) {
      throw OnlinePricesUnavailable(e.toString());
    }
  }

  @override
  Future<OnlineFetchResult> fetch(List<({String store, String externalId})> links) async {
    try {
      final found = <String, OnlineArticle>{};
      final byStore = <String, List<String>>{};
      for (final l in links) {
        byStore.putIfAbsent(l.store, () => []).add(l.externalId);
      }
      for (final entry in byStore.entries) {
        final rows = await _client.from('online_prices').select(_columns).eq('store', entry.key).inFilter('external_id', entry.value).timeout(_timeout);
        for (final r in rows) {
          final a = onlineArticleFromRow(Map<String, dynamic>.from(r));
          if (a != null) found[onlineKey(a.store, a.externalId)] = a;
        }
      }
      final status = await _client.from('online_feed_status').select('feed_last_modified').eq('source', 'heisse_preise').maybeSingle().timeout(_timeout);
      final modified = status?['feed_last_modified'];
      return OnlineFetchResult(found: found, feedLastModified: modified is String ? DateTime.tryParse(modified)?.toUtc() : null);
    } catch (e) {
      throw OnlinePricesUnavailable(e.toString());
    }
  }
}
