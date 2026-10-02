import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/features/diary/journal_page.dart';
import 'package:einkaufstracker/features/diary/meal_form_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;

import 'support/fakes.dart';

/// Journal (Phase 7e): Monats-Mosaik, gewaehlter Tag, Wochenrueckblick.
Meal _meal(String id, DateTime utc, {String title = 'Mahlzeit', String type = 'lunch', bool photo = false, bool estimate = false}) => Meal(
      id: id, householdId: 'h1', eatenAt: utc, mealType: type, title: title, servingsEaten: 1, servingsMade: 1,
      source: 'manual', isEstimate: estimate, updatedAt: DateTime.utc(2026),
    ).copyWith(photoPath: Value(photo ? 'h1/$id.jpg' : null));

MealIngredient _ing(String id, String mealId, {double? kcal}) => MealIngredient(
      id: id, householdId: 'h1', mealId: mealId, freeText: 'Zutat', quantity: 1, unit: 'kg', source: 'manual',
      kcal: kcal, updatedAt: DateTime.utc(2026),
    );

Uint8List _png() => Uint8List.fromList(img.encodePng(img.Image(width: 8, height: 8)));

void main() {
  // Freitag, 2. Oktober 2026. Der Oktober beginnt an einem Donnerstag, die laufende Woche am Montag, 28. September.
  final now = DateTime.utc(2026, 10, 2, 12);

  Widget host(List<Meal> meals, List<MealIngredient> ingredients, {FakeMealPhotoService? photos}) => ProviderScope(
        overrides: [
          mealsStreamProvider.overrideWith((ref) => Stream.value(meals)),
          mealIngredientsStreamProvider.overrideWith((ref) => Stream.value(ingredients)),
          if (photos != null) mealPhotoServiceProvider.overrideWithValue(photos),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(routes: [
            GoRoute(path: '/', builder: (_, _) => JournalPage(now: now)),
            GoRoute(
              path: '/meal-form',
              builder: (_, s) => Scaffold(body: Text('BEARBEITEN ${(s.extra as MealFormArgs).existing!.title}')),
            ),
          ]),
        ),
      );

  Future<void> open(WidgetTester tester, List<Meal> meals, List<MealIngredient> ingredients, {FakeMealPhotoService? photos}) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(meals, ingredients, photos: photos));
    await tester.pumpAndSettle();
  }

  String text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

  testWidgets('ohne Mahlzeiten: Monat, Hinweis zu leeren Tagen, "Nichts erfasst" fuer heute, leere Woche', (tester) async {
    await open(tester, const [], const []);
    expect(text(tester, 'journal-month'), 'Oktober 2026');
    expect(text(tester, 'journal-hint'), contains('nicht erfasst'));
    expect(text(tester, 'journal-day-empty'), 'Nichts erfasst.');
    expect(text(tester, 'journal-week-empty'), 'In dieser Woche wurde nichts erfasst.');
    for (var d = 1; d <= 31; d++) {
      expect(find.byKey(Key('journal-day-$d')), findsOneWidget, reason: 'Tag $d');
    }
  });

  testWidgets('Wochentage stimmen: der 1. Oktober 2026 (Donnerstag) steht in derselben Spalte wie der 8.', (tester) async {
    await open(tester, const [], const []);
    expect(tester.getTopLeft(find.byKey(const Key('journal-day-1'))).dx, tester.getTopLeft(find.byKey(const Key('journal-day-8'))).dx);
    expect(tester.getTopLeft(find.byKey(const Key('journal-day-5'))).dx, lessThan(tester.getTopLeft(find.byKey(const Key('journal-day-1'))).dx),
        reason: 'der Montag (5.) steht links vom Donnerstag (1.)');
  });

  testWidgets('heute ist gewaehlt: Mahlzeiten des Tages mit kcal, Wochenrueckblick', (tester) async {
    await open(
      tester,
      [_meal('a', DateTime.utc(2026, 10, 2, 10), title: 'Reispfanne'), _meal('b', DateTime.utc(2026, 10, 1, 10), title: 'Suppe')],
      [_ing('i1', 'a', kcal: 700), _ing('i2', 'b', kcal: 300)],
    );
    expect(text(tester, 'journal-day-totals'), '700 kcal');
    expect(find.byKey(const Key('journal-meal-a')), findsOneWidget);
    expect(find.byKey(const Key('journal-meal-b')), findsNothing, reason: 'gehoert zu einem anderen Tag');
    expect(text(tester, 'journal-week-count'), '2 Mahlzeiten an 2 von 7 Tagen');
    expect(text(tester, 'journal-week-kcal'), 'Ø 500 kcal pro erfasstem Tag');
  });

  testWidgets('Tag antippen waehlt ihn und zeigt dessen Mahlzeiten', (tester) async {
    await open(tester, [_meal('b', DateTime.utc(2026, 10, 1, 10), title: 'Suppe')], [_ing('i2', 'b', kcal: 300)]);
    expect(find.byKey(const Key('journal-day-empty')), findsOneWidget, reason: 'heute ist leer');
    await tester.tap(find.byKey(const Key('journal-day-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('journal-meal-b')), findsOneWidget);
    expect(text(tester, 'journal-day-totals'), '300 kcal');
  });

  testWidgets('ohne Energiewerte steht "Naehrwerte unbekannt" statt 0 kcal, Schaetzwerte werden genannt', (tester) async {
    await open(tester, [_meal('a', DateTime.utc(2026, 10, 2, 10), estimate: true)], [_ing('i1', 'a')]);
    expect(text(tester, 'journal-day-totals'), 'Nährwerte unbekannt · enthält Schätzwerte');
    expect(find.byKey(const Key('journal-week-kcal')), findsNothing, reason: 'ohne Energiewerte kein Durchschnitt');
  });

  testWidgets('Wochenrueckblick: haeufigste Gerichte mit Anzahl', (tester) async {
    await open(
      tester,
      [
        _meal('1', DateTime.utc(2026, 9, 28, 8), title: 'Müsli'),
        _meal('2', DateTime.utc(2026, 9, 29, 8), title: 'Müsli'),
        _meal('3', DateTime.utc(2026, 9, 30, 18), title: 'Pizza'),
      ],
      const [],
    );
    expect(text(tester, 'journal-week-top'), 'Am häufigsten: Müsli (2×), Pizza');
  });

  testWidgets('Wochenrueckblick gilt fuer die Woche des gewaehlten Tages', (tester) async {
    await open(
      tester,
      [_meal('alt', DateTime.utc(2026, 9, 23, 10), title: 'Altwoche'), _meal('neu', DateTime.utc(2026, 10, 2, 10), title: 'Diese Woche')],
      const [],
    );
    expect(text(tester, 'journal-week-count'), '1 Mahlzeit an 1 von 7 Tagen', reason: 'Woche vom 28.9. bis 4.10.');

    await tester.tap(find.byKey(const Key('journal-day-6'))); // Dienstag, 6.10.: naechste Woche
    await tester.pumpAndSettle();
    expect(text(tester, 'journal-week-empty'), 'In dieser Woche wurde nichts erfasst.');
    expect(find.byKey(const Key('journal-week-count')), findsNothing);
  });

  testWidgets('Monatswechsel: Vormonat zeigt dessen Tage, naechster Monat ist im laufenden gesperrt', (tester) async {
    await open(tester, [_meal('sep', DateTime.utc(2026, 9, 12, 10), title: 'Septemberessen')], const []);
    expect(tester.widget<IconButton>(find.byKey(const Key('journal-next'))).onPressed, isNull);

    await tester.tap(find.byKey(const Key('journal-prev')));
    await tester.pumpAndSettle();
    expect(text(tester, 'journal-month'), 'September 2026');
    expect(find.byKey(const Key('journal-day-30')), findsOneWidget);
    expect(find.byKey(const Key('journal-day-31')), findsNothing, reason: 'der September hat 30 Tage');
    expect(find.byKey(const Key('journal-meal-sep')), findsOneWidget, reason: 'gewaehlt ist der letzte erfasste Tag des Monats');
    expect(tester.widget<IconButton>(find.byKey(const Key('journal-next'))).onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('journal-next')));
    await tester.pumpAndSettle();
    expect(text(tester, 'journal-month'), 'Oktober 2026');
  });

  testWidgets('Monat ueber den Jahreswechsel: Januar 2026 hat 31 Tage, davor kommt Dezember 2025', (tester) async {
    await open(tester, const [], const []);
    for (var i = 0; i < 9; i++) {
      await tester.tap(find.byKey(const Key('journal-prev')));
      await tester.pumpAndSettle();
    }
    expect(text(tester, 'journal-month'), 'Januar 2026');
    await tester.tap(find.byKey(const Key('journal-prev')));
    await tester.pumpAndSettle();
    expect(text(tester, 'journal-month'), 'Dezember 2025');
  });

  testWidgets('Tag mit Foto zeigt das Bild im Mosaik, Wochenrueckblick zeigt die Fotos der Woche', (tester) async {
    final db = memoryDb();
    addTearDown(db.close);
    final photos = FakeMealPhotoService(db, mealRepo(db))
      ..photos['a'] = _png()
      ..photos['b'] = _png();
    await open(
      tester,
      [_meal('a', DateTime.utc(2026, 10, 2, 10), photo: true), _meal('b', DateTime.utc(2026, 9, 29, 10), photo: true), _meal('c', DateTime.utc(2026, 10, 3, 10))],
      const [],
      photos: photos,
    );
    expect(find.descendant(of: find.byKey(const Key('journal-day-2')), matching: find.byKey(const Key('meal-photo-image'))), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('journal-day-3')), matching: find.byKey(const Key('meal-photo-image'))), findsNothing);
    expect(find.byKey(const Key('journal-week-photo-a')), findsOneWidget);
    expect(find.byKey(const Key('journal-week-photo-b')), findsOneWidget);
    expect(find.byKey(const Key('journal-week-photo-c')), findsNothing, reason: 'Mahlzeit ohne Foto');
  });

  testWidgets('Foto nicht abrufbar: Tag bleibt als erfasster Tag sichtbar, kein Fehler', (tester) async {
    final db = memoryDb();
    addTearDown(db.close);
    final photos = FakeMealPhotoService(db, mealRepo(db)); // kein Foto vorhanden
    await open(tester, [_meal('a', DateTime.utc(2026, 10, 2, 10), photo: true)], const [], photos: photos);
    expect(find.byKey(const Key('meal-photo-image')), findsNothing);
    expect(find.byKey(const Key('journal-day-2')), findsOneWidget);
    expect(find.byKey(const Key('journal-meal-a')), findsOneWidget);
  });

  testWidgets('Mahlzeit in der Tageskarte antippen oeffnet sie zum Bearbeiten', (tester) async {
    await open(tester, [_meal('a', DateTime.utc(2026, 10, 2, 10), title: 'Reispfanne')], const []);
    await tester.tap(find.byKey(const Key('journal-meal-a')));
    await tester.pumpAndSettle();
    expect(find.text('BEARBEITEN Reispfanne'), findsOneWidget);
  });
}
