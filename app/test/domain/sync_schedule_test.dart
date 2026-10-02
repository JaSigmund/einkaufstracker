import 'package:einkaufstracker/domain/sync/sync_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

/// Takt der automatischen Synchronisierung (ADR-018): allein 2 Minuten, zu mehreren 30 Sekunden.
void main() {
  group('syncIntervalFor', () {
    test('allein im Haushalt: 2 Minuten', () => expect(syncIntervalFor(1), const Duration(minutes: 2)));
    test('zwei Personen: 30 Sekunden', () => expect(syncIntervalFor(2), const Duration(seconds: 30)));
    test('viele Personen: ebenfalls 30 Sekunden, nicht schneller', () => expect(syncIntervalFor(8), const Duration(seconds: 30)));
    test('0 oder negativ (unbekannt) zaehlt wie allein', () {
      expect(syncIntervalFor(0), soloSyncInterval);
      expect(syncIntervalFor(-3), soloSyncInterval);
    });
  });

  group('isSyncDue', () {
    test('noch nie synchronisiert: sofort faellig', () {
      expect(isSyncDue(members: 1, sinceLastSync: null), isTrue);
      expect(isSyncDue(members: 3, sinceLastSync: null), isTrue);
    });

    test('allein: nach 30 und 90 Sekunden noch nicht, nach 2 Minuten ja', () {
      expect(isSyncDue(members: 1, sinceLastSync: const Duration(seconds: 30)), isFalse);
      expect(isSyncDue(members: 1, sinceLastSync: const Duration(seconds: 90)), isFalse);
      expect(isSyncDue(members: 1, sinceLastSync: const Duration(minutes: 2)), isTrue);
    });

    test('zu mehreren: schon nach 30 Sekunden faellig', () {
      expect(isSyncDue(members: 2, sinceLastSync: const Duration(seconds: 10)), isFalse);
      expect(isSyncDue(members: 2, sinceLastSync: const Duration(seconds: 30)), isTrue);
    });

    test('Toleranz von einer Sekunde: ein Tick knapp vor dem Abstand zaehlt schon', () {
      expect(isSyncDue(members: 2, sinceLastSync: const Duration(seconds: 29)), isTrue);
      expect(isSyncDue(members: 2, sinceLastSync: const Duration(seconds: 28)), isFalse);
      expect(isSyncDue(members: 1, sinceLastSync: const Duration(minutes: 1, seconds: 59)), isTrue);
    });

    test('der Grundtakt ist nicht groesser als der kuerzeste Abstand (kein verpasster Takt)', () {
      expect(syncTickPeriod <= sharedSyncInterval, isTrue);
      expect(soloSyncInterval.inSeconds % syncTickPeriod.inSeconds, 0, reason: 'der lange Abstand ist ein Vielfaches des Takts');
    });
  });

  group('isHouseholdSizeStale', () {
    final now = DateTime.utc(2026, 10, 2, 12);
    test('noch nie geholt: veraltet', () => expect(isHouseholdSizeStale(fetchedAt: null, now: now), isTrue));
    test('vor 5 Minuten geholt: aktuell', () => expect(isHouseholdSizeStale(fetchedAt: now.subtract(const Duration(minutes: 5)), now: now), isFalse));
    test('vor genau 10 Minuten: veraltet', () => expect(isHouseholdSizeStale(fetchedAt: now.subtract(householdSizeMaxAge), now: now), isTrue));
  });
}
