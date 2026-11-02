import 'dart:async';

import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/supplement_repository.dart';
import 'package:einkaufstracker/data/share/quick_action_source.dart';
import 'package:einkaufstracker/domain/nutrition/micros.dart';
import 'package:einkaufstracker/features/diary/quick_action_handler.dart';
import 'package:einkaufstracker/features/diary/quick_intake_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Schnell eintragen (ADR-041). Heute ist der 2. November 2026.
final _now = DateTime.utc(2026, 11, 2, 10);

class _FakeSource implements QuickActionSource {
  _FakeSource([this.initial]);
  String? initial;
  final controller = StreamController<String>.broadcast();

  @override
  Future<String?> takeInitial() async {
    final value = initial;
    initial = null;
    return value;
  }

  @override
  Stream<String> get incoming => controller.stream;
}

void pageTest(String name, Future<void> Function(WidgetTester tester) body) => testWidgets(name, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

void main() {
  late AppDatabase db;
  late SupplementRepository repo;

  setUp(() {
    db = memoryDb();
    repo = SupplementRepository(db, householdId: () async => 'h1');
  });
  tearDown(() => db.close());

  group('Wasser', () {
    test('Der erste Tipp legt den Eintrag an, weitere nutzen ihn, die Kennung ist je Haushalt fest', () async {
      final first = await repo.takeWater(at: _now);
      await repo.takeWater(at: _now);
      final water = await db.select(db.supplements).getSingle();
      expect(water.id, repo.waterIdFor('h1'));
      expect(water.name, 'Wasser');
      expect(water.servingLabel, 'Glas');
      expect(repo.isWater(water), isTrue);
      expect(first.supplementId, water.id);
      expect(parseMicros(first.micros), {'water_g': 250.0});
      expect(await db.select(db.supplementIntakes).get(), hasLength(2));
    });

    test('Eine geaenderte Glasgroesse gilt, ein geloeschter Eintrag kommt zurueck', () async {
      await repo.takeWater(at: _now);
      final water = await db.select(db.supplements).getSingle();
      await repo.save(id: water.id, name: 'Wasser', servingLabel: 'Glas', micros: const {'water_g': 330.0});
      expect(parseMicros((await repo.takeWater(at: _now)).micros), {'water_g': 330.0});
      await repo.delete(water.id);
      expect(parseMicros((await repo.takeWater(at: _now)).micros), {'water_g': 250.0});
      expect((await db.select(db.supplements).getSingle()).deletedAt, isNull);
    });

    test('Eine normale Ergaenzung ist kein Wasser', () async {
      final s = await repo.save(name: 'Vitamin D3', servingLabel: 'Kapsel', micros: const {'vit_d_ug': 25.0});
      expect(repo.isWater(s), isFalse);
    });
  });

  group('Seite', () {
    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db), supplementRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(home: QuickIntakePage(now: _now)),
      ));
      await tester.pumpAndSettle();
    }

    pageTest('Ein Tipp traegt ein Glas ein, zaehlt mit, laesst sich zuruecknehmen, die Meldung bleibt nicht stehen', (tester) async {
      await open(tester);
      expect(find.text('Heute noch kein Glas'), findsOneWidget);
      await tester.tap(find.byKey(const Key('quick-water')));
      await tester.pumpAndSettle();
      expect(find.text('Heute: 1 Glas · 250 ml'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(tester.widget<SnackBar>(find.byType(SnackBar)).persist, isFalse);

      await tester.tap(find.byKey(const Key('quick-water')));
      await tester.pumpAndSettle();
      expect(find.text('Heute: 2 Gläser · 500 ml'), findsOneWidget);

      await tester.tap(find.text('Rückgängig'));
      await tester.pumpAndSettle();
      expect(find.text('Heute: 1 Glas · 250 ml'), findsOneWidget);
    });

    pageTest('Ergaenzung mit einem Tipp, Wasser steht nicht doppelt da', (tester) async {
      final s = await repo.save(name: 'Vitamin D3', servingLabel: 'Kapsel', micros: const {'vit_d_ug': 25.0});
      await repo.takeWater(at: _now);
      await open(tester);
      expect(find.text('Wasser'), findsOneWidget);
      expect(find.byKey(const Key('quick-add-supplement')), findsNothing);
      expect(find.text('Heute noch nicht genommen'), findsOneWidget);
      await tester.tap(find.byKey(Key('quick-take-${s.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Heute: 1 × Kapsel'), findsOneWidget);
    });

    pageTest('Ohne Ergaenzung gibt es den Weg zum Anlegen', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('quick-add-supplement')), findsOneWidget);
    });
  });

  group('Schnellaktion von aussen', () {
    QuickActionHandler handler(_FakeSource source, {required bool Function() signedIn, required List<String> log, bool fail = false}) => QuickActionHandler(
          source: source,
          isSignedIn: signedIn,
          takeWater: () async {
            log.add('water');
            if (fail) throw StateError('kein Haushalt');
          },
          open: () => log.add('open'),
        );

    test('Start mit "water": eintragen, dann die Seite', () async {
      final log = <String>[];
      final h = handler(_FakeSource('water'), signedIn: () => true, log: log);
      await h.start();
      expect(log, ['water', 'open']);
      h.dispose();
    });

    test('"open" oeffnet nur die Seite, auch bei laufender App', () async {
      final log = <String>[];
      final source = _FakeSource();
      final h = handler(source, signedIn: () => true, log: log);
      await h.start();
      source.controller.add('open');
      await Future<void>.delayed(Duration.zero);
      expect(log, ['open']);
      h.dispose();
    });

    test('Ohne Anmeldung wartet die Aktion bis nach dem Login und zaehlt nur einmal', () async {
      final log = <String>[];
      var signedIn = false;
      final h = handler(_FakeSource('water'), signedIn: () => signedIn, log: log);
      await h.start();
      expect(log, isEmpty);
      signedIn = true;
      await h.onSignedIn();
      await h.onSignedIn();
      expect(log, ['water', 'open']);
      h.dispose();
    });

    test('Scheitert das Eintragen, oeffnet die Seite trotzdem', () async {
      final log = <String>[];
      final h = handler(_FakeSource('water'), signedIn: () => true, log: log, fail: true);
      await h.start();
      expect(log, ['water', 'open']);
      h.dispose();
    });
  });
}
