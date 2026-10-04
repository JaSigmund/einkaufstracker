/// Mehrstufige Ablauf-Erinnerungen (Ausbau 1.14): statt einer einzigen Vorlaufzeit ("1 Tag vorher") erinnert die App auf Wunsch
/// mehrfach, z.B. 3 Tage vorher und am Tag selbst. Gilt fuer alle Produkte, ein Produkt kann eigene Stufen haben. Reine Funktionen.
///
/// Gespeichert werden die Stufen als gemeinsame Einstellungen des Haushalts (`household_prefs`):
/// `expiry_reminder_stages` (alle Produkte) und `expiry_stages:<Produkt-ID>` (nur dieses Produkt). Ohne beides gilt die bisherige
/// Vorlaufzeit der Einstellungen als einzige Stufe, es aendert sich also nichts, solange niemand Stufen waehlt.
library;

/// Schluessel der gemeinsamen Einstellungen.
const expiryStagesPref = 'expiry_reminder_stages';
String expiryStagesPrefFor(String productId) => 'expiry_stages:$productId';

/// Waehlbare Stufen in Tagen vor dem Ablauf (0 = am Tag selbst), die groessten zuerst.
const selectableExpiryStages = [7, 5, 3, 2, 1, 0];

/// Hoechstens so viele Stufen je Produkt, sonst wird aus einer Erinnerung ein Dauerfeuer.
const maxExpiryStages = 4;

/// Liest eine Stufenliste aus einem JSON-Wert (Zahlen, auch als Text), defensiv: nur 0 bis 13 (der Planungshorizont ist 14 Tage),
/// ohne Doppelte, groesste zuerst, hoechstens [maxExpiryStages]. `null`, wenn nichts Brauchbares uebrig bleibt (dann gilt der Standard).
List<int>? parseExpiryStages(Object? json) {
  if (json is! List) return null;
  final out = <int>{};
  for (final v in json) {
    final n = v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
    if (n != null && n >= 0 && n <= 13) out.add(n);
  }
  if (out.isEmpty) return null;
  return (out.toList()..sort((a, b) => b.compareTo(a))).take(maxExpiryStages).toList();
}

/// Die Stufen, die fuer einen Posten gelten: bei einem **Verbrauchsdatum** nie frueher als einen Tag vorher (wie die Ampel,
/// `effectiveLeadDays`): [3, 1, 0] wird zu [1, 0], [3] zu [1]. Mindesthaltbarkeitsdaten behalten ihre Stufen. Groesste zuerst.
List<int> effectiveExpiryStages(String dateKind, List<int> stages) {
  final mapped = <int>{for (final s in stages) dateKind == 'use_by' && s > 1 ? 1 : s};
  return mapped.toList()..sort((a, b) => b.compareTo(a));
}

/// "3 Tage und 1 Tag vorher, am Tag selbst" fuer die Anzeige.
String describeExpiryStages(List<int> stages) {
  final sorted = [...stages]..sort((a, b) => b.compareTo(a));
  final days = [for (final s in sorted) if (s > 0) s == 1 ? '1 Tag' : '$s Tage'];
  final parts = <String>[
    if (days.isNotEmpty) '${days.join(' und ')} vorher',
    if (sorted.contains(0)) 'am Tag selbst',
  ];
  return parts.join(', ');
}
