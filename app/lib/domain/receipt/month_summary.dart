import 'vienna_time.dart';

/// Ein Kauf fuer die Monatsrechnung (unabhaengig von der Datenbank-Klasse).
typedef PurchaseRecord = ({DateTime purchasedAtUtc, int totalCents});

class MonthSummary {
  const MonthSummary({required this.year, required this.month, required this.totalCents, required this.receiptCount});

  final int year;
  final int month;
  final int totalCents;
  final int receiptCount;
}

/// Summiert die Kaeufe eines Kalendermonats in **Wiener Ortszeit** (Doku 02 FR-07): Ein Einkauf am
/// 30.09. um 23:30 UTC gehoert schon in den Oktober, weil es in Wien nach Mitternacht ist.
MonthSummary summarizeMonth(Iterable<PurchaseRecord> purchases, {required int year, required int month}) {
  var total = 0;
  var count = 0;
  for (final p in purchases) {
    final local = utcToViennaLocal(p.purchasedAtUtc);
    if (local.year == year && local.month == month) {
      total += p.totalCents;
      count++;
    }
  }
  return MonthSummary(year: year, month: month, totalCents: total, receiptCount: count);
}
