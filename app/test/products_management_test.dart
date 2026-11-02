import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/household_prefs_repository.dart';
import 'package:einkaufstracker/features/products/product_form_page.dart';
import 'package:einkaufstracker/features/products/products_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';

/// Fehlerbericht "Alias ändern" (2026-09-27): ein Produkt liess sich bisher nur ueber den Barcode-Flow
/// oeffnen, und eine falsch gelernte Bon-Zuordnung liess sich gar nicht loesen. Testet beides: die neue
/// Produktliste (Einstiegspunkt); die Alias-Verwaltung steht seit Doku 27 auf der Produktseite (product_page_test).
///
/// Wie an anderer Stelle im Projekt ueblich: die live aus der Datenbank lesenden Stream-Provider
/// (productsStreamProvider, productAliasesStreamProvider) werden mit einer Momentaufnahme ueberschrieben,
/// sonst haelt der echte Drift-Stream `pumpAndSettle()` endlos beschaeftigt (bis zum 10-Minuten-Timeout).
void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  Widget app({List<Product> products = const [], List<ProductAlias> aliases = const []}) => ProviderScope(
        overrides: [
          productRepositoryProvider.overrideWithValue(productRepo(db)),
          categoriesStreamProvider.overrideWith((ref) => Stream.value(const <Category>[])),
          productsStreamProvider.overrideWith((ref) => Stream.value(products)),
          productAliasesStreamProvider.overrideWith((ref, _) => Stream.value(aliases)),
          householdPrefsRepositoryProvider.overrideWithValue(HouseholdPrefsRepository(db, householdId: () async => 'h1')),
          householdPrefsProvider.overrideWith((ref) => Stream.value(const <String, Object?>{})),
          allBarcodesStreamProvider.overrideWith((ref) => Stream.value(const <ProductBarcode>[])),
          allProductAliasesStreamProvider.overrideWith((ref) => Stream.value(aliases)),
          allOnlineLinksStreamProvider.overrideWith((ref) => Stream.value(const <ProductOnlineLink>[])),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(initialLocation: '/', routes: [
            GoRoute(path: '/', builder: (_, _) => const ProductsListPage()),
            GoRoute(path: '/product/:id', builder: (_, s) => Text('PRODUKTSEITE ${s.pathParameters['id']}', textDirection: TextDirection.ltr)),
            GoRoute(
              path: '/product-form',
              builder: (_, s) {
                final a = s.extra as ProductFormArgs?;
                return ProductFormPage(ean: a?.ean, suggestion: a?.suggestion, existing: a?.existing);
              },
            ),
          ]),
        ),
      );

  group('ProductsListPage', () {
    testWidgets('zeigt alle Produkte, Suche filtert', (tester) async {
      final repo = productRepo(db);
      final milk = await repo.create(name: 'Vollmilch');
      final paprika = await repo.create(name: 'Paprika Tricolore');
      await tester.pumpWidget(app(products: [milk, paprika]));
      await tester.pumpAndSettle();

      expect(find.text('Vollmilch'), findsOneWidget);
      expect(find.text('Paprika Tricolore'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('products-search')), 'paprika');
      await tester.pumpAndSettle();
      expect(find.text('Vollmilch'), findsNothing);
      expect(find.text('Paprika Tricolore'), findsOneWidget);
    });

    testWidgets('Antippen oeffnet die Produktseite', (tester) async {
      tester.view.physicalSize = const Size(1080, 3400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final product = await productRepo(db).create(name: 'Vollmilch');
      await tester.pumpWidget(app(products: [product]));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key('product-${product.id}')));
      await tester.pumpAndSettle();
      expect(find.text('PRODUKTSEITE ${product.id}'), findsOneWidget);
    });

    testWidgets('Wischen und bestaetigen loescht das Produkt (Fehlerbericht "Produkt löschen", 2026-09-28)', (tester) async {
      final product = await productRepo(db).create(name: 'Auslaufmodell');
      await tester.pumpWidget(app(products: [product]));
      await tester.pumpAndSettle();

      await tester.drag(find.byKey(Key('product-${product.id}')), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.text('Produkt löschen?'), findsOneWidget);
      await tester.tap(find.text('Löschen'));
      await tester.pumpAndSettle();

      final row = await (db.select(db.products)..where((p) => p.id.equals(product.id))).getSingle();
      expect(row.deletedAt, isNotNull);
    });

    testWidgets('Wischen und abbrechen: Produkt bleibt', (tester) async {
      final product = await productRepo(db).create(name: 'Bleibt');
      await tester.pumpWidget(app(products: [product]));
      await tester.pumpAndSettle();

      await tester.drag(find.byKey(Key('product-${product.id}')), const Offset(-500, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();

      final row = await (db.select(db.products)..where((p) => p.id.equals(product.id))).getSingle();
      expect(row.deletedAt, isNull);
    });

    testWidgets('keine Produkte: Hinweistext', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('Keine Produkte gefunden'), findsOneWidget);
    });

    testWidgets('unterschiedliche Produkte: kein Duplikat-Hinweis (ADR-023)', (tester) async {
      final repo = productRepo(db);
      final milk = await repo.create(name: 'Vollmilch');
      final paprika = await repo.create(name: 'Paprika Tricolore');
      await tester.pumpWidget(app(products: [milk, paprika]));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('product-view-duplicates')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('product-view-duplicates')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('duplicate-suggestions')), findsNothing);
      expect(find.byKey(const Key('duplicates-empty')), findsOneWidget);
    });

    testWidgets('aehnliche Produktnamen: Duplikat-Vorschlag erscheint, aber ohne automatische Zusammenfuehrung (ADR-023)', (tester) async {
      final repo = productRepo(db);
      final red = await repo.create(name: 'Paprika rot');
      final yellow = await repo.create(name: 'Paprika gelb');
      await tester.pumpWidget(app(products: [red, yellow]));
      await tester.pumpAndSettle();
      expect(find.text('Duplikate 1'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('product-view-duplicates')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('product-view-duplicates')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('duplicate-suggestions')), findsOneWidget);
      expect(find.byKey(Key('duplicate-${red.id}-${yellow.id}')), findsOneWidget);
      // beide bleiben als eigene Zeilen bestehen, solange niemand aktiv zusammenfuehrt
      final rows = await (db.select(db.products)..where((p) => p.deletedAt.isNull())).get();
      expect(rows, hasLength(2));
    });

    testWidgets('Vorschlag antippen und bestaetigen fuehrt die beiden Produkte zusammen (ADR-023)', (tester) async {
      final repo = productRepo(db);
      final red = await repo.create(name: 'Paprika rot');
      final yellow = await repo.create(name: 'Paprika gelb');
      await tester.pumpWidget(app(products: [red, yellow]));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('product-view-duplicates')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('product-view-duplicates')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key('duplicate-merge-${red.id}-${yellow.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Produkte zusammenführen?'), findsOneWidget);
      // find.text waere hier zweideutig: der Vorschlags-Button im Hintergrund traegt denselben Text.
      await tester.tap(find.widgetWithText(FilledButton, 'Zusammenführen'));
      await tester.pumpAndSettle();

      final survivor = await repo.byId(red.id);
      final dropped = await repo.byId(yellow.id);
      expect(survivor!.deletedAt, isNull);
      expect(dropped!.deletedAt, isNotNull);
    });
  });
}
