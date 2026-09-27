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

  testWidgets('Unbekanntes Produkt ohne OFF-Treffer: manuell anlegen, dann Bestand erfassen', (tester) async {
    await tester.pumpWidget(app(scanner: FakeBarcodeScanner('9008700000099')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-barcode')));
    await tester.pumpAndSettle();
    expect(find.text('Neues Produkt'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('product-name')), 'Testartikel');
    for (var i = 0; i < 5; i++) {
      await tester.drag(find.byKey(const Key('product-restock')), const Offset(0, -400), warnIfMissed: false);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('product-save')));
    await tester.pumpAndSettle();

    expect(find.text('Testartikel'), findsWidgets); // Titel der Bestandserfassung
    final product = await db.select(db.products).getSingle();
    expect(product.name, 'Testartikel');
    final barcode = await db.select(db.productBarcodes).getSingle();
    expect((barcode.ean, barcode.productId), ('9008700000099', product.id));
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
