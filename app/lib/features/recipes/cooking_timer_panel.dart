import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/clock.dart';
import '../../data/local/database.dart';
import '../../domain/recipes/cooking_timer.dart';
import 'cooking_timer_controller.dart';

/// Oeffnet den Koch-Timer wie den Koch-Chat von unten. Mit [recipeTitle] laesst sich die Kochzeit dieses Gerichts messen, ohne ihn gibt es nur die Kurzzeitmesser.
Future<void> showCookingTimerPanel(BuildContext context, {String? recipeTitle}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CookingTimerPanel(recipeTitle: recipeTitle),
    );

/// Laesst die Anzeige jede Sekunde neu zeichnen, aber nur solange etwas laeuft.
mixin _Ticking<T extends StatefulWidget> on State<T> {
  Timer? _tick;

  void keepTicking(bool active) {
    if (!active) {
      _tick?.cancel();
      _tick = null;
    } else {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }
}

class CookingTimerPanel extends ConsumerStatefulWidget {
  const CookingTimerPanel({super.key, this.recipeTitle});

  final String? recipeTitle;

  @override
  ConsumerState<CookingTimerPanel> createState() => _CookingTimerPanelState();
}

class _CookingTimerPanelState extends ConsumerState<CookingTimerPanel> with _Ticking {
  static const _presets = [3, 5, 10, 15, 20, 30, 45, 60];

  final _label = TextEditingController();

  /// Die gerade abgeschlossene Kochzeit, damit man sie zuruecknehmen kann. Eine SnackBar laege hinter dem Panel.
  CookingSession? _saved;
  String? _note;

  /// `null` solange unbekannt. Ohne Erlaubnis kann sich der Alarm im Hintergrund verspaeten.
  bool? _exactAllowed;

  @override
  void initState() {
    super.initState();
    _checkExactAlarms();
    // Der Timer laeuft weiter, auch wenn das Panel nie Zustandsaenderungen sieht
    keepTicking(true);
  }

  Future<void> _checkExactAlarms() async {
    try {
      final allowed = await ref.read(notificationSchedulerProvider).canScheduleExactAlarms();
      if (mounted) setState(() => _exactAllowed = allowed);
    } catch (_) {
      // ohne Antwort bleibt der Hinweis weg
    }
  }

  Future<void> _allowExactAlarms() async {
    await ref.read(notificationSchedulerProvider).requestExactAlarms();
    await _checkExactAlarms();
    if (_exactAllowed == true) await _controller.rescheduleTimers();
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  CookingTimerController get _controller => ref.read(cookingTimerProvider.notifier);

  Future<void> _finish() async {
    final session = await _controller.finishRun();
    if (!mounted) return;
    setState(() {
      _saved = session;
      _note = session == null ? 'Unter einer Minute: nicht gespeichert.' : 'Gespeichert: ${formatCookingMinutes(session.activeSeconds)}';
    });
  }

  Future<void> _undoSaved() async {
    final saved = _saved;
    if (saved == null) return;
    await ref.read(cookingSessionRepositoryProvider).delete(saved.id);
    if (!mounted) return;
    setState(() {
      _saved = null;
      _note = 'Nicht gespeichert.';
    });
  }

  Future<void> _addTimer(Duration duration) async {
    final added = await _controller.addTimer(_label.text, duration);
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() {
      if (added) _label.clear();
      _note = added ? null : 'Es laufen schon $kitchenTimerSlots Timer.';
    });
  }

  Future<void> _customTimer() async {
    final minutes = await showDialog<int>(context: context, builder: (_) => const _MinutesDialog());
    if (minutes != null) await _addTimer(Duration(minutes: minutes));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final state = ref.watch(cookingTimerProvider);
    final now = appClock.now().toUtc();
    final title = state.run?.recipeTitle ?? widget.recipeTitle;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (title != null) ...[
              Text('Kochzeit: $title', key: const Key('timer-run-title'), style: t.textTheme.titleMedium),
              _runSection(t, state.run, title, now),
              const Divider(height: 24),
            ],
            if (title == null && _note != null) Text(_note!, key: const Key('timer-note')),
            Text('Timer', style: t.textTheme.titleMedium),
            for (final timer in state.bySoonest) _timerTile(t, timer, now),
            const SizedBox(height: 8),
            TextField(
              key: const Key('timer-label'),
              controller: _label,
              maxLength: 40,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Wofür? (optional)', hintText: 'zum Beispiel Ofen', counterText: ''),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final m in _presets)
                ActionChip(key: Key('timer-preset-$m'), label: Text('$m min'), onPressed: () => _addTimer(Duration(minutes: m))),
              ActionChip(key: const Key('timer-custom'), avatar: const Icon(Icons.edit_outlined, size: 18), label: const Text('Andere Zeit'), onPressed: _customTimer),
            ]),
            if (kIsWeb)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('Im Browser gibt es keinen Alarm: Das Ende siehst du nur hier in der App.', style: t.textTheme.bodySmall),
              )
            else if (_exactAllowed == false && state.timers.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Android kann den Alarm verspäten, solange genaue Alarme nicht erlaubt sind.', key: const Key('timer-exact-hint'), style: t.textTheme.bodySmall),
                  TextButton(key: const Key('timer-exact-allow'), onPressed: _allowExactAlarms, child: const Text('Genaue Alarme erlauben')),
                ]),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _runSection(ThemeData t, CookingRun? run, String title, DateTime now) {
    final sessions = ref.watch(cookingSessionsStreamProvider).value ?? const <CookingSession>[];
    final stats = cookingStatsFor(title, [for (final s in sessions) (title: s.recipeTitle, seconds: s.activeSeconds)]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (stats != null) Text(stats.label, key: const Key('timer-run-stats'), style: t.textTheme.bodySmall),
      if (run != null) ...[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(formatTimerClock(run.elapsedSeconds(now)), key: const Key('timer-run-clock'), textAlign: TextAlign.center, style: t.textTheme.displaySmall),
        ),
        Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
          if (run.isRunning)
            OutlinedButton.icon(key: const Key('timer-run-pause'), onPressed: _controller.pauseRun, icon: const Icon(Icons.pause), label: const Text('Pause'))
          else
            OutlinedButton.icon(key: const Key('timer-run-resume'), onPressed: _controller.resumeRun, icon: const Icon(Icons.play_arrow), label: const Text('Weiter')),
          FilledButton.icon(key: const Key('timer-run-finish'), onPressed: _finish, icon: const Icon(Icons.check), label: const Text('Fertig')),
          TextButton(key: const Key('timer-run-discard'), onPressed: _controller.discardRun, child: const Text('Verwerfen')),
        ]),
      ] else
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: FilledButton.icon(
            key: const Key('timer-run-start'),
            onPressed: () {
              setState(() {
                _saved = null;
                _note = null;
              });
              _controller.startRun(title);
            },
            icon: const Icon(Icons.play_arrow),
            label: const Text('Kochzeit starten'),
          ),
        ),
      if (_note != null)
        Row(children: [
          Expanded(child: Text(_note!, key: const Key('timer-note'))),
          if (_saved != null) TextButton(key: const Key('timer-run-undo'), onPressed: _undoSaved, child: const Text('Rückgängig')),
        ]),
    ]);
  }

  Widget _timerTile(ThemeData t, KitchenTimer timer, DateTime now) {
    final done = timer.isDone(now);
    return ListTile(
      key: Key('kitchen-timer-${timer.slot}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(done ? Icons.notifications_active : Icons.timer_outlined, color: done ? t.colorScheme.error : null),
      title: Text(timer.label),
      subtitle: Text(
        done ? 'Fertig' : formatTimerClock(timer.remainingSeconds(now)),
        key: Key('kitchen-timer-clock-${timer.slot}'),
        style: done ? TextStyle(color: t.colorScheme.error) : t.textTheme.titleMedium,
      ),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        TextButton(key: Key('kitchen-timer-plus-${timer.slot}'), onPressed: () => _controller.extendTimer(timer.slot, const Duration(minutes: 1)), child: const Text('+1 min')),
        IconButton(key: Key('kitchen-timer-remove-${timer.slot}'), tooltip: done ? 'Schließen' : 'Abbrechen', icon: const Icon(Icons.close), onPressed: () => _controller.removeTimer(timer.slot)),
      ]),
    );
  }
}

