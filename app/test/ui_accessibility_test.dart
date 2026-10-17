// Barrierefreiheit der Hauptseiten (Codereview 2026-10-16): beschriftete und ausreichend grosse Tippflaechen (TalkBack,
// Android-Richtwert 48 dp) und Text mit ausreichendem Kontrast (WCAG AA). Bewusst mit der Testschrift von flutter_test:
// deren Zeichen sind volle Flaechen, so misst die Kontrastpruefung die echte Textfarbe statt der Kantenglaettung einer
// duennen Schrift. Die Seiten selbst stehen in test/support/ui_pages.dart.
import 'package:einkaufstracker/data/local/database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/ui_pages.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  for (final page in uiQualityPages) {
    testWidgets('${page.name}: Tippflaechen beschriftet und gross genug, Text mit ausreichendem Kontrast', (tester) async {
      useDevice(tester, const Size(412, 915)); // typisches Android-Handy
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(page.build(db));
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantics.dispose();
    });
  }
}
