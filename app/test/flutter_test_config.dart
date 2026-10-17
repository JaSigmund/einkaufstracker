// Zeitreise fuer die ganze Suite (Codereview 2026-10-16, B1): mit --dart-define=TEST_CLOCK_OFFSET_DAYS=N laeuft jeder Test,
// als waere heute N Tage spaeter. So fallen Tests auf, die ein festes Datum gegen die echte Uhr pruefen und erst in
// einigen Wochen rot wuerden. Voraussetzung: App und Tests lesen die Zeit ueber `appClock` (lib/core/clock.dart);
// test/architecture_test.dart prueft das.
import 'dart:async';

import 'package:einkaufstracker/core/clock.dart';

const testClockOffsetDays = int.fromEnvironment('TEST_CLOCK_OFFSET_DAYS');

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  appClockOffset = const Duration(days: testClockOffsetDays);
  await testMain();
}
