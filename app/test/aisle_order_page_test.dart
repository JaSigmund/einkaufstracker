import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/repositories/household_prefs_repository.dart';
import 'package:einkaufstracker/domain/shopping_list/aisle_order.dart';
import 'package:einkaufstracker/features/shopping_list/aisle_order_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Pflege der Regal-Reihenfolge je Markt (Ausbau 1.14).
Category _cat(String id, String name, {bool deleted = false}) => Category(
      id: id, householdId: 'h1', name: name, sortOrder: 0, isStorable: true, updatedAt: DateTime.utc(2026), deletedAt: deleted ? DateTime.utc(2026) : null,
    );

Store _store(String id, String chain, {String? branch}) => Store(id: id, householdId: 'h1', chain: chain, branch: branch, updatedAt: DateTime.utc(2026));

void main() {
  late AppDatabase db;
  late HouseholdPrefsRepository prefs;

  setUp(() {
    db = memoryDb();
    prefs = HouseholdPrefsRepository(db, householdId: () async => 'h1');
  });
  tearDown(() => db.close());

  final categories = [_cat('c-brot', 'Backwaren'), _cat('c-obst', 'Obst'), _cat('c-milch', 'Milch'), _cat('c-alt', 'Alt', deleted: true)];
  final stores = [_store('s-billa', 'Billa', branch: '0643'), _store('s-spar', 'Spar')];

  Future<void> open(WidgetTester tester, {List<Store>? shops, String? initialStoreId}) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        householdPrefsRepositoryProvider.overrideWithValue(prefs),
        storesStreamProvider.overrideWith((ref) => Stream.value(shops ?? stores)),
        categoriesStreamProvider.overrideWith((ref) => Stream.value(categories)),
      ],
      child: MaterialApp(home: AisleOrderPage(initialStoreId: initialStoreId)),
    ));
    await tester.pumpAndSettle();
  }

  List<String> shown(WidgetTester tester) {
    final tiles = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('aisle-cat-')).evaluate();
    return [for (final e in tiles) (e.widget.key! as ValueKey<String>).value.substring('aisle-cat-'.length)];
  }

  testWidgets('ohne bekannten Markt steht ein Hinweis da', (tester) async {
    await open(tester, shops: const []);
    expect(find.byKey(const Key('aisle-no-store')), findsOneWidget);
    expect(find.byKey(const Key('aisle-store')), findsNothing);
  });

  testWidgets('ein Markt waehlen: Kategorien alphabetisch, geloeschte fehlen, Filialkennung steht im Namen', (tester) async {
    await open(tester);
    expect(find.text('Wähle einen Markt.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('aisle-store')));
    await tester.pumpAndSettle();
    expect(find.text('Billa 0643').last, findsOneWidget);
    await tester.tap(find.byKey(const Key('aisle-store-s-billa')).last);
    await tester.pumpAndSettle();
    expect(shown(tester), ['c-brot', 'c-milch', 'c-obst']);
  });

  testWidgets('die gespeicherte Reihenfolge wird beim Oeffnen mit vorgewaehltem Markt gezeigt, neue Kategorien kommen danach', (tester) async {
    await prefs.set(aislePrefFor('s-billa'), ['c-obst', 'c-geloescht', 'c-brot']);
    await open(tester, initialStoreId: 's-billa');
    expect(shown(tester), ['c-obst', 'c-brot', 'c-milch']);
  });

  testWidgets('Ziehen speichert die neue Reihenfolge fuer diesen Markt', (tester) async {
    await open(tester, initialStoreId: 's-billa');
    expect(shown(tester), ['c-brot', 'c-milch', 'c-obst']);
    // die letzte Kategorie (Obst) an den Anfang ziehen
    await tester.drag(find.byIcon(Icons.drag_handle).last, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(shown(tester).first, 'c-obst');
    final saved = parseAisleOrder((await prefs.load())[aislePrefFor('s-billa')])!;
    expect(saved.first, 'c-obst');
    expect(saved.toSet(), {'c-brot', 'c-milch', 'c-obst'});
    expect((await prefs.load()).containsKey(aislePrefFor('s-spar')), isFalse, reason: 'andere Maerkte bleiben unberuehrt');
  });

  testWidgets('Zuruecksetzen entfernt die Reihenfolge und zeigt wieder alphabetisch', (tester) async {
    await prefs.set(aislePrefFor('s-billa'), ['c-obst', 'c-milch', 'c-brot']);
    await open(tester, initialStoreId: 's-billa');
    expect(shown(tester).first, 'c-obst');
    await tester.tap(find.byKey(const Key('aisle-reset')));
    await tester.pumpAndSettle();
    expect(shown(tester), ['c-brot', 'c-milch', 'c-obst']);
    expect(parseAisleOrder((await prefs.load())[aislePrefFor('s-billa')]), isNull);
  });

  testWidgets('der Hinweis erklaert, wozu die Reihenfolge dient', (tester) async {
    await open(tester);
    expect(tester.widget<Text>(find.byKey(const Key('aisle-hint'))).data, contains('abgehst'));
  });
}
