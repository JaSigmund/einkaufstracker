import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/products/off_client.dart';
import 'package:einkaufstracker/features/home/home_shell.dart';
import 'package:einkaufstracker/features/products/product_form_page.dart';
import 'package:einkaufstracker/features/products/stock_entry_page.dart';
import 'package:einkaufstracker/features/receipt_import/receipt_import_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';

/// Drift-Streams beenden ihren internen Timer nicht zuverlaessig innerhalb eines Widget-Tests
/// (siehe andere Tests im Projekt): die Provider, die live aus der Datenbank lesen, werden hier
/// deshalb mit einer einmaligen Momentaufnahme ueberschrieben, wie an anderer Stelle im Projekt ueblich.
void main() {

  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  Widget app({
    required FakeBarcodeScanner scanner,
    OffProduct? offResult,
    List<Product> products = const [],
    List<InventoryItem> active = const [],
  }) =>
      ProviderScope(
        overrides: [
          barcodeScannerProvider.overrideWithValue(scanner),
          productRepositoryProvider.overrideWithValue(productRepo(db, off: FakeOffClient(offResult))),
          inventoryRepositoryProvider.overrideWithValue(inventoryRepo(db)),
          categoriesStreamProvider.overrideWith((ref) => Stream.value(const <Category>[])),
          receiptsStreamProvider.overrideWith((ref) => Stream.value(const <Receipt>[])),
          storesStreamProvider.overrideWith((ref) => Stream.value(const <Store>[])),
          productsStreamProvider.overrideWith((ref) => Stream.value(products)),
          activeInventoryStreamProvider.overrideWith((ref) => Stream.value(active)),
          inventorySuggestionsStreamProvider.overrideWith((ref) => Stream.value(const <InventoryItem>[])),
          receiptImportServiceProvider.overrideWithValue(ReceiptImportService(FakePdfReader(text: ''), receiptRepo(db))),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(initialLocation: '/', routes: [
            GoRoute(path: '/', builder: (_, _) => const HomeShell()),
            GoRoute(
              path: '/product-form',
              builder: (_, s) {
                final a = s.extra as ProductFormArgs?;
                return ProductFormPage(ean: a?.ean, suggestion: a?.suggestion, existing: a?.existing);
              },
            ),
            GoRoute(
              path: '/stock-entry',
              builder: (_, s) {
                final a = s.extra as StockEntryArgs;
                return StockEntryPage(product: a.product, ean: a.ean);
              },
            ),
          ]),
        ),
      );

  testWidgets('Bekanntes Produkt: Scan fuehrt direkt zur Bestandserfassung und speichert', (tester) async {
    final product = await productRepo(db).create(name: 'Vollmilch 1l', baseUnit: 'l', ean: '9008700000001');
    await tester.pumpWidget(app(scanner: FakeBarcodeScanner('9008700000001')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan-barcode')));
    await tester.pumpAndSettle();
    expect(find.text('Vollmilch 1l'), findsWidgets);

    await tester.tap(find.byKey(const Key('stock-save')));
    await tester.pumpAndSettle();
    final item = await db.select(db.inventoryItems).getSingle();
    expect(item.productId, product.id);
    expect(item.status, 'sealed');
  });

  testWidgets('Einheit fuer diesen Kauf aendern und fuer das Produkt merken', (tester) async {
    final product = await productRepo(db).create(name: 'Clever Champignon weiß', baseUnit: 'piece', ean: '9008700000101');
    await tester.pumpWidget(app(scanner: FakeBarcodeScanner('9008700000101')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-barcode')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('stock-remember-unit')), findsNothing); // noch unveraendert: kein Haken noetig
    await tester.tap(find.byKey(const Key('stock-unit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('kg').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('stock-remember-unit')), findsOneWidget);
    await tester.tap(find.byKey(const Key('stock-remember-unit')));
    await tester.enterText(find.byKey(const Key('stock-quantity')), '0,5');

    await tester.tap(find.byKey(const Key('stock-save')));
    await tester.pumpAndSettle();

    final item = await db.select(db.inventoryItems).getSingle();
    expect((item.unit, item.quantity), ('kg', 0.5));
    final updatedProduct = await (db.select(db.products)..where((p) => p.id.equals(product.id))).getSingle();
    expect(updatedProduct.baseUnit, 'kg'); // fuer kuenftige Kaeufe gemerkt
  });

  testWidgets('Unbekanntes Produkt ohne OFF-Treffer: manuell anlegen, dann Bestand erfassen', (tester) async {
    await tester.pumpWidget(app(scanner: FakeBarcodeScanner('9008700000099')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-barcode')));
    await tester.pumpAndSettle();
    expect(find.text('Neues Produkt'), findsOneWidget);

    tester.view.physicalSize = const Size(1080, 3400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('product-name')), 'Testartikel');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('product-save')));
    await tester.pumpAndSettle();

    expect(find.text('Testartikel'), findsWidgets); // Titel der Bestandserfassung
    final product = await db.select(db.products).getSingle();
    expect(product.name, 'Testartikel');
    final barcode = await db.select(db.productBarcodes).getSingle();
    expect((barcode.ean, barcode.productId), ('9008700000099', product.id));
  });

  testWidgets('Unbekannter Barcode: bestehendes Produkt (z.B. aus einem Bon-Vorschlag) verknuepfen statt duplizieren', (tester) async {
    final existing = await productRepo(db).create(name: 'Clever Champignon weiß', baseUnit: 'piece');
    await tester.pumpWidget(app(scanner: FakeBarcodeScanner('9008700000100'), products: [existing]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-barcode')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('product-search')), 'Champignon');
    await tester.pumpAndSettle();
    expect(find.byKey(Key('match-${existing.id}')), findsOneWidget);

    await tester.tap(find.byKey(Key('match-${existing.id}')));
    await tester.pumpAndSettle();

    expect(await db.select(db.products).get(), hasLength(1)); // kein zweites Produkt
    final barcode = await db.select(db.productBarcodes).getSingle();
    expect((barcode.ean, barcode.productId), ('9008700000100', existing.id));
    expect(find.text('Clever Champignon weiß'), findsWidgets); // Titel der Bestandserfassung
  });

  testWidgets('Unbekannter Barcode MIT OFF-Vorschlag: die Suche laeuft automatisch, kein Tippen noetig', (tester) async {
    final existing = await productRepo(db).create(name: 'DKIH Paprika Tricolore', baseUnit: 'kg', categoryId: null);
    await tester.pumpWidget(app(
      scanner: FakeBarcodeScanner('9008700000200'),
      offResult: const OffProduct(name: 'Paprika Tricolore', brand: 'Da komm ich her!'), // OFF-Name weicht vom Bon-Namen ab
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-barcode')));
    await tester.pumpAndSettle();

    // Die Suche lief automatisch mit dem OFF-Namen, kein eigenes Tippen noetig (Fehlerbericht
    // "Automatische Bonzuordnung", 2026-09-28). "Paprika Tricolore" ist ein Teilstring von "DKIH Paprika
    // Tricolore", die Suche findet das Bon-Produkt also trotz des abweichenden OFF-Namens.
    expect(find.byKey(Key('match-${existing.id}')), findsOneWidget);

    await tester.tap(find.byKey(Key('match-${existing.id}')));
    await tester.pumpAndSettle();
    expect(find.text('DKIH Paprika Tricolore'), findsWidgets); // Titel der Bestandserfassung
    expect((await db.select(db.productBarcodes).getSingle()).productId, existing.id);
  });

  testWidgets('Falsch verknuepfter Barcode: ueber "Andere Zuordnung" neu zuweisen', (tester) async {
    final wrong = await productRepo(db).create(name: 'Falsches Produkt', ean: '9008700000201');
    final right = await productRepo(db).create(name: 'Richtiges Produkt');
    await tester.pumpWidget(app(scanner: FakeBarcodeScanner('9008700000201'), products: [wrong, right]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-barcode')));
    await tester.pumpAndSettle();
    expect(find.text('Falsches Produkt'), findsWidgets);

    await tester.tap(find.byKey(const Key('stock-reassign')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('product-search')), 'Richtiges');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('match-${right.id}')));
    await tester.pumpAndSettle();

    expect(find.text('Richtiges Produkt'), findsWidgets);
    final mapping = await db.select(db.productBarcodes).getSingle();
    expect(mapping.productId, right.id); // die Zuordnung zeigt jetzt auf das richtige Produkt
  });

  testWidgets('Unbekanntes Produkt MIT OFF-Vorschlag: Formular ist vorbelegt', (tester) async {
    await tester.pumpWidget(app(
      scanner: FakeBarcodeScanner('9008700000002'),
      offResult: const OffProduct(name: 'Bio-Joghurt', brand: 'Ja! Natürlich'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-barcode')));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.byKey(const Key('product-name'))).controller!.text, 'Bio-Joghurt');
    expect(tester.widget<TextField>(find.byKey(const Key('product-brand'))).controller!.text, 'Ja! Natürlich');
    expect(find.textContaining('Vorschlag von Open Food Facts'), findsOneWidget);
  });

  testWidgets('Unbekanntes Produkt MIT OFF-Vorschlag: Haltbarkeit-nach-Oeffnen und Lagerort werden vorbelegt (Doku 06 §3.2)', (tester) async {
    tester.view.physicalSize = const Size(1080, 3400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app(
      scanner: FakeBarcodeScanner('9008700000002'),
      offResult: const OffProduct(name: 'Vollmilch'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-barcode')));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.byKey(const Key('product-opened-days'))).controller!.text, '3');
    expect(tester.widget<DropdownButtonFormField<String>>(find.byKey(const Key('product-location'))).initialValue, 'fridge');
  });

  testWidgets('Unbekanntes Produkt MIT OFF-Vorschlag: Stueckgewicht aus der Packungsangabe wird mitgespeichert', (tester) async {
    tester.view.physicalSize = const Size(1080, 3400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app(
      scanner: FakeBarcodeScanner('9008700000003'),
      offResult: const OffProduct(name: 'Joghurt', quantityText: '500 g'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-barcode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('product-save')));
    await tester.pumpAndSettle();

    final product = await (db.select(db.products)..where((p) => p.name.equals('Joghurt'))).getSingle();
    expect(product.unitWeightG, 500);
  });

  testWidgets('Abbruch im Scanner: nichts passiert', (tester) async {
    await tester.pumpWidget(app(scanner: FakeBarcodeScanner(null)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-barcode')));
    await tester.pumpAndSettle();
    expect(find.text('Neues Produkt'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('Bereits vorhandener Bestand: Schnellaktionen Oeffnen/Aufgebraucht angeboten', (tester) async {
    final product = await productRepo(db).create(name: 'Joghurt', ean: '9008700000003');
    final item = await inventoryRepo(db).recordFromScan(productId: product.id, ean: '9008700000003');
    await tester.pumpWidget(app(scanner: FakeBarcodeScanner('9008700000003'), products: [product], active: [item]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-barcode')));
    await tester.pumpAndSettle();

    expect(find.text('Bereits im Inventar'), findsOneWidget);
    expect(find.text('Öffnen'), findsOneWidget);
    expect(find.text('Aufgebraucht'), findsWidgets);
  });
}
