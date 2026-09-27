import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/features/products/product_form_page.dart';
import 'package:einkaufstracker/features/products/products_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';

/// Fehlerbericht "Alias ändern" (2026-09-27): ein Produkt liess sich bisher nur ueber den Barcode-Flow
/// oeffnen, und eine falsch gelernte Bon-Zuordnung liess sich gar nicht loesen. Testet beides: die neue
/// Produktliste (Einstiegspunkt) und die Alias-Verwaltung im Bearbeitungsformular.
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
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(initialLocation: '/', routes: [
            GoRoute(path: '/', builder: (_, _) => const ProductsListPage()),
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

    testWidgets('Antippen oeffnet das Produkt zum Bearbeiten', (tester) async {
      tester.view.physicalSize = const Size(1080, 3400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final product = await productRepo(db).create(name: 'Vollmilch');
      await tester.pumpWidget(app(products: [product]));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key('product-${product.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Produkt bearbeiten'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Name'), findsOneWidget);
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
  });

  group('ProductFormPage: Alias-Verwaltung', () {
    testWidgets('zeigt gelernte Bon-Zuordnung, loesen entfernt sie in der Datenbank', (tester) async {
      tester.view.physicalSize = const Size(1080, 3400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = productRepo(db);
      final product = await repo.findOrCreateForReceiptItem('DKIH Paprika Tricolore');
      // Einmalige Abfrage statt eines live Drift-Streams: ein `.watch()`/`.first` haelt in einem Widget-Test
      // einen Timer aktiv, den die Test-Bindung nie freigibt (Prozess haengt nach dem Testende weiter).
      final alias = await (db.select(db.productAliases)..where((a) => a.productId.equals(product.id) & a.deletedAt.isNull())).getSingle();

      await tester.pumpWidget(ProviderScope(
        overrides: [
          productRepositoryProvider.overrideWithValue(repo),
          categoriesStreamProvider.overrideWith((ref) => Stream.value(const <Category>[])),
          productAliasesStreamProvider.overrideWith((ref, _) => Stream.value([alias])),
        ],
        child: MaterialApp(home: ProductFormPage(existing: product)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Gelernte Bon-Zuordnungen'), findsOneWidget);
      expect(find.byKey(Key('alias-${alias.id}')), findsOneWidget);

      await tester.tap(find.byKey(Key('alias-remove-${alias.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lösen'));
      await tester.pumpAndSettle();

      // Die statische Momentaufnahme aktualisiert die Anzeige nicht (wie ueberall sonst im Projekt bei
      // ueberschriebenen Stream-Providern), aber die Datenbank ist der massgebliche Nachweis:
      final row = await (db.select(db.productAliases)..where((a) => a.id.equals(alias.id))).getSingle();
      expect(row.deletedAt, isNotNull);
    });

    testWidgets('neues Produkt: kein Alias-Abschnitt', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          productRepositoryProvider.overrideWithValue(productRepo(db)),
          categoriesStreamProvider.overrideWith((ref) => Stream.value(const <Category>[])),
          productAliasesStreamProvider.overrideWith((ref, _) => Stream.value(const <ProductAlias>[])),
        ],
        child: const MaterialApp(home: ProductFormPage()),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Gelernte Bon-Zuordnungen'), findsNothing);
    });
  });
}
