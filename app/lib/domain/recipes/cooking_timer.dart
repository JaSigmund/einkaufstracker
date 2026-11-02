import 'dart:convert';

/// Koch-Timer (ADR-046): die laufende Kochzeit eines Rezepts und beliebige Kurzzeitmesser ("Ofen", "Nudeln"). Rein fachlich, ohne Oberflaeche.
///
/// Alles rechnet mit Zeitpunkten statt mit einem Zaehler, der im Speicher mitlaeuft: Die Zeit stimmt auch, wenn die App zwischendurch im
/// Hintergrund war oder das Betriebssystem sie beendet hat.

/// Kuerzere Laeufe sind Fehlbedienung und wuerden die spaetere Statistik verfaelschen, sie werden nicht gespeichert.
const cookingSessionMinSeconds = 60;

/// So viele Kurzzeitmesser gleichzeitig. Jeder belegt eine feste Benachrichtigungs-ID (`NotificationScheduler`).
const kitchenTimerSlots = 10;

/// Die laufende Kochzeit. Pausen zaehlen nicht mit: [accumulatedSeconds] ist die Zeit bis zur letzten Pause, [runningSince] der Beginn des
/// aktuellen Abschnitts, `null` waehrend einer Pause.
class CookingRun {
  const CookingRun({required this.recipeTitle, required this.startedAt, this.accumulatedSeconds = 0, this.runningSince});

  final String recipeTitle;
  final DateTime startedAt;
  final int accumulatedSeconds;
  final DateTime? runningSince;

  bool get isRunning => runningSince != null;

  /// Eine zurueckgestellte Geraeteuhr darf keine negative Zeit ergeben.
  int elapsedSeconds(DateTime now) {
    final since = runningSince;
    if (since == null) return accumulatedSeconds;
    final running = now.difference(since).inSeconds;
    return accumulatedSeconds + (running < 0 ? 0 : running);
  }

  CookingRun pausedAt(DateTime now) => CookingRun(recipeTitle: recipeTitle, startedAt: startedAt, accumulatedSeconds: elapsedSeconds(now));

  CookingRun resumedAt(DateTime now) => CookingRun(recipeTitle: recipeTitle, startedAt: startedAt, accumulatedSeconds: accumulatedSeconds, runningSince: now);

  Map<String, dynamic> toJson() => {
        'recipeTitle': recipeTitle,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'accumulatedSeconds': accumulatedSeconds,
        if (runningSince != null) 'runningSince': runningSince!.toUtc().toIso8601String(),
      };

  factory CookingRun.fromJson(Map<String, dynamic> j) => CookingRun(
        recipeTitle: j['recipeTitle'] as String,
        startedAt: DateTime.parse(j['startedAt'] as String),
        accumulatedSeconds: (j['accumulatedSeconds'] as num?)?.toInt() ?? 0,
        runningSince: j['runningSince'] == null ? null : DateTime.parse(j['runningSince'] as String),
      );
}

/// Ein Kurzzeitmesser. [slot] (0 bis [kitchenTimerSlots] - 1) bestimmt die Benachrichtigungs-ID.
class KitchenTimer {
  const KitchenTimer({required this.slot, required this.label, required this.endsAt});

  final int slot;
  final String label;
  final DateTime endsAt;

  /// Aufgerundet, damit "00:00" erst dasteht, wenn die Zeit wirklich um ist.
  int remainingSeconds(DateTime now) {
    final ms = endsAt.difference(now).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  bool isDone(DateTime now) => !endsAt.isAfter(now);

  Map<String, dynamic> toJson() => {'slot': slot, 'label': label, 'endsAt': endsAt.toUtc().toIso8601String()};

  factory KitchenTimer.fromJson(Map<String, dynamic> j) =>
      KitchenTimer(slot: (j['slot'] as num).toInt(), label: j['label'] as String, endsAt: DateTime.parse(j['endsAt'] as String));
}

/// Alles, was gerade laeuft; liegt nur auf diesem Geraet (die abgeschlossenen Kochzeiten werden synchronisiert).
class CookingTimerState {
  const CookingTimerState({this.run, this.timers = const []});

  final CookingRun? run;
  final List<KitchenTimer> timers;

  bool get isEmpty => run == null && timers.isEmpty;

  /// Die kleinste freie Kennung, `null` wenn alle belegt sind.
  int? get freeSlot {
    final used = {for (final t in timers) t.slot};
    for (var i = 0; i < kitchenTimerSlots; i++) {
      if (!used.contains(i)) return i;
    }
    return null;
  }

  /// Was als Naechstes ablaeuft; Abgelaufene zuerst, damit sie auffallen.
  List<KitchenTimer> get bySoonest => [...timers]..sort((a, b) => a.endsAt.compareTo(b.endsAt));

  String encode() => jsonEncode({if (run != null) 'run': run!.toJson(), 'timers': [for (final t in timers) t.toJson()]});

  /// Ein beschaedigter Eintrag darf die App nicht aufhalten: was nicht lesbar ist, faellt weg (gleiches Prinzip wie `SavedRecipeRepository`).
  static CookingTimerState decode(String? raw) {
    if (raw == null) return const CookingTimerState();
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      CookingRun? run;
      try {
        if (j['run'] != null) run = CookingRun.fromJson(j['run'] as Map<String, dynamic>);
      } catch (_) {
        // die Kochzeit ist nicht mehr lesbar, die Timer bleiben
      }
      final timers = <KitchenTimer>[];
      for (final t in j['timers'] as List? ?? const []) {
        try {
          timers.add(KitchenTimer.fromJson(t as Map<String, dynamic>));
        } catch (_) {
          // dieser eine Timer ist nicht mehr lesbar
        }
      }
      return CookingTimerState(run: run, timers: timers);
    } catch (_) {
      return const CookingTimerState();
    }
  }
}

/// "04:12", ab einer Stunde "1:02:03".
String formatTimerClock(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  String two(int v) => v.toString().padLeft(2, '0');
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  return h > 0 ? '$h:${two(m)}:${two(s % 60)}' : '${two(m)}:${two(s % 60)}';
}

/// "42 min", "1 h 5 min": fuer abgeschlossene Kochzeiten, Sekunden interessieren dort nicht.
String formatCookingMinutes(int seconds) {
  final minutes = (seconds / 60).round();
  if (minutes < 60) return '$minutes min';
  final rest = minutes % 60;
  return rest == 0 ? '${minutes ~/ 60} h' : '${minutes ~/ 60} h $rest min';
}

/// Rezepte haben keine haushaltsweite Kennung (gespeicherte liegen nur auf dem Geraet, Vorschlaege gar nicht), deshalb zaehlt der Name. Gross- und
/// Kleinschreibung oder Leerzeichen am Rand machen kein anderes Gericht.
String normalizeRecipeTitle(String title) => title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Wie lange ein Gericht bisher gedauert hat.
class CookingStats {
  const CookingStats({required this.count, required this.averageSeconds});
  final int count;
  final int averageSeconds;

  /// "3× gekocht, im Schnitt 42 min".
  String get label => '$count× gekocht, im Schnitt ${formatCookingMinutes(averageSeconds)}';
}

/// `null`, wenn das Gericht noch nie gemessen wurde.
CookingStats? cookingStatsFor(String title, Iterable<({String title, int seconds})> sessions) {
  final key = normalizeRecipeTitle(title);
  final own = [for (final s in sessions) if (normalizeRecipeTitle(s.title) == key) s.seconds];
  if (own.isEmpty) return null;
  return CookingStats(count: own.length, averageSeconds: (own.reduce((a, b) => a + b) / own.length).round());
}
