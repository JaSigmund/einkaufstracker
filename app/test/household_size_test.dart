import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/household/household_invites.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Haushaltsgroesse fuer den Sync-Takt (ADR-018): zu mehreren wird oefter synchronisiert.
void main() {
  late AppDatabase db;
  late FakeHouseholdInviteRepository repo;

  setUp(() {
    db = memoryDb();
    repo = FakeHouseholdInviteRepository();
  });
  tearDown(() => db.close());

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      householdInviteRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('Startwert ist 1 (allein), bis der Server geantwortet hat', () {
    expect(container().read(householdSizeProvider), 1);
  });

  test('refreshIfStale holt die Mitgliederzahl und merkt sie sich lokal', () async {
    repo.members = 3;
    final c = container();
    await c.read(householdSizeProvider.notifier).refreshIfStale();
    expect(c.read(householdSizeProvider), 3);
    expect(await db.getKv('household_member_count'), '3');
  });

  test('innerhalb von 10 Minuten wird der Server nicht erneut gefragt', () async {
    repo.members = 2;
    final c = container();
    final n = c.read(householdSizeProvider.notifier);
    await n.refreshIfStale();
    repo.members = 5;
    await n.refreshIfStale();
    expect(c.read(householdSizeProvider), 2, reason: 'Wert gilt noch');
    expect(repo.memberCountCalls, 1);
  });

  test('offline bleibt der bisherige Wert stehen, ohne Fehler', () async {
    repo.members = 4;
    final c = container();
    final n = c.read(householdSizeProvider.notifier);
    await n.refreshIfStale();
    expect(c.read(householdSizeProvider), 4);

    final offline = FakeHouseholdInviteRepository()..failWith = const InviteFailure('Kein Netz');
    final c2 = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      householdInviteRepositoryProvider.overrideWithValue(offline),
    ]);
    addTearDown(c2.dispose);
    c2.read(householdSizeProvider); // laedt den zuletzt gemerkten Wert (4) aus dem lokalen Speicher
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await c2.read(householdSizeProvider.notifier).refreshIfStale();
    expect(c2.read(householdSizeProvider), 4, reason: 'letzter bekannter Wert, nicht 1');
  });

  test('der zuletzt bekannte Wert wird beim Start aus dem lokalen Speicher geladen', () async {
    await db.setKv('household_member_count', '3');
    final c = container();
    c.read(householdSizeProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.read(householdSizeProvider), 3);
  });

  test('ein unsinniger gemerkter Wert (0, Text) wird ignoriert', () async {
    for (final bad in ['0', 'viele', '']) {
      await db.setKv('household_member_count', bad);
      final c = container();
      c.read(householdSizeProvider);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(c.read(householdSizeProvider), 1, reason: 'Wert "$bad"');
    }
  });

  test('eine Zahl unter 1 vom Server zaehlt als 1', () async {
    repo.members = 0;
    final c = container();
    await c.read(householdSizeProvider.notifier).refreshIfStale();
    expect(c.read(householdSizeProvider), 1);
  });
}
