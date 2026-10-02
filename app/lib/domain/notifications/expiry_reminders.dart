import '../../data/local/database.dart';
import '../inventory/expiry.dart';

/// Eine gebuendelte Ablauf-Erinnerung fuer einen Tag (Doku 06 §5): alle Produkte, deren
/// `expires_on - notify_lead_days` auf diesen Tag faellt, werden zu einer Benachrichtigung zusammengefasst.
class ExpiryReminderDay {
  const ExpiryReminderDay(
      {required this.date, required this.productIds, required this.productNames, this.isOverdue = false, this.leadDays = 0});

  /// Kalendertag (Wiener Ortszeit, Mitternacht), an dem die Erinnerung ausgeloest wird.
  final DateTime date;
  final List<String> productIds;
  final List<String> productNames;

  /// True, wenn der eigentliche Erinnerungstag (Ablauf − Vorlaufzeit) schon vor [date] lag und die
  /// Erinnerung deshalb nachgeholt wird (siehe Funktionskommentar unten, "Nachholen" von verpassten
  /// Tagen) -- die Formulierung in `expiryReminderBody` soll dann nicht "läuft morgen ab" sagen, wenn
  /// es eigentlich schon faellig oder abgelaufen ist.
  final bool isOverdue;

  /// Fuer den Nachrichtentext (`expiryReminderBody`): die kleinste tatsaechlich wirksame Vorlaufzeit
  /// (siehe `effectiveLeadDays`) unter den an diesem Tag gebuendelten Produkten -- bei einer Mischung aus
  /// Verbrauchsdatum (immer 1 Tag) und Mindesthaltbarkeitsdatum (eingestellte Vorlaufzeit) soll der Text
  /// den dringlicheren Fall nennen, statt den Nutzer zu spaet zu warnen (Codereview-Fund 2026-10-01).
  final int leadDays;
}

/// Fuer jeden Tag in den naechsten [horizonDays] Tagen: welche aktiven Bestaende (mit bekanntem Ablauf)
/// an diesem Tag erinnert werden sollen (Doku 06 §5, Schritt 1-2). Reine Funktion, keine Abhaengigkeit von
/// Uhrzeit/Plattform, damit sie ohne Benachrichtigungs-Plugin testbar ist.
///
/// **Nachholen verpasster Erinnerungstage** (Fehlerbericht "keine Push-Benachrichtigung", zweiter
/// Anlauf 2026-10-01): Diese Funktion wird nur bei App-Start oder einer Inventaraenderung neu
/// aufgerufen (`rescheduleExpiryReminders`), nicht exakt am Erinnerungstag selbst. Lag der
/// rechnerische Erinnerungstag (`expires_on - leadDays`) schon VOR [today] — z.B. weil die App
/// zwischendurch nicht geoeffnet wurde — wurde dieser Tag bisher stillschweigend verworfen (`offset <
/// 0`), die Erinnerung ging also fuer immer verloren, obwohl der Artikel noch aktiv (nicht
/// aufgebraucht/weggeworfen) im Inventar steht. Jetzt wird ein verpasster Tag auf [today] nachgeholt,
/// solange er nicht laenger als [horizonDays] zurueckliegt (sonst waere ein uralter Posten, der nie
/// bearbeitet wurde, jeden Tag aufs Neue dabei).
List<ExpiryReminderDay> computeExpiryReminders({
  required List<InventoryItem> activeItems,
  required Map<String, String> productNameById,
  required int leadDays,
  required DateTime today,
  int horizonDays = 14,
}) {
  final byDay = <DateTime, Map<String, String>>{};
  final overdueDays = <DateTime>{};
  final leadByDay = <DateTime, int>{};
  for (final item in activeItems) {
    final expiresOn = item.expiresOn;
    if (expiresOn == null) continue;
    final name = productNameById[item.productId];
    if (name == null) continue;
    // Codereview-Fund 2026-10-01: dieselbe Sonderregel wie die UI-Ampel (expiry.dart) -- sonst kam die
    // Benachrichtigung bei einem Verbrauchsdatum schon Tage vor der eingestellten Vorlaufzeit, obwohl die
    // App den Eintrag selbst noch gar nicht als "bald faellig" zeigte.
    final lead = effectiveLeadDays(item.dateKind, leadDays);
    final reminderDate = DateTime.utc(expiresOn.year, expiresOn.month, expiresOn.day).subtract(Duration(days: lead));
    final offset = reminderDate.difference(today).inDays;
    if (offset >= horizonDays || offset < -horizonDays) continue;
    final effectiveDate = offset < 0 ? today : reminderDate;
    if (offset < 0) overdueDays.add(effectiveDate);
    byDay.putIfAbsent(effectiveDate, () => {})[item.productId] = name;
    // Bei einer Mischung aus Verbrauchs- und Mindesthaltbarkeitsdatum am selben Tag gilt die kleinere
    // (dringlichere) Vorlaufzeit fuer den Nachrichtentext, siehe ExpiryReminderDay.leadDays.
    final existingLead = leadByDay[effectiveDate];
    leadByDay[effectiveDate] = existingLead == null ? lead : (lead < existingLead ? lead : existingLead);
  }
  final sortedDays = byDay.keys.toList()..sort();
  return [
    for (final day in sortedDays)
      ExpiryReminderDay(
        date: day,
        productIds: byDay[day]!.keys.toList(),
        productNames: byDay[day]!.values.toList(),
        isOverdue: overdueDays.contains(day),
        leadDays: leadByDay[day]!,
      ),
  ];
}

/// Text der Benachrichtigung, z.B. "Milch, Joghurt laufen morgen ab." (Doku 06 §5). Bei einer
/// nachgeholten, eigentlich schon faelligen Erinnerung ([isOverdue]) wird bewusst nicht
/// "läuft morgen ab" behauptet, wenn der Artikel in Wahrheit schon faellig oder abgelaufen ist.
String expiryReminderBody(List<String> productNames, int leadDays, {bool isOverdue = false}) {
  final names = productNames.join(', ');
  if (isOverdue) {
    final verb = productNames.length == 1 ? 'ist' : 'sind';
    return '$names $verb bereits fällig oder abgelaufen.';
  }
  final verb = productNames.length == 1 ? 'läuft' : 'laufen';
  final when = switch (leadDays) {
    0 => 'heute',
    1 => 'morgen',
    _ => 'in $leadDays Tagen',
  };
  return '$names $verb $when ab.';
}
