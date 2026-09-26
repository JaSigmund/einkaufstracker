import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';

/// Inhalt des Tabs "Scan": Einstiegspunkte zum Erfassen von Bons.
class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key});

  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage> {
  bool _busy = false;

  Future<void> _importPdf() async {
    setState(() => _busy = true);
    try {
      final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['pdf']);
      if (file == null) return; // abgebrochen
      final Uint8List bytes = await file.readAsBytes();
      final preview = await ref.read(receiptImportServiceProvider).preview(bytes);
      if (!mounted) return;
      await context.push('/import-review', extra: preview);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import nicht möglich: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('Digitalen Bon importieren'),
            subtitle: const Text('PDF aus der jö-App auswählen. Der Bon wird direkt aus dem Text gelesen, ohne Foto und ohne Cloud.'),
            trailing: _busy
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right),
            onTap: _busy ? null : _importPdf,
          ),
        ),
        const Card(
          child: ListTile(
            enabled: false,
            leading: Icon(Icons.document_scanner_outlined),
            title: Text('Papierbon fotografieren'),
            subtitle: Text('Folgt in einem späteren Schritt von Phase 2.'),
          ),
        ),
        const Card(
          child: ListTile(
            enabled: false,
            leading: Icon(Icons.qr_code_scanner),
            title: Text('Barcode scannen'),
            subtitle: Text('Folgt in Phase 3 (Inventar).'),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Tipp: Speichere den digitalen Bon in der jö-App als PDF und wähle ihn hier aus. Derselbe Einkauf wird nie doppelt gespeichert.',
          style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline),
        ),
      ],
    );
  }
}
