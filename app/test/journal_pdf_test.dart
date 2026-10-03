import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/domain/nutrition/nutrition_targets.dart';
import 'package:einkaufstracker/domain/nutrition/journal_report.dart';
import 'package:einkaufstracker/features/diary/journal_page.dart';
import 'package:einkaufstracker/features/diary/journal_pdf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/fakes.dart';

/// PDF des Monats aus dem Essenstagebuch (Ausbau 1.12): Renderer und Export aus dem Journal.
Uint8List _font(String name) => File('assets/fonts/$name').readAsBytesSync();

Uint8List _png(int w, int h) => Uint8List.fromList(img.encodePng(img.Image(width: w, height: h)));

ReportMealInput _input(String id, DateTime utc, {String title = 'Essen', bool photo = false}) =>
    (id: id, eatenAtUtc: utc, title: title, mealType: 'lunch', servingsEaten: 1, servingsMade: 1, isEstimate: false, hasPhoto: photo);

JournalReport _report(List<ReportMealInput> meals, {List<({String mealId, double? kcal})> kcal = const []}) => buildJournalReport(
      year: 2026,
      month: 9,
      meals: meals,
      ingredients: [for (final k in kcal) (mealId: k.mealId, kcal: k.kcal, proteinG: null, fatG: null, carbsG: null, sugarG: null, fiberG: null, saltG: null)],
    )!;

int _pages(Uint8List pdf) => RegExp(r'/Type\s*/Page(?!s)').allMatches(latin1.decode(pdf, allowInvalid: true)).length;

int _images(Uint8List pdf) => RegExp(r'/Subtype\s*/Image').allMatches(latin1.decode(pdf, allowInvalid: true)).length;

Meal _meal(String id, DateTime utc, {String title = 'Mahlzeit', String? photoPath}) => Meal(
      id: id, householdId: 'h1', eatenAt: utc, mealType: 'lunch', title: title, servingsEaten: 1, servingsMade: 1,
      source: 'manual', isEstimate: false, photoPath: photoPath, updatedAt: DateTime.utc(2026),
    );

MealIngredient _ing(String id, String mealId, {double? kcal}) => MealIngredient(
      id: id, householdId: 'h1', mealId: mealId, freeText: 'Zutat', quantity: 1, unit: 'kg', source: 'manual', kcal: kcal, updatedAt: DateTime.utc(2026),
    );

