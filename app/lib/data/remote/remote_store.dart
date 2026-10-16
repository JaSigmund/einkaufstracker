import 'package:supabase_flutter/supabase_flutter.dart';

/// Nach dieser Zeit gilt ein Netzaufruf als haengen geblieben (z.B. abgerissene Mobilfunkverbindung ohne
/// sauberen Verbindungsabbruch) und wird abgebrochen, statt die Synchronisierung fuer immer zu blockieren
/// (Fehlerbericht "Sync bleibt bei 'Synchronisiere...' haengen", 2026-09-28).
const _networkTimeout = Duration(seconds: 20);

/// Abstraktion des Servers fuer den Sync (damit der Sync-Code ohne Netz getestet werden kann).
abstract class RemoteStore {
  /// Zeilen mit updated_at >= [since] (Server-Format), aufsteigend nach updated_at und bei gleichem Zeitstempel nach
  /// [orderKeys] (Primaerschluessel, damit die Reihenfolge stabil ist), ab der [offset]-ten Zeile, hoechstens [limit].
  Future<List<Map<String, dynamic>>> fetchChanges(String table,
      {String? since, int limit = 500, int offset = 0, List<String> orderKeys = const ['id']});

  /// Legt eine Zeile an oder aktualisiert sie (Primaerschluessel id). Liefert den `updated_at` der geschriebenen Zeile
  /// (Server-Zeit, vom Trigger gesetzt), `null` wenn der Server ihn nicht mitgibt.
  Future<String?> upsert(String table, Map<String, dynamic> row);

  /// `updated_at` der Zeilen mit diesen IDs (Server-Format). Zeilen, die es nicht gibt, fehlen im Ergebnis. Grundlage der
  /// Konflikterkennung beim Senden (ADR-018): hat jemand anderes die Zeile seit dem letzten Holen geaendert?
  Future<Map<String, String>> fetchUpdatedAt(String table, List<String> ids);
}

/// Ein Fehler des Servers wegen der Daten selbst (z.B. Unique-Verletzung), nicht wegen des Netzes.
/// Solche Eintraege werden in der Outbox markiert und uebersprungen, damit sie die Queue nicht blockieren.
class RemoteDataException implements Exception {
  RemoteDataException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SupabaseRemoteStore implements RemoteStore {
  SupabaseRemoteStore(this._client);
  final SupabaseClient _client;

  @override
  Future<List<Map<String, dynamic>>> fetchChanges(String table,
      {String? since, int limit = 500, int offset = 0, List<String> orderKeys = const ['id']}) async {
    final base = _client.from(table).select();
    final filtered = since == null ? base : base.gte('updated_at', since);
    var ordered = filtered.order('updated_at', ascending: true);
    for (final key in orderKeys) {
      ordered = ordered.order(key, ascending: true);
    }
    final rows = await ordered.range(offset, offset + limit - 1).timeout(_networkTimeout);
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Future<Map<String, String>> fetchUpdatedAt(String table, List<String> ids) async {
    if (ids.isEmpty) return const {};
    final rows = await _client.from(table).select('id, updated_at').inFilter('id', ids).timeout(_networkTimeout);
    return {for (final r in rows) r['id'] as String: r['updated_at'] as String};
  }

  @override
  Future<String?> upsert(String table, Map<String, dynamic> row) async {
    try {
      final written = await _client.from(table).upsert(row).select('updated_at').timeout(_networkTimeout);
      return written.isEmpty ? null : written.first['updated_at'] as String?;
    } on PostgrestException catch (e) {
      // 4xx/Constraint-Fehler sind Datenfehler, alles andere (Netz, Auth) bleibt eine normale Exception
      final code = int.tryParse(e.code ?? '');
      final isDataError = (e.code != null && RegExp(r'^(23|22|42|PGRST)').hasMatch(e.code!)) ||
          (code != null && code >= 400 && code < 500 && code != 401 && code != 408 && code != 429);
      if (isDataError) throw RemoteDataException('${e.code}: ${e.message}');
      rethrow;
    }
  }
}
