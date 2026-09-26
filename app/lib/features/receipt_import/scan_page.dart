import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import 'receipt_import_service.dart';

/// Inhalt des Tabs "Scan": Einstiegspunkte zum Erfassen von Bons.
class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key, this.pickPdf = _pickPdfFromSystem});

  /// Liefert die Bytes des gewaehlten PDFs oder null bei Abbruch. Austauschbar fuer Tests.
  final Future<Uint8List?> Function() pickPdf;

  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage> {
  bool _busy = false;

  Future<void> _importPdf() async {
    setState(() => _busy = true);
    ImportPreview? preview;
    try {
      final bytes = await widget.pickPdf();
      if (bytes != null) preview = await ref.read(receiptImportServiceProvider).preview(bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import nicht möglich: $e')));
      }
    } finally {
      // Die Ladeanzeige gilt nur fuers Auswaehlen und Lesen. Sie MUSS vor dem Oeffnen der Pruefansicht
      // ausgehen: Nach dem Speichern kehrt die App per go('/') zurueck, dabei kommt ein wartendes
      // push() nie zurueck und die Anzeige bliebe sonst haengen.
      if (mounted) setState(() => _busy = false);
    }
    if (preview != null && mounted) {
      await context.push('/import-review', extra: preview);
    }
  }

  Future<void> _scanPaper() async {
    setState(() => _busy = true);
    ImportPreview? preview;
    try {
      final pages = await ref.read(receiptScannerProvider).scan();
      if (pages != null) preview = await ref.read(photoReceiptServiceProvider).read(pages);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scan nicht möglich: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (preview != null && mounted) {
      await context.push('/import-review', extra: preview);
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
        Card(
          child: ListTile(
            key: const Key('scan-paper'),
            leading: const Icon(Icons.document_scanner_outlined),
            title: const Text('Papierbon fotografieren'),
            subtitle: const Text(
                'Der Bon wird auf dem Handy gelesen. Nur wenn die Prüfung nicht aufgeht, hilft die Cloud, und dann ohne Zahlungsdaten.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _busy ? null : _scanPaper,
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

Future<Uint8List?> _pickPdfFromSystem() async {
  final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['pdf']);
  return file?.readAsBytes();
}
