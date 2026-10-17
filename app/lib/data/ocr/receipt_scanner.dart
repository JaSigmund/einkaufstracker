import '../../domain/ocr/row_cluster.dart';

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
