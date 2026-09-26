import 'dart:typed_data';

import '../../data/pdf/pdf_text_reader.dart';
import '../../data/repositories/receipt_repository.dart';
import '../../domain/receipt/billa_text_parser.dart';
import '../../domain/receipt/parsed_receipt.dart';

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
  const ImportPreview({required this.receipt, this.duplicateOfReceiptId, this.error, this.source = ReceiptSources.pdfText, this.note});

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
  ReceiptImportService(this._reader, this._repo, {this.parser = const BillaTextParser()});

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
    return ImportPreview(receipt: parsed, duplicateOfReceiptId: existing?.id);
  }

  /// Speichert die Vorschau als bestaetigten Bon. Wirft, wenn sie nicht importierbar ist.
  Future<ReceiptSaveResult> save(ImportPreview preview) {
    if (!preview.canImport) throw StateError('Der Bon kann nicht importiert werden.');
    return _repo.saveParsed(preview.receipt, source: preview.source);
  }
}
