import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../products/barcode_flow.dart';
import 'receipt_import_service.dart';

enum _Busy { pdf, paper, barcode }

/// Inhalt des Tabs "Scan": Einstiegspunkte zum Erfassen von Bons.
class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key, this.pickPdf = _pickPdfFromSystem});

  /// Liefert die Bytes des gewaehlten PDFs oder null bei Abbruch. Austauschbar fuer Tests.
  final Future<Uint8List?> Function() pickPdf;

  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage> {
  /// Was gerade laeuft: null = nichts, sonst die Karte, die angetippt wurde. Nur diese zeigt den Ladekreis.
  _Busy? _busy;
  String _status = '';

  bool get _isBusy => _busy != null;

  Future<void> _importPdf() async {
    setState(() {
      _busy = _Busy.pdf;
      _status = 'PDF wird gelesen …';
    });
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
      if (mounted) setState(() => _busy = null);
    }
    if (preview != null && mounted) {
      await context.push('/import-review', extra: preview);
    }
  }

  Future<void> _scanPaper() async {
    setState(() {
      _busy = _Busy.paper;
      _status = 'Scanner wird geöffnet …';
    });
    ImportPreview? preview;
    try {
      final pages = await ref.read(receiptScannerProvider).scan();
      if (pages != null) {
        preview = await ref.read(photoReceiptServiceProvider).read(
          pages,
          onStatus: (s) {
            if (mounted) setState(() => _status = s);
          },
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scan nicht möglich: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
    if (preview != null && mounted) {
      await context.push('/import-review', extra: preview);
    }
  }

  Future<void> _scanBarcode() async {
    setState(() => _busy = _Busy.barcode);
    // Die Ladeanzeige gilt nur fuer Scan und Suche, nicht fuer die Anlage-/Erfassungsseiten danach
    // (sonst blockiert ein wartendes push() wie beim PDF-Import die Anzeige, siehe dortigen Kommentar).
    await startBarcodeScan(
      context,
      ref,
      onStatus: (s) {
        if (mounted) setState(() => _status = s);
      },
      onLookupDone: () {
        if (mounted) setState(() => _busy = null);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_isBusy)
          Card(
            key: const Key('scan-status'),
            color: t.colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_status, style: t.textTheme.bodyMedium),
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ]),
            ),
          ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('Digitalen Bon importieren'),
            subtitle: const Text('PDF aus der jö-App auswählen. Der Bon wird direkt aus dem Text gelesen, ohne Foto und ohne Cloud.'),
            trailing: _busy == _Busy.pdf
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right),
            onTap: _isBusy ? null : _importPdf,
          ),
        ),
        // Der Dokumentenscanner (google_mlkit_document_scanner) ist eine reine Android/iOS-Funktion
        // (ADR: ML Kit hat keine Web-Implementierung) -- im Browser (PWA) gaebe es hier nur einen
        // kryptischen Plugin-Fehler statt eines Ergebnisses, deshalb wird die Karte dort ausgeblendet.
        if (!kIsWeb)
          Card(
            child: ListTile(
              key: const Key('scan-paper'),
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('Papierbon fotografieren'),
              subtitle: const Text(
                  'Der Bon wird auf dem Handy gelesen. Nur wenn die Prüfung nicht aufgeht, hilft die Cloud, und dann ohne Zahlungsdaten.'),
              trailing: _busy == _Busy.paper
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.chevron_right),
              onTap: _isBusy ? null : _scanPaper,
            ),
          ),
        Card(
          child: ListTile(
            key: const Key('scan-barcode'),
            leading: const Icon(Icons.qr_code_scanner),
            title: const Text('Barcode scannen'),
            subtitle: const Text('Inventar erfassen: Produkt suchen oder neu anlegen, Haltbarkeit eintragen.'),
            trailing: _busy == _Busy.barcode
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right),
            onTap: _isBusy ? null : _scanBarcode,
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
