import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

/// Zeigt, ob alles synchronisiert ist, wie viele Aenderungen noch warten und ob der letzte Sync scheiterte.
class SyncStatusBanner extends ConsumerWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncControllerProvider);
    final pending = ref.watch(pendingChangesProvider).value ?? 0;
    final t = Theme.of(context);

    final IconData icon;
    final String text;
    final Color color;
    if (status.running) {
      icon = Icons.sync;
      text = 'Synchronisiere …';
      color = t.colorScheme.primary;
    } else if (status.error != null) {
      icon = Icons.cloud_off;
      text = pending > 0 ? '${status.error} ($pending wartend)' : status.error!;
      color = t.colorScheme.error;
    } else if (pending > 0) {
      icon = Icons.cloud_upload_outlined;
      text = '$pending Änderung(en) warten auf die Übertragung';
      color = t.colorScheme.tertiary;
    } else {
      icon = Icons.cloud_done_outlined;
      final last = status.lastSync;
      text = last == null ? 'Noch nicht synchronisiert' : 'Synchronisiert um ${last.hour.toString().padLeft(2, '0')}:${last.minute.toString().padLeft(2, '0')} Uhr';
      color = t.colorScheme.outline;
    }

    return InkWell(
      onTap: () => ref.read(syncControllerProvider.notifier).sync(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: t.textTheme.bodySmall?.copyWith(color: color))),
          Text('Tippen zum Aktualisieren', style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.outline)),
        ]),
      ),
    );
  }
}
