import 'package:supabase_flutter/supabase_flutter.dart';

/// Abstraktion des Servers fuer den Sync (damit der Sync-Code ohne Netz getestet werden kann).
abstract class RemoteStore {
  /// Zeilen mit updated_at >= [since] (Server-Format), aufsteigend nach updated_at, hoechstens [limit].
  Future<List<Map<String, dynamic>>> fetchChanges(String table, {String? since, int limit = 500});

  /// Legt eine Zeile an oder aktualisiert sie (Primaerschluessel id).
  Future<void> upsert(String table, Map<String, dynamic> row);
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
  Future<List<Map<String, dynamic>>> fetchChanges(String table, {String? since, int limit = 500}) async {
    final base = _client.from(table).select();
    final filtered = since == null ? base : base.gte('updated_at', since);
    final rows = await filtered.order('updated_at', ascending: true).limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Future<void> upsert(String table, Map<String, dynamic> row) async {
    try {
      await _client.from(table).upsert(row);
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
