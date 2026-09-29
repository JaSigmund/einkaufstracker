import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../domain/receipt/csv_export.dart';
import '../common/sync_status_banner.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  Future<void> _update(BuildContext context, WidgetRef ref, Map<String, dynamic> changes) async {
    try {
      final hid = await ref.read(householdIdProvider.future);
      await ref.read(settingsRepositoryProvider).update(hid!, changes);
      ref.invalidate(householdSettingsProvider);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Speichern nicht möglich. Für Einstellungen wird Netz gebraucht.')));
      }
    }
  }

  /// Monatsbudget setzen oder loeschen (Doku 07 §2 "Budget"), leere Eingabe entfernt das Budget wieder.
  Future<void> _editBudget(BuildContext context, WidgetRef ref, int? currentCents) async {
    final controller = TextEditingController(text: currentCents == null ? '' : formatEuro(currentCents).replaceAll(' €', ''));
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Monatsbudget'),
        content: TextField(
          key: const Key('budget-input'),
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Betrag in Euro (leer = kein Budget)', suffixText: '€'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Speichern')),
        ],
      ),
    );
    if (result == null) return;
    final cents = result.trim().isEmpty ? null : parseEuroCents(result);
    if (result.trim().isNotEmpty && cents == null) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ungültiger Betrag')));
      return;
    }
    if (!context.mounted) return;
    await _update(context, ref, {'monthly_budget_cents': cents});
  }

  /// Bon-Positionen als CSV exportieren (Doku 07 §5), zum Teilen/Speichern ueber den System-Dialog.
  Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
    try {
      final receipts = ref.read(receiptRepositoryProvider);
      final results = await Future.wait([
        receipts.allSnapshot(),
        receipts.allItemsSnapshot(),
        receipts.storesSnapshot(),
        ref.read(productRepositoryProvider).allSnapshot(),
        ref.read(categoryRepositoryProvider).allSnapshot(),
      ]);
      final csv = buildReceiptItemsCsv(
        receipts: results[0] as List<Receipt>,
        items: results[1] as List<ReceiptItem>,
        stores: results[2] as List<Store>,
        products: results[3] as List<Product>,
        categories: results[4] as List<Category>,
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/einkaufstracker_export.csv');
      await file.writeAsString(csv);
      if (!context.mounted) return;
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: 'Einkaufstracker-Export'));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Export nicht möglich.')));
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

  /// Unwiderrufliche Loeschung: Rueckfrage verlangt das Eintippen von "LÖSCHEN", damit ein
  /// versehentliches Antippen nicht reicht (Play-Store-Pflicht "Account Deletion").
  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Konto endgültig löschen?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Dein Konto und alle Daten (Bons, Inventar, Einkaufsliste, Kategorien) werden unwiderruflich gelöscht. '
                  'Das kann nicht rückgängig gemacht werden.'),
              const SizedBox(height: 16),
              Text('Tippe "LÖSCHEN" ein, um zu bestätigen:', style: Theme.of(ctx).textTheme.bodySmall),
              TextField(controller: controller, onChanged: (_) => setState(() {}), autofocus: true),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: controller.text.trim() == 'LÖSCHEN' ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Endgültig löschen'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(authRepositoryProvider).deleteAccount();
      await ref.read(databaseProvider).wipe();
      await ref.read(authRepositoryProvider).signOut();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(householdSettingsProvider);
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
              ListTile(
                key: const Key('settings-budget'),
                leading: const Icon(Icons.savings_outlined),
                title: const Text('Monatsbudget'),
                subtitle: Text(s.monthlyBudgetCents == null ? 'Kein Budget gesetzt' : 'Warnung ab ${formatEuro(s.monthlyBudgetCents!)} pro Monat'),
                onTap: () => _editBudget(context, ref, s.monthlyBudgetCents),
              ),
              ListTile(
                key: const Key('settings-csv-export'),
                leading: const Icon(Icons.file_download_outlined),
                title: const Text('Bon-Daten exportieren (CSV)'),
                subtitle: const Text('Eine Zeile je Bon-Position, für Excel oder Obsidian'),
                onTap: () => _exportCsv(context, ref),
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
            key: const Key('settings-feature-request'),
            leading: const Icon(Icons.lightbulb_outline),
            title: const Text('Feature vorschlagen'),
            subtitle: const Text('Deine Idee kommt auf die Planungsliste, sobald sie angenommen wurde.'),
            onTap: () => context.push('/feature-request'),
          ),
          ListTile(
            key: const Key('settings-bug-reports'),
            leading: const Icon(Icons.list_alt_outlined),
            title: const Text('Meine Rückmeldungen'),
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
          ListTile(
            key: const Key('settings-delete-account'),
            leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
            title: Text('Konto löschen', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            subtitle: const Text('Löscht dein Konto und alle Daten unwiderruflich'),
            onTap: () => _deleteAccount(context, ref),
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
