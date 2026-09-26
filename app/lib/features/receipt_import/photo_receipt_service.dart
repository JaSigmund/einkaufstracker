import 'dart:typed_data';

import '../../data/cloud/cloud_receipt.dart';
import '../../data/repositories/receipt_repository.dart';
import '../../domain/ocr/ocr_text.dart';
import '../../domain/ocr/row_cluster.dart';
import '../../domain/receipt/billa_text_parser.dart';
import '../../domain/receipt/parsed_receipt.dart';
import 'receipt_import_service.dart';

/// Eine fotografierte Seite: Bilddatei und die per OCR erkannten Zeilen (Koordinaten in Pixeln dieser Datei).
class ScannedPage {
  const ScannedPage(this.imagePath, this.lines);
  final String imagePath;
  final List<OcrLine> lines;
}

/// Dokumentenscanner plus OCR. Gibt null zurueck, wenn der Nutzer abbricht.
abstract class ReceiptScanner {
  Future<List<ScannedPage>?> scan();
}

/// Bereitet ein Foto fuer die Cloud auf: verkleinern und alles ab [cutY] (Zahlungsblock) abschneiden.
typedef ImagePreparer = Future<Uint8List> Function(String imagePath, {double? cutY});

/// Ablauf fuer Papierbons nach ADR-003 ("lokal zuerst, Cloud als Rueckfall"):
/// 1. lokale OCR + Parser, 2. Pruef-Tor (Summe und Steuerblock), 3. nur bei Nichtbestehen die Cloud, aber nur mit
/// Einwilligung und nur mit Bildern **ohne Zahlungsblock** (Go/No-Go B4).
class PhotoReceiptService {
  PhotoReceiptService({
    required this.repo,
    required this.cloud,
    required this.cloudAllowed,
    required this.prepare,
    this.parser = const BillaTextParser(lenient: true),
  });

  final ReceiptRepository repo;
  final CloudReceiptReader cloud;
  final Future<bool> Function() cloudAllowed;
  final ImagePreparer prepare;
  final BillaTextParser parser;

  Future<ImportPreview> read(List<ScannedPage> pages) async {
    final local = _readLocal(pages);
    if (local.isParsed && local.isTrustworthy) return _preview(local, ReceiptSources.photoLocal);

    // Lokal nicht sicher genug: Cloud fragen, soweit erlaubt und moeglich
    String? note;
    ParsedReceipt? remote;
    try {
      if (!await cloudAllowed()) {
        note = 'Die Cloud-Erkennung ist ausgeschaltet oder nicht erreichbar. Das Ergebnis stammt nur aus der lokalen Erkennung.';
      } else {
        final images = await _cloudImages(pages);
        if (images == null) {
          note = 'Zur Sicherheit wurde nichts hochgeladen: Die Zeile "Summe" wurde nicht erkannt, deshalb ließ sich der '
              'Zahlungsblock nicht abschneiden. Bitte den Bon neu fotografieren, mit der Zeile "Summe" gut lesbar.';
        } else {
          remote = await cloud.read(images);
        }
      }
    } on CloudNotAllowed {
      note = 'Die Cloud-Erkennung ist in den Einstellungen ausgeschaltet.';
    } on CloudUnavailable catch (e) {
      note = 'Die Cloud war nicht erreichbar (${e.message}). Das Ergebnis stammt nur aus der lokalen Erkennung.';
    }

    if (remote != null && remote.isParsed) {
      // Das bessere Ergebnis gewinnt: bestandene Pruefung vor kleinerer Abweichung; bei Gleichstand die Cloud,
      // weil lokale Lesefehler bei Namen haeufiger sind
      final useRemote = remote.isTrustworthy || !local.isParsed || _gap(remote) < _gap(local);
      if (useRemote) {
        return _preview(remote, ReceiptSources.photoCloud, note: 'Die lokale Erkennung war nicht sicher genug, die Cloud hat mitgelesen.');
      }
      note = 'Auch die Cloud hat die Summe nicht getroffen. Angezeigt wird das genauere Ergebnis, bitte prüfen.';
    }

    if (!local.isParsed) {
      return ImportPreview(
        receipt: local,
        source: ReceiptSources.photoLocal,
        error: 'Der Bon konnte nicht gelesen werden. ${local.warnings.join(' ')} ${note ?? ''}'.trim(),
      );
    }
    return _preview(local, ReceiptSources.photoLocal, note: note);
  }

  int _gap(ParsedReceipt r) => (r.checks?.differenceCents ?? 1 << 30).abs();

  Future<ImportPreview> _preview(ParsedReceipt r, String source, {String? note}) async {
    final existing = await repo.findDuplicate(r);
    return ImportPreview(receipt: r, source: source, note: note, duplicateOfReceiptId: existing?.id);
  }

  ParsedReceipt _readLocal(List<ScannedPage> pages) {
    final text = pages.map((p) {
      final rows = clusterRows(p.lines, slope: estimateSlope(p.lines));
      return ocrRowsToText(rows);
    }).join('\n');
    return parser.parse(text);
  }

  /// Bilder fuer die Cloud: ab der Seite mit "Summe" bzw. den ersten Zahlungsdaten wird abgeschnitten, spaetere
  /// Seiten (reiner Kundenbeleg) entfallen. Null, wenn nirgends ein sicherer Schnitt moeglich ist.
  Future<List<Uint8List>?> _cloudImages(List<ScannedPage> pages) async {
    for (var i = 0; i < pages.length; i++) {
      final p = pages[i];
      final cut = paymentCutY(p.lines, slope: estimateSlope(p.lines));
      if (cut != null) {
        return [
          for (var j = 0; j < i; j++) await prepare(pages[j].imagePath),
          await prepare(p.imagePath, cutY: cut),
        ];
      }
    }
    return null;
  }
}
