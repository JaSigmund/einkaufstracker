import 'dart:convert';
import 'dart:io';

import 'package:einkaufstracker/features/settings/settings_page.dart';
import 'package:flutter_test/flutter_test.dart';

/// CSV-Export teilen (Codereview-Fund 2026-10-16): im Browser ohne Datei im Temp-Ordner, auf dem Handy wie bisher.
void main() {
  const csv = 'Datum;Artikel;Betrag\n2026-10-01;Milch;1,29\n';

  test('Web: Datei kommt direkt aus dem Speicher, mit Namen und MIME-Typ, ohne Temp-Ordner', () async {
    final params = await csvShareParams(csv, web: true, tempDir: () => throw StateError('kein Temp-Ordner im Browser'));
    final file = params.files!.single;
    expect(utf8.decode(await file.readAsBytes()), csv);
    expect(file.mimeType, 'text/csv');
    expect(params.fileNameOverrides, ['einkaufstracker_export.csv']);
  });

  test('Handy: Datei im Temp-Ordner, Inhalt unveraendert', () async {
    final dir = Directory.systemTemp.createTempSync('csv');
    addTearDown(() => dir.deleteSync(recursive: true));
    final params = await csvShareParams(csv, web: false, tempDir: () async => dir);
    final path = params.files!.single.path;
    expect(path, '${dir.path}/einkaufstracker_export.csv');
    expect(File(path).readAsStringSync(), csv);
  });
}
