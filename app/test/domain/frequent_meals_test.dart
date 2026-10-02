import 'package:einkaufstracker/domain/nutrition/frequent_meals.dart';
import 'package:flutter_test/flutter_test.dart';

FrequentCandidate _m(String id, String title, int day) => (id: id, title: title, eatenAtUtc: DateTime.utc(2026, 9, day, 12));

void main() {
  test('keine Mahlzeiten: leer', () => expect(frequentMeals(const []), isEmpty));

  test('haeufigste zuerst, bei Gleichstand die zuletzt gegessene', () {
    final r = frequentMeals([
      _m('a1', 'Müsli', 1), _m('a2', 'Müsli', 2), _m('a3', 'Müsli', 3),
      _m('b1', 'Pizza', 5), _m('b2', 'Pizza', 6),
      _m('c1', 'Apfel', 7),
      _m('d1', 'Banane', 9),
    ]);
    expect(r.map((e) => e.title), ['Müsli', 'Pizza', 'Banane', 'Apfel']);
    expect(r.map((e) => e.count), [3, 2, 1, 1]);
  });

  test('gleich benannte Mahlzeiten werden zusammengefasst (Gross-/Kleinschreibung, Leerzeichen am Rand)', () {
    final r = frequentMeals([_m('a', 'Müsli', 1), _m('b', ' müsli ', 2), _m('c', 'MÜSLI', 3)]);
    expect(r, hasLength(1));
    expect(r.single.count, 3);
  });

  test('als Vorlage dient die juengste Mahlzeit der Gruppe, auch bei unsortierter Eingabe', () {
    final r = frequentMeals([_m('neu', 'Müsli', 9), _m('alt', 'Müsli', 1), _m('mitte', 'Müsli', 5)]);
    expect(r.single.latestId, 'neu');
    expect(r.single.title, 'Müsli');
  });

  test('der Titel stammt von der juengsten Mahlzeit, ohne Leerzeichen am Rand', () {
    final r = frequentMeals([_m('alt', 'müsli', 1), _m('neu', '  Müsli  ', 2)]);
    expect(r.single.title, 'Müsli');
  });

  test('Mahlzeiten ohne Titel zaehlen nicht', () {
    expect(frequentMeals([_m('a', '', 1), _m('b', '   ', 2)]), isEmpty);
  });

  test('limit begrenzt die Auswahl', () {
    final meals = [for (var i = 0; i < 10; i++) _m('m$i', 'Gericht $i', i + 1)];
    expect(frequentMeals(meals, limit: 3), hasLength(3));
    expect(frequentMeals(meals, limit: 3).first.title, 'Gericht 9', reason: 'Gleichstand: zuletzt gegessen zuerst');
  });

  test('since blendet alte Mahlzeiten aus und zaehlt sie nicht mit', () {
    final r = frequentMeals(
      [_m('a', 'Müsli', 1), _m('b', 'Müsli', 2), _m('c', 'Müsli', 20), _m('d', 'Pizza', 3)],
      since: DateTime.utc(2026, 9, 10),
    );
    expect(r.map((e) => (e.title, e.count)), [('Müsli', 1)]);
  });
}
