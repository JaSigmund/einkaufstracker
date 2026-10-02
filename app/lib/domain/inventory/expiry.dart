/// Haltbarkeitslogik fuer das Inventar (Doku 06 §1 und §3), rein auf Kalenderdaten (keine Uhrzeit).
library;


/// Ablaufdatum: das frueheste aus Mindesthaltbarkeitsdatum und Oeffnungsfrist, fehlende Werte werden
/// ignoriert. Spiegelt die generierte Spalte `inventory_items.expires_on` in Postgres.
DateTime? computeExpiresOn({DateTime? bestBefore, DateTime? openedOn, int? openShelfLifeDays}) {
  if (openedOn != null && openShelfLifeDays != null) {
    final openExpiry = _dateOnly(openedOn).add(Duration(days: openShelfLifeDays));
    if (bestBefore == null) return openExpiry;
    final bb = _dateOnly(bestBefore);
    return bb.isBefore(openExpiry) ? bb : openExpiry;
  }
  return bestBefore == null ? null : _dateOnly(bestBefore);
}

DateTime _dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// Vorlaufzeit fuer eine Ablauf-Ampel/-Erinnerung: ein Verbrauchsdatum wird erst einen Tag vorher "bald
/// faellig", unabhaengig von der eingestellten Vorlaufzeit fuer Mindesthaltbarkeitsdaten (Doku 06 §3.1).
/// Gemeinsam genutzt von [expiryLevel] (UI-Ampel) und `computeExpiryReminders` (Push-Benachrichtigung,
/// `expiry_reminders.dart`) -- Codereview-Fund 2026-10-01: vorher hatte nur die Ampel diese Sonderregel,
/// die Benachrichtigung kam dadurch bei einem Verbrauchsdatum zu frueh, bevor die App selbst den Eintrag
/// ueberhaupt als "bald faellig" anzeigte.
int effectiveLeadDays(String dateKind, int leadDays) => dateKind == 'use_by' ? 1 : leadDays;

/// Ampel eines Inventareintrags.
enum ExpiryLevel {
  /// Kein Ablaufdatum bekannt (z.B. Bon-Vorschlag ohne MHD und ohne Standardwert).
  unknown,
  ok,
  soon,
  expired,
}

/// Bestimmt die Ampel (Doku 06 §3.1): Verbrauchsdatum wird schon einen Tag vorher gelb, Mindesthaltbarkeits-
/// datum erst innerhalb von [leadDays] (Standard aus den Einstellungen, notify_lead_days).
ExpiryLevel expiryLevel({
  required DateTime? expiresOn,
  required String dateKind, // 'best_before' | 'use_by'
  required DateTime today,
  int leadDays = 3,
}) {
  if (expiresOn == null) return ExpiryLevel.unknown;
  final days = _dateOnly(expiresOn).difference(_dateOnly(today)).inDays;
  final lead = effectiveLeadDays(dateKind, leadDays);
  if (days < 0) return ExpiryLevel.expired;
  if (days <= lead) return ExpiryLevel.soon;
  return ExpiryLevel.ok;
}
