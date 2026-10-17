import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../domain/nutrition/micros.dart';
import '../../domain/nutrition/supplements.dart';
import '../../domain/receipt/vienna_time.dart';

/// Nahrungsergaenzung (Phase N4, ADR-035): was der Haushalt nimmt, "Genommen" mit einem Tipp, und was heute schon eingetragen ist.
/// Die Werte erscheinen auf der Seite Naehrstoffe als eigene Quelle, getrennt von den Mahlzeiten. Die App bewertet nicht, ob eine
/// Menge passt.
class SupplementsPage extends ConsumerWidget {
  const SupplementsPage({super.key, this.now});

  /// Aktueller Zeitpunkt (UTC), austauschbar fuer Tests.
  final DateTime? now;

  DateTime _today() {
    final l = utcToViennaLocal(now ?? DateTime.now().toUtc());
    return DateTime(l.year, l.month, l.day);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final supplements = ref.watch(supplementsStreamProvider);
    final intakes = ref.watch(supplementIntakesStreamProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Nahrungsergänzung')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('supplement-add'),
        onPressed: () => context.push('/supplement-form'),
        icon: const Icon(Icons.add),
        label: const Text('Ergänzung anlegen'),
      ),
      body: (supplements.isLoading || intakes.isLoading)
          ? const Center(child: CircularProgressIndicator())
          : (supplements.hasError || intakes.hasError)
              ? Center(child: Text('Fehler: ${supplements.error ?? intakes.error}'))
              : _content(context, ref, t, supplements.value!, intakes.value!),
    );
  }

  Widget _content(BuildContext context, WidgetRef ref, ThemeData t, List<Supplement> supplements, List<SupplementIntake> intakes) {
    final today = _today();
    final todays = [
      for (final i in intakes)
        if (_sameDay(utcToViennaLocal(i.takenAt), today)) i,
    ].reversed.toList(); // frueheste zuerst
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
      Text(
        'Trag ein, was auf der Packung steht (Inhalt je Tablette, Kapsel oder Messlöffel). Ein Tipp auf „Genommen“ rechnet es für heute ein. '
        'Die Werte stehen auf der Seite Nährstoffe als eigene Quelle, getrennt von den Mahlzeiten. Die App bewertet nicht, ob die Menge passt.',
        key: const Key('supplements-hint'),
        style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 8),
      if (supplements.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Text('Noch keine Ergänzung angelegt.', key: const Key('supplements-empty'), textAlign: TextAlign.center, style: t.textTheme.bodyMedium),
        ),
      for (final s in supplements) _tile(context, ref, t, s),
      if (todays.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Heute genommen', style: t.textTheme.titleSmall),
        for (final i in todays)
          ListTile(
            key: Key('intake-${i.id}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(i.name),
            subtitle: Text('${formatViennaTime(i.takenAt)} · ${formatServings(i.servings, _unitOf(supplements, i))}'),
            trailing: IconButton(
              key: Key('intake-delete-${i.id}'),
              tooltip: 'Einnahme zurücknehmen',
              icon: const Icon(Icons.undo),
              onPressed: () => ref.read(supplementRepositoryProvider).deleteIntake(i.id),
            ),
          ),
      ],
    ]);
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// Die Einheit zur Einnahme: die der Ergaenzung, sonst neutral "Einheit" (die Ergaenzung wurde geloescht).
  static String _unitOf(List<Supplement> supplements, SupplementIntake i) =>
      supplements.where((s) => s.id == i.supplementId).map((s) => s.servingLabel).firstOrNull ?? 'Einheit';

  Widget _tile(BuildContext context, WidgetRef ref, ThemeData t, Supplement s) {
    final micros = parseMicros(s.micros) ?? const <String, double>{};
    return Card(
      key: Key('supplement-${s.id}'),
      child: ListTile(
        title: Text(s.name),
        subtitle: Text('Je ${s.servingLabel}: ${summarizeMicros(micros)}', key: Key('supplement-summary-${s.id}')),
        onTap: () => context.push('/supplement-form', extra: s),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          FilledButton.tonal(key: Key('supplement-take-${s.id}'), onPressed: () => _take(context, ref, s, 1), child: const Text('Genommen')),
          PopupMenuButton<String>(
            key: Key('supplement-menu-${s.id}'),
            onSelected: (v) async {
              switch (v) {
                case 'several':
                  final n = await _askServings(context, s);
                  if (n != null && context.mounted) await _take(context, ref, s, n);
                case 'edit':
                  context.push('/supplement-form', extra: s);
                case 'delete':
                  await _confirmDelete(context, ref, s);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(key: Key('supplement-several-${s.id}'), value: 'several', child: const Text('Mehrere Einheiten eintragen …')),
              PopupMenuItem(key: Key('supplement-edit-${s.id}'), value: 'edit', child: const Text('Bearbeiten')),
              PopupMenuItem(key: Key('supplement-delete-${s.id}'), value: 'delete', child: const Text('Löschen')),
            ],
          ),
        ]),
      ),
    );
  }

  Future<void> _take(BuildContext context, WidgetRef ref, Supplement s, double servings) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final intake = await ref.read(supplementRepositoryProvider).take(s, at: now, servings: servings);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text('${s.name}: ${formatServings(servings, s.servingLabel)} eingetragen'),
        action: SnackBarAction(label: 'Rückgängig', onPressed: () => ref.read(supplementRepositoryProvider).deleteIntake(intake.id)),
      ));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Eintragen nicht möglich.')));
    }
  }

  Future<double?> _askServings(BuildContext context, Supplement s) {
    final controller = TextEditingController(text: '2');
    return showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Wie viele ${s.servingLabel}?'),
        content: TextField(
          key: const Key('supplement-servings-field'),
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Anzahl', suffixText: s.servingLabel, helperText: 'Auch halbe sind möglich, zum Beispiel 0,5'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(
            key: const Key('supplement-servings-ok'),
            onPressed: () {
              final v = parseAmount(controller.text);
              if (isValidServings(v)) Navigator.pop(ctx, v);
            },
            child: const Text('Eintragen'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Supplement s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${s.name} löschen?'),
        content: const Text('Bisherige Einnahmen bleiben erhalten und zählen weiter.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(key: const Key('supplement-delete-ok'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok == true) await ref.read(supplementRepositoryProvider).delete(s.id);
  }
}