class _MinutesDialog extends StatefulWidget {
  const _MinutesDialog();

  @override
  State<_MinutesDialog> createState() => _MinutesDialogState();
}

class _MinutesDialogState extends State<_MinutesDialog> {
  final _controller = TextEditingController();

  int? get _minutes {
    final v = int.tryParse(_controller.text.trim());
    return v == null || v <= 0 || v > 24 * 60 ? null : v;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Wie lange?'),
        content: TextField(
          key: const Key('timer-custom-minutes'),
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Minuten', suffixText: 'min'),
          onChanged: (_) => setState(() {}),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
          FilledButton(key: const Key('timer-custom-ok'), onPressed: _minutes == null ? null : () => Navigator.pop(context, _minutes), child: const Text('Starten')),
        ],
      );
}

/// Was gerade laeuft, in einer Zeile: "Ofen 04:12 · Kürbissuppe 23:10". Leer, wenn nichts laeuft.
String cookingTimerSummary(CookingTimerState state, DateTime now) => [
      for (final t in state.bySoonest) t.isDone(now) ? '${t.label}: fertig' : '${t.label} ${formatTimerClock(t.remainingSeconds(now))}',
      if (state.run case final run?) '${run.recipeTitle} ${formatTimerClock(run.elapsedSeconds(now))}${run.isRunning ? '' : ' (Pause)'}',
    ].join(' · ');

