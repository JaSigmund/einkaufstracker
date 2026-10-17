import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../data/repositories/auth_repository.dart';
import '../../domain/notifications/expiry_stages.dart';
import '../../data/export/csv_export.dart';
import '../common/sync_status_banner.dart';
import 'expiry_stages_dialog.dart';

const _csvFileName = 'einkaufstracker_export.csv';

/// Teilt die CSV-Datei: auf dem Handy als Datei im Temp-Ordner, im Browser direkt aus dem Speicher. Codereview-Fund
/// 2026-10-16: im Browser gibt es weder dart:io noch einen Temp-Ordner, der Export scheiterte dort immer; share_plus teilt
/// die Datei dort ueber den Browser oder bietet sie zum Herunterladen an.
@visibleForTesting
Future<ShareParams> csvShareParams(String csv, {bool web = kIsWeb, Future<Directory> Function() tempDir = getTemporaryDirectory}) async {
  if (web) {
    return ShareParams(
      files: [XFile.fromData(utf8.encode(csv), mimeType: 'text/csv', name: _csvFileName)],
      fileNameOverrides: const [_csvFileName],
      text: 'Einkaufstracker-Export',
    );
  }
  final file = File('${(await tempDir()).path}/$_csvFileName');
  await file.writeAsString(csv);
  return ShareParams(files: [XFile(file.path)], text: 'Einkaufstracker-Export');
}

