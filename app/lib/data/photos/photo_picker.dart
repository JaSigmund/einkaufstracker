import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// Foto fuer eine Mahlzeit aufnehmen ([camera] true) oder aus der Galerie waehlen. `null`, wenn der Nutzer abbricht.
///
/// image_picker oeffnet im Browser einen Datei-Dialog (auf Mobilgeraeten mit Kamera-Vorauswahl), deshalb funktioniert
/// das auch in der PWA. Das Timeout faengt Browser ab, die das Abbrechen des Dialogs nicht zuverlaessig melden
/// (gleiche Begruendung wie beim Bon-Scan), sonst bliebe die Seite fuer immer in "Foto wird geladen".
typedef MealPhotoPicker = Future<Uint8List?> Function({required bool camera});

Future<Uint8List?> pickMealPhoto({required bool camera}) async {
  final file = await ImagePicker()
      .pickImage(source: camera ? ImageSource.camera : ImageSource.gallery, imageQuality: 90)
      .timeout(const Duration(minutes: 3), onTimeout: () => null);
  return file?.readAsBytes();
}
