import 'dart:io';

/// Technischer Stand zum Zeitpunkt eines Fehlerberichts (siehe `bug_reports.app_info`).
///
/// Bewusst ohne zusaetzliches Paket (package_info_plus): die App-Version wird bisher nicht pro Release
/// erhoeht (README), ein "genauer" Versionsstand waere also ohnehin nicht aussagekraeftig. Stattdessen
/// wird der fachlich wichtige Kontext erfasst: wo in der App der Fehler auftrat und ob gerade
/// unsynchronisierte Aenderungen vorlagen (haeufige Fehlerquelle bei Offline-Bugs).
Map<String, dynamic> collectAppInfo({
  required String route,
  required int pendingChanges,
  String? lastSyncError,
  DateTime? lastSyncAt,
}) {
  final now = DateTime.now().toUtc();
  return {
    'platform': Platform.operatingSystem,
    'os_version': Platform.operatingSystemVersion,
    'route': route,
    'pending_changes': pendingChanges,
    'last_sync_error': lastSyncError,
    'last_sync_at': lastSyncAt?.toIso8601String(),
    'reported_at_utc': now.toIso8601String(),
  };
}
