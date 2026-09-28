import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Testet `rescheduleExpiryReminders` (Doku 06 §5): liest aktiven Bestand und Einstellungen, plant ueber
/// den [NotificationScheduler] neu. Der echte Scheduler (`flutter_local_notifications`) braucht Plattform-
/// Kanaele, die es in `flutter test` nicht gibt, deshalb eine Attrappe (siehe support/fakes.dart).
void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  testWidgets('liest aktiven Bestand und Einstellungen, plant ueber den Scheduler', (tester) async {
    final product = await productRepo(db).create(name: 'Vollmilch', baseUnit: 'l');
    await inventoryRepo(db).recordFromScan(
      productId: product.id,
      ean: '1',
      bestBefore: DateTime.utc(2026, 9, 28),
      now: DateTime.utc(2026, 9, 27),
    );
    final scheduler = FakeNotificationScheduler();
    late WidgetRef ref;

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        householdIdProvider.overrideWith((r) async => 'h1'),
        settingsRepositoryProvider.overrideWithValue(
          FakeSettingsRepository(const HouseholdSettings(notifyTime: '07:30', notifyLeadDays: 1, allowCloudOcr: false, keepReceiptImages: true)),
        ),
        inventoryRepositoryProvider.overrideWithValue(inventoryRepo(db)),
        productRepositoryProvider.overrideWithValue(productRepo(db)),
        notificationSchedulerProvider.overrideWithValue(scheduler),
      ],
      child: MaterialApp(home: Consumer(builder: (context, r, _) {
        ref = r;
        return const SizedBox();
      })),
    ));
    await tester.pumpAndSettle();

    await rescheduleExpiryReminders(ref, now: DateTime.utc(2026, 9, 27));

    expect(scheduler.lastScheduled, isNotNull);
    expect(scheduler.lastScheduled!.single.productNames, ['Vollmilch']);
    expect(scheduler.lastNotifyTime, '07:30');
    expect(scheduler.lastLeadDays, 1);
  });

  testWidgets('bezieht auch noch unbestaetigte Bon-Vorschlaege mit ein (Fehlerbericht "keine '
      'Push-Benachrichtigung", 2026-09-28)', (tester) async {
    final product = await productRepo(db).create(name: 'Vollmilch', baseUnit: 'l');
    await inventoryRepo(db).createSuggestionFromReceipt(
      productId: product.id,
      receiptItemId: 'ri1',
      quantity: 1,
      unit: 'l',
      purchasedOn: DateTime.utc(2026, 9, 27),
      sealedShelfLifeDays: 1, // Ablauf 2026-09-28
    );
    final scheduler = FakeNotificationScheduler();
    late WidgetRef ref;

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        householdIdProvider.overrideWith((r) async => 'h1'),
        settingsRepositoryProvider.overrideWithValue(
          FakeSettingsRepository(const HouseholdSettings(notifyTime: '07:30', notifyLeadDays: 1, allowCloudOcr: false, keepReceiptImages: true)),
        ),
        inventoryRepositoryProvider.overrideWithValue(inventoryRepo(db)),
        productRepositoryProvider.overrideWithValue(productRepo(db)),
        notificationSchedulerProvider.overrideWithValue(scheduler),
      ],
      child: MaterialApp(home: Consumer(builder: (context, r, _) {
        ref = r;
        return const SizedBox();
      })),
    ));
    await tester.pumpAndSettle();

    await rescheduleExpiryReminders(ref, now: DateTime.utc(2026, 9, 27));

    expect(scheduler.lastScheduled, isNotNull);
    expect(scheduler.lastScheduled!.single.productNames, ['Vollmilch']);
  });

  testWidgets('ohne Haushalt: kein Absturz, Scheduler wird nicht aufgerufen', (tester) async {
    final scheduler = FakeNotificationScheduler();
    late WidgetRef ref;

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        householdIdProvider.overrideWith((r) async => null),
        notificationSchedulerProvider.overrideWithValue(scheduler),
      ],
      child: MaterialApp(home: Consumer(builder: (context, r, _) {
        ref = r;
        return const SizedBox();
      })),
    ));
    await tester.pumpAndSettle();

    await rescheduleExpiryReminders(ref);
    expect(scheduler.lastScheduled, isNull);
  });

  testWidgets('Einstellungen nicht erreichbar (offline): kein Absturz, Scheduler wird nicht aufgerufen', (tester) async {
    final scheduler = FakeNotificationScheduler();
    late WidgetRef ref;

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        householdIdProvider.overrideWith((r) async => 'h1'),
        settingsRepositoryProvider.overrideWith((r) => _ThrowingSettingsRepository()),
        notificationSchedulerProvider.overrideWithValue(scheduler),
      ],
      child: MaterialApp(home: Consumer(builder: (context, r, _) {
        ref = r;
        return const SizedBox();
      })),
    ));
    await tester.pumpAndSettle();

    await rescheduleExpiryReminders(ref);
    expect(scheduler.lastScheduled, isNull);
  });
}

class _ThrowingSettingsRepository implements SettingsRepository {
  @override
  Future<HouseholdSettings> load(String householdId) async => throw Exception('kein Netz');

  @override
  Future<void> update(String householdId, Map<String, dynamic> changes) async {}
}
