import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../domain/diagnostics/app_info.dart';

const _areas = ['Übersicht', 'Inventar', 'Scan', 'Liste', 'Auswertung', 'Einstellungen', 'Sonstiges'];

/// Feature vorschlagen (Jakobs Wunsch 2026-09-28): teilt sich Tabelle und Status-Workflow mit den
/// Fehlerberichten (kind = 'feature'), aber mit eigenen, auf eine Idee statt einen Fehler zugeschnittenen
/// Feldern. Ein Vorschlag wird erst umgesetzt, nachdem er von der Entwicklung angenommen wurde (Status
/// 'confirmed', die Planungsliste) — das entscheidet nicht der Client.
class FeatureRequestPage extends ConsumerStatefulWidget {
  const FeatureRequestPage({super.key});

  @override
  ConsumerState<FeatureRequestPage> createState() => _FeatureRequestPageState();
}

class _FeatureRequestPageState extends ConsumerState<FeatureRequestPage> {
  late final _title = TextEditingController();
  late final _idea = TextEditingController();
  late final _benefit = TextEditingController();
  String _area = _areas.first;
  var _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _idea.dispose();
    _benefit.dispose();
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
      final appInfo = collectAppInfo(route: _area, pendingChanges: 0, lastSyncError: null, lastSyncAt: null);
      final description = [
        if (_idea.text.trim().isNotEmpty) 'Was schlägst du vor:\n${_idea.text.trim()}',
        if (_benefit.text.trim().isNotEmpty) 'Warum wäre das hilfreich:\n${_benefit.text.trim()}',
      ].join('\n\n');

      await ref.read(bugReportRepositoryProvider).create(title: title, description: description, appInfo: appInfo, kind: 'feature');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Feature-Vorschlag gespeichert')));
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
      appBar: AppBar(title: const Text('Feature vorschlagen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(key: const Key('feature-title'), controller: _title, decoration: const InputDecoration(labelText: 'Kurzer Titel')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const Key('feature-area'),
            initialValue: _area,
            decoration: const InputDecoration(labelText: 'Wo würde es hinpassen?'),
            items: [for (final a in _areas) DropdownMenuItem(value: a, child: Text(a))],
            onChanged: (v) => setState(() => _area = v ?? _area),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('feature-idea'),
            controller: _idea,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Was schlägst du vor?', alignLabelWithHint: true),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('feature-benefit'),
            controller: _benefit,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Warum wäre das hilfreich? (optional)', alignLabelWithHint: true),
          ),
          if (_error != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: t.colorScheme.error))),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('feature-submit'),
            onPressed: _saving ? null : _submit,
            child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Vorschlag speichern'),
          ),
        ],
      ),
    );
  }
}
