import 'package:supabase_flutter/supabase_flutter.dart';

/// Server-seitig gepflegte App-Konfiguration (ADR-022 "Update erforderlich"): aktuell nur die
/// Mindest-Build-Nummer, unter der Sync/Cloud-Funktionen gesperrt werden.
class AppConfig {
  const AppConfig({required this.minSupportedBuildNumber, this.message});

  final int minSupportedBuildNumber;

  /// Optionaler, von Jakob gepflegter Zusatztext fuer die Update-Meldung (z.B. "wegen eines neuen
  /// Preisvergleichs"). `null` zeigt einen Standardtext.
  final String? message;

  factory AppConfig.fromJson(Map<String, dynamic> j) => AppConfig(
        minSupportedBuildNumber: (j['min_supported_build_number'] as num).toInt(),
        message: j['message'] as String?,
      );
}

/// Liest `app_config` direkt vom Server (gleiches Muster wie `ChangelogRepository`: reine Infotabelle,
/// kein Haushaltsbezug, von der Entwicklung per SQL gepflegt, kein Sync/Outbox noetig).
class AppConfigRepository {
  AppConfigRepository(this._client);
  final SupabaseClient _client;

  Future<AppConfig> load() async {
    final row = await _client.from('app_config').select().eq('id', true).single().timeout(const Duration(seconds: 20));
    return AppConfig.fromJson(row);
  }
}
