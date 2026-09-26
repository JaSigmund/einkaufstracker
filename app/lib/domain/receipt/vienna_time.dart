/// Umrechnung von Bon-Zeiten (Ortszeit Europe/Vienna) nach UTC, ohne Zeitzonendatenbank.
///
/// Sommerzeit (MESZ, UTC+2) gilt vom letzten Sonntag im Maerz 01:00 UTC bis zum letzten Sonntag
/// im Oktober 01:00 UTC, sonst MEZ (UTC+1). Die eine mehrdeutige Stunde beim Zurueckstellen wird
/// als Sommerzeit gelesen.
library;

DateTime _lastSunday(int year, int month) {
  final last = DateTime.utc(year, month + 1, 0); // letzter Tag des Monats
  return last.subtract(Duration(days: last.weekday % 7)); // weekday: Mo=1 .. So=7
}

/// true, wenn der UTC-Zeitpunkt in der mitteleuropaeischen Sommerzeit liegt.
bool isViennaDst(DateTime utc) {
  final start = _lastSunday(utc.year, 3).add(const Duration(hours: 1));
  final end = _lastSunday(utc.year, 10).add(const Duration(hours: 1));
  return !utc.isBefore(start) && utc.isBefore(end);
}

/// Ortszeit in Wien (Kalenderfelder wie auf dem Bon gedruckt) als UTC-Zeitpunkt.
DateTime viennaLocalToUtc(int year, int month, int day, int hour, int minute) {
  final asIfUtc = DateTime.utc(year, month, day, hour, minute);
  final summer = asIfUtc.subtract(const Duration(hours: 2));
  if (isViennaDst(summer)) return summer;
  return asIfUtc.subtract(const Duration(hours: 1));
}

/// UTC-Zeitpunkt als Wiener Ortszeit (zur Anzeige). Das Ergebnis ist ein "naives" DateTime ohne Zeitzone,
/// dessen Kalenderfelder der Wanduhr in Wien entsprechen.
DateTime utcToViennaLocal(DateTime utc) {
  final u = utc.toUtc();
  final local = u.add(Duration(hours: isViennaDst(u) ? 2 : 1));
  return DateTime(local.year, local.month, local.day, local.hour, local.minute, local.second);
}