enum _SignOutChoice { cancel, syncFirst, signOut }

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  Future<void> _update(BuildContext context, WidgetRef ref, Map<String, dynamic> changes) async {
    try {
      final hid = await ref.read(householdIdProvider.future);
      await ref.read(settingsRepositoryProvider).update(hid!, changes);
      ref.invalidate(householdSettingsProvider);
      // Codereview-Fund 2026-10-01 (Fehlerbericht "Erinnerungszeit aendern wirkt nicht sofort"): ohne das
      // blieb eine bereits geplante Ablauf-Erinnerung mit der ALTEN Uhrzeit/Vorlaufzeit aktiv, bis die App
      // neu gestartet wird oder sich das Inventar aendert -- `rescheduleExpiryReminders` laeuft sonst nur
      // bei genau diesen beiden Ausloesern (siehe `app/app.dart`), eine Einstellungsaenderung war keiner
      // davon.
      if (changes.containsKey('notify_time') || changes.containsKey('notify_lead_days')) {
        await rescheduleExpiryReminders(ref);
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Speichern nicht möglich. Für Einstellungen wird Netz gebraucht.')));
      }
    }
  }

  /// Stufen der Ablauf-Erinnerung fuer alle Produkte (Ausbau 1.14), gemeinsame Einstellung des Haushalts.
  Future<void> _editStages(BuildContext context, WidgetRef ref, int leadDays) async {
    final prefs = await ref.read(householdPrefsOnceProvider.future).catchError((_) => <String, Object?>{});
    final current = parseExpiryStages(prefs[expiryStagesPref]) ?? [leadDays];
    if (!context.mounted) return;
    final picked = await showExpiryStagesDialog(
      context,
      initial: current,
      title: 'Wann erinnern?',
      helper: 'Die App erinnert zu jedem gewählten Zeitpunkt vor dem Ablauf, zur eingestellten Uhrzeit. Einzelne Produkte können eigene Zeitpunkte haben (im Bestand beim Artikel).',
    );
    if (picked == null || picked.isEmpty) return;
    try {
      await ref.read(householdPrefsRepositoryProvider).set(expiryStagesPref, picked);
      ref.invalidate(householdPrefsOnceProvider);
    } catch (_) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Speichern nicht möglich.')));
      return;
    }
    // Die Erinnerungen werden sofort neu geplant; scheitert das (kein Netz fuer die Einstellungen), gilt es beim naechsten App-Start
    try {
      await rescheduleExpiryReminders(ref);
    } catch (_) {}
  }

  Future<void> _editNotifyTime(BuildContext context, WidgetRef ref, String notifyTime) async {
    final parts = notifyTime.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
    );
    if (picked != null && context.mounted) {
      final hh = picked.hour.toString().padLeft(2, '0');
      final mm = picked.minute.toString().padLeft(2, '0');
      await _update(context, ref, {'notify_time': '$hh:$mm:00'});
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
      final params = await csvShareParams(csv);
      if (!context.mounted) return;
      await SharePlus.instance.share(params);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Export nicht möglich.')));
      }
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final pending = ref.read(pendingChangesProvider).value ?? 0;
    // Codereview-Fund 2026-10-16: mit wartenden Aenderungen fragte der Dialog "Erst ... synchronisieren?", bot aber nur
    // "Abbrechen" und "Abmelden" an. Jetzt gibt es die Antwort dazu, und das verlustreiche Abmelden ist als solches markiert.
    final choice = await showDialog<_SignOutChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Abmelden?'),
        content: Text(pending > 0
            ? '$pending Änderung(en) sind noch nicht übertragen und gehen beim Abmelden verloren. Erst mit dem Netz verbinden und synchronisieren?'
            : 'Die lokalen Daten werden von diesem Gerät entfernt. Deine Daten bleiben in der Cloud.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, _SignOutChoice.cancel), child: const Text('Abbrechen')),
          if (pending > 0) ...[
            TextButton(
              key: const Key('sign-out-anyway'),
              style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, _SignOutChoice.signOut),
              child: const Text('Trotzdem abmelden'),
            ),
            FilledButton(
              key: const Key('sign-out-sync-first'),
              onPressed: () => Navigator.pop(ctx, _SignOutChoice.syncFirst),
              child: const Text('Jetzt synchronisieren'),
            ),
          ] else
            FilledButton(onPressed: () => Navigator.pop(ctx, _SignOutChoice.signOut), child: const Text('Abmelden')),
        ],
      ),
    );
    if (choice == _SignOutChoice.syncFirst) {
      await ref.read(syncControllerProvider.notifier).sync();
      if (!context.mounted) return;
      final left = (await ref.read(databaseProvider).select(ref.read(databaseProvider).outbox).get()).length;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(left == 0
            ? 'Alles übertragen. Du kannst dich jetzt ohne Verlust abmelden.'
            : 'Noch $left Änderung(en) offen. Bitte mit dem Netz verbinden und erneut versuchen.'),
      ));
      return;
    }
    if (choice != _SignOutChoice.signOut) return;
    // Codereview-Fund 2026-10-01: blockiert einen parallel ausgeloesten Sync (Timer, Connectivity, Tipp auf
    // den Banner), solange die lokale DB geleert wird -- sonst koennte er mit der noch gueltigen Session
    // Daten zurueckschreiben, bevor signOut() sie ungueltig macht (Privacy-Risiko bei Geraete-Weitergabe).
    ref.read(authTransitionInProgressProvider.notifier).start();
    try {
      await clearLocalAccountData(ref);
      await ref.read(authRepositoryProvider).signOut();
    } catch (e) {
      debugPrint('[abmelden] fehlgeschlagen: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Abmelden nicht möglich. Bitte erneut versuchen.')));
      }
    } finally {
      ref.read(authTransitionInProgressProvider.notifier).finish();
    }
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
              const Text('Bist du das einzige Mitglied deines Haushalts, werden dein Konto und alle Daten (Bons, Inventar, '
                  'Einkaufsliste, Kategorien, Essenstagebuch samt Fotos) unwiderruflich gelöscht. Gibt es weitere Mitglieder, '
                  'verlierst nur du den Zugang, die Daten bleiben für die anderen erhalten. '
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
    ref.read(authTransitionInProgressProvider.notifier).start();
    try {
      await ref.read(authRepositoryProvider).deleteAccount();
    } catch (e) {
      debugPrint('[konto-loeschen] fehlgeschlagen: $e');
      if (context.mounted) {
        // SignInFailure traegt schon einen verstaendlichen Text, alles andere nicht (Codereview-Fund 2026-10-16)
        final text = e is SignInFailure ? e.message : 'Konto konnte nicht gelöscht werden. Bitte erneut versuchen.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
      }
      ref.read(authTransitionInProgressProvider.notifier).finish();
      return;
    }
    // Ab hier ist das Konto serverseitig bereits unwiderruflich geloescht (Codereview-Fund 2026-10-01):
    // wipe()/signOut() laufen deshalb unabhaengig voneinander und werfen nicht mehr, egal ob der jeweils
    // andere Schritt klappt -- sonst bliebe bei einem Fehler z.B. in wipe() eine scheinbar gueltige Session
    // mit den Daten des geloeschten Kontos auf dem Geraet stehen, ohne Weg zurueck ueber die UI (ein
    // erneuter Loeschversuch scheitert, das Konto existiert ja schon nicht mehr).
    try {
      await clearLocalAccountData(ref, continueOnDatabaseError: true);
    } catch (_) {
      // best effort, siehe oben
    }
    try {
      await ref.read(authRepositoryProvider).signOut();
    } catch (_) {
      // best effort, siehe oben
    }
    ref.read(authTransitionInProgressProvider.notifier).finish();
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
            key: const Key('settings-household'),
            leading: const Icon(Icons.group_outlined),
            title: const Text('Haushalt'),
            subtitle: const Text('Personen einladen, Einladungen verwalten'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/household'),
          ),
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
              if (s.fromCache)
                const ListTile(
                  key: Key('settings-offline'),
                  leading: Icon(Icons.cloud_off),
                  title: Text('Ohne Netz: zuletzt bekannte Werte'),
                  subtitle: Text('Ändern geht wieder, sobald das Gerät online ist.'),
                ),
              SwitchListTile(
                secondary: const Icon(Icons.cloud_outlined),
                title: const Text('Cloud-Auswertung erlauben'),
                subtitle: const Text('Ist ein Bon lokal nicht sicher lesbar, darf das Foto zur Auswertung an eine KI gesendet werden. Es enthält u.U. Kartenendziffern und Kassierernamen.'),
                value: s.allowCloudOcr,
                onChanged: s.fromCache ? null : (v) => _update(context, ref, {'allow_cloud_ocr': v}),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.photo_outlined),
                title: const Text('Originalbelege speichern'),
                subtitle: const Text('Foto (ohne Zahlungsblock) oder PDF wird beim Bon abgelegt, privat auf dem Server. Gilt für neue Bons.'),
                value: s.keepReceiptImages,
                onChanged: s.fromCache ? null : (v) => _update(context, ref, {'keep_receipt_images': v}),
              ),
              ListTile(
                key: const Key('settings-reminder-stages'),
                leading: const Icon(Icons.alarm_add_outlined),
                title: const Text('Erinnern'),
                subtitle: Text(describeExpiryStages(parseExpiryStages(ref.watch(householdPrefsOnceProvider).value?[expiryStagesPref]) ?? [s.notifyLeadDays])),
                onTap: s.fromCache ? null : () => _editStages(context, ref, s.notifyLeadDays),
              ),
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('Ablauf-Erinnerung um'),
                subtitle: Text('${s.notifyTime} Uhr, ${s.notifyLeadDays} Tag(e) vorher'),
                onTap: s.fromCache ? null : () => _editNotifyTime(context, ref, s.notifyTime),
              ),
              ListTile(
                key: const Key('settings-budget'),
                leading: const Icon(Icons.savings_outlined),
                title: const Text('Monatsbudget'),
                subtitle: Text(s.monthlyBudgetCents == null ? 'Kein Budget gesetzt' : 'Warnung ab ${formatEuro(s.monthlyBudgetCents!)} pro Monat'),
                onTap: s.fromCache ? null : () => _editBudget(context, ref, s.monthlyBudgetCents),
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
            key: const Key('settings-sign-out'),
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
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
