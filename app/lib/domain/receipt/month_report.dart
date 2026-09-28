import '../categorization/normalize_name.dart';
import 'vienna_time.dart';

/// Kopfdaten eines Bons fuer die Auswertung.
typedef ReportReceipt = ({String id, DateTime purchasedAtUtc});

/// Eine Bonposition fuer die Auswertung (unabhaengig von der Datenbank-Klasse).
typedef ReportItem = ({
  String receiptId,
  int lineNo,
  String kind, // article | discount | bill_discount | deposit
  String rawText,
  String? categoryId,
  String? productId,
  double quantity,
  int lineTotalCents,
});

/// Eine einzelne Zeile, die in eine Summe eingeht (fuer die Erklaerung "woraus setzt sich der Betrag zusammen").
typedef ReportLine = ({String receiptId, DateTime purchasedAtUtc, String label, int cents, String kind});

/// Schluessel fuer Positionen ohne Kategorie.
const unassignedKey = '';

/// Schluessel der Sammelzeile fuer Rabatte, die sich nicht auf einen Artikel beziehen (z.B. jö Rabattsammler).
/// Sie werden bewusst NICHT auf Kategorien verteilt, sondern getrennt ausgewiesen.
const billDiscountKey = '~bill-discount';

/// Bezeichnung dieser Sammelzeile.
const billDiscountLabel = 'Rabatte auf den ganzen Bon';

/// Sammelzeile in der Artikelliste fuer Rabatte, die sich keinem Artikel darueber zuordnen lassen.
const otherDiscountLabel = 'Sonstige Rabatte';

/// Ein Einzelartikel (gleicher normalisierter Name) innerhalb einer Kategorie.
class ItemAggregate {
  ItemAggregate(this.key, this.label);
  final String key;
  final String label;
  double quantity = 0;
  int totalCents = 0;
  int purchases = 0;

  /// Produkt-Zuordnung fuer den Sprung ins Artikel-Detail (Doku 07 §2), sofern eine bekannt ist.
  String? productId;
}

class CategoryTotal {
  CategoryTotal(this.categoryId);

  /// [unassignedKey] fuer Positionen ohne Kategorie, [billDiscountKey] fuer Bon-Rabatte.
  final String categoryId;
  int totalCents = 0;
  final Map<String, ItemAggregate> _items = {};

  /// Alle Zeilen, die in [totalCents] eingehen, in Bon-Reihenfolge (Datum, Zeilennummer).
  final List<ReportLine> lines = [];

  /// Absteigend nach Betrag (Rabatt-Sammelzeilen sind negativ und stehen daher unten).
  List<ItemAggregate> get items => _items.values.toList()..sort((a, b) => b.totalCents.compareTo(a.totalCents));

  bool get isBillDiscount => categoryId == billDiscountKey;
}

class MonthReport {
  MonthReport({
    required this.year,
    required this.month,
    required this.categories,
    required this.receiptCount,
    required this.savedCents,
    required this.discountLines,
  });
  final int year;
  final int month;
  final int receiptCount;

  /// Absteigend nach Betrag; "nicht zugeordnet" und die Bon-Rabatte stehen nur drin, wenn es Positionen gibt.
  final List<CategoryTotal> categories;

  /// Durch Rabatte gespart (positiver Betrag): alle Rabatte, ob auf einen Artikel oder den ganzen Bon.
  final int savedCents;

  /// Alle Rabattzeilen des Monats (fuer die Erklaerung von [savedCents]).
  final List<ReportLine> discountLines;

  int get totalCents => categories.fold(0, (s, c) => s + c.totalCents);

  CategoryTotal? category(String id) => categories.where((c) => c.categoryId == id).firstOrNull;
}

