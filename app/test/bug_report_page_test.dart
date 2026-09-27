import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/features/bugreport/bug_report_list_page.dart';
import 'package:einkaufstracker/features/bugreport/bug_report_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  Widget app() => ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          bugReportRepositoryProvider.overrideWithValue(bugReportRepo(db)),
          pendingChangesProvider.overrideWith((ref) => Stream.value(0)),
          bugReportsStreamProvider.overrideWith((ref) => Stream.value(const <BugReport>[])),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(initialLocation: '/', routes: [
            GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('START'))),
            GoRoute(path: '/bug-report', builder: (_, _) => const BugReportPage()),
            GoRoute(path: '/bug-reports', builder: (_, _) => const BugReportListPage()),
            GoRoute(
              path: '/bug-reports/detail',
              builder: (_, s) => BugReportDetailPage(report: s.extra as BugReport),
            ),
          ]),
        ),
      );

  testWidgets('Ohne Titel: Fehlermeldung, nichts wird gespeichert', (tester) async {
    await tester.pumpWidget(app());
    tester.view.physicalSize = const Size(1080, 3400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('START'))).push('/bug-report');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bug-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Bitte einen kurzen Titel eingeben.'), findsOneWidget);
    expect(await db.select(db.bugReports).get(), isEmpty);
  });

  testWidgets('Ausfuellen und Speichern legt einen Bericht mit Datenausschnitt an', (tester) async {
    await tester.pumpWidget(app());
    tester.view.physicalSize = const Size(1080, 3400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('START'))).push('/bug-report');
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('bug-title')), 'Scan legt Duplikat an');
    await tester.enterText(find.byKey(const Key('bug-happened')), 'Barcode gescannt, Produkt doppelt.');
    await tester.tap(find.byKey(const Key('bug-submit')));
    await tester.pumpAndSettle();

    final report = await db.select(db.bugReports).getSingle();
    expect(report.title, 'Scan legt Duplikat an');
    expect(report.description, contains('Barcode gescannt'));
    expect(report.dataSnapshot, isNotNull); // Haken war per Vorgabe an
    expect(find.text('START'), findsOneWidget); // zurueck
  });

  testWidgets('Ohne Datenausschnitt-Haken wird keiner gespeichert', (tester) async {
    await tester.pumpWidget(app());
    tester.view.physicalSize = const Size(1080, 3400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('START'))).push('/bug-report');
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('bug-title')), 'x');
    await tester.tap(find.byKey(const Key('bug-snapshot')));
    await tester.tap(find.byKey(const Key('bug-submit')));
    await tester.pumpAndSettle();

    final report = await db.select(db.bugReports).getSingle();
    expect(report.dataSnapshot, isNull);
  });

  testWidgets('Liste ohne Berichte: Hinweistext', (tester) async {
    await tester.pumpWidget(app());
    tester.view.physicalSize = const Size(1080, 3400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('START'))).push('/bug-reports');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bug-list-empty')), findsOneWidget);
  });

  testWidgets('Liste mit einem Bericht, Detail zeigt den technischen Stand und laesst kopieren', (tester) async {
    final report = await bugReportRepo(db).create(title: 'Erster Bericht', appInfo: const {'platform': 'android'}, description: 'Details hier');

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        bugReportRepositoryProvider.overrideWithValue(bugReportRepo(db)),
        bugReportsStreamProvider.overrideWith((ref) => Stream.value([report])),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(initialLocation: '/', routes: [
          GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('START'))),
          GoRoute(path: '/bug-reports', builder: (_, _) => const BugReportListPage()),
          GoRoute(path: '/bug-reports/detail', builder: (_, s) => BugReportDetailPage(report: s.extra as BugReport)),
        ]),
      ),
    ));
    tester.view.physicalSize = const Size(1080, 3400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('START'))).push('/bug-reports');
    await tester.pumpAndSettle();
    expect(find.text('Erster Bericht'), findsOneWidget);

    await tester.tap(find.text('Erster Bericht'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Details hier'), findsOneWidget);
    expect(find.textContaining('platform'), findsOneWidget);

    expect(find.byKey(const Key('bug-copy')), findsOneWidget); // Kopieren ist verfuegbar
    expect(reportAsText(report), contains('Erster Bericht'));
    expect(reportAsText(report), contains('Details hier'));
    expect(reportAsText(report), contains('"platform": "android"'));
  });
}
