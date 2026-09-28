import 'package:einkaufstracker/domain/receipt/month_report.dart';
import 'package:flutter_test/flutter_test.dart';

ReportItem _i(String rid, int no, String text, int cents, {String kind = 'article', String? cat, double qty = 1}) =>
    (receiptId: rid, lineNo: no, kind: kind, rawText: text, categoryId: cat, productId: null, quantity: qty, lineTotalCents: cents);

ReportReceipt _r(String id, DateTime utc) => (id: id, purchasedAtUtc: utc);

int _total(MonthReport r, String cat) => r.categories.firstWhere((c) => c.categoryId == cat).totalCents;

void main() {
  group('buildMonthReport', () {
    final sep = DateTime.utc(2026, 9, 10, 10);

    test('summiert je Kategorie, nur der gewaehlte Monat (Wiener Zeit)', () {
      final rep = buildMonthReport(
        [_r('a', sep), _r('b', DateTime.utc(2026, 9, 30, 23, 30)), _r('c', DateTime.utc(2026, 8, 20))],
        [
          _i('a', 1, 'Tomaten', 300, cat: 'g'),
          _i('a', 2, 'Paprika', 200, cat: 'g'),
          _i('a', 3, 'Käse', 400, cat: 'k'),
          _i('b', 1, 'Zwiebel', 999, cat: 'g'), // 30.09. 23:30 UTC = 01.10. in Wien -> Oktober
          _i('c', 1, 'Zwiebel', 777, cat: 'g'), // August
        ],
        year: 2026,
        month: 9,
      );
      expect(rep.receiptCount, 1);
      expect(_total(rep, 'g'), 500);
      expect(_total(rep, 'k'), 400);
      expect(rep.totalCents, 900);
      expect(rep.categories.first.categoryId, 'g'); // absteigend
    });

    test('Artikel ohne Kategorie landen in "nicht zugeordnet"', () {
      final rep = buildMonthReport([_r('a', sep)], [_i('a', 1, 'scharfer Aufstrich', 250)], year: 2026, month: 9);
      expect(_total(rep, unassignedKey), 250);
    });

    test('Rabatt mit Kategorie wird dem Artikel darueber zugeschlagen', () {
      final rep = buildMonthReport(
        [_r('a', sep)],
        [
          _i('a', 1, 'IC DKIH Paprika Tricolore', 300, cat: 'g'),
          _i('a', 2, 'EXTREM AKTION', -100, kind: 'discount', cat: 'g'),
        ],
        year: 2026,
        month: 9,
      );
      expect(_total(rep, 'g'), 200);
      final items = rep.categories.single.items;
      expect(items, hasLength(1));
      expect(items.single.totalCents, 200);
      expect(items.single.purchases, 1);
    });

    test('Bon-Rabatt steht getrennt und wird NICHT auf Kategorien verteilt', () {
      final rep = buildMonthReport(
        [_r('a', sep)],
        [
          _i('a', 1, 'Tomaten', 600, cat: 'g'),
          _i('a', 2, 'Käse', 300, cat: 'k'),
          _i('a', 3, 'Coca-Cola Flasche', 249, cat: 'd'),
          _i('a', 4, 'jö Rabattsammler 20%', -451, kind: 'bill_discount'),
        ],
        year: 2026,
        month: 9,
      );
      expect(_total(rep, 'g'), 600);
      expect(_total(rep, 'k'), 300);
      expect(_total(rep, 'd'), 249); // Regression: war durch den Bon-Rabatt negativ
      expect(_total(rep, billDiscountKey), -451);
      expect(rep.category(billDiscountKey)!.isBillDiscount, isTrue);
      expect(rep.totalCents, 698);
    });

    test('Durch Rabatte gespart: Artikel-Rabatte und Bon-Rabatte zusammen', () {
      final rep = buildMonthReport(
        [_r('a', sep)],
        [
          _i('a', 1, 'Paprika', 380, cat: 'g'),
          _i('a', 2, 'EXTREM AKTION', -134, kind: 'discount', cat: 'g'),
          _i('a', 3, 'Faschiertes', 499, cat: 'f'),
          _i('a', 4, 'NIMM MEHR', -50, kind: 'discount', cat: 'f'),
          _i('a', 5, 'Rabattsammler', -451, kind: 'bill_discount'),
          _i('a', 6, 'PFANDARTIKEL', 25, kind: 'deposit', cat: 'p'),
          _i('a', 7, 'LEERGUT-RET.', -20, kind: 'deposit', cat: 'p'), // Pfand-Rueckgabe ist kein Rabatt
        ],
        year: 2026,
        month: 9,
      );
      expect(rep.savedCents, 134 + 50 + 451);
      expect(rep.discountLines, hasLength(3));
      expect(rep.discountLines.map((l) => l.cents).reduce((a, b) => a + b), -635);
    });

    test('Zeilen einer Kategorie verweisen auf ihre Bons (fuer die Erklaerung)', () {
      final rep = buildMonthReport(
        [_r('b', DateTime.utc(2026, 9, 20)), _r('a', sep)],
        [
          _i('a', 1, 'Tomaten', 300, cat: 'g'),
          _i('a', 2, 'AKTION', -100, kind: 'discount', cat: 'g'),
          _i('b', 1, 'Paprika', 200, cat: 'g'),
        ],
        year: 2026,
        month: 9,
      );
      final g = rep.category('g')!;
      expect(g.totalCents, 400);
      expect(g.lines.map((l) => (l.receiptId, l.label, l.cents)), [('a', 'Tomaten', 300), ('a', 'AKTION', -100), ('b', 'Paprika', 200)]);
      expect(g.lines.fold<int>(0, (s, l) => s + l.cents), g.totalCents);
      expect(g.lines.first.purchasedAtUtc, sep);
    });

    test('Rabatt nach einem nicht zugeordneten Artikel bleibt bei diesem Artikel', () {
      final rep = buildMonthReport(
        [_r('a', sep)],
        [_i('a', 1, 'unbekannt', 500), _i('a', 2, 'AKTION', -100, kind: 'discount')],
        year: 2026,
        month: 9,
      );
      expect(_total(rep, unassignedKey), 400);
      expect(rep.category(billDiscountKey), isNull);
    });

    test('Pfand ist eine eigene Kategorie und hat keinen Einfluss auf die Summe', () {
      final rep = buildMonthReport(
        [_r('a', sep)],
        [_i('a', 1, 'Cola', 200, cat: 'g'), _i('a', 2, 'PFANDARTIKEL', 25, kind: 'deposit', cat: 'p')],
        year: 2026,
        month: 9,
      );
      expect(_total(rep, 'p'), 25);
      expect(rep.totalCents, 225);
    });

    test('Gleiche Artikel werden zusammengefasst (Menge, Anzahl Einkaeufe)', () {
      final rep = buildMonthReport(
        [_r('a', sep), _r('b', DateTime.utc(2026, 9, 12))],
        [
          _i('a', 1, 'IC DKIH Paprika Tricolore', 300, cat: 'g', qty: 2),
          _i('b', 1, 'DKIH Paprika Tricolore', 150, cat: 'g'),
        ],
        year: 2026,
        month: 9,
      );
      final a = rep.categories.single.items.single;
      expect((a.totalCents, a.quantity, a.purchases), (450, 3.0, 2));
    });

    test('Kein Bon im Monat: leer', () {
      final rep = buildMonthReport([_r('a', sep)], [_i('a', 1, 'x', 100)], year: 2026, month: 5);
      expect(rep.categories, isEmpty);
      expect(rep.totalCents, 0);
    });
  });
}
