import 'package:einkaufstracker/domain/nutrition/daily_nutrition.dart';
import 'package:einkaufstracker/domain/nutrition/journal.dart';
import 'package:flutter_test/flutter_test.dart';

/// Journal-Ansicht (Phase 7e): Monats-Mosaik und Wochenrueckblick.
JournalMeal _m(String id, DateTime utc, {String title = 'Gericht', bool photo = false, double eaten = 1, double made = 1, bool estimate = false}) =>
    (id: id, eatenAtUtc: utc, title: title, hasPhoto: photo, servingsEaten: eaten, servingsMade: made, isEstimate: estimate);

NutritionIngredient _i(String mealId, {double? kcal, double? protein}) =>
    (mealId: mealId, kcal: kcal, proteinG: protein, fatG: null, carbsG: null, sugarG: null, fiberG: null, saltG: null);

void main() {
  group('buildMonthJournal', () {
    test('liefert alle Tage des Monats, auch ohne Eintrag und ohne jede Mahlzeit', () {
      final days = buildMonthJournal(year: 2026, month: 10, meals: const [], ingredients: const []);
      expect(days, hasLength(31));
      expect(days.first.day, DateTime(2026, 10, 1));
      expect(days.last.day, DateTime(2026, 10, 31));
      expect(days.every((d) => !d.logged && d.kcal == null), isTrue);
    });

    test('Schaltjahr und kurze Monate', () {
      expect(buildMonthJournal(year: 2028, month: 2, meals: const [], ingredients: const []), hasLength(29));
      expect(buildMonthJournal(year: 2026, month: 2, meals: const [], ingredients: const []), hasLength(28));
      expect(buildMonthJournal(year: 2026, month: 4, meals: const [], ingredients: const []), hasLength(30));
    });

    test('Mahlzeiten landen am richtigen Tag, die spaetere zuerst', () {
      final days = buildMonthJournal(
        year: 2026,
        month: 10,
        meals: [_m('frueh', DateTime.utc(2026, 10, 5, 6)), _m('spaet', DateTime.utc(2026, 10, 5, 17)), _m('anderer', DateTime.utc(2026, 10, 6, 10))],
        ingredients: const [],
      );
      expect(days[4].mealIds, ['spaet', 'frueh']);
      expect(days[5].mealIds, ['anderer']);
      expect(days[3].logged, isFalse);
    });

    test('Mahlzeiten anderer Monate zaehlen nicht', () {
      final days = buildMonthJournal(
        year: 2026,
        month: 10,
        meals: [_m('sep', DateTime.utc(2026, 9, 30, 10)), _m('nov', DateTime.utc(2026, 11, 1, 12))],
        ingredients: const [],
      );
      expect(days.where((d) => d.logged), isEmpty);
    });

    test('Tagesgrenze in Wiener Zeit: 22:30 UTC am 30.9. ist schon der 1.10. (MESZ)', () {
      final days = buildMonthJournal(year: 2026, month: 10, meals: [_m('nacht', DateTime.utc(2026, 9, 30, 22, 30))], ingredients: const []);
      expect(days.first.mealIds, ['nacht']);
    });

    test('Monatsgrenze im Winter: 23:30 UTC am 31.1. ist schon der 1.2. (MEZ)', () {
      final feb = buildMonthJournal(year: 2026, month: 2, meals: [_m('nacht', DateTime.utc(2026, 1, 31, 23, 30))], ingredients: const []);
      final jan = buildMonthJournal(year: 2026, month: 1, meals: [_m('nacht', DateTime.utc(2026, 1, 31, 23, 30))], ingredients: const []);
      expect(feb.first.mealIds, ['nacht']);
      expect(jan.where((d) => d.logged), isEmpty);
    });

    test('Foto des Tages ist das der juengsten Mahlzeit mit Foto, Mahlzeiten ohne Foto werden uebergangen', () {
      final days = buildMonthJournal(
        year: 2026,
        month: 10,
        meals: [
          _m('mittag', DateTime.utc(2026, 10, 5, 10), photo: true),
          _m('abend', DateTime.utc(2026, 10, 5, 17), photo: false),
          _m('frueh', DateTime.utc(2026, 10, 5, 5), photo: true),
        ],
        ingredients: const [],
      );
      expect(days[4].photoMealId, 'mittag');
    });

    test('Tag ohne Foto hat kein Foto', () {
      final days = buildMonthJournal(year: 2026, month: 10, meals: [_m('a', DateTime.utc(2026, 10, 5, 10))], ingredients: const []);
      expect(days[4].photoMealId, isNull);
    });

    test('kcal: Summe der Zutaten mit Portionsanteil (FR-13)', () {
      final days = buildMonthJournal(
        year: 2026,
        month: 10,
        meals: [_m('a', DateTime.utc(2026, 10, 5, 10), eaten: 1, made: 4), _m('b', DateTime.utc(2026, 10, 5, 17))],
        ingredients: [_i('a', kcal: 800), _i('b', kcal: 300)],
      );
      expect(days[4].kcal, 500);
    });

    test('ohne jeden Energiewert ist kcal unbekannt (null), nicht 0', () {
      final days = buildMonthJournal(
        year: 2026,
        month: 10,
        meals: [_m('a', DateTime.utc(2026, 10, 5, 10))],
        ingredients: [_i('a', protein: 10), _i('a')],
      );
      expect(days[4].logged, isTrue);
      expect(days[4].kcal, isNull);
    });

    test('Schaetzwerte werden erkennbar (FR-17)', () {
      final days = buildMonthJournal(
        year: 2026,
        month: 10,
        meals: [_m('a', DateTime.utc(2026, 10, 5, 10), estimate: true), _m('b', DateTime.utc(2026, 10, 6, 10))],
        ingredients: [_i('a', kcal: 100), _i('b', kcal: 100)],
      );
      expect([days[4].hasEstimates, days[5].hasEstimates], [true, false]);
    });

    test('Zutaten anderer Monate und fremder Mahlzeiten fliessen nicht ein', () {
      final days = buildMonthJournal(
        year: 2026,
        month: 10,
        meals: [_m('a', DateTime.utc(2026, 10, 5, 10))],
        ingredients: [_i('a', kcal: 100), _i('fremd', kcal: 9999)],
      );
      expect(days[4].kcal, 100);
    });
  });

  group('buildWeekReview', () {
    final monday = DateTime(2026, 9, 28);

    test('eine Woche ohne Eintrag hat keinen Rueckblick', () {
      expect(buildWeekReview(weekStart: monday, meals: [_m('a', DateTime.utc(2026, 10, 7, 10))], ingredients: const []), isNull);
    });

    test('Woche reicht von Montag bis Sonntag, Nachbarwochen zaehlen nicht', () {
      final r = buildWeekReview(
        weekStart: monday,
        meals: [
          _m('vorher', DateTime.utc(2026, 9, 27, 10)), // Sonntag davor
          _m('mo', DateTime.utc(2026, 9, 28, 10)),
          _m('so', DateTime.utc(2026, 10, 4, 10)),
          _m('danach', DateTime.utc(2026, 10, 5, 10)), // Montag danach
        ],
        ingredients: const [],
      )!;
      expect(r.mealCount, 2);
      expect(r.daysLogged, 2);
    });

    test('Durchschnitt je erfasstem Tag, nicht je Kalendertag (FR-15)', () {
      final r = buildWeekReview(
        weekStart: monday,
        meals: [_m('a', DateTime.utc(2026, 9, 29, 10)), _m('b', DateTime.utc(2026, 10, 1, 10))],
        ingredients: [_i('a', kcal: 2000), _i('b', kcal: 1000)],
      )!;
      expect(r.daysLogged, 2);
      expect(r.averagePerDay.kcal, 1500);
    });

    test('haeufigste Gerichte der Woche, hoechstens drei', () {
      final r = buildWeekReview(
        weekStart: monday,
        meals: [
          _m('1', DateTime.utc(2026, 9, 28, 8), title: 'Müsli'),
          _m('2', DateTime.utc(2026, 9, 29, 8), title: 'Müsli'),
          _m('3', DateTime.utc(2026, 9, 30, 8), title: 'Müsli'),
          _m('4', DateTime.utc(2026, 9, 28, 18), title: 'Pizza'),
          _m('5', DateTime.utc(2026, 9, 29, 18), title: 'Pizza'),
          _m('6', DateTime.utc(2026, 9, 30, 18), title: 'Salat'),
          _m('7', DateTime.utc(2026, 10, 1, 18), title: 'Suppe'),
        ],
        ingredients: const [],
      )!;
      expect(r.topMeals.map((t) => t.title), ['Müsli', 'Pizza', 'Suppe']);
      expect(r.topMeals.first.count, 3);
    });

    test('Fotos: die juengsten Mahlzeiten mit Foto, hoechstens sechs', () {
      final r = buildWeekReview(
        weekStart: monday,
        meals: [
          for (var i = 0; i < 9; i++) _m('p$i', DateTime.utc(2026, 9, 28, 6 + i), photo: true),
          _m('ohne', DateTime.utc(2026, 9, 28, 20)),
        ],
        ingredients: const [],
      )!;
      expect(r.photoMealIds, hasLength(WeekReview.maxPhotos));
      expect(r.photoMealIds.first, 'p8', reason: 'juengste zuerst, Mahlzeit ohne Foto uebergangen');
    });

    test('Schaetzwerte in der Woche werden gemeldet', () {
      final r = buildWeekReview(
        weekStart: monday,
        meals: [_m('a', DateTime.utc(2026, 9, 29, 10), estimate: true), _m('b', DateTime.utc(2026, 9, 30, 10))],
        ingredients: const [],
      )!;
      expect(r.hasEstimates, isTrue);
    });

    test('weekStart mit Uhrzeit wird auf den Tag abgeschnitten', () {
      final r = buildWeekReview(weekStart: DateTime(2026, 9, 28, 15, 30), meals: [_m('a', DateTime.utc(2026, 9, 28, 4))], ingredients: const []);
      expect(r, isNotNull);
      expect(r!.weekStart, DateTime(2026, 9, 28));
    });
  });
}
