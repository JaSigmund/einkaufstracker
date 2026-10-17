import 'dart:typed_data';

import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/ocr/label_text_reader.dart';
import 'package:einkaufstracker/features/products/stock_entry_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';

/// MHD-Foto auf der Bestandserfassung (Ausbau 1.14): Foto, Texterkennung auf dem Geraet, Funde zur Bestaetigung.
class _FakeReader implements LabelTextReader {
  _FakeReader(this.text, {this.fail = false});
  final String? text;
  final bool fail;
  var calls = 0;

  @override
  Future<String?> read(Uint8List image) async {
    calls++;
    if (fail) throw StateError('Erkennung kaputt');
    return text;
  }
}

void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  final year = DateTime.now().year + 1;
  Product product({String dateKind = 'best_before'}) => Product(
        id: 'p1', householdId: 'h1', name: 'Joghurt', baseUnit: 'piece', defaultDateKind: dateKind, defaultLocation: 'fridge', restock: false, updatedAt: DateTime.utc(2026),
      );

  Future<void> open(
    WidgetTester tester, {
    required _FakeReader reader,
    Uint8List? photo,
    bool available = true,
    bool cancelPicker = false,
  }) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await db.into(db.products).insert(ProductsCompanion.insert(id: 'p1', householdId: 'h1', name: 'Joghurt', updatedAt: DateTime.utc(2026)));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        inventoryRepositoryProvider.overrideWithValue(inventoryRepo(db)),
        productRepositoryProvider.overrideWithValue(productRepo(db)),
        activeInventoryStreamProvider.overrideWith((ref) => Stream.value(const <InventoryItem>[])),
        labelPhotoPickerProvider.overrideWithValue(({required bool camera}) async => cancelPicker ? null : (photo ?? Uint8List.fromList([1, 2, 3]))),
        labelTextReaderProvider.overrideWithValue(reader),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(initialLocation: '/stock', routes: [
          GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('START'))),
          GoRoute(path: '/inventory', builder: (_, _) => const Scaffold(body: Text('INVENTAR'))),
          GoRoute(path: '/stock', builder: (_, _) => StockEntryPage(product: product(), ean: '9001', labelScanAvailable: available)),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> scan(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('stock-date-scan')));
    await tester.pumpAndSettle();
  }

  String dateText(WidgetTester tester) => ((tester.widget<ListTile>(find.byKey(const Key('stock-date'))).title) as Text).data!;

  testWidgets('im Browser (nicht verfuegbar) gibt es den Knopf nicht', (tester) async {
    await open(tester, reader: _FakeReader(null), available: false);
    expect(find.byKey(const Key('stock-date-scan')), findsNothing);
  });

  testWidgets('ein Fund mit Stichwort: Dialog zeigt Datum, Art und Textstelle, Uebernehmen setzt das Datum, Speichern legt den Bestand an', (tester) async {
    final reader = _FakeReader('Kühl lagern\nMHD 12.03.$year\nL0123');
    await open(tester, reader: reader);
    await scan(tester);
    expect(find.text('Erkanntes Datum'), findsOneWidget);
    expect(find.text('12.03.$year'), findsOneWidget);
    expect(find.textContaining('Mindestens haltbar bis'), findsWidgets);
    expect(find.textContaining('MHD 12.03.$year'), findsOneWidget);

    await tester.tap(find.byKey(const Key('scan-accept')));
    await tester.pumpAndSettle();
    expect(dateText(tester), '12.03.$year');
    expect(reader.calls, 1);

    await tester.tap(find.byKey(const Key('stock-save')));
    await tester.pumpAndSettle();
    final item = await db.select(db.inventoryItems).getSingle();
    expect(item.bestBefore, DateTime.utc(year, 3, 12));
    expect(item.dateKind, 'best_before');
    // zurueck ins Inventar, wo der neue Posten steht (nicht auf die Uebersicht)
    expect(find.text('INVENTAR'), findsOneWidget);
  });

  testWidgets('"zu verbrauchen bis" stellt die Art des Datums um', (tester) async {
    await open(tester, reader: _FakeReader('zu verbrauchen bis 12.03.$year'));
    await scan(tester);
    await tester.tap(find.byKey(const Key('scan-accept')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stock-save')));
    await tester.pumpAndSettle();
    expect((await db.select(db.inventoryItems).getSingle()).dateKind, 'use_by');
  });

  testWidgets('mehrere Funde: das spaetere ist vorgewaehlt, ein anderer laesst sich waehlen', (tester) async {
    await open(tester, reader: _FakeReader('MHD 12.03.$year  und  15.11.$year'));
    await scan(tester);
    expect(find.byKey(const Key('scan-candidate-0')), findsOneWidget);
    expect(find.byKey(const Key('scan-candidate-1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('scan-candidate-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-accept')));
    await tester.pumpAndSettle();
    expect(dateText(tester), '12.03.$year', reason: 'vorgewaehlt war das spaetere (15.11.), gewaehlt wurde das andere');
  });

  testWidgets('Abbrechen im Dialog aendert nichts', (tester) async {
    await open(tester, reader: _FakeReader('MHD 12.03.$year'));
    await scan(tester);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(dateText(tester), 'Kein Datum');
  });

  testWidgets('kein Datum im Text: Hinweis, nichts wird uebernommen', (tester) async {
    await open(tester, reader: _FakeReader('Zutaten: Milch, Zucker'));
    await scan(tester);
    expect(find.textContaining('Kein Datum erkannt'), findsOneWidget);
    expect(dateText(tester), 'Kein Datum');
  });

  testWidgets('nichts erkannt (null): derselbe Hinweis', (tester) async {
    await open(tester, reader: _FakeReader(null));
    await scan(tester);
    expect(find.textContaining('Kein Datum erkannt'), findsOneWidget);
  });

  testWidgets('Foto abgebrochen: die Erkennung laeuft gar nicht erst', (tester) async {
    final reader = _FakeReader('MHD 12.03.$year');
    await open(tester, reader: reader, cancelPicker: true);
    await scan(tester);
    expect(reader.calls, 0);
    expect(find.text('Erkanntes Datum'), findsNothing);
  });

  testWidgets('Fehler bei der Erkennung: Hinweis statt Absturz, der Knopf ist wieder bedienbar', (tester) async {
    await open(tester, reader: _FakeReader('x', fail: true));
    await scan(tester);
    expect(find.textContaining('konnte nicht gelesen werden'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byKey(const Key('stock-date-scan'))).onPressed, isNotNull);
  });
}
