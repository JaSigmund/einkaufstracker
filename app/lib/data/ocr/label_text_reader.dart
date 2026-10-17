import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/clock.dart';

/// Liest den Text eines Foto-Etiketts auf dem Geraet (Ausbau 1.14, MHD-Foto). Als Schnittstelle, damit Tests eine Attrappe einsetzen koennen
/// (die Texterkennung braucht Plattform-Kanaele, die es in `flutter test` nicht gibt).
abstract class LabelTextReader {
  /// Der erkannte Text, `null` wenn nichts erkannt wurde oder die Erkennung nicht moeglich ist.
  Future<String?> read(Uint8List image);
}

/// ML-Kit-Texterkennung (lateinische Schrift), vollstaendig auf dem Geraet: das Foto verlaesst das Telefon nicht.
class MlKitLabelTextReader implements LabelTextReader {
  @override
  Future<String?> read(Uint8List image) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    File? file;
    try {
      final dir = await getTemporaryDirectory();
      file = File('${dir.path}/etikett-${appClock.now().microsecondsSinceEpoch}.jpg');
      await file.writeAsBytes(image, flush: true);
      final text = await recognizer.processImage(InputImage.fromFilePath(file.path));
      final result = text.text.trim();
      return result.isEmpty ? null : result;
    } catch (_) {
      return null;
    } finally {
      await recognizer.close();
      try {
        await file?.delete();
      } catch (_) {}
    }
  }
}
