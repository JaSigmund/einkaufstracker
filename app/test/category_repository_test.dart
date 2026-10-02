import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/category_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// `CategoryRepository.rename` hatte bisher keinen eigenen Test (nur `add`/die Reaktivierung einer
/// geloeschten Kategorie ist in sync_test.dart abgedeckt).
void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  group('rename', () {
    test('benennt um', () async {
      final repo = categoryRepo(db);
      await repo.add('Obst');
      final cat = (await repo.watchAll().first).single;
      await repo.rename(cat.id, 'Frisches Obst');
      expect((await repo.watchAll().first).single.name, 'Frisches Obst');
    });

    test('echtes Duplikat (eine andere, noch sichtbare Kategorie hat den Namen schon): wird abgelehnt', () async {
      final repo = categoryRepo(db);
      await repo.add('Obst');
      await repo.add('Gemüse');
      final obst = (await repo.watchAll().first).firstWhere((c) => c.name == 'Obst');
      expect(() => repo.rename(obst.id, 'Gemüse'), throwsA(isA<DuplicateCategoryException>()));
    });

    test('Codereview-Fund 2026-10-01: Umbenennen auf den Namen einer bereits geloeschten (unsichtbaren) Kategorie ist erlaubt', () async {
      final repo = categoryRepo(db);
      await repo.add('Süßes');
      final suesses = (await repo.watchAll().first).single;
      await repo.softDelete(suesses.id);
      expect(await repo.watchAll().first, isEmpty); // nicht mehr sichtbar

      await repo.add('Naschereien');
      final naschereien = (await repo.watchAll().first).single;
      await repo.rename(naschereien.id, 'Süßes'); // durfte vorher faelschlich nicht
      expect((await repo.watchAll().first).single.name, 'Süßes');
    });

    test('leerer Name wird abgelehnt', () async {
      final repo = categoryRepo(db);
      await repo.add('Obst');
      final cat = (await repo.watchAll().first).single;
      expect(() => repo.rename(cat.id, '   '), throwsArgumentError);
    });

    test('gleicher Name: kein Fehler, keine Aenderung', () async {
      final repo = categoryRepo(db);
      await repo.add('Obst');
      final cat = (await repo.watchAll().first).single;
      await repo.rename(cat.id, 'Obst');
      expect((await repo.watchAll().first).single.updatedAt, cat.updatedAt);
    });
  });
}
