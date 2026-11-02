import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/cooking_session_repository.dart';
import 'package:einkaufstracker/features/recipes/cooking_timer_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  late AppDatabase db;
  late FakeNotificationScheduler scheduler;
  var sessions = <CookingSession>[];

  setUp(() {
    db = memoryDb();
    scheduler = FakeNotificationScheduler();
    sessions = [];
  });
  tearDown(() => db.close());

  Widget host({String? recipeTitle}) => ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          notificationSchedulerProvider.overrideWithValue(scheduler),
          cookingSessionRepositoryProvider.overrideWithValue(CookingSessionRepository(db, householdId: () async => 'h1')),
          cookingSessionsStreamProvider.overrideWith((ref) => Stream.value(sessions)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: const CookingTimerBanner(),
            floatingActionButton: Builder(
              builder: (context) => recipeTitle == null
                  ? FloatingActionButton(key: const Key('open'), onPressed: () => showCookingTimerPanel(context), child: const Icon(Icons.timer))
                  : CookingTimerFab(recipeTitle: recipeTitle),
            ),
          ),
        ),
      );

  /// Die Seite aushaengen, damit der Sekundentakt endet.
  void panelTest(String name, Future<void> Function(WidgetTester tester) body) => testWidgets(name, (tester) async {
        await body(tester);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 2));
      });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => pumpEventQueue());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> tap(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.tap(find.byKey(key));
    await settle(tester);
  }

  panelTest('Timer fuer zwischendurch: ohne Rezept keine Kochzeit, die Leiste zeigt ihn weiter', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();
    expect(find.byKey(const Key('timer-banner')), findsNothing);

    await tap(tester, const Key('open'));
    expect(find.byKey(const Key('timer-run-start')), findsNothing);

    await tester.enterText(find.byKey(const Key('timer-label')), 'Ofen');
    await tap(tester, const Key('timer-preset-5'));

    expect(find.descendant(of: find.byKey(const Key('kitchen-timer-0')), matching: find.text('Ofen')), findsOneWidget);
    expect(scheduler.kitchenTimers[0]!.label, 'Ofen');
    expect(find.byKey(const Key('timer-banner')), findsOneWidget);

    await tap(tester, const Key('kitchen-timer-remove-0'));
    expect(find.byKey(const Key('kitchen-timer-0')), findsNothing);
    expect(scheduler.kitchenTimers, isEmpty);
  });

  panelTest('eigene Zeit ueber den Dialog', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();
    await tap(tester, const Key('open'));
    await tap(tester, const Key('timer-custom'));
    await tester.enterText(find.byKey(const Key('timer-custom-minutes')), '7');
    await tester.pump();
    await tap(tester, const Key('timer-custom-ok'));
    expect(find.byKey(const Key('kitchen-timer-0')), findsOneWidget);
    expect(scheduler.kitchenTimers[0]!.label, 'Timer');
  });

  panelTest('Kochzeit vom Rezept aus: Start, Pause, Weiter, zu kurz wird nicht gespeichert', (tester) async {
    await tester.pumpWidget(host(recipeTitle: 'Kürbissuppe'));
    await tester.pump();
    expect(find.text('Timer'), findsOneWidget, reason: 'Knopf in Ruhe');

    await tap(tester, const Key('recipe-timer-button'));
    expect(find.text('Kochzeit: Kürbissuppe'), findsOneWidget);
    await tap(tester, const Key('timer-run-start'));
    expect(find.byKey(const Key('timer-run-clock')), findsOneWidget);
    await tap(tester, const Key('timer-run-pause'));
    await tap(tester, const Key('timer-run-resume'));
    await tap(tester, const Key('timer-run-finish'));

    expect(find.text('Unter einer Minute: nicht gespeichert.'), findsOneWidget);
    expect(find.byKey(const Key('timer-run-undo')), findsNothing);
    expect(find.byKey(const Key('timer-run-start')), findsOneWidget);
  });

  panelTest('zeigt, wie lange das Gericht bisher gedauert hat', (tester) async {
    sessions = [
      CookingSession(id: 's1', householdId: 'h1', recipeTitle: 'kürbissuppe', startedAt: DateTime.utc(2026), endedAt: DateTime.utc(2026), activeSeconds: 2520, updatedAt: DateTime.utc(2026)),
    ];
    await tester.pumpWidget(host(recipeTitle: 'Kürbissuppe'));
    await tester.pump();
    await tap(tester, const Key('recipe-timer-button'));
    expect(find.text('1× gekocht, im Schnitt 42 min'), findsOneWidget);
  });

  panelTest('Hinweis auf genaue Alarme nur, wenn sie fehlen und ein Timer laeuft', (tester) async {
    scheduler.exactAlarmsAllowed = false;
    await tester.pumpWidget(host());
    await tester.pump();
    await tap(tester, const Key('open'));
    expect(find.byKey(const Key('timer-exact-hint')), findsNothing);

    await tap(tester, const Key('timer-preset-3'));
    expect(find.byKey(const Key('timer-exact-hint')), findsOneWidget);

    scheduler.exactAlarmsAllowed = true;
    await tap(tester, const Key('timer-exact-allow'));
    expect(scheduler.exactAlarmRequests, 1);
    expect(scheduler.scheduleCalls, 2, reason: 'der laufende Timer wird jetzt genau geplant');
    expect(find.byKey(const Key('timer-exact-hint')), findsNothing);
  });
}
