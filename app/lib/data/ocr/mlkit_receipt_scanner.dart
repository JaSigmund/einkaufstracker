import 'dart:io';

import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/ocr/row_cluster.dart';
import 'receipt_scanner.dart';

/// Google-Dokumentenscanner (zuschneiden und entzerren) und ML-Kit-Texterkennung, beides auf dem Geraet.
/// Der Scanner braucht keine Kamera-Berechtigung, die Oberflaeche kommt von den Play-Diensten.
class MlKitReceiptScanner implements ReceiptScanner {
  @override
  Future<List<ScannedPage>?> scan() async {
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
      final images = result.images ?? const <String>[];
      if (images.isEmpty) return null;

      // Die Scanner-Dateien liegen im Cache der Play-Dienste: fuer die Dauer des Imports in den App-Cache kopieren
      final dir = await getTemporaryDirectory();
      final pages = <ScannedPage>[];
      for (var i = 0; i < images.length; i++) {
        final src = images[i].replaceFirst('file://', '');
        final dst = p.join(dir.path, 'bon-${DateTime.now().microsecondsSinceEpoch}-p${i + 1}.jpg');
        await File(src).copy(dst);
        final text = await recognizer.processImage(InputImage.fromFilePath(dst));
        pages.add(ScannedPage(dst, [
          for (final b in text.blocks)
            for (final l in b.lines) OcrLine(l.text, l.boundingBox),
        ]));
      }
      return pages;
    } finally {
      await recognizer.close();
      await scanner.close();
    }
  }
}
