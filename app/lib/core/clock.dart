import 'package:clock/clock.dart';

/// Zeitquelle fuer App und Tests statt `DateTime.now()` (Codereview 2026-10-16, B1). Folgt der Uhr von package:clock
/// (`withClock`, in testWidgets die FakeAsync-Uhr) und dazu dem Versatz [appClockOffset], mit dem der Zeitreise-Lauf
/// die ganze Testsuite in die Zukunft verlegt (test/flutter_test_config.dart). Ein Zonenwert reicht dafuer nicht:
/// package:test fuehrt die Testkoerper nicht in der Zone aus, in der sie deklariert wurden.
final appClock = Clock(() => clock.now().add(appClockOffset));

/// Nur fuer Tests; in der App immer null.
var appClockOffset = Duration.zero;
