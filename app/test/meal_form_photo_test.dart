import 'dart:typed_data';

import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/meal_repository.dart';
import 'package:einkaufstracker/features/diary/meal_form_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;

import 'support/fakes.dart';

/// Foto zur Mahlzeit im Formular (Doku 15 §3.1, Phase 7b): aufnehmen, ersetzen, entfernen, mit der Mahlzeit loeschen.
/// Der Foto-Dienst ist hier eine Attrappe im Speicher (Dateiverhalten: meal_photo_service_test.dart).
Uint8List _png(int shade) {
  final image = img.Image(width: 8, height: 8);
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 8; x++) {
      image.setPixelRgb(x, y, shade, 128, 64);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  late AppDatabase db;
  late MealRepository meals;
  late FakeMealPhotoService service;

  /// Was der Foto-Dialog als Naechstes liefert (`null` = abgebrochen) und wie er aufgerufen wurde.
  Uint8List? next;
  bool? lastCamera;

  setUp(() {
    db = memoryDb();
    meals = mealRepo(db);
    service = FakeMealPhotoService(db, meals);
    next = _png(10);
    lastCamera = null;
  });
  tearDown(() => db.close());

  Widget host({Meal? existing, FakeMealPhotoService? photos, bool photosAvailable = true}) => ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          mealRepositoryProvider.overrideWithValue(meals),
          productRepositoryProvider.overrideWithValue(productRepo(db)),
          inventoryRepositoryProvider.overrideWithValue(inventoryRepo(db)),
          productsStreamProvider.overrideWith((ref) => Stream.value(const <Product>[])),
          activeInventoryStreamProvider.overrideWith((ref) => Stream.value(const <InventoryItem>[])),
          mealPhotoServiceProvider.overrideWithValue(photos ?? service),
          mealPhotoPickerProvider.overrideWithValue(({required bool camera}) async {
            lastCamera = camera;
            return next;
          }),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(routes: [
            GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('START'))),
            GoRoute(path: '/form', builder: (_, _) => MealFormPage(existing: existing, photosAvailable: photosAvailable)),
          ]),
        ),
      );

  Future<void> open(WidgetTester tester, Widget app) async {
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('START'))).push('/form');
    await tester.pumpAndSettle();
  }

  Future<Meal> mealWithPhoto() async {
    final m = await meals.create(MealDraft(title: 'Pasta', eatenAt: DateTime.utc(2026, 10, 1, 12)));
    await service.attach(m, _png(200));
    service.attached.clear();
    return (await meals.get(m.id))!;
  }

  testWidgets('Web-Version (kein lokaler Dateispeicher): kein Foto-Bereich, keine Foto-Analyse, Mahlzeit laesst sich speichern', (tester) async {
    await open(tester, host(photosAvailable: false));
    expect(find.byKey(const Key('meal-photo-camera')), findsNothing);
    expect(find.byKey(const Key('meal-photo-gallery')), findsNothing);
    expect(find.byKey(const Key('meal-analyze')), findsNothing);
    await tester.enterText(find.byKey(const Key('meal-title')), 'Suppe');
    await tester.tap(find.byKey(const Key('meal-save')));
    await tester.pumpAndSettle();
    expect((await db.select(db.meals).get()).single.title, 'Suppe');
    expect(service.attached, isEmpty);
  });

  testWidgets('ohne Foto: Knoepfe zum Aufnehmen und aus der Galerie, keine Vorschau', (tester) async {
    await open(tester, host());
    expect(find.byKey(const Key('meal-photo-camera')), findsOneWidget);
    expect(find.byKey(const Key('meal-photo-gallery')), findsOneWidget);
    expect(find.byKey(const Key('meal-photo-remove')), findsNothing);
    expect(find.byKey(const Key('meal-photo-preview')), findsNothing);
  });

  testWidgets('Foto aufnehmen und speichern: Foto wird der gespeicherten Mahlzeit zugeordnet, ohne erneutes Verkleinern', (tester) async {
    await open(tester, host());
    await tester.enterText(find.byKey(const Key('meal-title')), 'Nudeln');
    await tester.tap(find.byKey(const Key('meal-photo-camera')));
    await tester.pumpAndSettle();
    expect(lastCamera, isTrue);
    expect(find.byKey(const Key('meal-photo-preview')), findsOneWidget);

    await tester.tap(find.byKey(const Key('meal-save')));
    await tester.pumpAndSettle();

    final meal = (await db.select(db.meals).get()).single;
    expect(meal.title, 'Nudeln');
    expect(meal.photoPath, 'h1/${meal.id}.jpg');
    expect(service.attached, hasLength(1));
    expect(service.attached.single.mealId, meal.id);
    expect(service.attached.single.bytes, _png(10));
    expect(service.attached.single.prepared, isTrue, reason: 'beim Aufnehmen schon verkleinert');
  });

  testWidgets('beim Aufnehmen wird verkleinert: der Dienst bekommt die verkleinerten, nicht die Originalbytes', (tester) async {
    final shrunk = _png(99);
    final shrinking = FakeMealPhotoService(db, meals, prepare: (_) async => shrunk);
    await open(tester, host(photos: shrinking));
    await tester.enterText(find.byKey(const Key('meal-title')), 'Nudeln');
    await tester.tap(find.byKey(const Key('meal-photo-camera')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('meal-save')));
    await tester.pumpAndSettle();
    expect(shrinking.attached.single.bytes, shrunk);
    expect(shrunk, isNot(_png(10)), reason: 'Testaufbau: Original und verkleinertes Bild unterscheiden sich');
  });

  testWidgets('Foto aus der Galerie waehlen', (tester) async {
    await open(tester, host());
    await tester.tap(find.byKey(const Key('meal-photo-gallery')));
    await tester.pumpAndSettle();
    expect(lastCamera, isFalse);
    expect(find.byKey(const Key('meal-photo-preview')), findsOneWidget);
  });

  testWidgets('Abbrechen des Foto-Dialogs aendert nichts und zeigt keinen Fehler', (tester) async {
    next = null;
    await open(tester, host());
    await tester.tap(find.byKey(const Key('meal-photo-camera')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('meal-photo-preview')), findsNothing);
    expect(find.byKey(const Key('meal-error')), findsNothing);
  });

  testWidgets('unlesbares Foto: sofort eine Meldung, kein Foto, Mahlzeit bleibt speicherbar', (tester) async {
    final strict = FakeMealPhotoService(db, meals, prepare: (_) async => throw const FormatException('kein Bild'));
    await open(tester, host(photos: strict));
    await tester.tap(find.byKey(const Key('meal-photo-gallery')));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.byKey(const Key('meal-error'))).data, contains('konnte nicht gelesen werden'));
    expect(find.byKey(const Key('meal-photo-preview')), findsNothing);
    await tester.enterText(find.byKey(const Key('meal-title')), 'Salat');
    await tester.tap(find.byKey(const Key('meal-save')));
    await tester.pumpAndSettle();
    expect((await db.select(db.meals).get()).single.photoPath, isNull);
    expect(strict.attached, isEmpty);
  });

  testWidgets('Bearbeiten: vorhandenes Foto wird angezeigt', (tester) async {
    final meal = await mealWithPhoto();
    await open(tester, host(existing: meal));
    expect(find.byKey(const Key('meal-photo-image')), findsOneWidget);
    expect(find.byKey(const Key('meal-photo-remove')), findsOneWidget);
    expect(find.text('Neues Foto'), findsOneWidget);
  });

  testWidgets('Foto entfernen und speichern: Pfad ist weg, Mahlzeit bleibt', (tester) async {
    final meal = await mealWithPhoto();
    await open(tester, host(existing: meal));
    await tester.tap(find.byKey(const Key('meal-photo-remove')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('meal-photo-image')), findsNothing);
    expect(find.byKey(const Key('meal-photo-remove')), findsNothing);

    await tester.tap(find.byKey(const Key('meal-save')));
    await tester.pumpAndSettle();

    expect(service.purged.single, (mealId: meal.id, clearPath: true));
    expect((await meals.get(meal.id))!.photoPath, isNull);
    expect((await meals.get(meal.id))!.deletedAt, isNull);
  });

  testWidgets('Entfernen und dann ein neues Foto waehlen ersetzt das Foto statt es zu loeschen', (tester) async {
    final meal = await mealWithPhoto();
    await open(tester, host(existing: meal));
    await tester.tap(find.byKey(const Key('meal-photo-remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('meal-photo-camera')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('meal-save')));
    await tester.pumpAndSettle();
    expect(service.purged, isEmpty);
    expect(service.photos[meal.id], _png(10));
  });

  testWidgets('Foto ersetzen: neue Bytes ersetzen die alten', (tester) async {
    final meal = await mealWithPhoto();
    await open(tester, host(existing: meal));
    await tester.tap(find.byKey(const Key('meal-photo-camera')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('meal-save')));
    await tester.pumpAndSettle();
    expect(service.photos[meal.id], _png(10));
    expect((await meals.get(meal.id))!.photoPath, 'h1/${meal.id}.jpg');
  });

  testWidgets('Speichern ohne Fotoaenderung laesst das vorhandene Foto unangetastet', (tester) async {
    final meal = await mealWithPhoto();
    await open(tester, host(existing: meal));
    await tester.tap(find.byKey(const Key('meal-save')));
    await tester.pumpAndSettle();
    expect(service.attached, isEmpty);
    expect(service.purged, isEmpty);
    expect((await meals.get(meal.id))!.photoPath, 'h1/${meal.id}.jpg');
    expect(service.photos[meal.id], _png(200));
  });

  testWidgets('Mahlzeit loeschen raeumt auch das Foto auf', (tester) async {
    final meal = await mealWithPhoto();
    await open(tester, host(existing: meal));
    await tester.tap(find.byKey(const Key('meal-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('meal-delete-confirm')));
    await tester.pumpAndSettle();

    expect(service.purged.single.mealId, meal.id);
    expect(service.photos, isEmpty);
    expect((await meals.get(meal.id))!.deletedAt, isNotNull);
  });

  testWidgets('Mahlzeit ohne Foto loeschen ruft den Foto-Dienst nicht auf', (tester) async {
    final m = await meals.create(MealDraft(title: 'Suppe', eatenAt: DateTime.utc(2026, 10, 1, 12)));
    await open(tester, host(existing: m));
    await tester.tap(find.byKey(const Key('meal-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('meal-delete-confirm')));
    await tester.pumpAndSettle();
    expect(service.purged, isEmpty);
  });

  testWidgets('Foto kann nicht abgelegt werden: Mahlzeit ist gespeichert und der Nutzer erfaehrt es', (tester) async {
    service.attachError = StateError('Speicher voll');
    await open(tester, host());
    await tester.enterText(find.byKey(const Key('meal-title')), 'Suppe');
    await tester.tap(find.byKey(const Key('meal-photo-camera')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('meal-save')));
    await tester.pumpAndSettle();

    expect((await db.select(db.meals).get()).single.title, 'Suppe');
    expect(find.text('START'), findsOneWidget);
    expect(find.textContaining('Foto konnte nicht abgelegt werden'), findsOneWidget);
  });
}
