import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:einkaufstracker/data/files/meal_photo_service.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/meal_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/fakes.dart';

/// Essensfotos (Doku 15 §3.1): lokal ablegen, offline-tauglich hochladen, bei Bedarf nachladen.
void main() {
  late AppDatabase db;
  late FakeRemoteFileStore remote;
  late Directory dir;
  late MealRepository meals;
  late MealPhotoService service;

  final photo = Uint8List.fromList([1, 2, 3, 4, 5]);

  setUp(() {
    db = memoryDb();
    remote = FakeRemoteFileStore();
    dir = Directory.systemTemp.createTempSync('mealphoto');
    meals = mealRepo(db);
    service = mealPhotoService(db, remote, dir, meals: meals);
  });
  tearDown(() async {
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<Meal> newMeal([String title = 'Pasta']) => meals.create(MealDraft(title: title, eatenAt: DateTime.utc(2026, 10, 1, 12)));

  test('attach: Foto liegt lokal, Pfad steht an der Mahlzeit, Upload ist eingereiht', () async {
    final meal = await newMeal();
    await service.attach(meal, photo);

    final stored = (await meals.get(meal.id))!;
    expect(stored.photoPath, 'h1/${meal.id}.jpg');
    expect(File('${dir.path}/meal_photos/${meal.id}.jpg').readAsBytesSync(), photo);
    expect(remote.files, isEmpty, reason: 'Upload erst beim Sync');
    final outbox = await db.select(db.outbox).get();
    expect(outbox.where((o) => o.remoteTable == 'meals' && o.payload.contains('${meal.id}.jpg')), isNotEmpty, reason: 'Pfad wird synchronisiert');
  });

  test('deleteAllLocal (Abmelden): alle lokalen Fotos weg, Server-Dateien bleiben, ohne Ordner kein Fehler', () async {
    final meal = await newMeal();
    await service.attach(meal, photo);
    await service.uploadPending();
    await service.deleteAllLocal();
    expect(Directory('${dir.path}/meal_photos').existsSync(), isFalse);
    expect(remote.files, isNotEmpty);
    await service.deleteAllLocal(); // zweimal ist kein Fehler
  });

  test('uploadPending: laedt in den Bucket-Pfad der Mahlzeit, JPEG, danach ist die Warteschlange leer', () async {
    final meal = await newMeal();
    await service.attach(meal, photo);

    expect(await service.uploadPending(), 1);
    expect(remote.files['h1/${meal.id}.jpg'], photo);
    expect(remote.contentTypes['h1/${meal.id}.jpg'], 'image/jpeg');
    expect(await service.uploadPending(), 0, reason: 'nichts mehr zu tun');
    expect(remote.uploads, 1);
  });

  test('offline bleibt das Foto in der Warteschlange und geht beim naechsten Versuch hoch', () async {
    final meal = await newMeal();
    await service.attach(meal, photo);
    remote.offline = true;
    expect(await service.uploadPending(), 0);
    remote.offline = false;
    expect(await service.uploadPending(), 1);
    expect(remote.files, hasLength(1));
  });

  test('Foto ersetzen: neue Bytes lokal, genau ein Eintrag in der Warteschlange', () async {
    final meal = await newMeal();
    await service.attach(meal, photo);
    await service.attach(meal, Uint8List.fromList([9, 9]));
    expect(await service.uploadPending(), 1);
    expect(remote.files['h1/${meal.id}.jpg'], [9, 9]);
  });

  test('geloeschte Mahlzeit: wartender Upload wird verworfen statt fuer immer wiederholt', () async {
    final meal = await newMeal();
    await service.attach(meal, photo);
    await meals.delete(meal.id);
    expect(await service.uploadPending(), 0);
    expect(remote.uploads, 0);
    expect(await service.uploadPending(), 0);
  });

  test('verschwundene lokale Datei: Eintrag wird verworfen, kein Absturz', () async {
    final meal = await newMeal();
    await service.attach(meal, photo);
    File('${dir.path}/meal_photos/${meal.id}.jpg').deleteSync();
    expect(await service.uploadPending(), 0);
  });

  test('Race: ein waehrend des Uploads hinzugekommenes Foto geht nicht verloren', () async {
    final a = await newMeal('A');
    final b = await newMeal('B');
    await service.attach(a, photo);
    final gate = Completer<void>();
    remote.uploadGate = gate.future;
    final running = service.uploadPending();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await service.attach(b, Uint8List.fromList([7]));
    gate.complete();
    await running;
    remote.uploadGate = null;

    expect(await service.uploadPending(), 1, reason: 'B war noch in der Warteschlange');
    expect(remote.files.keys, containsAll(['h1/${a.id}.jpg', 'h1/${b.id}.jpg']));
  });

  group('bytes', () {
    test('ohne Foto: null', () async {
      expect(await service.bytes(await newMeal()), isNull);
    });

    test('lokale Kopie wird ohne Netz gelesen', () async {
      final meal = await newMeal();
      await service.attach(meal, photo);
      remote.offline = true;
      expect(await service.bytes((await meals.get(meal.id))!), photo);
    });

    test('Foto von einem anderen Geraet: wird vom Server geholt und lokal gemerkt', () async {
      final meal = await newMeal();
      await service.attach(meal, photo);
      await service.uploadPending();
      File('${dir.path}/meal_photos/${meal.id}.jpg').deleteSync();

      final stored = (await meals.get(meal.id))!;
      expect(await service.bytes(stored), photo);
      expect(File('${dir.path}/meal_photos/${meal.id}.jpg').existsSync(), isTrue);
      remote.offline = true;
      expect(await service.bytes(stored), photo, reason: 'beim zweiten Mal reicht die lokale Kopie');
    });

    test('weder lokal noch erreichbar: null statt Fehler', () async {
      final meal = await newMeal();
      await service.attach(meal, photo);
      File('${dir.path}/meal_photos/${meal.id}.jpg').deleteSync();
      remote.offline = true;
      expect(await service.bytes((await meals.get(meal.id))!), isNull);
    });
  });

  group('purge', () {
    test('entfernt lokale Datei, Server-Datei und Warteschlange', () async {
      final meal = await newMeal();
      await service.attach(meal, photo);
      await service.uploadPending();
      final stored = (await meals.get(meal.id))!;
      await service.purge(stored);

      expect(File('${dir.path}/meal_photos/${meal.id}.jpg').existsSync(), isFalse);
      expect(remote.files, isEmpty);
    });

    test('clearPath loescht zusaetzlich den Pfad an der Mahlzeit (Foto entfernt, Mahlzeit bleibt)', () async {
      final meal = await newMeal();
      await service.attach(meal, photo);
      await service.purge((await meals.get(meal.id))!, clearPath: true);
      expect((await meals.get(meal.id))!.photoPath, isNull);
    });

    test('noch nicht hochgeladenes Foto verschwindet auch aus der Warteschlange', () async {
      final meal = await newMeal();
      await service.attach(meal, photo);
      await service.purge((await meals.get(meal.id))!, clearPath: true);
      expect(await service.uploadPending(), 0);
      expect(remote.uploads, 0);
    });

    test('ohne Netz scheitert purge nicht', () async {
      final meal = await newMeal();
      await service.attach(meal, photo);
      await service.uploadPending();
      remote.offline = true;
      await service.purge((await meals.get(meal.id))!, clearPath: true);
      expect((await meals.get(meal.id))!.photoPath, isNull);
    });
  });

  group('prepareMealPhoto', () {
    Uint8List jpeg(int w, int h) {
      final image = img.Image(width: w, height: h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          image.setPixelRgb(x, y, (x * 255 ~/ w), (y * 255 ~/ h), ((x ^ y) & 255));
        }
      }
      return Uint8List.fromList(img.encodeJpg(image, quality: 95));
    }

    test('verkleinert auf hoechstens 1600 px laengste Kante und unter die Groessengrenze', () async {
      final out = await prepareMealPhoto(jpeg(3200, 2400));
      final decoded = img.decodeJpg(out)!;
      expect(decoded.width, 1600);
      expect(decoded.height, 1200);
      expect(out.length, lessThanOrEqualTo(mealPhotoMaxBytes));
    });

    test('kleine Bilder bleiben in der Groesse', () async {
      final decoded = img.decodeJpg(await prepareMealPhoto(jpeg(640, 480)))!;
      expect([decoded.width, decoded.height], [640, 480]);
    });

    test('kein lesbares Bild: FormatException statt stiller Muell-Datei', () async {
      await expectLater(prepareMealPhoto(Uint8List.fromList([1, 2, 3])), throwsFormatException);
    });
  });
}
