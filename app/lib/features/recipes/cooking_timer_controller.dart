import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/clock.dart';
import '../../data/local/database.dart';
import '../../domain/recipes/cooking_timer.dart';

/// Koch-Timer der ganzen App (ADR-046): lebt ausserhalb der Seiten, damit er weiterlaeuft, wenn man das Rezept verlaesst. Der Stand liegt im lokalen
/// Schluessel-Wert-Speicher und uebersteht so einen Neustart; den Alarm im Hintergrund plant das Betriebssystem.
class CookingTimerController extends Notifier<CookingTimerState> {
  static const _kvKey = 'cooking_timers';

  late Future<void> _ready;

  @override
  CookingTimerState build() {
    _ready = _load();
    return const CookingTimerState();
  }

  Future<void> _load() async {
    try {
      final loaded = CookingTimerState.decode(await ref.read(databaseProvider).getKv(_kvKey));
      if (!ref.mounted) return;
      state = loaded;
      // Ein Geraete-Neustart loescht geplante Alarme (ADR-007): beim Start nachholen, was noch aussteht
      final now = _now;
      for (final t in loaded.timers) {
        if (!t.isDone(now)) await _schedule(t);
      }
    } catch (e) {
      debugPrint('[cooking-timer] Stand nicht lesbar: $e');
    }
  }

  DateTime get _now => appClock.now().toUtc();

  Future<void> _commit(CookingTimerState next) async {
    state = next;
    await ref.read(databaseProvider).setKv(_kvKey, next.encode());
  }

  /// Ein Fehler beim Planen (z.B. verweigerte Berechtigung) darf den Timer nicht aufhalten: Die Zeit laeuft in der App trotzdem.
  Future<void> _schedule(KitchenTimer t) async {
    try {
      await ref.read(notificationSchedulerProvider).scheduleKitchenTimer(slot: t.slot, label: t.label, at: t.endsAt);
    } catch (e) {
      debugPrint('[cooking-timer] Alarm nicht geplant: $e');
    }
  }

  Future<void> _unschedule(int slot) async {
    try {
      await ref.read(notificationSchedulerProvider).cancelKitchenTimer(slot);
    } catch (e) {
      debugPrint('[cooking-timer] Alarm nicht storniert: $e');
    }
  }

  /// Startet die Kochzeit, ausser es laeuft schon eine: die muss erst abgeschlossen werden, damit keine still verloren geht.
  Future<void> startRun(String recipeTitle) async {
    await _ready;
    if (state.run != null) return;
    final now = _now;
    await _commit(CookingTimerState(run: CookingRun(recipeTitle: recipeTitle.trim(), startedAt: now, runningSince: now), timers: state.timers));
  }

  Future<void> pauseRun() async {
    await _ready;
    final run = state.run;
    if (run == null || !run.isRunning) return;
    await _commit(CookingTimerState(run: run.pausedAt(_now), timers: state.timers));
  }

  Future<void> resumeRun() async {
    await _ready;
    final run = state.run;
    if (run == null || run.isRunning) return;
    await _commit(CookingTimerState(run: run.resumedAt(_now), timers: state.timers));
  }

  /// Schliesst die Kochzeit ab und speichert sie; `null`, wenn sie unter [cookingSessionMinSeconds] blieb.
  Future<CookingSession?> finishRun() async {
    await _ready;
    final run = state.run;
    if (run == null) return null;
    final now = _now;
    final seconds = run.elapsedSeconds(now);
    // Erst speichern, dann beenden: Scheitert das Speichern, ist die gemessene Zeit nicht verloren
    final saved = seconds < cookingSessionMinSeconds
        ? null
        : await ref.read(cookingSessionRepositoryProvider).add(recipeTitle: run.recipeTitle, startedAt: run.startedAt, endedAt: now, activeSeconds: seconds);
    await _commit(CookingTimerState(timers: state.timers));
    return saved;
  }

  Future<void> discardRun() async {
    await _ready;
    await _commit(CookingTimerState(timers: state.timers));
  }

  /// Startet einen Kurzzeitmesser; `false`, wenn schon alle belegt sind.
  Future<bool> addTimer(String label, Duration duration) async {
    await _ready;
    final slot = state.freeSlot;
    if (slot == null) return false;
    final timer = KitchenTimer(slot: slot, label: label.trim().isEmpty ? 'Timer' : label.trim(), endsAt: _now.add(duration));
    await _commit(CookingTimerState(run: state.run, timers: [...state.timers, timer]));
    await _schedule(timer);
    return true;
  }

  /// Verlaengert um [by]; ein schon abgelaufener Timer laeuft von jetzt an weiter.
  Future<void> extendTimer(int slot, Duration by) async {
    await _ready;
    final now = _now;
    final timers = [
      for (final t in state.timers)
        if (t.slot == slot) KitchenTimer(slot: slot, label: t.label, endsAt: (t.isDone(now) ? now : t.endsAt).add(by)) else t,
    ];
    await _commit(CookingTimerState(run: state.run, timers: timers));
    await _schedule(timers.firstWhere((t) => t.slot == slot));
  }

  /// Plant alle ausstehenden Alarme neu, etwa nachdem genaue Alarme erlaubt wurden: Die schon geplanten bleiben sonst ungenau.
  Future<void> rescheduleTimers() async {
    await _ready;
    final now = _now;
    for (final t in state.timers) {
      if (!t.isDone(now)) await _schedule(t);
    }
  }

  Future<void> removeTimer(int slot) async {
    await _ready;
    await _commit(CookingTimerState(run: state.run, timers: [for (final t in state.timers) if (t.slot != slot) t]));
    await _unschedule(slot);
  }
}

final cookingTimerProvider = NotifierProvider<CookingTimerController, CookingTimerState>(CookingTimerController.new);
