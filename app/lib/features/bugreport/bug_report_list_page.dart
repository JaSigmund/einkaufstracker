import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';

const _prettyJson = JsonEncoder.withIndent('  ');

/// Text, den der Nutzer kopieren und weitergeben kann (Jakobs Wunsch: "sodass ich dir diese dann geben kann").
String reportAsText(BugReport r) {
  final buf = StringBuffer()
    ..writeln('# ${r.title}')
    ..writeln('Gemeldet: ${formatViennaDateTime(r.createdAt)}')
    ..writeln();
  if (r.description != null) buf..writeln(r.description)..writeln();
  buf..writeln('## Technischer Stand')..writeln(_prettyJson.convert(jsonDecode(r.appInfo)));
  if (r.dataSnapshot != null) {
    buf..writeln()..writeln('## Datenausschnitt')..writeln(_prettyJson.convert(jsonDecode(r.dataSnapshot!)));
  }
  return buf.toString();
}

/// Liste der eigenen Fehlerberichte, zum Nachschauen und Kopieren (siehe [BugReportDetailPage]).
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
                      trailing: const Icon(Icons.chevron_right),
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
      ),
    );
  }
}
