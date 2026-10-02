/// Verbrauchsbilanz je Woche mit Deckungsgrad (LH-MEAL-10, Doku 15 §4).
///
/// Verbrauch = Anfangsbestand + Einkauf - Endbestand - Abfall. Das Ledger `inventory_movements` haelt jede
/// Bestandsaenderung fest, damit ergibt sich der Bestandsabgang einer Woche direkt aus den Buchungen:
///
///   erwarteter Verbrauch = Mahlzeit-Abzuege + "aufgebraucht" - Korrekturen (ohne Mahlzeit)
///   Deckungsgrad         = durch Mahlzeiten erklaerter Anteil = Mahlzeit-Abzuege / erwarteter Verbrauch
///
/// Weggeworfenes zaehlt bewusst **nicht** zum Verbrauch (Abfall steht separat). Eine Gegenbuchung zu einer
/// geloeschten oder geaenderten Mahlzeit (positive `adjustment` mit `meal_id`, FR-12) nimmt den Abzug wieder
/// zurueck und mindert deshalb die erfassten Mahlzeit-Mengen, statt als Korrektur zu gelten.
///
/// Mengen werden in Gramm gerechnet; Milliliter gelten als Gramm (Dichte 1, Doku 15 §5.3). Buchungen in Stueck
/// brauchen das Stueckgewicht des Produkts und fallen sonst aus der Rechnung heraus (siehe [WeekBalance.skipped]).
/// Reine Funktionen ohne Datenbankzugriff.
library;

import '../receipt/vienna_time.dart';

/// Eine Ledger-Buchung fuer die Bilanz (unabhaengig von der Datenbank-Klasse).
typedef BalanceMovement = ({String productId, DateTime occurredAtUtc, String type, double quantityDelta, String unit, String? mealId});

/// Bilanz einer Kalenderwoche (Montag bis Sonntag, Wiener Ortszeit). Alle Mengen in Gramm.
class WeekBalance {
  WeekBalance(this.weekStart);

  /// Montag der Woche (Wiener Ortszeit, Mitternacht).
  final DateTime weekStart;

  /// Eingekauft, ueber Bon-Import und Barcode-Erfassung.
  double purchasedG = 0;

  /// Durch Mahlzeiten aus dem Bestand genommen (netto nach Gegenbuchungen).
  double eatenG = 0;

  /// Von Hand als "aufgebraucht" gebucht, ohne dass eine Mahlzeit dazu eingetragen ist.
  double consumedManualG = 0;

  /// Weggeworfen.
  double discardedG = 0;

  /// Korrekturen (Inventur) ohne Bezug zu einer Mahlzeit, mit Vorzeichen: negativ = Bestand war kleiner als gebucht.
  double adjustedG = 0;

  /// Buchungen in Stueck, deren Gewicht unbekannt ist und die deshalb nicht eingehen.
  int skipped = 0;

  /// Bestandsabgang der Woche, der als Verbrauch gilt (nie negativ).
  double get expectedG {
    final v = eatenG + consumedManualG - adjustedG;
    return v < 0 ? 0 : v;
  }

  /// Anteil des Verbrauchs, der durch Mahlzeiten erklaert ist. `null`, wenn gar nichts abging.
  /// Kann ueber 1 liegen, wenn mehr Mahlzeiten als Bestandsabgang gebucht sind (z.B. nach einer positiven Korrektur).
  double? get coverage => expectedG > 0 ? eatenG / expectedG : null;

  /// Es gibt irgendeine Buchung in dieser Woche, die in die Rechnung eingeht.
  bool get hasData => purchasedG != 0 || eatenG != 0 || consumedManualG != 0 || discardedG != 0 || adjustedG != 0;
}

/// Bilanz je Woche, neueste zuerst. [unitWeightG] liefert das Stueckgewicht je Produkt (g), falls bekannt.
List<WeekBalance> buildWeeklyBalance(Iterable<BalanceMovement> movements, {required Map<String, double> unitWeightG}) {
  final weeks = <DateTime, WeekBalance>{};

  double? toGrams(BalanceMovement m, double quantity) => switch (m.unit) {
        'kg' || 'l' => quantity * 1000,
        'piece' => unitWeightG[m.productId] == null ? null : quantity * unitWeightG[m.productId]!,
        _ => null,
      };

  DateTime mondayOf(DateTime utc) {
    final local = utcToViennaLocal(utc);
    return DateTime(local.year, local.month, local.day - (local.weekday - 1));
  }

  final all = movements.toList();

  // Eine Gegenbuchung gehoert in die Woche der Mahlzeit, die sie zuruecknimmt, nicht in die Woche, in der man die
  // Mahlzeit loescht: sonst waere die eine Woche zu hoch und die andere negativ.
  final mealWeek = <String, DateTime>{};
  for (final m in all) {
    if (m.type != 'meal' || m.mealId == null) continue;
    final monday = mondayOf(m.occurredAtUtc);
    final known = mealWeek[m.mealId!];
    if (known == null || monday.isBefore(known)) mealWeek[m.mealId!] = monday;
  }

  for (final m in all) {
    final monday = m.type == 'adjustment' && m.mealId != null ? mealWeek[m.mealId!] ?? mondayOf(m.occurredAtUtc) : mondayOf(m.occurredAtUtc);
    final week = weeks.putIfAbsent(monday, () => WeekBalance(monday));
    final g = toGrams(m, m.quantityDelta);
    if (g == null) {
      week.skipped++;
      continue;
    }
    switch (m.type) {
      case 'purchase':
        week.purchasedG += g;
      case 'meal':
        week.eatenG -= g; // Abzug ist negativ
      case 'consumed':
        week.consumedManualG -= g;
      case 'discarded':
        week.discardedG -= g;
      case 'adjustment':
        if (m.mealId != null) {
          week.eatenG -= g; // Gegenbuchung (positiv) nimmt einen Mahlzeit-Abzug zurueck
        } else {
          week.adjustedG += g;
        }
    }
  }
  return weeks.values.toList()..sort((a, b) => b.weekStart.compareTo(a.weekStart));
}
