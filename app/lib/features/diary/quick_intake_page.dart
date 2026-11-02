import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/clock.dart';
import '../../core/format.dart';
import '../../core/vienna_time.dart';
import '../../data/local/database.dart';
import '../../domain/nutrition/micros.dart';
import '../../domain/nutrition/supplements.dart';
import '../recipes/cooking_timer_panel.dart';
import 'drinks_section.dart';

/// Schnell eintragen (ADR-041): ein Glas Wasser und jede Nahrungsergaenzung mit einem Tipp, erreichbar aus jedem Tab, vom Widget auf dem
/// Startbildschirm und ueber langes Druecken auf das App-Symbol.
class QuickIntakePage extends ConsumerWidget {
  const QuickIntakePage({super.key, this.now});

  /// Aktueller Zeitpunkt (UTC), austauschbar fuer Tests.
  final DateTime? now;

  List<SupplementIntake> _today(List<SupplementIntake> intakes) {
    final l = utcToViennaLocal(now ?? appClock.now().toUtc());
    return [
      for (final i in intakes)
        if (utcToViennaLocal(i.takenAt) case final t when t.year == l.year && t.month == l.month && t.day == l.day) i,
    ];
  }

  void _confirm(BuildContext context, WidgetRef ref, ScaffoldMessengerState messenger, String text, SupplementIntake intake) {
    final repo = ref.read(supplementRepositoryProvider);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        // mit Aktion bliebe die SnackBar sonst stehen, bis man sie wegwischt
        persist: false,
        action: SnackBarAction(label: 'Rückgängig', onPressed: () => repo.deleteIntake(intake.id)),
      ));
  }

  Future<void> _takeWater(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final intake = await ref.read(supplementRepositoryProvider).takeWater(at: now);
      if (context.mounted) _confirm(context, ref, messenger, 'Ein Glas Wasser eingetragen', intake);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Eintragen nicht möglich.')));
    }
  }

  Future<void> _take(BuildContext context, WidgetRef ref, Supplement s) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final intake = await ref.read(supplementRepositoryProvider).take(s, at: now);
      if (context.mounted) _confirm(context, ref, messenger, '${s.name}: ${formatServings(1, s.servingLabel)} eingetragen', intake);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Eintragen nicht möglich.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final repo = ref.watch(supplementRepositoryProvider);
    final supplements = ref.watch(supplementsStreamProvider).value ?? const <Supplement>[];
    final today = _today(ref.watch(supplementIntakesStreamProvider).value ?? const <SupplementIntake>[]);

    final waterIds = {for (final s in supplements) if (repo.isWater(s)) s.id};
    final glasses = today.where((i) => waterIds.contains(i.supplementId));
    final glassCount = glasses.fold<double>(0, (sum, i) => sum + i.servings);
    final waterMl = glasses.fold<double>(0, (sum, i) => sum + (parseMicros(i.micros)?['water_g'] ?? 0));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Schnell eintragen'),
        actions: [
          IconButton(
            key: const Key('quick-manage'),
            tooltip: 'Nahrungsergänzung verwalten',
            icon: const Icon(Icons.tune),
            onPressed: () => context.push('/supplements'),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.water_drop_outlined),
            title: const Text('Wasser'),
            subtitle: Text(
              glassCount == 0 ? 'Heute noch kein Glas' : 'Heute: ${formatQuantity(glassCount)} ${glassCount == 1 ? 'Glas' : 'Gläser'} · ${formatQuantity(waterMl)} ml',
              key: const Key('quick-water-today'),
            ),
            trailing: FilledButton(key: const Key('quick-water'), onPressed: () => _takeWater(context, ref), child: const Text('+ 1 Glas')),
          ),
        ),
        for (final s in supplements)
          if (!repo.isWater(s))
            Card(
              key: Key('quick-supplement-${s.id}'),
              child: ListTile(
                leading: const Icon(Icons.medication_outlined),
                title: Text(s.name),
                subtitle: Text(_todayLabel(today, s)),
                trailing: FilledButton.tonal(key: Key('quick-take-${s.id}'), onPressed: () => _take(context, ref, s), child: const Text('Genommen')),
              ),
            ),
        if (supplements.every(repo.isWater))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: TextButton.icon(
              key: const Key('quick-add-supplement'),
              onPressed: () => context.push('/supplement-form'),
              icon: const Icon(Icons.add),
              label: const Text('Nahrungsergänzung anlegen'),
            ),
          ),
        DrinksSection(now: now),
        const Padding(padding: EdgeInsets.only(top: 8), child: Divider()),
        // Von jedem Tab aus erreichbar, deshalb auch hier: der Timer fuer zwischendurch (ADR-046)
        Card(
          child: ListTile(
            key: const Key('quick-timer'),
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Timer'),
            subtitle: const Text('Für den Ofen oder die Nudeln'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showCookingTimerPanel(context),
          ),
        ),
        if (!kIsWeb)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Noch schneller: Leg das Widget „Einkaufstracker“ auf den Startbildschirm oder halte das App-Symbol gedrückt.',
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
            ),
          ),
      ]),
    );
  }

  static String _todayLabel(List<SupplementIntake> today, Supplement s) {
    final servings = today.where((i) => i.supplementId == s.id).fold<double>(0, (sum, i) => sum + i.servings);
    return servings == 0 ? 'Heute noch nicht genommen' : 'Heute: ${formatServings(servings, s.servingLabel)}';
  }
}
