import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/household_prefs_repository.dart';
import 'package:einkaufstracker/data/repositories/settings_repository.dart';
import 'package:einkaufstracker/domain/notifications/expiry_stages.dart';
import 'package:einkaufstracker/features/inventory/inventory_item_detail_page.dart';
import 'package:einkaufstracker/features/settings/expiry_stages_dialog.dart';
import 'package:einkaufstracker/features/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';

/// Oberflaeche der mehrstufigen Ablauf-Erinnerungen: Dialog, Einstellungen und Produkt (Ausbau 1.14).
const _settings = HouseholdSettings(notifyTime: '07:30', notifyLeadDays: 1, allowCloudOcr: false, keepReceiptImages: true);

void pageTest(String name, Future<void> Function(WidgetTester tester) body) => testWidgets(name, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

void main() {
  late AppDatabase db;
  late HouseholdPrefsRepository prefs;
  late FakeNotificationScheduler scheduler;

  setUp(() {
    db = memoryDb();
    prefs = HouseholdPrefsRepository(db, householdId: () async => 'h1');
    scheduler = FakeNotificationScheduler();
  });
  tearDown(() => db.close());

  List<Override> base() => [
        databaseProvider.overrideWithValue(db),
        householdIdProvider.overrideWith((r) async => 'h1'),
        settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository(_settings)),
        inventoryRepositoryProvider.overrideWithValue(inventoryRepo(db)),
        productRepositoryProvider.overrideWithValue(productRepo(db)),
        householdPrefsRepositoryProvider.overrideWithValue(prefs),
        notificationSchedulerProvider.overrideWithValue(scheduler),
        pendingChangesProvider.overrideWith((ref) => Stream.value(0)),
      ];

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('Dialog', () {
    List<int>? result;
    var closed = false;

    Future<void> open(WidgetTester tester, {List<int> initial = const [1], bool inherit = false}) async {
      tall(tester);
      result = null;
      closed = false;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showExpiryStagesDialog(context, initial: initial, title: 'Wann erinnern?', allowInherit: inherit);
                closed = true;
              },
              child: const Text('OEFFNEN'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('OEFFNEN'));
      await tester.pumpAndSettle();
    }

    FilterChip chip(WidgetTester tester, int s) => tester.widget<FilterChip>(find.byKey(Key('stage-chip-$s')));

    pageTest('die Vorbelegung ist gewaehlt, die Zusammenfassung nennt sie', (tester) async {
      await open(tester, initial: [3, 0]);
      expect(chip(tester, 3).selected, isTrue);
      expect(chip(tester, 0).selected, isTrue);
      expect(chip(tester, 1).selected, isFalse);
      expect(tester.widget<Text>(find.byKey(const Key('stage-summary'))).data, '3 Tage vorher, am Tag selbst');
    });

    pageTest('Speichern liefert die Auswahl, groesste Vorlaufzeit zuerst', (tester) async {
      await open(tester, initial: [1]);
      await tester.tap(find.byKey(const Key('stage-chip-5')));
      await tester.tap(find.byKey(const Key('stage-chip-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('stage-ok')));
      await tester.pumpAndSettle();
      expect(result, [5, 1, 0]);
    });

    pageTest('ohne Auswahl ist Speichern gesperrt und der Hinweis sagt warum', (tester) async {
      await open(tester, initial: [1]);
      await tester.tap(find.byKey(const Key('stage-chip-1')));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.byKey(const Key('stage-ok'))).onPressed, isNull);
      expect(tester.widget<Text>(find.byKey(const Key('stage-summary'))).data, 'Wähle mindestens einen Zeitpunkt.');
    });

    pageTest('bei vier Zeitpunkten lassen sich keine weiteren waehlen, nur abwaehlen', (tester) async {
      await open(tester, initial: [7, 5, 3, 2]);
      expect(chip(tester, 1).onSelected, isNull);
      expect(chip(tester, 0).onSelected, isNull);
      expect(chip(tester, 7).onSelected, isNotNull);
      await tester.tap(find.byKey(const Key('stage-chip-7')));
      await tester.pumpAndSettle();
      expect(chip(tester, 1).onSelected, isNotNull);
    });

    pageTest('"Wie Standard" gibt es nur auf Wunsch und liefert eine leere Liste', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('stage-inherit')), findsNothing);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(closed, isTrue);

      await open(tester, inherit: true);
      await tester.tap(find.byKey(const Key('stage-inherit')));
      await tester.pumpAndSettle();
      expect(result, isEmpty);
    });
  });

  group('Einstellungen', () {
    Future<void> openSettings(WidgetTester tester) async {
      tall(tester);
      await tester.pumpWidget(ProviderScope(
        overrides: [...base(), authRepositoryProvider.overrideWithValue(FakeAuth())],
        child: MaterialApp.router(routerConfig: GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => const SettingsPage())])),
      ));
      await tester.pumpAndSettle();
    }

    String subtitle(WidgetTester tester) {
      final tile = tester.widget<ListTile>(find.byKey(const Key('settings-reminder-stages')));
      return (tile.subtitle! as Text).data!;
    }

    pageTest('ohne Auswahl zeigt die Zeile die bisherige Vorlaufzeit', (tester) async {
      await openSettings(tester);
      expect(subtitle(tester), '1 Tag vorher');
    });

    pageTest('Auswahl speichern: gemeinsame Einstellung, Anzeige aktualisiert, Erinnerungen werden neu geplant', (tester) async {
      await db.into(db.products).insert(ProductsCompanion.insert(id: 'p1', householdId: 'h1', name: 'Milch', updatedAt: DateTime.utc(2026)));
      await openSettings(tester);
      await tester.tap(find.byKey(const Key('settings-reminder-stages')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('stage-chip-3')));
      await tester.tap(find.byKey(const Key('stage-chip-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('stage-ok')));
      await tester.pumpAndSettle();

      expect((await prefs.load())[expiryStagesPref], [3, 1, 0]);
      expect(subtitle(tester), '3 Tage und 1 Tag vorher, am Tag selbst');
      expect(scheduler.lastScheduled, isNotNull, reason: 'die Planung lief nach dem Speichern neu');
    });

    pageTest('Abbrechen aendert nichts', (tester) async {
      await openSettings(tester);
      await tester.tap(find.byKey(const Key('settings-reminder-stages')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(await prefs.load(), isEmpty);
    });
  });

  group('Produkt im Bestand', () {
    InventoryItem item() => InventoryItem(
          id: 'i1', householdId: 'h1', productId: 'p1', quantity: 1, unit: 'piece', location: 'pantry', dateKind: 'best_before', status: 'sealed',
          isSuggestion: false, updatedAt: DateTime.utc(2026),
        );

    Product product() => Product(
          id: 'p1', householdId: 'h1', name: 'Milch', baseUnit: 'piece', defaultDateKind: 'best_before', defaultLocation: 'pantry', restock: false, updatedAt: DateTime.utc(2026),
        );

    Future<void> openDetail(WidgetTester tester) async {
      tall(tester);
      await tester.pumpWidget(ProviderScope(
        overrides: [...base(), inventoryMovementsStreamProvider.overrideWith((ref, _) => Stream.value(const <InventoryMovement>[]))],
        child: MaterialApp.router(routerConfig: GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => InventoryItemDetailPage(item: item(), product: product()))])),
      ));
      await tester.pumpAndSettle();
    }

    String subtitle(WidgetTester tester) => (tester.widget<ListTile>(find.byKey(const Key('item-reminder-stages'))).subtitle! as Text).data!;

    pageTest('ohne eigene Stufen: "Wie Standard" mit den gemeinsamen Zeitpunkten', (tester) async {
      await prefs.set(expiryStagesPref, [3, 0]);
      await openDetail(tester);
      await tester.scrollUntilVisible(find.byKey(const Key('item-reminder-stages')), 200, scrollable: find.byType(Scrollable).first);
      expect(subtitle(tester), 'Wie Standard (3 Tage vorher, am Tag selbst)');
    });

    pageTest('eigene Stufen speichern und wieder auf Standard zuruecksetzen', (tester) async {
      await openDetail(tester);
      await tester.scrollUntilVisible(find.byKey(const Key('item-reminder-stages')), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byKey(const Key('item-reminder-stages')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('stage-chip-5')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('stage-ok')));
      await tester.pumpAndSettle();
      expect((await prefs.load())[expiryStagesPrefFor('p1')], [5, 1]);
      expect(subtitle(tester), '5 Tage und 1 Tag vorher');

      await tester.tap(find.byKey(const Key('item-reminder-stages')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('stage-inherit')));
      await tester.pumpAndSettle();
      expect((await prefs.load())[expiryStagesPrefFor('p1')], isEmpty);
      expect(subtitle(tester), 'Wie Standard (1 Tag vorher)');
    });
  });
}
