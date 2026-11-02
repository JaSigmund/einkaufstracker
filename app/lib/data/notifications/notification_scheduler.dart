import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../domain/notifications/expiry_reminders.dart';
import '../../domain/recipes/cooking_timer.dart' show kitchenTimerSlots;

/// Plant lokale Ablauf-Erinnerungen (Doku 06 §5, ADR-007: `flutter_local_notifications` statt Server-Push).
/// Als Interface, damit Widget-/Repository-Tests eine Attrappe einsetzen koennen (keine Plattform-Kanaele
/// in `flutter test`).
abstract class NotificationScheduler {
  Future<void> initialize();

  /// Verwirft alle geplanten Ablauf-Erinnerungen und plant sie aus [reminders] neu (Doku 06 §5, Schritt 1).
  Future<void> scheduleExpiryReminders(List<ExpiryReminderDay> reminders, {required String notifyTime, required int leadDays});

  /// Verwirft alle geplanten Ablauf-Erinnerungen, ohne neue zu planen (Abmelden, Konto loeschen): sonst kaeme nach dem
  /// Abmelden noch eine Erinnerung mit den Produktnamen des alten Kontos (Codereview-Fund 2026-10-16).
  Future<void> cancelExpiryReminders();

  /// Plant den Alarm eines Kurzzeitmessers (ADR-046) oder ersetzt den bisherigen in diesem [slot].
  Future<void> scheduleKitchenTimer({required int slot, required String label, required DateTime at});

  Future<void> cancelKitchenTimer(int slot);

  /// Verwirft alle Alarme der Kurzzeitmesser (Abmelden): Sie tragen selbst gewaehlte Bezeichnungen.
  Future<void> cancelKitchenTimers();

  /// Ob Android den Alarm auf die Sekunde genau ausloesen darf. Ohne diese Erlaubnis kann er sich im Hintergrund um Minuten verspaeten.
  Future<bool> canScheduleExactAlarms();

  /// Oeffnet die Systemeinstellung "Wecker und Erinnerungen".
  Future<void> requestExactAlarms();
}

/// Reservierter ID-Bereich, damit `cancel`/`schedule` nur die eigenen Ablauf-Erinnerungen betreffen
/// (14 Tage Horizont, siehe [computeExpiryReminders]).
const _idBase = 5000;
const _horizonDays = 14;
const _channelId = 'expiry_reminders';

/// Eigener ID-Bereich und Kanal der Kurzzeitmesser: ein Timer soll laut sein, eine Ablauf-Erinnerung nicht.
const _timerIdBase = 6000;
const _timerChannelId = 'kitchen_timers';

class FlutterLocalNotificationsScheduler implements NotificationScheduler {
  FlutterLocalNotificationsScheduler({required this.onAddToList});

  /// Aktion "Auf Liste setzen": legt fuer jede in der Erinnerung enthaltene Produkt-ID einen
  /// Einkaufslisten-Eintrag an (Doku 06 §5, Schritt 4).
  final Future<void> Function(String productId) onAddToList;

  final _plugin = FlutterLocalNotificationsPlugin();
  var _initialized = false;

  /// Codereview-Fund 2026-10-02 (Fehlerbericht "Ablauf-Erinnerung kommt nicht an, auch nicht nach
  /// Neustart"): `scheduleExpiryReminders` wird bei JEDER Aenderung des aktiven Bestands oder der
  /// Bon-Vorschlaege neu aufgerufen -- laut Log teils mehrmals pro Sekunde (z.B. beim App-Start oder
  /// durch den periodischen Sync-Timer). Fuer einen nachgeholten (ueberfaelligen) Tag wird unten die
  /// Erinnerung relativ zu "jetzt" um 5 Sekunden verschoben (siehe Kommentar dort) -- kommt der naechste
  /// Aufruf schneller als diese 5 Sekunden, wird der gerade erst geplante Alarm storniert und wieder um
  /// 5 Sekunden verschoben, immer wieder, ohne dass er je auslöst. Bleibt der Inhalt (Artikel, Tag,
  /// Einstellungen) zwischen zwei Aufrufen unveraendert, aendert sich auch nichts am noetigen Alarm --
  /// so ein Aufruf wird hier uebersprungen, statt den laufenden Alarm grundlos neu aufzusetzen.
  String? _lastSignature;

