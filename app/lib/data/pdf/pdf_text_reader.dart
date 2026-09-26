import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

/// Liest den Text aus einem PDF (Textebene, keine OCR).
abstract class PdfTextReader {
  /// Liefert den Text aller Seiten, Zeilen mit \n getrennt. Wirft [PdfReadException], wenn die Datei kein lesbares PDF ist.
  Future<String> readText(Uint8List bytes);
}

class PdfReadException implements Exception {
  PdfReadException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Umsetzung mit pdfrx (PDFium). PDFium liefert den Text der digitalen Billa-Bons mit einfachen Leerzeichen und
/// CRLF-Zeilenenden, so wie es der Parser erwartet (in Phase 2 an sechs echten Bons geprueft).
class PdfrxTextReader implements PdfTextReader {
  const PdfrxTextReader();

  @override
  Future<String> readText(Uint8List bytes) async {
    PdfDocument? doc;
    try {
      doc = await PdfDocument.openData(bytes, sourceName: 'bon.pdf');
      final buffer = StringBuffer();
      for (final page in doc.pages) {
        final text = await page.loadText();
        if (text != null) buffer.writeln(text.fullText);
      }
      final result = buffer.toString();
      if (result.trim().isEmpty) {
        throw PdfReadException('Im PDF wurde kein Text gefunden. Es ist vermutlich ein Foto oder Scan.');
      }
      return result;
    } on PdfReadException {
      rethrow;
    } catch (e) {
      throw PdfReadException('Die Datei konnte nicht als PDF gelesen werden.');
    } finally {
      await doc?.dispose();
    }
  }
}
