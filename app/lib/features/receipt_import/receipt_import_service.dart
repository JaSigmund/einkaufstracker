import 'dart:typed_data';

import '../../data/files/receipt_file_service.dart';
import '../../data/pdf/pdf_text_reader.dart';
import '../../data/repositories/receipt_repository.dart';
import '../../domain/receipt/billa_text_parser.dart';
import '../../domain/receipt/parsed_receipt.dart';

/// Eine Datei, die nach dem Speichern zum Bon abgelegt wird. Bilder werden erst dann aufbereitet (verkleinert und
/// ohne Zahlungsblock), damit beim Verwerfen keine Arbeit anfaellt.
class AttachmentSource {
  const AttachmentSource.pdf(this.bytes)
      : kind = 'pdf',
        imagePath = null,
        cutY = null,
        pageNo = 1;
  const AttachmentSource.image(this.imagePath, {required this.cutY, required this.pageNo})
      : kind = 'image',
        bytes = null;

  final String kind;
  final Uint8List? bytes;
  final String? imagePath;

  /// Alles ab dieser Bildzeile (Zahlungsblock) wird abgeschnitten.
  final double? cutY;
  final int pageNo;
}

/// Werte der Spalte receipts.source (Postgres-Enum ocr_source).
class ReceiptSources {
  static const pdfText = 'pdf_text';
  static const photoLocal = 'on_device';
  static const photoCloud = 'llm';

  static String label(String source) => switch (source) {
        pdfText => 'Digitaler Bon (PDF)',
        photoLocal => 'Foto, lokal gelesen',
        photoCloud => 'Foto, per Cloud gelesen',
        _ => 'Quelle: $source',
      };
}

/// Vorschau eines Imports: der gelesene Bon und, falls er schon gespeichert ist, dessen ID.
class ImportPreview {
  const ImportPreview({
    required this.receipt,
    this.duplicateOfReceiptId,
    this.error,
    this.source = ReceiptSources.pdfText,
    this.note,
    this.edited = false,
    this.attachments = const [],
  });

  /// Originalbelege, die nach dem Speichern abgelegt werden.
  final List<AttachmentSource> attachments;

  /// Vom Nutzer in der Bearbeitungsansicht veraendert.
  final bool edited;

  ImportPreview copyWith({ParsedReceipt? receipt, bool? edited, bool clearError = false}) =>
      ImportPreview(
        receipt: receipt ?? this.receipt,
        duplicateOfReceiptId: duplicateOfReceiptId,
        error: clearError ? null : error,
        source: source,
        note: note,
        edited: edited ?? this.edited,
        attachments: attachments,
      );

  final ParsedReceipt receipt;

  /// Gesetzt, wenn ein Bon mit derselben Re-Nr bereits gespeichert ist.
  final String? duplicateOfReceiptId;

  /// Gesetzt, wenn die Datei nicht gelesen werden konnte (dann ist [receipt] ein Fehlerergebnis).
  final String? error;

  /// Wie der Bon gelesen wurde (Wert der Spalte receipts.source).
  final String source;

  /// Hinweis fuer die Pruefansicht, z.B. "Cloud wurde zur Hilfe genommen".
  final String? note;

  bool get isDuplicate => duplicateOfReceiptId != null;
  bool get canImport => error == null && receipt.isParsed && !isDuplicate;
}

/// Ablauf des PDF-Imports: PDF lesen, Text parsen, auf Duplikat pruefen, speichern.
class ReceiptImportService {
  ReceiptImportService(
    this._reader,
    this._repo, {
    this.parser = const BillaTextParser(),
    this.files,
    this.prepareImage,
  });

  /// Ablage der Originalbelege. Null = nichts ablegen.
  final ReceiptFileService? files;

  /// Bereitet ein Foto zum Ablegen auf (verkleinern, Zahlungsblock abschneiden).
  final Future<Uint8List> Function(String path, {double? cutY})? prepareImage;

  final PdfTextReader _reader;
  final ReceiptRepository _repo;
  final BillaTextParser parser;

  Future<ImportPreview> preview(Uint8List pdfBytes) async {
    final String text;
    try {
      text = await _reader.readText(pdfBytes);
    } on PdfReadException catch (e) {
      return ImportPreview(receipt: const ParsedReceipt.failed([]), error: e.message);
    }

    final parsed = parser.parse(text);
    if (!parsed.isParsed) {
      return ImportPreview(
        receipt: parsed,
        error: 'Das ist kein Billa-Bon in einem bekannten Format. ${parsed.warnings.join(' ')}'.trim(),
      );
    }
    final existing = await _repo.findDuplicate(parsed);
    return ImportPreview(receipt: parsed, duplicateOfReceiptId: existing?.id, attachments: [AttachmentSource.pdf(pdfBytes)]);
  }

  /// Prueft nach einer Bearbeitung erneut, ob der Einkauf schon gespeichert ist (Summe oder Zeit koennen sich geaendert haben).
  Future<ImportPreview> recheckDuplicate(ImportPreview preview) async {
    final existing = await _repo.findDuplicate(preview.receipt);
    return ImportPreview(
      receipt: preview.receipt,
      duplicateOfReceiptId: existing?.id,
      error: preview.error,
      source: preview.source,
      note: preview.note,
      edited: preview.edited,
      attachments: preview.attachments,
    );
  }

  /// Speichert die Vorschau als bestaetigten Bon. Wirft, wenn sie nicht importierbar ist.
  Future<ReceiptSaveResult> save(ImportPreview preview) async {
    if (!preview.canImport) throw StateError('Der Bon kann nicht importiert werden.');
    final result = await _repo.saveParsed(preview.receipt, source: preview.source);
    if (result.outcome == ReceiptSaveOutcome.saved) await _storeAttachments(result.receiptId, preview.attachments);
    return result;
  }

  /// Legt die Originalbelege ab. Das darf das Speichern des Bons nie scheitern lassen.
  Future<void> _storeAttachments(String receiptId, List<AttachmentSource> sources) async {
    final files = this.files;
    if (files == null || sources.isEmpty) return;
    try {
      final list = <ReceiptAttachment>[];
      for (final s in sources) {
        if (s.kind == 'pdf') {
          list.add(ReceiptAttachment(kind: 'pdf', bytes: s.bytes!));
        } else if (prepareImage != null) {
          list.add(ReceiptAttachment(kind: 'image', bytes: await prepareImage!(s.imagePath!, cutY: s.cutY), pageNo: s.pageNo));
        }
      }
      await files.attach(receiptId, list);
    } catch (_) {
      // Beleg konnte nicht abgelegt werden (z.B. Speicher voll): der Bon selbst ist gespeichert
    }
  }
}
