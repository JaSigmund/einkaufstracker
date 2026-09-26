import 'dart:typed_data';

import 'package:einkaufstracker/data/ocr/image_prep.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _jpeg(int w, int h) {
  final image = img.Image(width: w, height: h);
  // oben weiss, unten schwarz: so laesst sich pruefen, dass der untere Teil fehlt
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  img.fillRect(image, x1: 0, y1: h ~/ 2, x2: w, y2: h, color: img.ColorRgb8(0, 0, 0));
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

void main() {
  test('Grosses Bild wird auf 1568 px Kantenlaenge verkleinert, Seitenverhaeltnis bleibt', () {
    final out = img.decodeJpg(prepareForCloudBytes(_jpeg(1200, 3200)))!;
    expect(out.height, cloudMaxEdge);
    expect(out.width, closeTo(1200 * cloudMaxEdge / 3200, 1));
  });

  test('Kleines Bild wird nicht vergroessert', () {
    final out = img.decodeJpg(prepareForCloudBytes(_jpeg(600, 900)))!;
    expect((out.width, out.height), (600, 900));
  });

  test('cutY schneidet alles darunter ab (Zahlungsblock verlaesst das Geraet nicht)', () {
    // schwarze Haelfte beginnt bei y = 1000; Schnitt bei 900 -> das Ergebnis ist komplett weiss
    final out = img.decodeJpg(prepareForCloudBytes(_jpeg(800, 2000), cutY: 900))!;
    expect(out.height, 900);
    for (final y in [0, 450, 899]) {
      expect(out.getPixel(400, y).r, greaterThan(230), reason: 'Zeile $y muss weiss sein');
    }
  });

  test('cutY ausserhalb des Bildes wird begrenzt', () {
    final out = img.decodeJpg(prepareForCloudBytes(_jpeg(400, 600), cutY: 5000))!;
    expect(out.height, 600);
  });

  test('Ergebnis bleibt unter der Groessengrenze der Edge Function', () {
    // verrauschtes Bild: schwer zu komprimieren
    final noisy = img.Image(width: 1500, height: 2500);
    var seed = 7;
    for (final p in noisy) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      p.setRgb(seed & 255, (seed >> 8) & 255, (seed >> 16) & 255);
    }
    final out = prepareForCloudBytes(Uint8List.fromList(img.encodeJpg(noisy, quality: 95)));
    expect(out.length, lessThanOrEqualTo(1500000));
  });

  test('Kein JPEG: klare Fehlermeldung', () {
    expect(() => prepareForCloudBytes(Uint8List.fromList([1, 2, 3])), throwsFormatException);
  });
}
