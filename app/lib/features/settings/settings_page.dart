import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/repositories/settings_repository.dart';
import '../common/sync_status_banner.dart';

/// Einstellungen des Haushalts (in Phase 1 online, Cache folgt bei Bedarf).
final _settingsProvider = FutureProvider.autoDispose<HouseholdSettings>((ref) async {
  final hid = await ref.watch(householdIdProvider.future);
  if (hid == null) throw StateError('Kein Haushalt gefunden');
  return ref.watch(settingsRepositoryProvider).load(hid);
});

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  Future<void> _update(BuildContext context, WidgetRef ref, Map<String, dynamic> changes) async {
    try {
      final hid = await ref.read(householdIdProvider.future);
      await ref.read(settingsRepositoryProvider).update(hid!, changes);
      ref.invalidate(_settingsProvider);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Speichern nicht möglich. Für Einstellungen wird Netz gebraucht.')));
      }
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final pending = ref.read(pendingChangesProvider).value ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Abmelden?'),
        content: Text(pending > 0
            ? '$pending Änderung(en) sind noch nicht übertragen und gehen beim Abmelden verloren. Erst mit dem Netz verbinden und synchronisieren?'
            : 'Die lokalen Daten werden von diesem Gerät entfernt. Deine Daten bleiben in der Cloud.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Abmelden')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(databaseProvider).wipe();
    await ref.read(authRepositoryProvider).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(_settingsProvider);
    final email = ref.watch(authRepositoryProvider).currentEmail;

    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(
        children: [
          const SyncStatusBanner(),
          const Divider(height: 1),
          ListTile(leading: const Icon(Icons.person_outline), title: const Text('Konto'), subtitle: Text(email ?? '–')),
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('Kategorien verwalten'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/categories'),
          ),
          ListTile(
            key: const Key('settings-products'),
            leading: const Icon(Icons.inventory_2_outlined),
            title: const Text('Meine Produkte'),
            subtitle: const Text('Bearbeiten, gelernte Bon-Zuordnungen lösen'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/products'),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('Bon-Auswertung und Erinnerungen', style: Theme.of(context).textTheme.titleSmall),
          ),
          settings.when(
            loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => const ListTile(leading: Icon(Icons.cloud_off), title: Text('Einstellungen nicht verfügbar'), subtitle: Text('Für dieses Fenster wird Netz gebraucht.')),
            data: (s) => Column(children: [
              SwitchListTile(
                secondary: const Icon(Icons.cloud_outlined),
                title: const Text('Cloud-Auswertung erlauben'),
                subtitle: const Text('Ist ein Bon lokal nicht sicher lesbar, darf das Foto zur Auswertung an eine KI gesendet werden. Es enthält u.U. Kartenendziffern und Kassierernamen.'),
                value: s.allowCloudOcr,
                onChanged: (v) => _update(context, ref, {'allow_cloud_ocr': v}),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.photo_outlined),
                title: const Text('Originalbelege speichern'),
                subtitle: const Text('Foto (ohne Zahlungsblock) oder PDF wird beim Bon abgelegt, privat auf dem Server. Gilt für neue Bons.'),
                value: s.keepReceiptImages,
                onChanged: (v) => _update(context, ref, {'keep_receipt_images': v}),
              ),
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('Ablauf-Erinnerung um'),
                subtitle: Text('${s.notifyTime} Uhr, ${s.notifyLeadDays} Tag(e) vorher (Erinnerungen folgen in Phase 3)'),
                onTap: () async {
                  final parts = s.notifyTime.split(':');
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
                  );
                  if (picked != null && context.mounted) {
                    final hh = picked.hour.toString().padLeft(2, '0');
                    final mm = picked.minute.toString().padLeft(2, '0');
                    await _update(context, ref, {'notify_time': '$hh:$mm:00'});
                  }
                },
              ),
            ]),
          ),
          const Divider(),
          ListTile(
            key: const Key('settings-bug-report'),
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Fehler melden'),
            subtitle: const Text('Hält fest, was passiert ist, damit der Fehler behoben werden kann.'),
            onTap: () => context.push('/bug-report'),
          ),
          ListTile(
            key: const Key('settings-bug-reports'),
            leading: const Icon(Icons.list_alt_outlined),
            title: const Text('Meine Fehlerberichte'),
            onTap: () => context.push('/bug-reports'),
          ),
          ListTile(
            key: const Key('settings-changelog'),
            leading: const Icon(Icons.new_releases_outlined),
            title: const Text('Änderungsprotokoll'),
            onTap: () => context.push('/changelog'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Abmelden'),
            onTap: () => _signOut(context, ref),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Consumer(
                builder: (context, ref, _) => Text(
                  ref.watch(appVersionProvider).when(
                        data: (v) => 'Einkaufstracker $v',
                        loading: () => 'Einkaufstracker',
                        error: (_, _) => 'Einkaufstracker',
                      ),
                  key: const Key('app-version'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
