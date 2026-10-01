import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

/// Zeigt, dass ein Update noetig ist, bevor Synchronisierung/Cloud-Funktionen wieder verfuegbar sind
/// (ADR-022). Erscheint ueberall in der App (nicht nur auf einer Unterseite wie `SyncStatusBanner`),
/// weil es alle Online-Funktionen betrifft, nicht nur eine davon. Zeigt nichts, solange kein Update
/// noetig ist -- kein leerer Platzhalter.
class AppUpdateBanner extends ConsumerWidget {
  const AppUpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updateRequired = ref.watch(appUpdateRequiredProvider);
    if (!updateRequired) return const SizedBox.shrink();

    final message = ref.watch(appConfigProvider).value?.message;
    final t = Theme.of(context);

    return Material(
      color: t.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          key: const Key('app-update-banner'),
          children: [
            Icon(Icons.system_update_outlined, size: 20, color: t.colorScheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message ?? 'Ein Update ist erforderlich. Synchronisierung und Cloud-Funktionen sind bis dahin deaktiviert.',
                style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