/// Ausgaben eines Kalendermonats (Wiener Ortszeit, FR-07) nach Kategorie.
///
/// - Rabatte auf einen Artikel zaehlen in dessen Kategorie und werden im Drill-down dem Artikel zugeschlagen.
/// - Rabatte auf den ganzen Bon ([bill_discount], z.B. Rabattsammler) stehen getrennt in einer eigenen Zeile.
/// - Pfand ist eine eigene Kategorie, sofern die Position so zugeordnet ist.
/// Die Summe aller Zeilen entspricht immer der Summe der Positionen der Bons des Monats.
MonthReport buildMonthReport(
  Iterable<ReportReceipt> receipts,
  Iterable<ReportItem> items, {
  required int year,
  required int month,
}) {
  final inMonth = <String, DateTime>{};
  for (final r in receipts) {
    final local = utcToViennaLocal(r.purchasedAtUtc);
    if (local.year == year && local.month == month) inMonth[r.id] = r.purchasedAtUtc;
  }

  final byReceipt = <String, List<ReportItem>>{};
  for (final i in items) {
    if (inMonth.containsKey(i.receiptId)) byReceipt.putIfAbsent(i.receiptId, () => []).add(i);
  }

  final totals = <String, CategoryTotal>{};
  final discountLines = <ReportLine>[];
  var saved = 0;

  void add(String receiptId, String categoryKey, String itemKey, String label, int cents, String kind,
      {double quantity = 0, bool purchase = false, String? productId}) {
    final c = totals.putIfAbsent(categoryKey, () => CategoryTotal(categoryKey));
    c.totalCents += cents;
    final a = c._items.putIfAbsent(itemKey, () => ItemAggregate(itemKey, label));
    a.totalCents += cents;
    a.quantity += quantity;
    if (purchase) a.purchases++;
    a.productId ??= productId;
    final line = (receiptId: receiptId, purchasedAtUtc: inMonth[receiptId]!, label: label, cents: cents, kind: kind);
    c.lines.add(line);
    if (kind == 'discount' || kind == 'bill_discount') {
      discountLines.add(line);
      if (cents < 0) saved -= cents;
    }
  }

  final receiptIds = byReceipt.keys.toList()..sort((a, b) => inMonth[a]!.compareTo(inMonth[b]!));
  for (final id in receiptIds) {
    final list = byReceipt[id]!..sort((a, b) => a.lineNo.compareTo(b.lineNo));
    String? lastKey, lastCategory;
    var hasArticle = false;

    for (final i in list) {
      if (i.kind == 'bill_discount') {
        add(id, billDiscountKey, billDiscountKey, i.rawText, i.lineTotalCents, i.kind);
        continue;
      }
      if (i.kind == 'discount') {
        final cat = i.categoryId ?? unassignedKey;
        if (hasArticle && i.categoryId == lastCategory) {
          add(id, cat, lastKey!, i.rawText, i.lineTotalCents, i.kind);
        } else {
          add(id, cat, '~other-discount', i.rawText, i.lineTotalCents, i.kind);
        }
        continue;
      }
      final key = normalizeItemName(i.rawText);
      final k = key.isEmpty ? i.rawText : key;
      add(id, i.categoryId ?? unassignedKey, k, i.rawText, i.lineTotalCents, i.kind, quantity: i.quantity, purchase: true, productId: i.productId);
      if (i.kind == 'article') {
        hasArticle = true;
        lastKey = k;
        lastCategory = i.categoryId;
      }
    }
  }

  // Sammelzeile "Sonstige Rabatte" bekommt ihren Anzeigenamen
  for (final c in totals.values) {
    final other = c._items['~other-discount'];
    if (other != null) {
      c._items['~other-discount'] = ItemAggregate('~other-discount', otherDiscountLabel)
        ..totalCents = other.totalCents
        ..quantity = other.quantity
        ..purchases = other.purchases;
    }
  }

  final sorted = totals.values.toList()..sort((a, b) => b.totalCents.compareTo(a.totalCents));
  return MonthReport(
    year: year,
    month: month,
    categories: sorted,
    receiptCount: inMonth.length,
    savedCents: saved,
    discountLines: discountLines,
  );
}

/// Ausgaben je Monat und Kategorie ueber mehrere Monate (Doku 07 §2 "Trend"), aeltester Monat zuerst.
/// [months] endet einschliesslich bei ([endYear], [endMonth]), typischerweise 6 oder 12.
List<MonthReport> buildTrend(
  Iterable<ReportReceipt> receipts,
  Iterable<ReportItem> items, {
  required int endYear,
  required int endMonth,
  int months = 6,
}) {
  final receiptList = receipts.toList();
  final itemList = items.toList();
  final result = <MonthReport>[];
  for (var i = months - 1; i >= 0; i--) {
    final offset = endMonth - 1 - i;
    final year = endYear + (offset / 12).floor();
    final month = offset % 12 + 1;
    result.add(buildMonthReport(receiptList, itemList, year: year, month: month));
  }
  return result;
}