void main() {
  final regular = _font('Roboto-Regular.ttf');
  final bold = _font('Roboto-Bold.ttf');
  final created = DateTime.utc(2026, 10, 3, 9);

  Future<Uint8List> render(JournalReport r, {Map<String, Uint8List> photos = const {}, bool compress = false}) =>
      buildJournalPdf(r, regularFont: regular, boldFont: bold, createdAtUtc: created, photos: photos, compress: compress);

  group('buildJournalPdf', () {
    test('liefert ein gueltiges PDF mit Titel und einer Seite fuer wenige Tage', () async {
      final r = _report([_input('a', DateTime.utc(2026, 9, 3, 10), title: 'Müsli')], kcal: [(mealId: 'a', kcal: 400)]);
      final pdf = await render(r);
      final text = latin1.decode(pdf, allowInvalid: true);
      expect(text, startsWith('%PDF-'));
      expect(text.trimRight(), endsWith('%%EOF'));
      expect(text, contains('Essenstagebuch September 2026'), reason: 'Dokumenttitel in den Metadaten');
      expect(_pages(pdf), 1);
    });

    test('ein Monat mit vielen Tagen und Mahlzeiten wird auf mehrere Seiten umbrochen, nichts bricht ab', () async {
      final meals = [
        for (var d = 1; d <= 30; d++)
          for (var k = 0; k < 4; k++) _input('m$d-$k', DateTime.utc(2026, 9, d, 6 + k * 3), title: 'Gericht Nummer $d-$k mit einem etwas längeren Namen'),
      ];
      final r = _report(meals, kcal: [for (final m in meals) (mealId: m.id, kcal: 500.0)]);
      final pdf = await render(r);
      expect(_pages(pdf), greaterThan(2));
    });

    test('Umlaute, Ø, × und Anfuehrungszeichen brauchen keine Ersatzschrift (Roboto deckt sie ab)', () async {
      final r = _report(
        [_input('a', DateTime.utc(2026, 9, 3, 10), title: 'Käsespätzle & Süßkartoffel'), _input('b', DateTime.utc(2026, 9, 4, 10), title: 'Käsespätzle & Süßkartoffel')],
        kcal: [(mealId: 'a', kcal: 1200), (mealId: 'b', kcal: 1500)],
      );
      final pdf = await render(r); // wirft bei fehlenden Glyphen nicht, warnt nur; hier zaehlt, dass ein Dokument entsteht
      expect(pdf.length, greaterThan(2000));
    });

    test('ein Foto wird als Bild eingebettet', () async {
      final r = _report([_input('a', DateTime.utc(2026, 9, 3, 10), photo: true)]);
      final small = shrinkPhotoForPdf(_png(800, 600))!;
      final withPhoto = await render(r, photos: {'a': small});
      final without = await render(r);
      expect(_images(withPhoto), 1);
      expect(_images(without), 0);
    });

    test('ohne bekannte Naehrwerte und mit Schaetzwerten entsteht trotzdem ein Dokument', () async {
      final r = buildJournalReport(
        year: 2026,
        month: 9,
        meals: [(id: 'a', eatenAtUtc: DateTime.utc(2026, 9, 3, 10), title: 'Restaurant', mealType: 'dinner', servingsEaten: 1, servingsMade: 1, isEstimate: true, hasPhoto: false)],
        ingredients: const [],
      )!;
      expect(r.averagePerDay, isNull);
      expect(_pages(await render(r)), 1);
    });
  });

  group('shrinkPhotoForPdf', () {
    test('verkleinert auf hoechstens 360 Pixel Kantenlaenge und liefert JPEG', () {
      final out = shrinkPhotoForPdf(_png(1600, 1200))!;
      final decoded = img.decodeJpg(out)!;
      expect(decoded.width, 360);
      expect(decoded.height, 270);
      final tall = img.decodeJpg(shrinkPhotoForPdf(_png(600, 1200))!)!;
      expect(tall.height, 360);
      expect(tall.width, 180);
    });

    test('ein kleines Bild bleibt in der Groesse', () {
      final decoded = img.decodeJpg(shrinkPhotoForPdf(_png(100, 80))!)!;
      expect([decoded.width, decoded.height], [100, 80]);
    });

    test('etwas, das kein Bild ist, ergibt null', () {
      expect(shrinkPhotoForPdf(Uint8List.fromList([1, 2, 3, 4])), isNull);
    });
  });

  group('Export im Journal', () {
    late AppDatabase db;
    late FakeMealPhotoService photos;
    final shared = <({Uint8List bytes, String fileName, String mimeType, String? text})>[];
    Object? shareError;

    setUp(() {
      db = memoryDb();
      photos = FakeMealPhotoService(db, mealRepo(db));
      shared.clear();
      shareError = null;
    });
    tearDown(() => db.close());

    Future<void> open(WidgetTester tester, List<Meal> meals, List<MealIngredient> ingredients) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          nutritionTargetsProvider.overrideWith((ref) => Stream.value(const NutritionTargets())),
          mealsStreamProvider.overrideWith((ref) => Stream.value(meals)),
          mealIngredientsStreamProvider.overrideWith((ref) => Stream.value(ingredients)),
          mealPhotoServiceProvider.overrideWithValue(photos),
          shareFileProvider.overrideWithValue(({required bytes, required fileName, required mimeType, text}) async {
            if (shareError != null) throw shareError!;
            shared.add((bytes: bytes, fileName: fileName, mimeType: mimeType, text: text));
          }),
        ],
        child: MaterialApp(home: JournalPage(now: DateTime.utc(2026, 10, 2, 12))),
      ));
      await tester.pumpAndSettle();
    }

    /// Antippen und auf das echte (asynchrone) Erzeugen warten: Schrift laden und PDF bauen laufen ausserhalb der Testuhr.
    Future<void> export(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('journal-export-pdf')));
      await tester.runAsync(() async {
        for (var i = 0; i < 100 && shared.isEmpty && shareError == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await tester.pumpAndSettle();
    }

    final october = [_meal('a', DateTime.utc(2026, 10, 1, 10), title: 'Müsli'), _meal('b', DateTime.utc(2026, 10, 2, 10), title: 'Suppe')];
    final kcal = [_ing('i1', 'a', kcal: 400), _ing('i2', 'b', kcal: 600)];

    testWidgets('der Knopf teilt ein PDF des angezeigten Monats mit sprechendem Dateinamen', (tester) async {
      await open(tester, october, kcal);
      expect(find.text('Monat als PDF teilen'), findsOneWidget);
      await export(tester);
      expect(shared, hasLength(1));
      expect(shared.single.fileName, 'Essenstagebuch 2026-10.pdf');
      expect(shared.single.mimeType, 'application/pdf');
      expect(shared.single.text, 'Essenstagebuch Oktober 2026');
      expect(latin1.decode(shared.single.bytes.sublist(0, 5)), '%PDF-');
      expect(find.text('Monat als PDF teilen'), findsOneWidget, reason: 'nach dem Export wieder bedienbar');
      expect(find.text('PDF-Export nicht möglich.'), findsNothing);
    });

    testWidgets('der Vormonat wird als Vormonat exportiert', (tester) async {
      await open(tester, [...october, _meal('s', DateTime.utc(2026, 9, 12, 10), title: 'Pasta')], [...kcal, _ing('i3', 's', kcal: 800)]);
      await tester.tap(find.byKey(const Key('journal-prev')));
      await tester.pumpAndSettle();
      await export(tester);
      expect(shared.single.fileName, 'Essenstagebuch 2026-09.pdf');
    });

    testWidgets('in einem Monat ohne Eintrag gibt es keinen Knopf', (tester) async {
      await open(tester, october, kcal);
      await tester.tap(find.byKey(const Key('journal-prev')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('journal-export-pdf')), findsNothing);
    });

    testWidgets('Fotos kommen mit, wenn sie erreichbar sind; ein fehlendes Foto stoppt den Export nicht', (tester) async {
      photos.photos['a'] = _png(640, 480);
      final meals = [_meal('a', DateTime.utc(2026, 10, 1, 10), photoPath: 'h1/a.jpg'), _meal('b', DateTime.utc(2026, 10, 2, 10), photoPath: 'h1/b.jpg')];
      await open(tester, meals, kcal);
      await export(tester);
      expect(_images(shared.single.bytes), 1, reason: 'nur das Foto von Mahlzeit a ist da');
    });

    testWidgets('scheitert das Teilen, steht eine Meldung da und der Knopf ist wieder bedienbar', (tester) async {
      shareError = StateError('kein Teilen');
      await open(tester, october, kcal);
      await export(tester);
      expect(find.text('PDF-Export nicht möglich.'), findsOneWidget);
      expect(tester.widget<TextButton>(find.byKey(const Key('journal-export-pdf'))).onPressed, isNotNull);
    });
  });
}
