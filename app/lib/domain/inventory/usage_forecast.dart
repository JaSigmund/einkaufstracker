/// Verbrauchsraten-Vorhersage (Ausbau 1.14): Aus dem Ledger `inventory_movements` ergibt sich, wie schnell ein Produkt im Haushalt
/// aufgebraucht wird, und damit, wie lange der aktuelle Bestand reicht. Reine Funktionen ohne Datenbankzugriff.
///
/// Regeln (alle gegen falsche Sicherheit):
/// - **Verbrauch** ist, was als "aufgebraucht" oder durch eine Mahlzeit abging, abzueglich der Gegenbuchungen zu geloeschten oder
///   geaenderten Mahlzeiten. Weggeworfenes und Inventur-Korrekturen zaehlen nicht (wie in der Verbrauchsbilanz).
/// - Die Rate ist Verbrauch je **Kalendertag** im Beobachtungszeitraum, nicht je Tag mit Verbrauch: Tage ohne Verbrauch gehoeren dazu.
/// - Es gibt erst eine Vorhersage, wenn der Zeitraum mindestens [minObservedDays] Tage umfasst und mindestens [minConsumptions]
///   Verbrauchsbuchungen vorliegen. Vorher ist "zu wenig Daten" die ehrliche Antwort, keine Zahl.
/// - Es zaehlen nur Buchungen in der Einheit des Bestands; alles andere bleibt aussen vor statt umgerechnet zu werden.
library;

import '../receipt/vienna_time.dart';

/// Eine Ledger-Buchung fuer die Vorhersage (unabhaengig von der Datenbank-Klasse).
typedef UsageMovement = ({String productId, DateTime occurredAtUtc, String type, double quantityDelta, String unit, String? mealId});

/// Der aktuelle Bestand eines Produkts in seiner Einheit (`piece` | `kg` | `l`).
typedef UsageStock = ({double quantity, String unit});

class UsageForecast {
  const UsageForecast({
    required this.productId,
    required this.dailyRate,
    required this.stock,
    required this.unit,
    required this.observedDays,
    required this.consumptions,
  });

  final String productId;

  /// Verbrauch je Kalendertag in [unit].
  final double dailyRate;
  final double stock;
  final String unit;

  /// Tage, aus denen die Rate stammt, und Zahl der Verbrauchsbuchungen darin.
  final int observedDays;
  final int consumptions;

  /// Tage, die der Bestand bei gleichbleibendem Verbrauch noch reicht.
  double get daysLeft => stock / dailyRate;

  /// "reicht voraussichtlich noch etwa 5 Tage"; `null`, wenn die Zahl nichts aussagt (mehr als zwei Monate).
  String? get text {
    final d = daysLeft;
    if (d > 60) return null;
    if (d < 1) return 'reicht voraussichtlich nur noch heute oder morgen';
    final n = d.round();
    return 'reicht voraussichtlich noch etwa ${n == 1 ? '1 Tag' : '$n Tage'}';
  }
}

const _consumptionTypes = {'consumed', 'meal'};

/// Vorhersage je Produkt mit Bestand. Produkte ohne ausreichende Daten, ohne Verbrauch oder ohne Bestand fehlen im Ergebnis.
Map<String, UsageForecast> forecastUsage({
  required Iterable<UsageMovement> movements,
  required Map<String, UsageStock> stock,
  required DateTime now,
  int windowDays = 56,
  int minConsumptions = 3,
  int minObservedDays = 14,
}) {
  final nowUtc = now.toUtc();
  final windowStart = nowUtc.subtract(Duration(days: windowDays));
  final byProduct = <String, List<UsageMovement>>{};
  for (final m in movements) {
    if (!stock.containsKey(m.productId) || m.occurredAtUtc.isAfter(nowUtc)) continue;
    byProduct.putIfAbsent(m.productId, () => []).add(m);
  }

  final out = <String, UsageForecast>{};
  for (final e in byProduct.entries) {
    final s = stock[e.key]!;
    if (!(s.quantity > 0)) continue;
    // nur Buchungen in der Einheit des Bestands; der Beobachtungszeitraum beginnt mit der ersten Buchung im Fenster
    final own = [for (final m in e.value) if (m.unit == s.unit && !m.occurredAtUtc.isBefore(windowStart)) m];
    if (own.isEmpty) continue;
    var consumed = 0.0;
    var count = 0;
    DateTime? first;
    for (final m in own) {
      if (first == null || m.occurredAtUtc.isBefore(first)) first = m.occurredAtUtc;
      if (_consumptionTypes.contains(m.type) && m.quantityDelta < 0) {
        consumed += -m.quantityDelta;
        count++;
      } else if (m.type == 'adjustment' && m.mealId != null && m.quantityDelta > 0) {
        consumed -= m.quantityDelta; // Gegenbuchung nimmt einen Mahlzeit-Abzug zurueck
      }
    }
    if (consumed <= 0 || count < minConsumptions || first == null) continue;
    final observed = _calendarDays(first, nowUtc);
    if (observed < minObservedDays) continue;
    out[e.key] = UsageForecast(
      productId: e.key,
      dailyRate: consumed / observed,
      stock: s.quantity,
      unit: s.unit,
      observedDays: observed,
      consumptions: count,
    );
  }
  return out;
}

/// Kalendertage zwischen zwei Zeitpunkten in Wiener Ortszeit, der erste Tag zaehlt mit.
int _calendarDays(DateTime fromUtc, DateTime toUtc) {
  final a = utcToViennaLocal(fromUtc);
  final b = utcToViennaLocal(toUtc);
  final days = DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays + 1;
  return days < 1 ? 1 : days;
}
