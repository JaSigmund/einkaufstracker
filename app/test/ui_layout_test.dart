// Layout der Hauptseiten (Codereview 2026-10-16): auf einem kleinen Handy, mit grosser Systemschrift und auf einem
// Tablet darf nichts ueberlaufen (RenderFlex overflow). Einen Ueberlauf meldet flutter_test selbst als Fehler, mit dem
// verursachenden Widget samt Datei und Zeile; der Test muss die Seite nur in den kritischen Groessen aufbauen.
// Die Seiten selbst stehen in test/support/ui_pages.dart.
import 'dart:io';
import 'dart:typed_data';

import 'package:einkaufstracker/data/local/database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/ui_pages.dart';

/// Echte Schrift statt der Testschrift von flutter_test: dort ist jedes Zeichen ein volles Quadrat, Texte waeren rund
/// doppelt so breit wie auf dem Geraet und jeder Test schluege faelschlich an. Roboto, die Android-Standardschrift,
/// liegt fuer den PDF-Export ohnehin in den Assets.
Future<void> _loadRoboto() async {
  final loader = FontLoader('Roboto');
  for (final f in ['assets/fonts/Roboto-Regular.ttf', 'assets/fonts/Roboto-Bold.ttf']) {
    loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await loader.load();
}

void main() {
  late AppDatabase db;
  setUpAll(_loadRoboto);
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  const devices = <(String, Size, double)>[
    ('kleines Handy (320x568)', Size(320, 568), 1.0),
    ('kleines Handy, Schrift 130 %', Size(320, 568), 1.3),
    ('normales Handy, Schrift 200 %', Size(412, 915), 2.0),
    ('kleines Handy, Schrift 200 %', Size(320, 568), 2.0),
    ('Tablet quer (1280x800)', Size(1280, 800), 1.0),
  ];

  for (final page in uiQualityPages) {
    for (final (label, size, scale) in devices) {
      testWidgets('${page.name}: $label, kein Ueberlauf', (tester) async {
        useDevice(tester, size, textScale: scale);
        await tester.pumpWidget(page.build(db));
        await tester.pumpAndSettle();
      });
    }
  }
}
