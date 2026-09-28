import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Ein Eintrag im Aenderungsprotokoll der App (Doku-Wunsch "Changelog der Versionen").
class ChangelogEntry {
  const ChangelogEntry({required this.version, required this.title, required this.highlights, required this.releasedAt});

  final String version;
  final String title;
  final List<String> highlights;
  final DateTime releasedAt;

  factory ChangelogEntry.fromJson(Map<String, dynamic> j) => ChangelogEntry(
        version: j['version'] as String,
        title: j['title'] as String,
        highlights: (j['highlights'] as List? ?? const []).cast<String>(),
        releasedAt: DateTime.parse(j['released_at'] as String).toUtc(),
      );
}

/// Liest das Aenderungsprotokoll direkt vom Server (Doku 09: reine Infotabelle, nicht haushaltsbezogen,
/// deshalb ohne die Outbox/Sync-Maschinerie der Fachdaten - sie wird von der Entwicklung per SQL gepflegt).
/// Braucht Netz; ohne Netz zeigt die Seite eine verstaendliche Fehlermeldung statt abzustuerzen.
class ChangelogRepository {
  ChangelogRepository(this._client);
  final SupabaseClient _client;

  Future<List<ChangelogEntry>> load() async {
    final rows = await _client.from('app_changelog').select().order('released_at', ascending: false).timeout(const Duration(seconds: 20));
    return (rows as List).map((r) => ChangelogEntry.fromJson(r as Map<String, dynamic>)).toList();
  }
}