  var _pluginReady = false;

  /// Plugin und Zeitzone, ohne nach der Berechtigung zu fragen (das Stornieren braucht keine).
  Future<void> _initializePlugin() async {
    if (_pluginReady) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Vienna'));
    await _plugin.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: _onResponse,
    );
    _pluginReady = true;
  }

  @override
  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;
    await _initializePlugin();
    // Codereview-Fund 2026-10-01 (Fehlerbericht "Ablauf-Erinnerung kommt nicht an"): das Ergebnis bisher
    // nirgends sichtbar gemacht -- verweigerte Benachrichtigungs-Berechtigung (Android 13+) ist ein sehr
    // naheliegender Grund dafuer, dass GEPLANTE Erinnerungen trotzdem nie als Benachrichtigung erscheinen,
    // ganz ohne Fehler an anderer Stelle.
    final granted =
        await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    debugPrint('[expiry-reminders] Benachrichtigungs-Berechtigung: $granted');
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
    // Browser koennen keine zeitgesteuerten Hintergrund-Benachrichtigungen (ADR-007-Update, iOS-PWA):
    // ohne eigenen Push-Server (Phase 6, FCM) gibt es dafuer keine verlaessliche Web-Entsprechung.
    // Statt eines kryptischen Plattform-Fehlers wird die Planung auf Web bewusst uebersprungen.
    if (kIsWeb) return;
    await initialize();
    final signature = '$notifyTime|$leadDays|${reminders.map((r) {
      final dateStr = '${r.date.year}-${r.date.month}-${r.date.day}';
      return '$dateStr:${r.isOverdue}:${r.leadDays}:${r.productIds.join(',')}';
    }).join(';')}';
    if (signature == _lastSignature) return;
    _lastSignature = signature;
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
        // Codereview-Fund 2026-10-01: r.leadDays statt der globalen Einstellung -- bei einem
        // Verbrauchsdatum (immer 1 Tag Vorlauf) soll der Text "morgen" sagen, nicht die laengere,
        // eingestellte Vorlaufzeit fuer Mindesthaltbarkeitsdaten.
        expiryReminderBody(r.productNames, r.leadDays, isOverdue: r.isOverdue),
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: r.productIds.join(','),
      );
      debugPrint('[expiry-reminders] id ${_idBase + i} geplant fuer $scheduled (jetzt: $now)');
    }
  }

  @override
  Future<void> cancelExpiryReminders() async {
    if (kIsWeb) return;
    // Auch nach einem App-Neustart: die Alarme eines frueheren Prozesses liegen beim Betriebssystem.
    await _initializePlugin();
    _lastSignature = null;
    for (var i = 0; i < _horizonDays; i++) {
      await _plugin.cancel(_idBase + i);
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<void> scheduleKitchenTimer({required int slot, required String label, required DateTime at}) async {
    // Browser koennen keine zeitgesteuerten Benachrichtigungen, siehe scheduleExpiryReminders: Das Ende steht dort nur in der App.
    if (kIsWeb) return;
    await initialize();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _timerChannelId,
        'Koch-Timer',
        channelDescription: 'Meldet sich, wenn ein Timer abgelaufen ist',
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.alarm,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
    );
    final exact = await _android?.canScheduleExactNotifications() ?? false;
    await _plugin.zonedSchedule(
      _timerIdBase + slot,
      label,
      'Die Zeit ist um.',
      tz.TZDateTime.from(at, tz.local),
      details,
      androidScheduleMode: exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  @override
  Future<void> cancelKitchenTimer(int slot) async {
    if (kIsWeb) return;
    await _initializePlugin();
    await _plugin.cancel(_timerIdBase + slot);
  }

  @override
  Future<void> cancelKitchenTimers() async {
    if (kIsWeb) return;
    await _initializePlugin();
    for (var i = 0; i < kitchenTimerSlots; i++) {
      await _plugin.cancel(_timerIdBase + i);
    }
  }

  @override
  Future<bool> canScheduleExactAlarms() async {
    if (kIsWeb) return true;
    await _initializePlugin();
    return await _android?.canScheduleExactNotifications() ?? true;
  }

  @override
  Future<void> requestExactAlarms() async {
    if (kIsWeb) return;
    await _initializePlugin();
    await _android?.requestExactAlarmsPermission();
  }
}
