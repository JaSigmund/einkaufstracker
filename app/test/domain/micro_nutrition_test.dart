import 'package:einkaufstracker/domain/nutrition/micro_nutrition.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tages- und Wochenwerte der Mikronaehrstoffe (Phase N3, ADR-032): Abdeckung je Naehrstoff, Portionsanteil, Beitraege.
MicroMeal meal(String id, DateTime utc, {double eaten = 1, double made = 1, String title = 'Mahlzeit'}) =>
    (id: id, title: title, eatenAtUtc: utc, servingsEaten: eaten, servingsMade: made);
MicroIngredient ing(String mealId, String name, Map<String, double>? micros) => (mealId: mealId, name: name, micros: micros);

void main() {
  // 3. Oktober 2026 liegt in der Sommerzeit (UTC+2): 10:00 UTC ist 12:00 Wiener Zeit, 22:30 UTC schon der Folgetag
  final noon = DateTime.utc(2026, 10, 3, 10);

  test('Summe der bekannten Beitraege und Abdeckung je Naehrstoff', () {
    final days = buildDailyMicros([meal('m1', noon)], [
      ing('m1', 'Banane', {'vit_c_mg': 13, 'iron_mg': 0.5}),
      ing('m1', 'Spinat', {'vit_c_mg': 28}),
      ing('m1', 'Gewuerz', null),
    ]);
    expect(days, hasLength(1));
    final d = days.single;
    expect(d.ingredients, 3);
    final c = d.valueOf('vit_c_mg');
    expect([c.total, c.withData, c.ingredients], [41, 2, 3]);
    expect(c.complete, isFalse);
    expect(c.unknown, isFalse);
    expect(c.coverage, closeTo(2 / 3, 1e-9));
    final iron = d.valueOf('iron_mg');
    expect([iron.total, iron.withData], [0.5, 1], reason: 'die Abdeckung gilt je Naehrstoff');
  });

  test('vollstaendig: alle Zutaten haben einen Wert; eine echte Null zaehlt als Wert', () {
    final d = buildDailyMicros([meal('m1', noon)], [
      ing('m1', 'a', {'vit_d_ug': 0}),
      ing('m1', 'b', {'vit_d_ug': 2.5}),
    ]).single;
    final v = d.valueOf('vit_d_ug');
    expect([v.total, v.withData, v.complete, v.unknown], [2.5, 2, true, false]);
  });

  test('unbekannt: kein einziger Wert bei vorhandenen Zutaten, die Summe ist dann keine 0', () {
    final d = buildDailyMicros([meal('m1', noon)], [ing('m1', 'a', {'vit_c_mg': 5}), ing('m1', 'b', null)]).single;
    final jod = d.valueOf('iodine_ug');
    expect(jod.unknown, isTrue);
    expect(jod.withData, 0);
    expect(jod.ingredients, 2);
  });

  test('Portionsanteil: gegessen durch gekocht', () {
    final d = buildDailyMicros([meal('m1', noon, eaten: 1, made: 4)], [ing('m1', 'Suppe', {'vit_c_mg': 40})]).single;
    expect(d.valueOf('vit_c_mg').total, 10);
  });

  test('mehrere Mahlzeiten desselben Wiener Kalendertags addieren sich, der Tageswechsel folgt der Wiener Zeit', () {
    final days = buildDailyMicros([
      meal('m1', DateTime.utc(2026, 10, 3, 6)),
      meal('m2', DateTime.utc(2026, 10, 3, 20)),
      meal('m3', DateTime.utc(2026, 10, 3, 22, 30)), // 00:30 am 4. Oktober
    ], [
      ing('m1', 'a', {'vit_c_mg': 10}),
      ing('m2', 'b', {'vit_c_mg': 5}),
      ing('m3', 'c', {'vit_c_mg': 7}),
    ]);
    expect(days.map((d) => d.day), [DateTime(2026, 10, 3), DateTime(2026, 10, 4)]);
    expect(days.first.valueOf('vit_c_mg').total, 15);
    expect(days.last.valueOf('vit_c_mg').total, 7);
    expect(days.first.meals, 2);
  });

  test('Beitraege: groesster zuerst, mit Zutat und Mahlzeit, nach Portionsanteil', () {
    final d = buildDailyMicros([
      meal('m1', noon, title: 'Fruehstueck'),
      meal('m2', noon, title: 'Suppe', eaten: 1, made: 2),
    ], [
      ing('m1', 'Orange', {'vit_c_mg': 50}),
      ing('m2', 'Paprika', {'vit_c_mg': 160}),
      ing('m2', 'Kartoffel', {'vit_c_mg': 10}),
    ]).single;
    final c = d.valueOf('vit_c_mg').contributions;
    expect(c.map((x) => x.ingredient), ['Paprika', 'Orange', 'Kartoffel']);
    expect(c.first.amount, 80);
    expect(c.first.mealTitle, 'Suppe');
    expect(c.last.amount, 5);
    expect(d.valueOf('vit_c_mg').total, 135);
  });

  test('Zutaten ohne passende Mahlzeit werden ignoriert, Mahlzeiten mit 0 gekochten Portionen auch', () {
    final days = buildDailyMicros([meal('m1', noon), meal('m2', noon, made: 0)], [ing('m9', 'x', {'vit_c_mg': 9}), ing('m2', 'y', {'vit_c_mg': 4})]);
    expect(days, hasLength(1));
    expect(days.single.ingredients, 0);
    expect(days.single.valueOf('vit_c_mg').total, 0);
    expect(days.single.valueOf('vit_c_mg').unknown, isFalse, reason: 'ohne Zutaten gibt es nichts, was unbekannt waere');
  });

  test('Schaetzwerte werden erkannt', () {
    final d = buildDailyMicros([meal('m1', noon)], [ing('m1', 'x', null)], isEstimate: (id) => id == 'm1').single;
    expect(d.hasEstimates, isTrue);
    expect(buildDailyMicros([meal('m1', noon)], [ing('m1', 'x', null)]).single.hasEstimates, isFalse);
  });

  test('ohne Mahlzeiten keine Tage', () {
    expect(buildDailyMicros(const [], const []), isEmpty);
    expect(buildWeeklyMicros(const []), isEmpty);
  });

  group('Woche', () {
    // Montag 28.9., Dienstag 29.9., Montag 5.10.
    final days = buildDailyMicros([
      meal('a', DateTime.utc(2026, 9, 28, 10)),
      meal('b', DateTime.utc(2026, 9, 29, 10)),
      meal('c', DateTime.utc(2026, 10, 5, 10)),
    ], [
      ing('a', 'x', {'vit_c_mg': 30, 'iron_mg': 2}),
      ing('b', 'y', {'vit_c_mg': 60}),
      ing('b', 'z', null),
      ing('c', 'w', {'vit_c_mg': 100}),
    ]);

    test('Durchschnitt je erfasstem Tag, nicht je Kalendertag der Woche', () {
      final weeks = buildWeeklyMicros(days);
      expect(weeks.map((w) => w.weekStart), [DateTime(2026, 9, 28), DateTime(2026, 10, 5)]);
      final w = weeks.first;
      expect(w.daysLogged, 2);
      expect(w.valueOf('vit_c_mg').total, 45, reason: '(30 + 60) / 2 erfasste Tage');
      expect(w.valueOf('iron_mg').total, 1, reason: '(2 + 0) / 2: der zweite Tag hat keine Daten und zaehlt hier als 0, die Abdeckung sagt es');
    });

    test('die Abdeckung zaehlt alle Zutaten der Woche', () {
      final w = buildWeeklyMicros(days).first;
      final c = w.valueOf('vit_c_mg');
      expect([c.withData, c.ingredients], [2, 3]);
      expect(c.complete, isFalse);
      expect(w.valueOf('iron_mg').withData, 1);
      expect(w.valueOf('iodine_ug').unknown, isTrue);
    });

    test('groesste Beitraege der Woche, hoechstens fuenf', () {
      final w = buildWeeklyMicros(days).first;
      expect(w.valueOf('vit_c_mg').contributions.map((c) => c.ingredient), ['y', 'x']);
    });
  });

  group('Referenz', () {
    test('Anteil an der Referenzmenge, ohne Referenz null', () {
      expect(referenceFraction(40, 80), 0.5);
      expect(referenceFraction(160, 80), 2);
      expect(referenceFraction(5, null), isNull);
      expect(referenceFraction(5, 0), isNull);
    });

    test('der Text bewertet nicht', () {
      expect(referenceText(0.62), '62 % der Referenzmenge');
      expect(referenceText(1.5), '150 % der Referenzmenge');
      expect(referenceText(0.004), '0 % der Referenzmenge');
    });
  });
}
