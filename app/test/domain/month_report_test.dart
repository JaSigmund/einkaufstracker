import 'package:einkaufstracker/domain/receipt/month_report.dart';
import 'package:flutter_test/flutter_test.dart';

ReportItem _i(String rid, int no, String text, int cents, {String kind = 'article', String? cat, double qty = 1}) =>
    (receiptId: rid, lineNo: no, kind: kind, rawText: text, categoryId: cat, quantity: qty, lineTotalCents: cents);

ReportReceipt _r(String id, DateTime utc) => (id: id, purchasedAtUtc: utc);

int _total(MonthReport r, String cat) => r.categories.firstWhere((c) => c.categoryId == cat).totalCents;

void main() {
  group('allocateProportionally (groesster Rest)', () {
    test('Summe stimmt immer exakt', () {
      final a = allocateProportionally(-100, [333, 333, 334]);
      expect(a.fold<int>(0, (s, x) => s + x), -100);
      expect(a, [-33, -33, -34]);
    });

    test('Gleichstand: fruehester Eintrag bekommt den Rest', () {
      expect(allocateProportionally(-1, [1, 1]), [-1, 0]);
    });

    test('positive Betraege, ein Gewicht 0, leere Liste', () {
      expect(allocateProportionally(10, [1, 0, 1]), [5, 0, 5]);
      expect(allocateProportionally(5, []), <int>[]);
      expect(allocateProportionally(5, [0, 0]), [0, 0]);
    });
  });

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

    test('Bon-Rabatt wird anteilig verteilt, Summe bleibt exakt', () {
      final rep = buildMonthReport(
        [_r('a', sep)],
        [
          _i('a', 1, 'Tomaten', 600, cat: 'g'),
          _i('a', 2, 'Käse', 300, cat: 'k'),
          _i('a', 3, 'Hack', 100, cat: 'f'),
          _i('a', 4, 'Rabattsammler', -101, kind: 'discount'), // 60,6 / 30,3 / 10,1 -> 61 / 30 / 10 (Summe 101)
        ],
        year: 2026,
        month: 9,
      );
      expect(rep.totalCents, 899);
      expect(_total(rep, 'g'), 600 - 61);
      expect(_total(rep, 'k'), 300 - 30);
      expect(_total(rep, 'f'), 100 - 10);
      expect(rep.categories.expand((c) => c.items).where((a) => a.label == billDiscountLabel), hasLength(3));
    });

    test('Bon-Rabatt bezieht auch nicht zugeordnete Artikel ein', () {
      final rep = buildMonthReport(
        [_r('a', sep)],
        [
          _i('a', 1, 'Tomaten', 500, cat: 'g'),
          _i('a', 2, 'unbekannt', 500),
          _i('a', 3, 'Rabattsammler', -100, kind: 'discount'),
        ],
        year: 2026,
        month: 9,
      );
      expect(_total(rep, 'g'), 450);
      expect(_total(rep, unassignedKey), 450);
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
