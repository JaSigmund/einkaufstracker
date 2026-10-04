import 'package:einkaufstracker/domain/nutrition/micro_nutrition.dart';
import 'package:flutter_test/flutter_test.dart';

/// Nahrungsergaenzung in der Mikronaehrstoff-Auswertung (Phase N4, ADR-035).
MicroMeal meal(String id, DateTime utc, {double eaten = 1, double made = 1}) => (id: id, title: 'Essen $id', eatenAtUtc: utc, servingsEaten: eaten, servingsMade: made);

MicroIngredient ing(String mealId, String name, Map<String, double>? micros) => (mealId: mealId, name: name, micros: micros);

MicroIntake intake(String id, DateTime utc, Map<String, double> micros, {String name = 'Vitamin C'}) => (id: id, name: name, takenAtUtc: utc, micros: micros);

void main() {
  final noon = DateTime.utc(2026, 10, 3, 10);
  final day = DateTime(2026, 10, 3);

  test('eine Einnahme addiert ihre Menge zum Tageswert, ohne die Abdeckung der Lebensmittel zu aendern', () {
    final days = buildDailyMicros(
      [meal('a', noon)],
      [ing('a', 'Banane', {'vit_c_mg': 11.0}), ing('a', 'Gewürz', null)],
      intakes: [intake('s1', noon, {'vit_c_mg': 80.0})],
    );
    final v = days.single.valueOf('vit_c_mg');
    expect(v.total, closeTo(91, 1e-9));
    expect(v.supplementTotal, 80);
    expect([v.withData, v.ingredients], [1, 2], reason: 'die Ergaenzung ist keine Zutat');
    expect(v.complete, isFalse, reason: 'die Lebensmittel sind unvollstaendig, also bleibt es ein "mindestens"');
    expect(days.single.ingredients, 2);
    expect(days.single.intakes, 1);
  });

  test('ein Wert nur aus der Ergaenzung ist nicht "unbekannt"', () {
    final days = buildDailyMicros([meal('a', noon)], [ing('a', 'Brot', {'iron_mg': 1.0})], intakes: [intake('s1', noon, {'vit_d_ug': 20.0})]);
    final d = days.single.valueOf('vit_d_ug');
    expect(d.unknown, isFalse);
    expect(d.total, 20);
    // ohne Einnahme bliebe es unbekannt
    final without = buildDailyMicros([meal('a', noon)], [ing('a', 'Brot', {'iron_mg': 1.0})]);
    expect(without.single.valueOf('vit_d_ug').unknown, isTrue);
  });

  test('"Woher kommt das?": die Einnahme steht als Nahrungsergaenzung zwischen den Beitraegen', () {
    final days = buildDailyMicros(
      [meal('a', noon)],
      [ing('a', 'Orange', {'vit_c_mg': 50.0})],
      intakes: [intake('s1', noon, {'vit_c_mg': 80.0}, name: 'Vitamin C 80')],
    );
    final c = days.single.valueOf('vit_c_mg').contributions;
    expect(c.map((e) => e.ingredient), ['Vitamin C 80', 'Orange'], reason: 'groesster Beitrag zuerst');
    expect(c.first.supplement, isTrue);
    expect(c.first.mealTitle, 'Nahrungsergänzung');
    expect(c.last.supplement, isFalse);
  });

  test('der Portionsanteil einer Mahlzeit gilt nicht fuer die Einnahme', () {
    final days = buildDailyMicros(
      [meal('a', noon, eaten: 1, made: 4)],
      [ing('a', 'Suppe', {'iron_mg': 4.0})],
      intakes: [intake('s1', noon, {'iron_mg': 14.0}, name: 'Eisen')],
    );
    expect(days.single.valueOf('iron_mg').total, closeTo(15, 1e-9), reason: '4 mg durch 4 plus 14 mg ganz');
  });

  test('ein Tag nur mit Einnahme existiert, hat aber keine Mahlzeit und keine Zutaten', () {
    final days = buildDailyMicros(const [], const [], intakes: [intake('s1', noon, {'vit_c_mg': 80.0})]);
    expect(days.single.day, day);
    expect([days.single.meals, days.single.ingredients, days.single.intakes], [0, 0, 1]);
    final v = days.single.valueOf('vit_c_mg');
    expect(v.total, 80);
    expect(v.complete, isTrue, reason: 'nichts Unbekanntes an diesem Tag');
    expect(v.unknown, isFalse);
  });

  test('der Tag richtet sich nach der Wiener Ortszeit', () {
    // 2. Oktober 22:30 UTC ist in Wien (Sommerzeit) schon der 3. Oktober
    final days = buildDailyMicros(const [], const [], intakes: [intake('s1', DateTime.utc(2026, 10, 2, 22, 30), {'vit_c_mg': 1.0})]);
    expect(days.single.day, day);
  });

  test('mehrere Einnahmen am Tag summieren sich', () {
    final days = buildDailyMicros(const [], const [], intakes: [
      intake('s1', noon, {'vit_c_mg': 80.0}),
      intake('s2', noon.add(const Duration(hours: 6)), {'vit_c_mg': 80.0, 'iron_mg': 14.0}, name: 'Multi'),
    ]);
    expect(days.single.valueOf('vit_c_mg').total, 160);
    expect(days.single.valueOf('iron_mg').total, 14);
    expect(days.single.intakes, 2);
  });

  test('Wochenwerte zaehlen nur Tage mit Mahlzeiten: ein Tag nur mit Ergaenzung ist kein erfasster Essenstag', () {
    final monday = DateTime.utc(2026, 9, 28, 10);
    final days = buildDailyMicros(
      [meal('a', monday), meal('b', monday.add(const Duration(days: 1)))],
      [ing('a', 'X', {'vit_c_mg': 40.0}), ing('b', 'Y', {'vit_c_mg': 60.0})],
      intakes: [
        intake('s1', monday, {'vit_c_mg': 100.0}),
        intake('s2', monday.add(const Duration(days: 4)), {'vit_c_mg': 1000.0}), // Freitag, nichts gegessen erfasst
      ],
    );
    final week = buildWeeklyMicros(days).single;
    expect(week.daysLogged, 2, reason: 'der Freitag zaehlt nicht');
    final v = week.valueOf('vit_c_mg');
    expect(v.total, closeTo((140 + 60) / 2, 1e-9), reason: 'Montag 40 + 100, Dienstag 60, Durchschnitt ueber die zwei Essenstage');
    expect(v.supplementTotal, closeTo(50, 1e-9));
  });

  test('eine Woche nur mit Ergaenzung hat keine Wochenwerte', () {
    final days = buildDailyMicros(const [], const [], intakes: [intake('s1', noon, {'vit_c_mg': 80.0})]);
    expect(buildWeeklyMicros(days), isEmpty);
  });
}
