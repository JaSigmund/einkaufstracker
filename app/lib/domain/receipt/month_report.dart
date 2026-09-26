import '../categorization/normalize_name.dart';
import 'vienna_time.dart';

/// Kopfdaten eines Bons fuer die Auswertung.
typedef ReportReceipt = ({String id, DateTime purchasedAtUtc});

/// Eine Bonposition fuer die Auswertung (unabhaengig von der Datenbank-Klasse).
typedef ReportItem = ({
  String receiptId,
  int lineNo,
  String kind, // article | discount | deposit
  String rawText,
  String? categoryId,
  double quantity,
  int lineTotalCents,
});

/// Schluessel fuer Positionen ohne Kategorie.
const unassignedKey = '';

/// Sammelzeile fuer Rabatte, die auf den ganzen Bon gehen und anteilig verteilt wurden.
const billDiscountLabel = 'Rabatte auf den Bon';

/// Sammelzeile fuer Rabatte, die sich keinem Artikel darueber zuordnen lassen.
const otherDiscountLabel = 'Sonstige Rabatte';

/// Ein Einzelartikel (gleicher normalisierter Name) innerhalb einer Kategorie.
class ItemAggregate {
  ItemAggregate(this.key, this.label);
  final String key;
  final String label;
  double quantity = 0;
  int totalCents = 0;
  int purchases = 0;
}

class CategoryTotal {
  CategoryTotal(this.categoryId);

  /// [unassignedKey] fuer Positionen ohne Kategorie.
  final String categoryId;
  int totalCents = 0;
  final Map<String, ItemAggregate> _items = {};

  /// Absteigend nach Betrag (Rabatt-Sammelzeilen sind negativ und stehen daher unten).
  List<ItemAggregate> get items => _items.values.toList()..sort((a, b) => b.totalCents.compareTo(a.totalCents));
}

class MonthReport {
  MonthReport({required this.year, required this.month, required this.categories, required this.receiptCount});
  final int year;
  final int month;
  final int receiptCount;

  /// Absteigend nach Betrag; "nicht zugeordnet" steht nur drin, wenn es Positionen gibt.
  final List<CategoryTotal> categories;

  int get totalCents => categories.fold(0, (s, c) => s + c.totalCents);
}

/// Verteilt [amount] im Verhaeltnis der [weights] auf ganze Cent (Verfahren des groessten Rests),
/// sodass die Summe exakt [amount] ergibt. Bei Gleichstand gewinnt der frueheste Eintrag.
List<int> allocateProportionally(int amount, List<int> weights) {
  final total = weights.fold<int>(0, (s, w) => s + w);
  if (weights.isEmpty || total <= 0) return List.filled(weights.length, 0);
  final sign = amount < 0 ? -1 : 1;
  final abs = amount.abs();
  final shares = [for (final w in weights) abs * w ~/ total];
  final remainders = [for (var i = 0; i < weights.length; i++) (i, abs * weights[i] % total)];
  remainders.sort((a, b) => b.$2 != a.$2 ? b.$2.compareTo(a.$2) : a.$1.compareTo(b.$1));
  var left = abs - shares.fold<int>(0, (s, x) => s + x);
  for (final r in remainders) {
    if (left == 0) break;
    shares[r.$1]++;
    left--;
  }
  return [for (final s in shares) s * sign];
}

/// Ausgaben eines Kalendermonats (Wiener Ortszeit, FR-07) nach Kategorie.
///
/// - Rabatte mit Kategorie zaehlen in dieser Kategorie und werden im Drill-down dem Artikel darueber zugeschlagen.
/// - Rabatte ohne Kategorie (Bon-Rabatte, z.B. Rabattsammler) werden **anteilig** auf die Kategorien des Bons
///   verteilt, im Verhaeltnis ihrer Ausgaben (groesster Rest, damit die Summe stimmt).
/// - Pfand ist eine eigene Kategorie, sofern die Position so zugeordnet ist.
/// Die Summe aller Kategorien entspricht immer der Summe der Positionen der Bons des Monats.
MonthReport buildMonthReport(
  Iterable<ReportReceipt> receipts,
  Iterable<ReportItem> items, {
  required int year,
  required int month,
}) {
  final inMonth = <String>{};
  for (final r in receipts) {
    final local = utcToViennaLocal(r.purchasedAtUtc);
    if (local.year == year && local.month == month) inMonth.add(r.id);
  }

  final byReceipt = <String, List<ReportItem>>{};
  for (final i in items) {
    if (inMonth.contains(i.receiptId)) byReceipt.putIfAbsent(i.receiptId, () => []).add(i);
  }

  final totals = <String, CategoryTotal>{};
  CategoryTotal cat(String? id) => totals.putIfAbsent(id ?? unassignedKey, () => CategoryTotal(id ?? unassignedKey));
  void add(String? categoryId, String key, String label, int cents, {double quantity = 0, bool purchase = false}) {
    final c = cat(categoryId);
    c.totalCents += cents;
    final a = c._items.putIfAbsent(key, () => ItemAggregate(key, label));
    a.totalCents += cents;
    a.quantity += quantity;
    if (purchase) a.purchases++;
  }

  for (final list in byReceipt.values) {
    list.sort((a, b) => a.lineNo.compareTo(b.lineNo));
    String? lastKey, lastLabel, lastCategory;
    var hasArticle = false;
    final billDiscounts = <int>[];

    for (final i in list) {
      if (i.kind == 'discount') {
        if (i.categoryId == null) {
          billDiscounts.add(i.lineTotalCents);
        } else if (hasArticle && i.categoryId == lastCategory) {
          add(i.categoryId, lastKey!, lastLabel!, i.lineTotalCents);
        } else {
          add(i.categoryId, '~other-discount', otherDiscountLabel, i.lineTotalCents);
        }
        continue;
      }
      final key = normalizeItemName(i.rawText);
      final k = key.isEmpty ? i.rawText : key;
      add(i.categoryId, k, i.rawText, i.lineTotalCents, quantity: i.quantity, purchase: true);
      if (i.kind == 'article') {
        hasArticle = true;
        lastKey = k;
        lastLabel = i.rawText;
        lastCategory = i.categoryId;
      }
    }

    final billDiscount = billDiscounts.fold<int>(0, (s, x) => s + x);
    if (billDiscount != 0) {
      // Gewicht = positive Ausgaben je Kategorie in diesem Bon (ohne die Bon-Rabatte selbst)
      final spend = <String, int>{};
      for (final i in list) {
        if (i.kind == 'discount' && i.categoryId == null) continue;
        final id = i.categoryId ?? unassignedKey;
        spend[id] = (spend[id] ?? 0) + i.lineTotalCents;
      }
      final ids = [for (final e in spend.entries) if (e.value > 0) e.key];
      if (ids.isEmpty) {
        add(null, '~bill-discount', billDiscountLabel, billDiscount);
      } else {
        final shares = allocateProportionally(billDiscount, [for (final id in ids) spend[id]!]);
        for (var n = 0; n < ids.length; n++) {
          if (shares[n] != 0) add(ids[n] == unassignedKey ? null : ids[n], '~bill-discount', billDiscountLabel, shares[n]);
        }
      }
    }
  }

  final sorted = totals.values.toList()..sort((a, b) => b.totalCents.compareTo(a.totalCents));
  return MonthReport(year: year, month: month, categories: sorted, receiptCount: inMonth.length);
}
