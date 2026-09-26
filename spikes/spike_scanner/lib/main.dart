// Phase-0-Spike: Dokumentenscanner + ML-Kit-OCR + Barcode + Open Food Facts.
// Zweck: echte Bons und echte Barcodes testen, Ergebnisse als Golden-Set-Rohdaten sichern.
// Doku: ClaudeBrain/02 Projekte/Einkaufstracker/11 Roadmap und Meilensteine.md (Phase 0)
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'row_cluster.dart';
import 'second_pass.dart';

void main() => runApp(const SpikeApp());

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Bon-Spike',
        theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
        home: const HomePage(),
      );
}

Future<Directory> spikeDir() async {
  final base = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
  final d = Directory('${base.path}/spike');
  if (!await d.exists()) await d.create(recursive: true);
  return d;
}

String stamp() => DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Einkaufstracker Spike'),
            bottom: const TabBar(tabs: [Tab(text: 'Bon'), Tab(text: 'Barcode')]),
          ),
          body: const TabBarView(children: [ReceiptTab(), BarcodeTab()]),
        ),
      );
}

// ---------------------------------------------------------------------------
// Tab 1: Bon scannen und OCR auswerten
// ---------------------------------------------------------------------------
class ReceiptTab extends StatefulWidget {
  const ReceiptTab({super.key});
  @override
  State<ReceiptTab> createState() => _ReceiptTabState();
}

class _ReceiptTabState extends State<ReceiptTab> with AutomaticKeepAliveClientMixin {
  bool busy = false;
  String status = 'Noch nichts gescannt.';
  String rowsText = '';
  String rawText = '';
  List<String> lastFiles = [];
  bool showRows = true;
  bool useSecondPass = false; // kostete 16 s und lieferte auf guten Fotos keinen Nachweis, siehe Doku 05 §7.6

  @override
  bool get wantKeepAlive => true;

