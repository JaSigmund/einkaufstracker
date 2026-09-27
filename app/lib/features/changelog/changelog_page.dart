import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';

/// Aenderungsprotokoll der App (Doku-Wunsch "Changelog der Versionen"), neueste zuerst.
class ChangelogPage extends ConsumerWidget {
  const ChangelogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(changelogProvider);
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Änderungsprotokoll')),
      body: entries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Nicht geladen (Netz nötig): $e', key: const Key('changelog-error'), textAlign: TextAlign.center),
          ),
        ),
        data: (list) => list.isEmpty
            ? const Center(child: Text('Noch keine Einträge', key: Key('changelog-empty')))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final e in list)
                    Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: t.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(6)),
                              child: Text(e.version, style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.onPrimaryContainer)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(e.title, style: t.textTheme.titleMedium)),
                          ]),
                          const SizedBox(height: 4),
                          Text(formatViennaDateTime(e.releasedAt).split(',').first, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
                          const SizedBox(height: 8),
                          for (final h in e.highlights)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const Text('•  '),
                                Expanded(child: Text(h)),
                              ]),
                            ),
                        ]),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
