import 'dart:typed_data';

import 'package:einkaufstracker/features/receipt_import/web_photo_crop_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Codereview-Fund 2026-10-01 (Go/No-Go B4): `WebPhotoCropPage` ist der Ersatz fuer den automatischen
/// Zahlungsblock-Zuschnitt im Browser, wo es keine On-Device-Texterkennung gibt. `kIsWeb`-gated Code
/// (`ScanPage._scanPaperWeb`) selbst laesst sich ueber `flutter test` nicht erreichen (kIsWeb ist beim
/// normalen Testlauf immer false) -- diese Seite pruefen wir deshalb direkt und unabhaengig davon.
Uint8List _jpeg(int w, int h) => Uint8List.fromList(img.encodeJpg(img.Image(width: w, height: h)));

void main() {
  testWidgets('zeigt das Foto und eine Linie, Bestaetigen liefert cutY nahe der Startposition', (tester) async {
    final jpeg = _jpeg(400, 1000);
    double? result;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return ElevatedButton(
        onPressed: () async => result = await Navigator.of(context).push<double>(MaterialPageRoute(builder: (_) => WebPhotoCropPage(jpeg: jpeg))),
        child: const Text('open'),
      );
    })));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('web-crop-area')), findsOneWidget);

    await tester.tap(find.byKey(const Key('web-crop-confirm')));
    await tester.pumpAndSettle();

    // Startwert ist 60% der Bildhoehe (1000px) -> 600, siehe WebPhotoCropPage._lineFraction.
    expect(result, closeTo(600, 1));
  });

  testWidgets('Linie antippen/verschieben aendert den zurueckgegebenen Schnittpunkt', (tester) async {
    final jpeg = _jpeg(400, 1000);
    double? result;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return ElevatedButton(
        onPressed: () async => result = await Navigator.of(context).push<double>(MaterialPageRoute(builder: (_) => WebPhotoCropPage(jpeg: jpeg))),
        child: const Text('open'),
      );
    })));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final area = find.byKey(const Key('web-crop-area'));
    final topLeft = tester.getTopLeft(area);
    final size = tester.getSize(area);

    // Knapp unter dem oberen Rand antippen -> ein deutlich kleinerer cutY-Wert als der Standard (600).
    await tester.tapAt(topLeft + Offset(size.width / 2, size.height * 0.1));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('web-crop-confirm')));
    await tester.pumpAndSettle();

    expect(result, lessThan(300));
  });

  testWidgets('nicht dekodierbares Bild: Fehlermeldung statt Absturz', (tester) async {
    await tester.pumpWidget(MaterialApp(home: WebPhotoCropPage(jpeg: Uint8List.fromList([1, 2, 3]))));
    await tester.pumpAndSettle();
    expect(find.textContaining('konnte nicht gelesen werden'), findsOneWidget);
  });
}
