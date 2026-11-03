// Gemeinsame Seitenliste fuer test/ui_accessibility_test.dart und test/ui_layout_test.dart (Codereview 2026-10-16).
import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/settings_repository.dart';
import 'package:einkaufstracker/features/auth/login_page.dart';
import 'package:einkaufstracker/domain/nutrition/nutrition_targets.dart';
import 'package:einkaufstracker/features/home/home_shell.dart';
import 'package:einkaufstracker/features/household/accept_invite_page.dart';
import 'package:einkaufstracker/features/inventory/inventory_page.dart';
import 'package:einkaufstracker/features/settings/settings_page.dart';
import 'package:einkaufstracker/features/shopping_list/shopping_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'fakes.dart';

const _settings = HouseholdSettings(notifyTime: '07:30', notifyLeadDays: 1, allowCloudOcr: false, keepReceiptImages: true);

Product _product(String id, String name) => Product(
      id: id,
      householdId: 'h1',
      name: name,
      baseUnit: 'piece',
      defaultDateKind: 'best_before',
      defaultLocation: 'pantry',
      restock: false,
      updatedAt: DateTime.utc(2026),
    );

InventoryItem _item(String id, String productId, {DateTime? expiresOn, String status = 'sealed'}) => InventoryItem(
      id: id,
      householdId: 'h1',
      productId: productId,
      quantity: 1,
      unit: 'piece',
      location: 'fridge',
      dateKind: 'best_before',
      status: status,
      isSuggestion: false,
      expiresOn: expiresOn,
      updatedAt: DateTime.utc(2026),
    );

ShoppingListItem _listItem(String id, {String? productId, String? freeText, double quantity = 1}) => ShoppingListItem(
      id: id,
      householdId: 'h1',
      listId: 'l1',
      productId: productId,
      freeText: freeText,
      quantity: quantity,
      unit: 'piece',
      checked: false,
      source: 'manual',
      isSuggestion: false,
      updatedAt: DateTime.utc(2026),
    );

/// Die Hauptnavigation mit allen fuenf Tabs und der Seite "Scannen"; weitere Ziele zeigen nur ihren Pfad.
GoRouter homeShellRouter({String location = '/'}) => GoRouter(initialLocation: location, routes: [
      homeShellRoute(),
      scanRoute(),
      for (final path in ['/settings', '/recipe-suggestions', '/journal', '/nutrition-targets', '/trend'])
        GoRoute(path: path, builder: (_, _) => Scaffold(body: Text('ZIEL $path'))),
    ]);

/// Alles, was die fuenf Tabs lesen, als feste Momentaufnahme (Drift-Streams liessen sonst Timer offen).
List<Override> homeShellOverrides(AppDatabase db) => [
      databaseProvider.overrideWithValue(db),
      householdSettingsProvider.overrideWith((ref) async => _settings),
      householdPrefsOnceProvider.overrideWith((ref) async => const <String, Object?>{}),
      householdPrefsProvider.overrideWith((ref) => Stream.value(const <String, Object?>{})),
      receiptsStreamProvider.overrideWith((ref) => Stream.value(const <Receipt>[])),
      storesStreamProvider.overrideWith((ref) => Stream.value(const <Store>[])),
      allItemsStreamProvider.overrideWith((ref) => Stream.value(const <ReceiptItem>[])),
      categoriesStreamProvider.overrideWith((ref) => Stream.value(const <Category>[])),
      productsStreamProvider.overrideWith((ref) => Stream.value([_product('p1', 'Vollmilch')])),
      productRepositoryProvider.overrideWithValue(productRepo(db)),
      inventoryRepositoryProvider.overrideWithValue(inventoryRepo(db)),
      activeInventoryStreamProvider.overrideWith((ref) => Stream.value([_item('i1', 'p1', expiresOn: DateTime.utc(2026, 9, 28))])),
      inventorySuggestionsStreamProvider.overrideWith((ref) => Stream.value(const <InventoryItem>[])),
      balanceMovementsProvider.overrideWith((ref) => Stream.value(const <InventoryMovement>[])),
      usageForecastProvider.overrideWithValue(const {}),
      shoppingListRepositoryProvider.overrideWithValue(shoppingListRepo(db)),
      shoppingListItemsStreamProvider.overrideWith((ref) => Stream.value([_listItem('s1', freeText: 'Brot')])),
      shoppingListsStreamProvider.overrideWith((ref) => Stream.value([
            ShoppingList(id: 'l1', householdId: 'h1', name: 'Einkaufsliste', isDefault: true, updatedAt: DateTime.utc(2026)),
          ])),
      mealsStreamProvider.overrideWith((ref) => Stream.value(const <Meal>[])),
      mealIngredientsStreamProvider.overrideWith((ref) => Stream.value(const <MealIngredient>[])),
      nutritionTargetsProvider.overrideWith((ref) => Stream.value(const NutritionTargets())),
    ];

/// Eine zu pruefende Seite: Name fuer die Testausgabe und wie sie aufgebaut wird (eigene Datenbank je Test).
typedef UiPage = ({String name, Widget Function(AppDatabase db) build});

