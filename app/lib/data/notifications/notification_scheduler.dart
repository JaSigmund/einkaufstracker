import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../domain/notifications/expiry_reminders.dart';

/// Plant lokale Ablauf-Erinnerungen (Doku 06 §5, ADR-007: `flutter_local_notifications` statt Server-Push).
/// Als Interface, damit Widget-/Repository-Tests eine Attrappe einsetzen koennen (keine Plattform-Kanaele
/// in `flutter test`).
abstract class NotificationScheduler {
  Future<void> initialize();

  /// Verwirft alle geplanten Ablauf-Erinnerungen und plant sie aus [reminders] neu (Doku 06 §5, Schritt 1).
  Future<void> scheduleExpiryReminders(List<ExpiryReminderDay> reminders, {required String notifyTime, required int leadDays});
}

/// Reservierter ID-Bereich, damit `cancel`/`schedule` nur die eigenen Ablauf-Erinnerungen betreffen
/// (14 Tage Horizont, siehe [computeExpiryReminders]).
const _idBase = 5000;
const _horizonDays = 14;
const _channelId = 'expiry_reminders';

class FlutterLocalNotificationsScheduler implements NotificationScheduler {
  FlutterLocalNotificationsScheduler({required this.onAddToList});

  /// Aktion "Auf Liste setzen": legt fuer jede in der Erinnerung enthaltene Produkt-ID einen
  /// Einkaufslisten-Eintrag an (Doku 06 §5, Schritt 4).
  final Future<void> Function(String productId) onAddToList;

  final _plugin = FlutterLocalNotificationsPlugin();
  var _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Vienna'));
    await _plugin.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: _onResponse,
    );
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    _initialized = true;
  }

  Future<void> _onResponse(NotificationResponse response) async {
    if (response.actionId != 'add_to_list') return;
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    for (final productId in payload.split(',')) {
      await onAddToList(productId);
    }
  }

  @override
  Future<void> scheduleExpiryReminders(List<ExpiryReminderDay> reminders, {required String notifyTime, required int leadDays}) async {
    await initialize();
    for (var i = 0; i < _horizonDays; i++) {
      await _plugin.cancel(_idBase + i);
    }
    final parts = notifyTime.split(':');
    final hour = int.tryParse(parts[0]) ?? 7;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 30 : 30;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'Ablauf-Erinnerungen',
        channelDescription: 'Erinnert an Produkte, deren Haltbarkeit bald abläuft',
        importance: Importance.defaultImportance,
        actions: [
          AndroidNotificationAction('add_to_list', 'Auf Liste setzen', showsUserInterface: true),
          AndroidNotificationAction('ignore', 'Ignorieren', cancelNotification: true),
        ],
      ),
    );

    for (var i = 0; i < reminders.length && i < _horizonDays; i++) {
      final r = reminders[i];
      var scheduled = tz.TZDateTime(tz.local, r.date.year, r.date.month, r.date.day, hour, minute);
      final now = tz.TZDateTime.now(tz.local);
      // Die Uhrzeit fuer den (ggf. nachgeholten, siehe computeExpiryReminders) heutigen Erinnerungstag
      // ist schon vorbei: sofort erinnern statt den ganzen Tag zu verlieren (Fehlerbericht "keine
      // Push-Benachrichtigung", zweiter Anlauf 2026-10-01 -- die erste Korrektur deckte nur
      // Bon-Vorschlaege ab, nicht verpasste Erinnerungstage).
      if (scheduled.isBefore(now)) scheduled = now.add(const Duration(seconds: 5));
      await _plugin.zonedSchedule(
        _idBase + i,
        r.productNames.length == 1 ? '1 Artikel läuft bald ab' : '${r.productNames.length} Artikel laufen bald ab',
        expiryReminderBody(r.productNames, leadDays, isOverdue: r.isOverdue),
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: r.productIds.join(','),
      );
    }
  }
}
