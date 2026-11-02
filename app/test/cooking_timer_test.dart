import 'package:clock/clock.dart';
import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/cooking_session_repository.dart';
import 'package:einkaufstracker/domain/recipes/cooking_timer.dart';
import 'package:einkaufstracker/features/recipes/cooking_timer_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

final _t0 = DateTime.utc(2026, 11, 2, 17);

void main() {
  group('Fachlogik', () {
    test('Kochzeit zaehlt ohne Pausen, eine zurueckgestellte Uhr ergibt nichts Negatives', () {
      final run = CookingRun(recipeTitle: 'Curry', startedAt: _t0, runningSince: _t0);
      expect(run.elapsedSeconds(_t0.add(const Duration(minutes: 10))), 600);
      expect(run.elapsedSeconds(_t0.subtract(const Duration(minutes: 1))), 0);

      final paused = run.pausedAt(_t0.add(const Duration(minutes: 10)));
      expect(paused.isRunning, isFalse);
      expect(paused.elapsedSeconds(_t0.add(const Duration(hours: 5))), 600);

      final resumed = paused.resumedAt(_t0.add(const Duration(hours: 5)));
      expect(resumed.elapsedSeconds(_t0.add(const Duration(hours: 5, minutes: 2))), 720);
    });

    test('Timer rundet auf, 00:00 erst wenn die Zeit um ist', () {
      final timer = KitchenTimer(slot: 0, label: 'Ofen', endsAt: _t0.add(const Duration(seconds: 90)));
      expect(timer.remainingSeconds(_t0.add(const Duration(milliseconds: 89500))), 1);
      expect(timer.isDone(_t0.add(const Duration(seconds: 89))), isFalse);
      expect(timer.isDone(_t0.add(const Duration(seconds: 90))), isTrue);
      expect(timer.remainingSeconds(_t0.add(const Duration(hours: 1))), 0);
    });

    test('Stand ueberlebt Speichern und Laden, Beschaedigtes faellt einzeln weg', () {
      final state = CookingTimerState(
        run: CookingRun(recipeTitle: 'Curry', startedAt: _t0, accumulatedSeconds: 30, runningSince: _t0),
        timers: [KitchenTimer(slot: 2, label: 'Ofen', endsAt: _t0)],
      );
      final back = CookingTimerState.decode(state.encode());
      expect(back.run!.recipeTitle, 'Curry');
      expect(back.run!.accumulatedSeconds, 30);
      expect(back.run!.isRunning, isTrue);
      expect(back.timers.single.slot, 2);

      expect(CookingTimerState.decode('kein json').isEmpty, isTrue);
      expect(CookingTimerState.decode(null).isEmpty, isTrue);
      final partly = CookingTimerState.decode('{"run":{"recipeTitle":1},"timers":[{"slot":"x"},{"slot":1,"label":"Tee","endsAt":"2026-11-02T17:00:00Z"}]}');
      expect(partly.run, isNull);
      expect(partly.timers.single.label, 'Tee');
    });

    test('freier Slot nimmt die kleinste Luecke, voll ergibt null', () {
      KitchenTimer at(int slot) => KitchenTimer(slot: slot, label: 'x', endsAt: _t0);
      expect(CookingTimerState(timers: [at(0), at(2)]).freeSlot, 1);
      expect(CookingTimerState(timers: [for (var i = 0; i < kitchenTimerSlots; i++) at(i)]).freeSlot, isNull);
    });

    test('Anzeigeformate', () {
      expect(formatTimerClock(252), '04:12');
      expect(formatTimerClock(3723), '1:02:03');
      expect(formatCookingMinutes(2520), '42 min');
      expect(formatCookingMinutes(3900), '1 h 5 min');
      expect(formatCookingMinutes(3600), '1 h');
    });

    test('Statistik: Schreibweise des Namens macht kein anderes Gericht', () {
      final sessions = [(title: 'Linsencurry', seconds: 2400), (title: ' linsencurry ', seconds: 3000), (title: 'Pizza', seconds: 900)];
      final stats = cookingStatsFor('LINSENCURRY', sessions)!;
      expect(stats.count, 2);
      expect(stats.averageSeconds, 2700);
      expect(stats.label, '2× gekocht, im Schnitt 45 min');
      expect(cookingStatsFor('Suppe', sessions), isNull);
    });
  });

  group('Controller', () {
    late AppDatabase db;
    late FakeNotificationScheduler scheduler;
    late ProviderContainer container;

    ProviderContainer newContainer() {
      final c = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        notificationSchedulerProvider.overrideWithValue(scheduler),
        cookingSessionRepositoryProvider.overrideWithValue(CookingSessionRepository(db, householdId: () async => 'h1')),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    setUp(() {
      db = memoryDb();
      scheduler = FakeNotificationScheduler();
      container = newContainer();
    });
    tearDown(() => db.close());

    CookingTimerController controller() => container.read(cookingTimerProvider.notifier);
    CookingTimerState state() => container.read(cookingTimerProvider);
    Future<T> at<T>(Duration offset, Future<T> Function() body) => withClock(Clock.fixed(_t0.add(offset)), body);

    test('Kochzeit mit Pause wird beim Abschluss gespeichert und der Lauf beendet', () async {
      await at(Duration.zero, () => controller().startRun('Curry'));
      await at(const Duration(minutes: 20), () => controller().pauseRun());
      await at(const Duration(minutes: 50), () => controller().resumeRun());
      final saved = await at(const Duration(minutes: 60), () => controller().finishRun());

      expect(saved!.activeSeconds, 30 * 60, reason: '20 + 10 Minuten, die Pause zaehlt nicht');
      expect(saved.recipeTitle, 'Curry');
      expect(saved.startedAt, _t0);
      expect(saved.endedAt, _t0.add(const Duration(minutes: 60)));
      expect(state().run, isNull);
      expect((await db.select(db.outbox).get()).single.remoteTable, 'cooking_sessions');
    });

    test('unter einer Minute wird nichts gespeichert', () async {
      await at(Duration.zero, () => controller().startRun('Curry'));
      final saved = await at(const Duration(seconds: 59), () => controller().finishRun());
      expect(saved, isNull);
      expect(state().run, isNull);
      expect(await db.select(db.cookingSessions).get(), isEmpty);
    });

    test('eine zweite Kochzeit ersetzt die laufende nicht', () async {
      await at(Duration.zero, () => controller().startRun('Curry'));
      await at(const Duration(minutes: 1), () => controller().startRun('Pizza'));
      expect(state().run!.recipeTitle, 'Curry');
      expect(state().run!.startedAt, _t0);
    });

    test('Verwerfen speichert nichts und laesst die Timer in Ruhe', () async {
      await at(Duration.zero, () => controller().startRun('Curry'));
      await at(Duration.zero, () => controller().addTimer('Ofen', const Duration(minutes: 5)));
      await at(const Duration(minutes: 30), () => controller().discardRun());
      expect(state().run, isNull);
      expect(state().timers, hasLength(1));
      expect(await db.select(db.cookingSessions).get(), isEmpty);
    });

    test('Timer plant den Alarm, Verlaengern verschiebt ihn, Entfernen storniert ihn', () async {
      expect(await at(Duration.zero, () => controller().addTimer('  Ofen ', const Duration(minutes: 5))), isTrue);
      expect(scheduler.kitchenTimers[0], (label: 'Ofen', at: _t0.add(const Duration(minutes: 5))));

      await at(const Duration(minutes: 1), () => controller().extendTimer(0, const Duration(minutes: 1)));
      expect(scheduler.kitchenTimers[0]!.at, _t0.add(const Duration(minutes: 6)));

      await at(const Duration(minutes: 10), () => controller().extendTimer(0, const Duration(minutes: 1)));
      expect(scheduler.kitchenTimers[0]!.at, _t0.add(const Duration(minutes: 11)), reason: 'abgelaufen: von jetzt an');

      await at(const Duration(minutes: 11), () => controller().removeTimer(0));
      expect(scheduler.kitchenTimers, isEmpty);
      expect(state().timers, isEmpty);
    });

    test('ohne Bezeichnung heisst er Timer, mehr als die Slots gehen nicht', () async {
      await at(Duration.zero, () => controller().addTimer(' ', const Duration(minutes: 1)));
      expect(state().timers.single.label, 'Timer');
      for (var i = 1; i < kitchenTimerSlots; i++) {
        await at(Duration.zero, () => controller().addTimer('t$i', const Duration(minutes: 1)));
      }
      expect(await at(Duration.zero, () => controller().addTimer('zu viel', const Duration(minutes: 1))), isFalse);
      expect(state().timers, hasLength(kitchenTimerSlots));
    });

    test('nach einem Neustart laeuft alles weiter und ausstehende Alarme werden neu geplant, abgelaufene nicht', () async {
      await at(Duration.zero, () => controller().startRun('Curry'));
      await at(Duration.zero, () => controller().addTimer('kurz', const Duration(minutes: 1)));
      await at(Duration.zero, () => controller().addTimer('lang', const Duration(hours: 1)));
      scheduler.kitchenTimers.clear();

      final restarted = newContainer();
      await at(const Duration(minutes: 10), () async {
        restarted.read(cookingTimerProvider);
        await pumpEventQueue();
      });
      final s = restarted.read(cookingTimerProvider);
      expect(s.run!.recipeTitle, 'Curry');
      expect(s.timers, hasLength(2));
      expect(scheduler.kitchenTimers.keys, [1]);
    });

    test('ein scheiternder Alarm haelt den Timer nicht auf', () async {
      final failing = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        notificationSchedulerProvider.overrideWithValue(_FailingScheduler()),
      ]);
      addTearDown(failing.dispose);
      expect(await failing.read(cookingTimerProvider.notifier).addTimer('Ofen', const Duration(minutes: 5)), isTrue);
      expect(failing.read(cookingTimerProvider).timers, hasLength(1));
    });
  });
}

class _FailingScheduler extends FakeNotificationScheduler {
  @override
  Future<void> scheduleKitchenTimer({required int slot, required String label, required DateTime at}) async => throw StateError('keine Berechtigung');
}
