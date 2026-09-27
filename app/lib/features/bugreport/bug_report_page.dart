import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../domain/diagnostics/app_info.dart';
import '../../domain/diagnostics/data_snapshot.dart';

const _areas = ['Übersicht', 'Inventar', 'Scan', 'Liste', 'Auswertung', 'Einstellungen', 'Sonstiges'];

/// Fehler melden (Jakobs Wunsch 2026-09-27): haelt fest, was passiert ist, was erwartet wurde, und den
/// technischen Stand (Plattform, ausstehende Aenderungen, optional ein Auszug der lokalen Daten), damit
/// sich ein Fehler moeglichst ohne Rueckfragen nachstellen laesst. Wird wie alle Daten offline-first
/// gespeichert und geht beim naechsten Sync raus.
class BugReportPage extends ConsumerStatefulWidget {
  const BugReportPage({super.key});

  @override
  ConsumerState<BugReportPage> createState() => _BugReportPageState();
}

class _BugReportPageState extends ConsumerState<BugReportPage> {
  late final _title = TextEditingController();
  late final _happened = TextEditingController();
  late final _expected = TextEditingController();
  late final _steps = TextEditingController();
  String _area = _areas.first;
  var _includeSnapshot = true;
  var _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _happened.dispose();
    _expected.dispose();
    _steps.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Bitte einen kurzen Titel eingeben.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final sync = ref.read(syncControllerProvider);
      final pending = ref.read(pendingChangesProvider).value ?? 0;
      final appInfo = collectAppInfo(
        route: _area,
        pendingChanges: pending,
        lastSyncError: sync.error,
        lastSyncAt: sync.lastSync,
      );
      final snapshot = _includeSnapshot ? await buildDataSnapshot(ref.read(databaseProvider)) : null;

      final description = [
        if (_happened.text.trim().isNotEmpty) 'Was ist passiert:\n${_happened.text.trim()}',
        if (_expected.text.trim().isNotEmpty) 'Was wurde erwartet:\n${_expected.text.trim()}',
        if (_steps.text.trim().isNotEmpty) 'Schritte zum Reproduzieren:\n${_steps.text.trim()}',
      ].join('\n\n');

      await ref.read(bugReportRepositoryProvider).create(
            title: title,
            description: description,
            appInfo: appInfo,
            dataSnapshot: snapshot,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fehlerbericht gespeichert')));
        context.pop();
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Speichern nicht möglich: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Fehler melden')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(key: const Key('bug-title'), controller: _title, decoration: const InputDecoration(labelText: 'Kurzer Titel')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const Key('bug-area'),
            initialValue: _area,
            decoration: const InputDecoration(labelText: 'Wo ist es aufgetreten?'),
            items: [for (final a in _areas) DropdownMenuItem(value: a, child: Text(a))],
            onChanged: (v) => setState(() => _area = v ?? _area),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('bug-happened'),
            controller: _happened,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Was ist passiert?', alignLabelWithHint: true),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('bug-expected'),
            controller: _expected,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Was hättest du erwartet? (optional)', alignLabelWithHint: true),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('bug-steps'),
            controller: _steps,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Schritte zum Nachstellen (optional)', alignLabelWithHint: true),
          ),
          SwitchListTile(
            key: const Key('bug-snapshot'),
            title: const Text('Aktuelle Daten anhängen'),
            subtitle: const Text('Jüngste Bons, Produkte und Inventareinträge, damit sich der Fehler nachstellen lässt.'),
            value: _includeSnapshot,
            onChanged: (v) => setState(() => _includeSnapshot = v),
          ),
          if (_error != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: t.colorScheme.error))),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('bug-submit'),
            onPressed: _saving ? null : _submit,
            child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Bericht speichern'),
          ),
        ],
      ),
    );
  }
}
