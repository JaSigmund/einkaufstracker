import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../data/cloud/cloud_receipt.dart';
import '../../data/ocr/image_prep.dart';
import '../../data/repositories/receipt_repository.dart';
import '../../domain/ocr/ocr_text.dart';
import '../../domain/ocr/row_cluster.dart';
import '../../domain/receipt/parsed_receipt.dart';
import '../../domain/receipt/receipt_text_parser.dart';
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
    this.parser = parseReceiptText,
  });

  final ReceiptRepository repo;
  final CloudReceiptReader cloud;
  final Future<bool> Function() cloudAllowed;
  final ImagePreparer prepare;

  /// Waehlt anhand der Kopfzeilen den passenden Bon-Parser (siehe `receipt_text_parser.dart`).
  final ParsedReceipt Function(String text) parser;

  /// [onStatus] meldet die Schritte fuer die Oberflaeche ("lokal lesen", "Cloud liest mit").
  Future<ImportPreview> read(List<ScannedPage> pages, {void Function(String status)? onStatus}) async {
    onStatus?.call('Bon wird auf dem Handy gelesen …');
    final ParsedReceipt local;
    final List<AttachmentSource> attachments;
    try {
      local = _readLocal(pages);
      attachments = _attachments(pages);
    } catch (e) {
      // Ein ungewohntes Foto/Bon-Format darf die lokale Zeilen-Geometrie nicht zum Absturz bringen
      // (Fehlerbericht "Scan nicht möglich: invalid argument(s): 0", 2026-09-28, Hofer-Bon): ohne
      // verlaessliche Geometrie gibt es ohnehin keinen sicheren Zuschnitt fuer Cloud/Ablage, aber der
      // Nutzer soll den Bon trotzdem von Hand erfassen koennen statt vor einem Absturz zu stehen.
      return ImportPreview(
        receipt: const ParsedReceipt.failed(['Der Bon konnte nicht gelesen werden.']),
        source: ReceiptSources.photoLocal,
        error: 'Auf dem Handy konnte der Bon nicht gelesen werden ($e). Du kannst den Bon später erneut scannen oder die Positionen von Hand eingeben.',
      );
    }
    if (local.isParsed && local.isTrustworthy) return _preview(local, ReceiptSources.photoLocal, attachments: attachments);
    if (!local.isParsed) {
      // Diagnose (Fehlerbericht "Hofer-Scan funktioniert nicht", 2026-09-28): der erkannte Text erscheint
      // nur bei Misserfolg im Geraete-Log, damit sich der Parser gegen echte OCR-Ausgabe schaerfen laesst.
      debugPrint('[bon-scan] lokal nicht gelesen: ${local.warnings.join('; ')}\n--- OCR-Text ---\n${_joinText(pages)}\n--- Ende ---');
    }

    // Lokal nicht sicher genug: Cloud fragen, soweit erlaubt und moeglich
    String? note;
    ParsedReceipt? remote;
    try {
      if (!await cloudAllowed()) {
        note = 'Die Cloud-Erkennung ist in den Einstellungen ausgeschaltet. Das Ergebnis stammt nur aus der lokalen Erkennung.';
      } else {
        onStatus?.call('Bilder werden vorbereitet …');
        final images = await _cloudImages(pages);
        if (images == null) {
          note = 'Zur Sicherheit wurde nichts hochgeladen: Die Zeile "Summe" wurde nicht erkannt, deshalb ließ sich der '
              'Zahlungsblock nicht abschneiden. Bitte den Bon neu fotografieren, mit der Zeile "Summe" gut lesbar.';
        } else {
          onStatus?.call('Die Cloud liest den Bon mit, das dauert etwa 10 Sekunden …');
          remote = await cloud.read(images);
        }
      }
    } on CloudNotAllowed {
      note = 'Die Cloud-Erkennung ist in den Einstellungen ausgeschaltet.';
    } on CloudUnavailable catch (e) {
      note = 'Die Cloud ist nicht erreichbar (${e.message}). Das Ergebnis stammt nur aus der lokalen Erkennung.';
    } catch (e) {
      // Jeder andere Fehler bei der Cloud-Vorbereitung (z.B. Bildverarbeitung bei einem ungewohnten Foto/
      // Bon-Format, Fehlerbericht "Scan nicht möglich: invalid argument(s): 0", 2026-09-28) darf den ganzen
      // Scan nicht zum Absturz bringen: die Cloud ist ein optionaler Rueckfall, kein Pflichtschritt. Das
      // lokale Ergebnis wird weiterverwendet, notfalls mit der "nicht gelesen"-Fehlermeldung unten.
      note = 'Die Cloud-Vorbereitung ist fehlgeschlagen ($e). Das Ergebnis stammt nur aus der lokalen Erkennung.';
    }

    if (remote != null && remote.isParsed) {
      // Das bessere Ergebnis gewinnt: bestandene Pruefung vor kleinerer Abweichung; bei Gleichstand die Cloud,
      // weil lokale Lesefehler bei Namen haeufiger sind
      final useRemote = remote.isTrustworthy || !local.isParsed || _gap(remote) < _gap(local);
      if (useRemote) {
        return _preview(remote, ReceiptSources.photoCloud, attachments: attachments, note: 'Die lokale Erkennung war nicht sicher genug, die Cloud hat mitgelesen.');
      }
      note = 'Auch die Cloud hat die Summe nicht getroffen. Angezeigt wird das genauere Ergebnis, bitte prüfen.';
    }

    if (!local.isParsed) {
      return ImportPreview(
        receipt: local,
        source: ReceiptSources.photoLocal,
        attachments: attachments,
        error: 'Auf dem Handy konnte der Bon nicht gelesen werden, und die Cloud konnte nicht helfen. '
            '${note ?? ''} ${local.warnings.isEmpty ? '' : 'Grund: ${local.warnings.join('; ')}.'} Du kannst den Bon später erneut scannen oder die Positionen von Hand eingeben.'.replaceAll('  ', ' '),
      );
    }
    return _preview(local, ReceiptSources.photoLocal, attachments: attachments, note: note);
  }

  int _gap(ParsedReceipt r) => (r.checks?.differenceCents ?? 1 << 30).abs();

  Future<ImportPreview> _preview(ParsedReceipt r, String source, {String? note, List<AttachmentSource> attachments = const []}) async {
    final existing = await repo.findDuplicate(r);
    return ImportPreview(receipt: r, source: source, note: note, duplicateOfReceiptId: existing?.id, attachments: attachments);
  }

  /// Foto-Scan im Browser (Doku 14 iOS-Strategie, Option D): ML Kit (Dokumentenscanner und lokale
  /// Texterkennung) hat keine Web-Implementierung, ein im Browser aufgenommenes Foto geht deshalb
  /// immer direkt an die Cloud -- ADR-003 ("lokal zuerst") gilt nur dort, wo lokale Erkennung
  /// ueberhaupt moeglich ist.
  ///
  /// [cutY] (Codereview-Fund 2026-10-01, Go/No-Go B4 "Zahlungsdaten verlassen nie das Geraet"): die
  /// automatische Zeilen-Geometrie aus der On-Device-Texterkennung gibt es im Browser nicht, deshalb
  /// markiert hier ein Mensch von Hand den Schnittpunkt (`WebPhotoCropPage`). Erforderlich, nicht
  /// optional -- ohne diesen Schritt darf kein Foto die Cloud erreichen, genau wie nativ ein fehlender
  /// Schnittpunkt den Upload verhindert (siehe `_cloudImages`).
  Future<ImportPreview> readSinglePhotoViaCloud(Uint8List jpeg, {required double cutY, void Function(String status)? onStatus}) async {
    final bool allowed;
    try {
      allowed = await cloudAllowed();
    } on CloudUnavailable catch (e) {
      return ImportPreview(
        receipt: const ParsedReceipt.failed(['Keine Verbindung.']),
        source: ReceiptSources.photoCloud,
        error: 'Die Einwilligung zur Cloud-Erkennung konnte nicht geprueft werden (${e.message}).',
      );
    }
    if (!allowed) {
      return ImportPreview(
        receipt: const ParsedReceipt.failed(['Cloud-Erkennung ist ausgeschaltet.']),
        source: ReceiptSources.photoCloud,
        error: 'Im Browser ist die Cloud-Erkennung der einzige Weg, ein Foto zu lesen (lokale Erkennung '
            'gibt es hier nicht). Bitte in den Einstellungen aktivieren, oder die Positionen von Hand eingeben.',
      );
    }
    onStatus?.call('Die Cloud liest den Bon mit, das dauert etwa 10 Sekunden …');
    final Uint8List cropped;
    try {
      cropped = prepareForCloudBytes(jpeg, cutY: cutY);
    } catch (e) {
      return ImportPreview(
        receipt: const ParsedReceipt.failed(['Das Foto konnte nicht zugeschnitten werden.']),
        source: ReceiptSources.photoCloud,
        error: 'Das Foto konnte nicht verarbeitet werden ($e). Bitte erneut versuchen.',
      );
    }
    try {
      final remote = await cloud.read([cropped]);
      if (!remote.isParsed) {
        return ImportPreview(
          receipt: remote,
          source: ReceiptSources.photoCloud,
          error: 'Der Bon konnte nicht gelesen werden. Du kannst es erneut versuchen oder die Positionen von Hand eingeben.',
        );
      }
      return await _preview(remote, ReceiptSources.photoCloud, note: remote.isTrustworthy ? null : 'Die Summe passte nicht genau, bitte prüfen.');
    } on CloudUnavailable catch (e) {
      return ImportPreview(
        receipt: const ParsedReceipt.failed(['Cloud nicht erreichbar.']),
        source: ReceiptSources.photoCloud,
        error: 'Die Cloud ist nicht erreichbar (${e.message}).',
      );
    } catch (e) {
      return ImportPreview(
        receipt: const ParsedReceipt.failed(['Der Bon konnte nicht gelesen werden.']),
        source: ReceiptSources.photoCloud,
        error: 'Der Bon konnte nicht gelesen werden ($e).',
      );
    }
  }

  /// Fotos zum Ablegen: alle Seiten bis zur Seite mit "Summe" bzw. den Zahlungsdaten, diese abgeschnitten, spaetere
  /// Seiten (Kundenbeleg) entfallen. Ohne sicheren Schnitt wird kein Foto abgelegt (wie beim Cloud-Upload, B4).
  List<AttachmentSource> _attachments(List<ScannedPage> pages) {
    for (var i = 0; i < pages.length; i++) {
      final cut = paymentCutY(pages[i].lines, slope: estimateSlope(pages[i].lines));
      if (cut != null) {
        return [
          for (var j = 0; j < i; j++) AttachmentSource.image(pages[j].imagePath, cutY: null, pageNo: j + 1),
          AttachmentSource.image(pages[i].imagePath, cutY: cut, pageNo: i + 1),
        ];
      }
    }
    return const [];
  }

  String _joinText(List<ScannedPage> pages) => pages.map((p) {
        final rows = clusterRows(p.lines, slope: estimateSlope(p.lines));
        return ocrRowsToText(rows);
      }).join('\n');

  ParsedReceipt _readLocal(List<ScannedPage> pages) => parser(_joinText(pages));

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
