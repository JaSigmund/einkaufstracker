import 'dart:io';
import 'dart:ui' show Rect;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

import 'row_cluster.dart';

/// Zweiter OCR-Durchgang nur auf der rechten Preisspalte: ausschneiden, Graustufen,
/// Kontrast erhoehen, vergroessern. Hintergrund: Auf einem echten Billa-Foto fehlten im
/// ersten Durchgang 6 von 15 Preisen, obwohl sie im Bild lesbar waren.
Future<List<OcrLine>> recognizePriceColumn(
  TextRecognizer recognizer,
  String imagePath,
  String tmpPath, {
  double fromX = 0.6,
  double scale = 2.0,
}) async {
  final decoded = img.decodeImage(await File(imagePath).readAsBytes());
  if (decoded == null) return [];
  final x0 = (decoded.width * fromX).round();
  var crop = img.copyCrop(decoded, x: x0, y: 0, width: decoded.width - x0, height: decoded.height);
  crop = img.grayscale(crop);
  crop = img.adjustColor(crop, contrast: 1.4);
  crop = img.copyResize(crop, width: (crop.width * scale).round(), interpolation: img.Interpolation.cubic);
  await File(tmpPath).writeAsBytes(img.encodeJpg(crop, quality: 92));

  final rec = await recognizer.processImage(InputImage.fromFilePath(tmpPath));
  return [
    for (final b in rec.blocks)
      for (final l in b.lines)
        OcrLine(
          l.text,
          Rect.fromLTRB(
            x0 + l.boundingBox.left / scale,
            l.boundingBox.top / scale,
            x0 + l.boundingBox.right / scale,
            l.boundingBox.bottom / scale,
          ),
          confidence: l.confidence,
          secondPass: true,
        ),
  ];
}

/// Uebernimmt Preiszeilen aus dem zweiten Durchgang, die im ersten nicht vorhanden sind.
List<OcrLine> mergeSecondPass(List<OcrLine> first, List<OcrLine> second) {
  final existing = first.where((l) => isPriceText(l.text)).toList();
  final added = <OcrLine>[];
  for (final s in second.where((l) => isPriceText(l.text))) {
    final duplicate = existing.any((f) =>
        (f.box.center.dy - s.box.center.dy).abs() < f.box.height * 0.6 && (f.box.center.dx - s.box.center.dx).abs() < 80);
    if (!duplicate) added.add(s);
  }
  return [...first, ...added];
}
