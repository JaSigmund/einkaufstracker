import 'package:einkaufstracker/domain/receipt/excluded_items.dart';
import 'package:einkaufstracker/domain/receipt/month_report.dart';
import 'package:flutter_test/flutter_test.dart';

ReportItem _i(String rid, int no, String text, int cents, {String kind = 'article', String? cat, double qty = 1}) => (
      receiptId: rid,
      lineNo: no,
      kind: kind,
      rawText: text,
      categoryId: cat,
      productId: null,
      productName: null,
      quantity: qty,
      quantityUnit: 'piece',
      productBaseUnit: null,
      productPackSize: null,
      lineTotalCents: cents,
    );

ReportReceipt _r(String id, DateTime utc) => (id: id, purchasedAtUtc: utc);

int _total(MonthReport r, String cat) => r.categories.firstWhere((c) => c.categoryId == cat).totalCents;

void main() {
  group('splitExcludedItems', () {
    test('ohne Ausschluesse: alles landet in own, excluded ist leer', () {
      final items = [_i('a', 1, 'Milch', 150, cat: 'milch'), _i('a', 2, 'Brot', 200, cat: 'brot')];
      final result = splitExcludedItems(items, const {});
      expect(result.own, items);
      expect(result.excluded, isEmpty);
    });

    test('ausgeschlossene Position landet in excluded, der Rest bleibt in own', () {
      final items = [
        _i('a', 1, 'Milch', 150, cat: 'milch'),
        _i('a', 2, 'Kollege-Snack', 500, cat: 'snacks'),
        _i('a', 3, 'Brot', 200, cat: 'brot'),
      ];
      final result = splitExcludedItems(items, {(receiptId: 'a', lineNo: 2)});
      expect(result.own.map((i) => i.rawText), ['Milch', 'Brot']);
      expect(result.excluded.map((i) => i.rawText), ['Kollege-Snack']);
    });

    test('Schluessel wirkt nur auf die passende Bon-ID+Zeile, nicht auf andere Bons mit gleicher Zeilennummer', () {
      final items = [_i('a', 1, 'Milch', 150), _i('b', 1, 'Brot', 200)];
      final result = splitExcludedItems(items, {(receiptId: 'a', lineNo: 1)});
      expect(result.own.single.receiptId, 'b');
      expect(result.excluded.single.receiptId, 'a');
    });

    test('Zusammenspiel mit buildMonthReport: ausgeschlossene Position zaehlt nicht zur eigenen Summe', () {
      final sep = DateTime.utc(2026, 9, 10, 10);
      final items = [
        _i('a', 1, 'Milch', 150, cat: 'milch'),
        _i('a', 2, 'Fuer Mitbewohner bezahlt', 1000, cat: 'sonstiges'),
      ];
      final split = splitExcludedItems(items, {(receiptId: 'a', lineNo: 2)});

      final ownReport = buildMonthReport([_r('a', sep)], split.own, year: 2026, month: 9);
      expect(ownReport.totalCents, 150);

      final excludedReport = buildMonthReport([_r('a', sep)], split.excluded, year: 2026, month: 9);
      expect(excludedReport.totalCents, 1000);
      expect(_total(excludedReport, 'sonstiges'), 1000);
    });
  });
}