Widget _routed(Widget page, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(routerConfig: GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => page)])),
    );

/// Seiten, die die Querschnittstests (Barrierefreiheit, Layout) pruefen, mit typischen Daten (lange Namen, mehrere
/// Eintraege, wartende Aenderungen). Neue Hauptseiten gehoeren hier dazu.
final uiQualityPages = <UiPage>[
  (
    name: 'Hauptnavigation, Übersicht',
    build: (db) => ProviderScope(overrides: homeShellOverrides(db), child: MaterialApp.router(routerConfig: homeShellRouter())),
  ),
  (
    // der Tab mit den meisten Aktionen in der Kopfzeile
    name: 'Hauptnavigation, Tagebuch',
    build: (db) => ProviderScope(
          overrides: homeShellOverrides(db),
          child: MaterialApp.router(routerConfig: homeShellRouter(location: '/diary')),
        ),
  ),
  (
    name: 'Anmeldung',
    build: (db) => _routed(const LoginPage(), [authRepositoryProvider.overrideWithValue(FakeAuth())]),
  ),
  (
    name: 'Einladung annehmen',
    build: (db) => _routed(const AcceptInvitePage(), [
          acceptInviteApiProvider.overrideWithValue(FakeAcceptInviteApi()),
          authRepositoryProvider.overrideWithValue(FakeAuth()),
        ]),
  ),
  (
    name: 'Einstellungen',
    build: (db) => _routed(const SettingsPage(), [
          householdIdProvider.overrideWith((r) async => 'h1'),
          settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository(_settings)),
          authRepositoryProvider.overrideWithValue(FakeAuth()),
          databaseProvider.overrideWithValue(db),
          pendingChangesProvider.overrideWith((ref) => Stream.value(3)),
          householdPrefsOnceProvider.overrideWith((ref) async => const <String, Object?>{}),
          appVersionProvider.overrideWith((ref) async => '1.15.0 (37)'),
        ]),
  ),
  (
    name: 'Inventar',
    build: (db) {
      final products = [_product('p1', 'Vollmilch 3,5 % Fett, laktosefrei, 1 Liter Packung'), _product('p2', 'Joghurt')];
      return _routed(Scaffold(body: InventoryPage(now: DateTime.utc(2026, 9, 27))), [
        databaseProvider.overrideWithValue(db),
        inventoryRepositoryProvider.overrideWithValue(inventoryRepo(db)),
        activeInventoryStreamProvider.overrideWith((ref) => Stream.value([
              _item('i1', 'p1', expiresOn: DateTime.utc(2026, 9, 28)),
              _item('i2', 'p2', expiresOn: DateTime.utc(2026, 9, 20), status: 'opened'),
            ])),
        inventorySuggestionsStreamProvider.overrideWith((ref) => Stream.value(const <InventoryItem>[])),
        productsStreamProvider.overrideWith((ref) => Stream.value(products)),
        householdPrefsProvider.overrideWith((ref) => Stream.value(const <String, Object?>{})),
        inventoryMovementsStreamProvider.overrideWith((ref, _) => Stream.value(const <InventoryMovement>[])),
        balanceMovementsProvider.overrideWith((ref) => Stream.value(const <InventoryMovement>[])),
        productRepositoryProvider.overrideWithValue(productRepo(db)),
      ]);
    },
  ),
  (
    name: 'Einkaufsliste',
    build: (db) => ProviderScope(
          overrides: [
            allItemsStreamProvider.overrideWith((ref) => Stream.value(const <ReceiptItem>[])),
            receiptsStreamProvider.overrideWith((ref) => Stream.value(const <Receipt>[])),
            databaseProvider.overrideWithValue(db),
            shoppingListRepositoryProvider.overrideWithValue(shoppingListRepo(db)),
            productRepositoryProvider.overrideWithValue(productRepo(db)),
            shoppingListItemsStreamProvider.overrideWith((ref) => Stream.value([
                  _listItem('s1', productId: 'p1', quantity: 2),
                  _listItem('s2', freeText: 'Sehr langer Freitext-Eintrag für die Einkaufsliste mit vielen Wörtern'),
                ])),
            shoppingListsStreamProvider.overrideWith((ref) => Stream.value([
                  ShoppingList(id: 'l1', householdId: 'h1', name: 'Einkaufsliste', isDefault: true, updatedAt: DateTime.utc(2026)),
                ])),
            usageForecastProvider.overrideWithValue(const {}),
            storesStreamProvider.overrideWith((ref) => Stream.value(const <Store>[])),
            productsStreamProvider.overrideWith((ref) => Stream.value([_product('p1', 'Vollmilch')])),
            categoriesStreamProvider.overrideWith((ref) => Stream.value(const <Category>[])),
          ],
          child: const MaterialApp(home: ShoppingListPage()),
        ),
  ),
];

/// Simuliert ein Geraet: logische Groesse (bei 3-facher Pixeldichte) und Schriftgroesse der Systemeinstellung.
void useDevice(WidgetTester tester, Size logical, {double textScale = 1}) {
  tester.view.physicalSize = logical * 3;
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}
