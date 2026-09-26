import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Laengste Kante fuer die Cloud (Doku 05 §3.1): genug fuer Bon-Schrift, klein genug fuer Kosten und Latenz.
const cloudMaxEdge = 1568;

/// Obergrenze je Bild, die die Edge Function annimmt (1,5 MB) mit etwas Luft.
const cloudMaxBytes = 1400000;

/// Bereitet ein Foto fuer die Cloud auf: alles ab [cutY] abschneiden (Zahlungsblock, Go/No-Go B4), auf
/// [cloudMaxEdge] verkleinern, als JPEG kodieren. Laeuft in einem eigenen Isolate, damit die Oberflaeche nicht ruckelt.
Future<Uint8List> prepareForCloud(String imagePath, {double? cutY}) async {
  final bytes = await File(imagePath).readAsBytes();
  return Isolate.run(() => prepareForCloudBytes(bytes, cutY: cutY));
}

/// Laengste Kante und Groessengrenze fuer das abgelegte Belegfoto (besser lesbar als das Cloud-Bild).
const storageMaxEdge = 2200;
const storageMaxBytes = 2500000;

/// Bereitet ein Foto zum Ablegen auf: wie [prepareForCloud], aber in hoeherer Qualitaet.
Future<Uint8List> prepareForStorage(String imagePath, {double? cutY}) async {
  final bytes = await File(imagePath).readAsBytes();
  return Isolate.run(() => prepareForCloudBytes(bytes, cutY: cutY, maxEdge: storageMaxEdge, maxBytes: storageMaxBytes));
}

/// Wie [prepareForCloud], auf Bytes (testbar ohne Dateien).
Uint8List prepareForCloudBytes(Uint8List bytes, {double? cutY, int maxEdge = cloudMaxEdge, int maxBytes = cloudMaxBytes}) {
  img.Image? image;
  try {
    image = img.decodeJpg(bytes);
  } catch (_) {
    image = null;
  }
  if (image == null) throw const FormatException('Bild konnte nicht gelesen werden');
  image = img.bakeOrientation(image);

  if (cutY != null) {
    final h = cutY.round().clamp(1, image.height);
    image = img.copyCrop(image, x: 0, y: 0, width: image.width, height: h);
  }
  final longest = image.width > image.height ? image.width : image.height;
  if (longest > maxEdge) {
    image = image.width >= image.height
        ? img.copyResize(image, width: maxEdge, interpolation: img.Interpolation.average)
        : img.copyResize(image, height: maxEdge, interpolation: img.Interpolation.average);
  }
  for (final quality in const [80, 70, 60, 50]) {
    final out = Uint8List.fromList(img.encodeJpg(image, quality: quality));
    if (out.length <= maxBytes) return out;
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 40));
}