  Future<void> scan() async {
    setState(() {
      busy = true;
      status = 'Scanner läuft …';
    });
    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormats: {DocumentFormat.jpeg},
        pageLimit: 4,
        mode: ScannerMode.full,
        isGalleryImport: true,
      ),
    );
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await scanner.scanDocument();
      final images = result.images ?? <String>[];
      if (images.isEmpty) {
        setState(() => status = 'Abgebrochen.');
        return;
      }
      final dir = await spikeDir();
      final id = stamp();
      final allLines = <OcrLine>[];
      final allRows = <List<OcrLine>>[];
      final pageJson = <Map<String, dynamic>>[];
      final rowsParts = <String>[];
      final rawParts = <String>[];
      final files = <String>[];
      var added = 0;
      final sw = Stopwatch()..start();

      for (var i = 0; i < images.length; i++) {
        final src = images[i].replaceFirst('file://', '');
        final dst = '${dir.path}/bon-$id-p${i + 1}.jpg';
        await File(src).copy(dst);
        files.add(dst);

        final rec = await recognizer.processImage(InputImage.fromFilePath(dst));
        var lines = <OcrLine>[
          for (final b in rec.blocks)
            for (final l in b.lines) OcrLine(l.text, l.boundingBox, confidence: l.confidence),
        ];
        if (useSecondPass) {
          try {
            final second = await recognizePriceColumn(recognizer, dst, '${dir.path}/tmp-price-col.jpg');
            final merged = mergeSecondPass(lines, second);
            added += merged.length - lines.length;
            lines = merged;
          } catch (e) {
            rowsParts.add('(zweiter Durchgang fehlgeschlagen: $e)');
          }
        }
        allLines.addAll(lines);
        final slope = estimateSlope(lines);
        final rows = clusterRows(lines, slope: slope);
        allRows.addAll(rows);
        final deg = (math.atan(slope) * 180 / math.pi).toStringAsFixed(1);
        rowsParts.add('--- Seite ${i + 1}: ${lines.length} Zeilen, ${rows.length} Bildzeilen, Schräglage $deg° ---\n${renderRows(rows)}');
        rawParts.add(rec.text);
        pageJson.add({
          'page': i + 1,
          'image': dst.split('/').last,
          'slope': slope,
          'lines': lines.map((l) => l.toJson()).toList(),
        });
      }
      sw.stop();

      final check = checkSum(allRows);
      final checkText = check.billTotal == null
          ? 'Summenprüfung: keine Zeile "Summe" gefunden'
          : 'Summenprüfung: ${check.pricesFound} Preise, Σ ${check.pricesSum.toStringAsFixed(2)} € gegen Bon-Summe ${check.billTotal!.toStringAsFixed(2)} € → ${check.ok ? 'PASST' : 'ABWEICHUNG ${check.difference!.toStringAsFixed(2)} €'}';
      rowsParts.insert(0, checkText);

      final jsonPath = '${dir.path}/bon-$id.ocr.json';
      await File(jsonPath).writeAsString(const JsonEncoder.withIndent(' ').convert({
        'scanned_at': DateTime.now().toIso8601String(),
        'pages': pageJson,
        'ocr_ms': sw.elapsedMilliseconds,
        'second_pass': useSecondPass,
        'second_pass_added': added,
        'sum_check': {'prices_found': check.pricesFound, 'prices_sum': check.pricesSum, 'bill_total': check.billTotal, 'ok': check.ok},
      }));
      final rowsPath = '${dir.path}/bon-$id.rows.txt';
      await File(rowsPath).writeAsString(rowsParts.join('\n\n'));
      files.addAll([jsonPath, rowsPath]);

      setState(() {
        lastFiles = files;
        rowsText = rowsParts.join('\n\n');
        rawText = rawParts.join('\n\n');
        status = '${images.length} Seite(n), ${allLines.length} Zeilen, ${useSecondPass ? '$added Preise aus 2. Durchgang, ' : ''}OCR ${sw.elapsedMilliseconds} ms\n'
            '$checkText\n'
            'Gespeichert unter ${dir.path}';
      });
    } catch (e) {
      setState(() => status = 'Fehler: $e');
    } finally {
      await recognizer.close();
      await scanner.close();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilledButton.icon(
          onPressed: busy ? null : scan,
          icon: const Icon(Icons.document_scanner),
          label: const Text('Bon scannen'),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('2. Durchgang: Preisspalte vergrößert'),
          value: useSecondPass,
          onChanged: busy ? null : (v) => setState(() => useSecondPass = v),
        ),
        Text(status, style: Theme.of(context).textTheme.bodySmall),
        Row(children: [
          ChoiceChip(label: const Text('Bildzeilen'), selected: showRows, onSelected: (_) => setState(() => showRows = true)),
          const SizedBox(width: 8),
          ChoiceChip(label: const Text('Roher OCR-Text'), selected: !showRows, onSelected: (_) => setState(() => showRows = false)),
          const Spacer(),
          IconButton(
            tooltip: 'Dateien teilen',
            onPressed: lastFiles.isEmpty ? null : () => SharePlus.instance.share(ShareParams(files: lastFiles.map((f) => XFile(f)).toList())),
            icon: const Icon(Icons.share),
          ),
        ]),
        Expanded(
          child: SingleChildScrollView(
            child: SelectableText(
              showRows ? rowsText : rawText,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 2: Barcode scannen und Open Food Facts abfragen
// ---------------------------------------------------------------------------
class OffResult {
  OffResult(this.ean, this.found, this.name, this.brand, this.quantity, this.ms);
  final String ean;
  final bool found;
  final String name, brand, quantity;
  final int ms;
  String toCsv() => [ean, found ? 1 : 0, name, brand, quantity, ms].map((v) => '"${'$v'.replaceAll('"', "'")}"').join(';');
}

class BarcodeTab extends StatefulWidget {
  const BarcodeTab({super.key});
  @override
  State<BarcodeTab> createState() => _BarcodeTabState();
}

class _BarcodeTabState extends State<BarcodeTab> {
  final controller = MobileScannerController();
  final results = <OffResult>[];
  final seen = <String>{};
  bool lookingUp = false;

  Future<OffResult> lookup(String ean) async {
    final sw = Stopwatch()..start();
    try {
      final uri = Uri.https('world.openfoodfacts.org', '/api/v2/product/$ean.json', {
        'fields': 'product_name,brands,quantity,categories_tags,stores',
      });
      // OFF verlangt einen aussagekraeftigen User-Agent
      final resp = await http
          .get(uri, headers: {'User-Agent': 'EinkaufstrackerSpike/0.1 (privates Testprojekt)'})
          .timeout(const Duration(seconds: 10));
      sw.stop();
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      if (j['status'] == 1) {
        final p = j['product'] as Map<String, dynamic>;
        final name = '${p['product_name'] ?? ''}';
        return OffResult(ean, name.isNotEmpty, name, '${p['brands'] ?? ''}', '${p['quantity'] ?? ''}', sw.elapsedMilliseconds);
      }
      return OffResult(ean, false, '', '', '', sw.elapsedMilliseconds);
    } catch (e) {
      return OffResult(ean, false, 'FEHLER: $e', '', '', sw.elapsedMilliseconds);
    }
  }

  Future<void> onDetect(BarcodeCapture capture) async {
    final ean = capture.barcodes.firstOrNull?.rawValue;
    if (ean == null || lookingUp || seen.contains(ean)) return;
    seen.add(ean);
    setState(() => lookingUp = true);
    final r = await lookup(ean);
    if (!mounted) return;
    setState(() {
      results.insert(0, r);
      lookingUp = false;
    });
    final dir = await spikeDir();
    await File('${dir.path}/off_results.csv')
        .writeAsString('ean;found;name;brand;quantity;ms\n${results.reversed.map((r) => r.toCsv()).join('\n')}\n');
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hits = results.where((r) => r.found).length;
    return Column(children: [
      SizedBox(height: 240, child: MobileScanner(controller: controller, onDetect: onDetect)),
      ListTile(
        dense: true,
        title: Text('OFF-Trefferquote: $hits / ${results.length}${results.isEmpty ? '' : ' (${(100 * hits / results.length).round()} %)'}'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: 'Gleichen Code erneut zulassen',
            onPressed: () => setState(() => seen.clear()),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'CSV teilen',
            onPressed: results.isEmpty
                ? null
                : () async {
                    final dir = await spikeDir();
                    await SharePlus.instance.share(ShareParams(files: [XFile('${dir.path}/off_results.csv')]));
                  },
            icon: const Icon(Icons.share),
          ),
        ]),
      ),
      Expanded(
        child: ListView(children: [
          for (final r in results)
            ListTile(
              leading: Icon(r.found ? Icons.check_circle : Icons.help_outline, color: r.found ? Colors.green : Colors.orange),
              title: Text(r.found ? r.name : 'Unbekannt ${r.name}'),
              subtitle: Text('${r.ean}  ·  ${r.brand}  ·  ${r.quantity}  ·  ${r.ms} ms'),
            ),
        ]),
      ),
    ]);
  }
}
