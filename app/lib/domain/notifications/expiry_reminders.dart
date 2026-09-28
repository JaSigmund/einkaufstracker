import '../../data/local/database.dart';

/// Eine gebuendelte Ablauf-Erinnerung fuer einen Tag (Doku 06 §5): alle Produkte, deren
/// `expires_on - notify_lead_days` auf diesen Tag faellt, werden zu einer Benachrichtigung zusammengefasst.
class ExpiryReminderDay {
  const ExpiryReminderDay({required this.date, required this.productIds, required this.productNames});

  /// Kalendertag (Wiener Ortszeit, Mitternacht), an dem die Erinnerung ausgeloest wird.
  final DateTime date;
  final List<String> productIds;
  final List<String> productNames;
}

/// Fuer jeden Tag in den naechsten [horizonDays] Tagen: welche aktiven Bestaende (mit bekanntem Ablauf)
/// an diesem Tag erinnert werden sollen (Doku 06 §5, Schritt 1-2). Reine Funktion, keine Abhaengigkeit von
/// Uhrzeit/Plattform, damit sie ohne Benachrichtigungs-Plugin testbar ist.
List<ExpiryReminderDay> computeExpiryReminders({
  required List<InventoryItem> activeItems,
  required Map<String, String> productNameById,
  required int leadDays,
  required DateTime today,
  int horizonDays = 14,
}) {
  final byDay = <DateTime, Map<String, String>>{};
  for (final item in activeItems) {
    final expiresOn = item.expiresOn;
    if (expiresOn == null) continue;
    final name = productNameById[item.productId];
    if (name == null) continue;
    final reminderDate = DateTime.utc(expiresOn.year, expiresOn.month, expiresOn.day).subtract(Duration(days: leadDays));
    final offset = reminderDate.difference(today).inDays;
    if (offset < 0 || offset >= horizonDays) continue;
    byDay.putIfAbsent(reminderDate, () => {})[item.productId] = name;
  }
  final sortedDays = byDay.keys.toList()..sort();
  return [
    for (final day in sortedDays)
      ExpiryReminderDay(date: day, productIds: byDay[day]!.keys.toList(), productNames: byDay[day]!.values.toList()),
  ];
}

/// Text der Benachrichtigung, z.B. "Milch, Joghurt laufen morgen ab." (Doku 06 §5).
String expiryReminderBody(List<String> productNames, int leadDays) {
  final names = productNames.join(', ');
  final verb = productNames.length == 1 ? 'läuft' : 'laufen';
  final when = switch (leadDays) {
    0 => 'heute',
    1 => 'morgen',
    _ => 'in $leadDays Tagen',
  };
  return '$names $verb $when ab.';
}
