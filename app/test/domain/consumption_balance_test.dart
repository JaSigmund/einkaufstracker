import 'package:einkaufstracker/domain/nutrition/consumption_balance.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verbrauchsbilanz (LH-MEAL-10, Doku 15 §4): Deckungsgrad = durch Mahlzeiten erklaerter Bestandsabgang.
BalanceMovement _m(String type, double delta, DateTime utc, {String product = 'p1', String unit = 'kg', String? mealId}) =>
    (productId: product, occurredAtUtc: utc, type: type, quantityDelta: delta, unit: unit, mealId: mealId);

void main() {
  // Woche 28.9.-4.10.2026 (Montag bis Sonntag), Vorwoche beginnt am 21.9.
  final mon = DateTime.utc(2026, 9, 28, 10);
  final wed = DateTime.utc(2026, 9, 30, 10);
  final prevFri = DateTime.utc(2026, 9, 25, 10);

  List<WeekBalance> build(List<BalanceMovement> ms, {Map<String, double> weights = const {}}) =>
      buildWeeklyBalance(ms, unitWeightG: weights);

  test('keine Buchungen: keine Wochen', () => expect(build(const []), isEmpty));

  test('Mahlzeit-Abzuege sind der erfasste Verbrauch, Einkauf zaehlt nicht zum Verbrauch', () {
    final w = build([_m('purchase', 2, mon), _m('meal', -0.5, wed, mealId: 'a'), _m('meal', -0.25, wed, mealId: 'b')]).single;
    expect(w.purchasedG, 2000);
    expect(w.eatenG, 750);
    expect(w.expectedG, 750);
    expect(w.coverage, 1.0);
  });

  test('"aufgebraucht" ohne Mahlzeit erhoeht den erwarteten Verbrauch und senkt den Deckungsgrad', () {
    final w = build([_m('meal', -0.6, wed, mealId: 'a'), _m('consumed', -0.4, wed)]).single;
    expect(w.eatenG, 600);
    expect(w.consumedManualG, 400);
    expect(w.expectedG, 1000);
    expect(w.coverage, closeTo(0.6, 1e-12));
  });

  test('Weggeworfenes ist Abfall und kein Verbrauch', () {
    final w = build([_m('meal', -0.5, wed, mealId: 'a'), _m('discarded', -0.3, wed)]).single;
    expect(w.discardedG, 300);
    expect(w.expectedG, 500);
    expect(w.coverage, 1.0);
  });

  test('negative Korrektur (Inventur: weniger da als gebucht) zaehlt als unerklaerter Verbrauch', () {
    final w = build([_m('meal', -0.5, wed, mealId: 'a'), _m('adjustment', -0.5, wed)]).single;
    expect(w.adjustedG, -500);
    expect(w.expectedG, 1000);
    expect(w.coverage, closeTo(0.5, 1e-12));
  });

  test('positive Korrektur ohne Mahlzeit mindert den erwarteten Verbrauch', () {
    final w = build([_m('meal', -1.0, wed, mealId: 'a'), _m('adjustment', 0.2, wed)]).single;
    expect(w.expectedG, 800);
    expect(w.coverage, closeTo(1.25, 1e-12), reason: 'mehr durch Mahlzeiten gebucht als abgegangen: Hinweis auf Unstimmigkeit, nicht auf 100 % gekappt');
  });

  test('Gegenbuchung zu einer geloeschten Mahlzeit nimmt den Abzug zurueck, sie ist keine Korrektur', () {
    final w = build([
      _m('meal', -0.5, wed, mealId: 'a'),
      _m('adjustment', 0.5, DateTime.utc(2026, 9, 30, 12), mealId: 'a'),
    ]).single;
    expect(w.eatenG, 0);
    expect(w.adjustedG, 0, reason: 'sonst wuerde die Rueckbuchung als Inventur-Fund gelten');
    expect(w.expectedG, 0);
    expect(w.coverage, isNull);
  });

  test('Gegenbuchung in einer spaeteren Woche gehoert in die Woche der Mahlzeit', () {
    final weeks = build([
      _m('meal', -0.5, mon, mealId: 'a'),
      _m('adjustment', 0.5, DateTime.utc(2026, 10, 6, 10), mealId: 'a'), // Folgewoche
      _m('meal', -0.1, DateTime.utc(2026, 10, 7, 10), mealId: 'b'),
    ]);
    expect(weeks, hasLength(2));
    final newer = weeks.first;
    final older = weeks.last;
    expect(newer.weekStart, DateTime(2026, 10, 5));
    expect(newer.eatenG, 100, reason: 'Folgewoche bleibt ohne negative Mengen');
    expect(older.weekStart, DateTime(2026, 9, 28));
    expect(older.eatenG, 0);
  });

  test('Teilrueckbuchung (Menge einer Mahlzeit verringert) rechnet netto', () {
    final w = build([
      _m('meal', -0.5, wed, mealId: 'a'),
      _m('adjustment', 0.2, wed, mealId: 'a'),
    ]).single;
    expect(w.eatenG, 300);
  });

  test('Liter zaehlen wie Kilogramm (Dichte 1)', () {
    final w = build([_m('meal', -0.25, wed, unit: 'l', mealId: 'a')]).single;
    expect(w.eatenG, 250);
  });

  test('Stueck brauchen das Gewicht des Produkts, sonst werden sie ausgelassen und gezaehlt', () {
    final ms = [_m('meal', -2, wed, product: 'egg', unit: 'piece', mealId: 'a'), _m('meal', -3, wed, product: 'mystery', unit: 'piece', mealId: 'b')];
    final w = build(ms, weights: {'egg': 60}).single;
    expect(w.eatenG, 120);
    expect(w.skipped, 1, reason: "nur das Produkt ohne bekanntes Stueckgewicht");
  });

  test('Wochen werden getrennt (Montag bis Sonntag, Wiener Zeit), neueste zuerst', () {
    final sundayNight = DateTime.utc(2026, 10, 4, 21, 30); // 23:30 MESZ, noch Sonntag
    final mondayAfterMidnight = DateTime.utc(2026, 10, 4, 22, 30); // 00:30 MESZ Montag
    final weeks = build([
      _m('meal', -0.1, prevFri, mealId: 'a'),
      _m('meal', -0.2, sundayNight, mealId: 'b'),
      _m('meal', -0.3, mondayAfterMidnight, mealId: 'c'),
    ]);
    expect(weeks.map((w) => w.weekStart), [DateTime(2026, 10, 5), DateTime(2026, 9, 28), DateTime(2026, 9, 21)]);
    expect(weeks.map((w) => w.eatenG), [300, 200, 100]);
  });

  test('ohne jeden Bestandsabgang gibt es keinen Deckungsgrad (kein Teilen durch null)', () {
    final w = build([_m('purchase', 1, wed)]).single;
    expect(w.expectedG, 0);
    expect(w.coverage, isNull);
    expect(w.hasData, isTrue);
  });
}
