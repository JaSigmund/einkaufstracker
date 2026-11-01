import 'dart:io';

import '../../core/clock.dart';

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
  List<Map<String, dynamic>> rejectedChanges = const [],
}) {
  final now = appClock.now().toUtc();
  return {
    'platform': Platform.operatingSystem,
    'os_version': Platform.operatingSystemVersion,
    'route': route,
    'pending_changes': pendingChanges,
    'last_sync_error': lastSyncError,
    'last_sync_at': lastSyncAt?.toIso8601String(),
    // Der Banner schickt bei abgelehnten Aenderungen zum Fehlerbericht, dort ist last_sync_error aber leer: der Grund muss hierher
    'rejected_changes': rejectedChanges,
    'reported_at_utc': now.toIso8601String(),
  };
}