/// Der schwebende Knopf ueber der Kochanleitung (neben dem Koch-Chat). Zeigt die naechste Zeit, solange etwas laeuft.
class CookingTimerFab extends ConsumerStatefulWidget {
  const CookingTimerFab({super.key, required this.recipeTitle});

  final String recipeTitle;

  @override
  ConsumerState<CookingTimerFab> createState() => _CookingTimerFabState();
}

class _CookingTimerFabState extends ConsumerState<CookingTimerFab> with _Ticking {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cookingTimerProvider);
    keepTicking(!state.isEmpty);
    final now = appClock.now().toUtc();
    final next = state.bySoonest.firstOrNull;
    final done = next != null && next.isDone(now);
    final t = Theme.of(context);
    return FloatingActionButton.extended(
      key: const Key('recipe-timer-button'),
      heroTag: 'recipe-timer-fab',
      backgroundColor: done ? t.colorScheme.errorContainer : null,
      icon: Icon(done ? Icons.notifications_active : Icons.timer_outlined),
      label: Text(next != null
          ? (done ? 'Fertig' : formatTimerClock(next.remainingSeconds(now)))
          : state.run != null
              ? formatTimerClock(state.run!.elapsedSeconds(now))
              : 'Timer'),
      onPressed: () => showCookingTimerPanel(context, recipeTitle: widget.recipeTitle),
    );
  }
}

/// Schmale Leiste ueber den Tabs, solange etwas laeuft: Wer das Rezept verlassen hat, sieht den Timer weiter und kommt mit einem Tipp zurueck.
class CookingTimerBanner extends ConsumerStatefulWidget {
  const CookingTimerBanner({super.key});

  @override
  ConsumerState<CookingTimerBanner> createState() => _CookingTimerBannerState();
}

class _CookingTimerBannerState extends ConsumerState<CookingTimerBanner> with _Ticking {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cookingTimerProvider);
    keepTicking(!state.isEmpty);
    if (state.isEmpty) return const SizedBox.shrink();
    final t = Theme.of(context);
    final now = appClock.now().toUtc();
    final done = state.timers.any((x) => x.isDone(now));
    return Material(
      color: done ? t.colorScheme.errorContainer : t.colorScheme.secondaryContainer,
      child: InkWell(
        key: const Key('timer-banner'),
        onTap: () => showCookingTimerPanel(context, recipeTitle: state.run?.recipeTitle),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Icon(done ? Icons.notifications_active : Icons.timer_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(cookingTimerSummary(state, now), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        ),
      ),
    );
  }
}
