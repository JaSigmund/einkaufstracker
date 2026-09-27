import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';

const _prettyJson = JsonEncoder.withIndent('  ');

/// Bearbeitungsstatus wie in einem Ticket-System (Doku-Wunsch "aehnlich wie in MS Azure"): Reihenfolge,
/// Farbe und Anzeigename je Status.
const _statusLabels = {
  'new': 'Gemeldet',
  'confirmed': 'Bestätigt',
  'in_progress': 'In Bearbeitung',
  'fixed': 'Behoben',
  'verified': 'Bestätigt behoben',
  'wont_fix': 'Wird nicht behoben',
  'duplicate': 'Duplikat',
};

Color _statusColor(String status, ColorScheme cs) => switch (status) {
      'new' => cs.outline,
      'confirmed' => Colors.blue.shade700,
      'in_progress' => Colors.amber.shade800,
      'fixed' => Colors.lightGreen.shade700,
      'verified' => Colors.green.shade700,
      'wont_fix' => cs.outline,
      'duplicate' => cs.outline,
      _ => cs.outline,
    };

const _severityLabels = {'low': 'Niedrig', 'medium': 'Mittel', 'high': 'Hoch', 'critical': 'Kritisch'};

/// Text, den der Nutzer kopieren und weitergeben kann (Jakobs Wunsch: "sodass ich dir diese dann geben kann").
String reportAsText(BugReport r) {
  final buf = StringBuffer()
    ..writeln('# ${r.title}')
    ..writeln('Gemeldet: ${formatViennaDateTime(r.createdAt)}')
    ..writeln('Status: ${_statusLabels[r.status] ?? r.status}')
    ..writeln();
  if (r.description != null) buf..writeln(r.description)..writeln();
  if (r.resolution != null) {
    buf.writeln('## Lösung${r.fixedInVersion == null ? '' : ' (Version ${r.fixedInVersion})'}\n${r.resolution}\n');
  }
  buf..writeln('## Technischer Stand')..writeln(_prettyJson.convert(jsonDecode(r.appInfo)));
  if (r.dataSnapshot != null) {
    buf..writeln()..writeln('## Datenausschnitt')..writeln(_prettyJson.convert(jsonDecode(r.dataSnapshot!)));
  }
  return buf.toString();
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status, Theme.of(context).colorScheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999)),
      child: Text(_statusLabels[status] ?? status, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

/// Liste der eigenen Fehlerberichte mit Status, zum Nachschauen und Kopieren (siehe [BugReportDetailPage]).
class BugReportListPage extends ConsumerWidget {
  const BugReportListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(bugReportsStreamProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Meine Fehlerberichte')),
      body: reports.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (list) => list.isEmpty
            ? const Center(child: Text('Noch keine Fehlerberichte', key: Key('bug-list-empty')))
            : ListView(
                children: [
                  for (final r in list)
                    ListTile(
                      key: Key('bug-${r.id}'),
                      leading: const Icon(Icons.bug_report_outlined),
                      title: Text(r.title),
                      subtitle: Text(formatViennaDateTime(r.createdAt)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        _StatusChip(status: r.status),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right),
                      ]),
                      onTap: () => context.push('/bug-reports/detail', extra: r),
                    ),
                ],
              ),
      ),
    );
  }
}

class BugReportDetailPage extends StatelessWidget {
  const BugReportDetailPage({super.key, required this.report});
  final BugReport report;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final text = reportAsText(report);
    return Scaffold(
      appBar: AppBar(
        title: Text(report.title),
        actions: [
          IconButton(
            key: const Key('bug-copy'),
            tooltip: 'In die Zwischenablage kopieren',
            icon: const Icon(Icons.copy_outlined),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('In die Zwischenablage kopiert')));
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            _StatusChip(status: report.status),
            if (report.severity != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: t.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(999)),
                child: Text('Dringlichkeit: ${_severityLabels[report.severity] ?? report.severity}', style: t.textTheme.labelMedium),
              ),
            if (report.fixedInVersion != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: t.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(999)),
                child: Text('Version ${report.fixedInVersion}', style: t.textTheme.labelMedium),
              ),
          ]),
          const SizedBox(height: 16),
          if (report.resolution != null) ...[
            Card(
              color: t.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Lösung', style: t.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(report.resolution!),
                ]),
              ),
            ),
            const SizedBox(height: 16),
          ],
          SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12), key: const Key('bug-detail-text')),
        ],
      ),
    );
  }
}
