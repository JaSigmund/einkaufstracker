import 'package:einkaufstracker/domain/inventory/usage_forecast.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verbrauchsraten-Vorhersage aus dem Ledger (Ausbau 1.14).
final now = DateTime.utc(2026, 10, 4, 12);

UsageMovement mv(String type, double delta, int daysAgo, {String product = 'p', String unit = 'kg', String? mealId}) => (
      productId: product,
      occurredAtUtc: now.subtract(Duration(days: daysAgo)),
      type: type,
      quantityDelta: delta,
      unit: unit,
      mealId: mealId,
    );

void main() {
  const stock = {'p': (quantity: 1.0, unit: 'kg')};

  /// 2 kg vor 20 Tagen gekauft, in 20 Tagen 4 mal je 250 g verbraucht.
  List<UsageMovement> typical() => [
        mv('purchase', 2, 20),
        mv('meal', -0.25, 16),
        mv('meal', -0.25, 12),
        mv('consumed', -0.25, 8),
        mv('meal', -0.25, 3),
      ];

  test('Rate je Kalendertag, Reichweite aus Bestand durch Rate', () {
    final f = forecastUsage(movements: typical(), stock: stock, now: now)['p']!;
    expect(f.observedDays, 21, reason: 'Kalendertage von vor 20 Tagen bis heute, beide mitgezaehlt');
    expect(f.consumptions, 4);
    expect(f.dailyRate, closeTo(1.0 / 21, 1e-9));
    expect(f.daysLeft, closeTo(21, 1e-9));
    expect(f.text, 'reicht voraussichtlich noch etwa 21 Tage');
  });

  test('zu wenig Daten: weniger als 14 Tage oder weniger als 3 Verbrauchsbuchungen ergeben keine Vorhersage', () {
    final shortSpan = [mv('purchase', 2, 10), mv('meal', -0.25, 8), mv('meal', -0.25, 5), mv('meal', -0.25, 2)];
    expect(forecastUsage(movements: shortSpan, stock: stock, now: now), isEmpty);
    final fewEvents = [mv('purchase', 2, 30), mv('meal', -0.5, 20), mv('meal', -0.5, 5)];
    expect(forecastUsage(movements: fewEvents, stock: stock, now: now), isEmpty);
  });

  test('Weggeworfenes und Inventur-Korrekturen zaehlen nicht als Verbrauch', () {
    final m = [...typical(), mv('discarded', -0.5, 5), mv('adjustment', -0.3, 4)];
    final f = forecastUsage(movements: m, stock: stock, now: now)['p']!;
    expect(f.dailyRate, closeTo(1.0 / 21, 1e-9));
  });

  test('eine Gegenbuchung zu einer geloeschten Mahlzeit nimmt den Verbrauch zurueck', () {
    final m = [...typical(), mv('adjustment', 0.25, 3, mealId: 'm1')];
    final f = forecastUsage(movements: m, stock: stock, now: now)['p']!;
    expect(f.dailyRate, closeTo(0.75 / 21, 1e-9));
    expect(f.consumptions, 4, reason: 'die Buchungen selbst bleiben gezaehlt, nur die Menge sinkt');
  });

  test('ohne Bestand oder ohne jeden Verbrauch gibt es nichts vorherzusagen', () {
    expect(forecastUsage(movements: typical(), stock: const {'p': (quantity: 0.0, unit: 'kg')}, now: now), isEmpty);
    expect(forecastUsage(movements: typical(), stock: const {}, now: now), isEmpty);
    expect(forecastUsage(movements: [mv('purchase', 2, 30), mv('purchase', 1, 10)], stock: stock, now: now), isEmpty);
  });

  test('Buchungen in einer anderen Einheit als der Bestand bleiben aussen vor', () {
    final m = [...typical(), mv('meal', -9, 5, unit: 'piece')];
    final f = forecastUsage(movements: m, stock: stock, now: now)['p']!;
    expect(f.dailyRate, closeTo(1.0 / 21, 1e-9));
  });

  test('nur das Fenster zaehlt: aeltere Buchungen und Buchungen aus der Zukunft werden ignoriert', () {
    final m = [
      mv('purchase', 5, 200),
      mv('meal', -4.0, 150), // weit ausserhalb des Fensters
      ...typical(),
      mv('meal', -9, -2), // in der Zukunft
    ];
    final f = forecastUsage(movements: m, stock: stock, now: now)['p']!;
    expect(f.dailyRate, closeTo(1.0 / 21, 1e-9));
    expect(f.observedDays, 21);
  });

  test('mehrere Produkte unabhaengig voneinander', () {
    final m = [
      ...typical(),
      mv('purchase', 10, 30, product: 'q', unit: 'piece'),
      mv('meal', -1, 25, product: 'q', unit: 'piece'),
      mv('meal', -1, 15, product: 'q', unit: 'piece'),
      mv('consumed', -1, 5, product: 'q', unit: 'piece'),
    ];
    final r = forecastUsage(movements: m, stock: const {'p': (quantity: 1.0, unit: 'kg'), 'q': (quantity: 3.0, unit: 'piece')}, now: now);
    expect(r.keys, {'p', 'q'});
    expect(r['q']!.dailyRate, closeTo(3 / 31, 1e-9));
    expect(r['q']!.daysLeft, closeTo(31, 1e-9));
  });

  group('Text', () {
    UsageForecast f(double stock, double rate) => UsageForecast(productId: 'p', dailyRate: rate, stock: stock, unit: 'kg', observedDays: 30, consumptions: 5);

    test('unter einem Tag, ein Tag, mehrere Tage', () {
      expect(f(0.1, 0.5).text, 'reicht voraussichtlich nur noch heute oder morgen');
      expect(f(1, 1).text, 'reicht voraussichtlich noch etwa 1 Tag');
      expect(f(2.4, 1).text, 'reicht voraussichtlich noch etwa 2 Tage');
      expect(f(3.6, 1).text, 'reicht voraussichtlich noch etwa 4 Tage');
    });

    test('mehr als zwei Monate sagen nichts aus und haben keinen Text', () {
      expect(f(70, 1).text, isNull);
      expect(f(60, 1).text, 'reicht voraussichtlich noch etwa 60 Tage');
    });
  });
}
