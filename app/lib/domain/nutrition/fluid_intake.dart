/// Trinkmenge, Ziel und Erinnerung (ADR-049, Doku 26 §2.7). Rein fachlich, ohne Oberflaeche.
library;

/// Vorbelegung des Ziels: rund 1,5 l Getraenke am Tag, der Richtwert der DGE fuer Erwachsene. Eine Orientierung, in den Einstellungen aenderbar.
const defaultFluidTargetMl = 1500.0;

/// Schluessel in `household_prefs`.
const fluidTargetPref = 'fluid_target_ml';
const fluidReminderOnPref = 'fluid_reminder_on';
const fluidReminderTimePref = 'fluid_reminder_time';

/// So viele Tage im Voraus wird die Erinnerung geplant. Wer die App so lange nicht oeffnet, bekommt keine mehr.
const fluidReminderDays = 7;

/// Ziel und Erinnerung, wie sie gelten. Die Erinnerung ist an, bis jemand sie abschaltet (Q-34).
class FluidSettings {
  const FluidSettings({this.targetMl = defaultFluidTargetMl, this.reminderOn = true, this.hour = 16, this.minute = 0});

  final double targetMl;
  final bool reminderOn;
  final int hour;
  final int minute;

  /// Liest defensiv: Was nicht passt, faellt auf die Vorbelegung zurueck.
  factory FluidSettings.fromPrefs(Map<String, Object?> prefs) {
    final target = prefs[fluidTargetPref];
    final time = prefs[fluidReminderTimePref];
    final parts = time is String ? time.split(':') : const <String>[];
    final hour = parts.length == 2 ? int.tryParse(parts[0]) : null;
    final minute = parts.length == 2 ? int.tryParse(parts[1]) : null;
    final validTime = hour != null && minute != null && hour >= 0 && hour < 24 && minute >= 0 && minute < 60;
    return FluidSettings(
      targetMl: target is num && target > 0 ? target.toDouble() : defaultFluidTargetMl,
      reminderOn: prefs[fluidReminderOnPref] != false,
      hour: validTime ? hour : 16,
      minute: validTime ? minute : 0,
    );
  }

  String get timeText => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// Die Menge einer Getraenke-Zutat in ml. Gewogenes (Kaffeepulver) und gezaehltes ohne Volumen (Teebeutel) ist kein Getrunkenes.
double drinkIngredientMl({required String unit, required double quantity, double? amountG}) => switch (unit) {
      'l' => quantity * 1000,
      'piece' => amountG ?? 0,
      _ => 0,
    };

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Getrunkene ml an dem Kalendertag von [day]; alle Zeitpunkte in Wiener Ortszeit. Das ist eine Naeherung: Auch Milch oder Alkohol zaehlen voll.
double fluidMlOn(DateTime day, Iterable<({DateTime at, double ml})> entries) =>
    entries.where((e) => _sameDay(e.at, day)).fold(0, (sum, e) => sum + e.ml);

/// Wann die Erinnerung kommt, in Wiener Ortszeit. Zum Ausloesezeitpunkt laeuft kein App-Code, deshalb wird im Voraus geplant und bei jedem Eintrag neu
/// gerechnet: Heute kommt sie nur, wenn die Uhrzeit noch bevorsteht und weniger als die Haelfte des Ziels getrunken ist.
List<DateTime> fluidReminderTimes({required DateTime now, required FluidSettings settings, required double drunkMl}) {
  if (!settings.reminderOn) return const [];
  return [
    for (var i = 0; i < fluidReminderDays; i++)
      if (DateTime(now.year, now.month, now.day + i, settings.hour, settings.minute) case final at
          when i > 0 || (at.isAfter(now) && drunkMl < settings.targetMl / 2))
        at,
  ];
}

/// "1,4 l".
String formatLiters(double ml) => '${(ml / 1000).toStringAsFixed(1).replaceAll('.', ',')} l';
