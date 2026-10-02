import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/features/report/online_price_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Product _product({String baseUnit = 'l'}) => Product(
      id: 'p1',
      householdId: 'h1',
      name: 'Vollmilch',
      baseUnit: baseUnit,
      defaultDateKind: 'best_before',
      defaultLocation: 'pantry',
      restock: false,
      updatedAt: DateTime.utc(2026),
    );

/// Online-Preise auf der Produkt-Preisseite (ADR-019): zuordnen, anzeigen mit Stand, aendern, loesen, ohne Netz.
void main() {
  late AppDatabase db;
  late FakeOnlinePriceRemote remote;
  final today = DateTime.utc(2026, 10, 2, 9);

  setUp(() {
    db = memoryDb();
    remote = FakeOnlinePriceRemote(
      feedLastModified: DateTime.utc(2026, 10, 2, 5, 5),
      articles: [
        onlineArticle(externalId: '00-2', name: 'Clever Vollmilch', priceCents: 132),
        onlineArticle(externalId: '00-1', name: 'Ja! Natürlich Bio-Vollmilch 3,5%', priceCents: 189, unitPriceNormCents: 189),
        onlineArticle(store: 'spar', externalId: '2020', name: 'A-zwei Vollmilch länger frisch', priceCents: 208, unitPriceNormCents: 208),
        onlineArticle(store: 'billa', externalId: '00-7', name: 'Schogetten Vollmilch', priceCents: 199, quantity: 100, unit: 'g', baseUnit: 'kg', unitPriceNormCents: 1990),
      ],
    );
  });
  tearDown(() => db.close());

  /// Wie testWidgets, haengt die Seite aber am Ende aus: sonst bleibt ein Zeitgeber der Drift-Abfragen offen und der
  /// Test scheitert an "A Timer is still pending".
  void sectionTest(String name, Future<void> Function(WidgetTester tester) body) => testWidgets(name, (tester) async {
        await body(tester);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });

  Widget host({DateTime? now, Product? product}) => ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          onlinePriceRemoteProvider.overrideWithValue(remote),
          onlinePriceRepositoryProvider.overrideWithValue(onlinePriceRepo(db, remote, now: () => now ?? today)),
        ],
        child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: OnlinePriceSection(product: product ?? _product(), now: () => now ?? today)))),
      );

  Future<void> pump(WidgetTester tester, {DateTime? now, Product? product}) async {
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(now: now, product: product));
    await tester.pumpAndSettle();
  }

  sectionTest('ohne Verknuepfung: beide Haendler "Noch kein Artikel zugeordnet" mit Knopf, getrennter Hinweis', (tester) async {
    await pump(tester);
    expect(find.text('Online-Preise'), findsOneWidget);
    expect(find.textContaining('getrennt von deinen Käufen'), findsOneWidget);
    expect(find.text('Noch kein Artikel zugeordnet'), findsNWidgets(2));
    expect(find.byKey(const Key('online-link-billa')), findsOneWidget);
    expect(find.byKey(const Key('online-link-spar')), findsOneWidget);
    expect(remote.fetchCalls, 0, reason: 'ohne Verknuepfung kein Netzaufruf');
  });

  sectionTest('Zuordnen: Suche startet mit dem Produktnamen nur bei diesem Haendler, Artikel bestaetigen, Preis erscheint mit Stand', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('online-link-billa')));
    await tester.pumpAndSettle();

    expect(remote.searches.single.query, 'Vollmilch');
    expect(remote.searches.single.stores, ['billa']);
    expect(remote.searches.single.preferBase, 'l');
    expect(find.text('Clever Vollmilch'), findsOneWidget);
    expect(find.text('Ja! Natürlich Bio-Vollmilch 3,5%'), findsOneWidget);
    expect(find.text('A-zwei Vollmilch länger frisch'), findsNothing, reason: 'Spar steht bei der Billa-Suche nicht zur Auswahl');
    expect(find.text('1 l · 1,32 €/l'), findsOneWidget);
    expect(find.text('100 g · 19,90 €/kg'), findsOneWidget);

    await tester.tap(find.byKey(const Key('online-result-billa-00-2')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('online-price-billa')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('online-price-billa'))).data, '1,32 €');
    expect(find.text('Billa · Clever Vollmilch'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('online-detail-billa'))).data, '1 l · 1,32 €/l');
    expect(tester.widget<Text>(find.byKey(const Key('online-status-billa'))).data, 'Stand vom 02.10.2026', reason: 'nach dem Zuordnen wird der Stand des Feeds geholt');
    expect(find.text('Noch kein Artikel zugeordnet'), findsOneWidget, reason: 'Spar ist noch offen');

    final links = await db.select(db.productOnlineLinks).get();
    expect(links.single.externalId, '00-2');
    expect(await db.select(db.outbox).get(), hasLength(1), reason: 'die Zuordnung wird synchronisiert');
  });

  sectionTest('Abbrechen der Suche aendert nichts', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('online-link-spar')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10)); // ausserhalb des Blatts
    await tester.pumpAndSettle();
    expect(await db.select(db.productOnlineLinks).get(), isEmpty);
    expect(find.byKey(const Key('online-link-spar')), findsOneWidget);
  });

  sectionTest('Suchfeld: andere Eingabe sucht neu, zu kurze Eingabe leert die Liste', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('online-link-billa')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('online-search-field')), 'Schogetten');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(remote.searches.last.query, 'Schogetten');
    expect(find.text('Schogetten Vollmilch'), findsOneWidget);
    expect(find.text('Clever Vollmilch'), findsNothing);

    await tester.enterText(find.byKey(const Key('online-search-field')), 'x');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('online-search-empty')), findsOneWidget);
  });

  sectionTest('keine Treffer und kein Netz: freundlicher Hinweis, nichts bricht', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('online-link-billa')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('online-search-field')), 'Zzzzzz');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('online-search-empty')), findsOneWidget);

    remote.fail = true;
    await tester.enterText(find.byKey(const Key('online-search-field')), 'Vollmilch');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('online-search-error')), findsOneWidget);
    expect(find.textContaining('nicht erreichbar'), findsOneWidget);
  });

  sectionTest('verknuepft und Feed aktuell: Stand vom Datum, Grundpreis, kein Warnhinweis', (tester) async {
    await onlinePriceRepo(db, remote, now: () => today).link('p1', onlineArticle(externalId: '00-2'));
    await pump(tester);

    expect(find.text('Billa · Clever Vollmilch'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('online-status-billa'))).data, 'Stand vom 02.10.2026');
    expect(find.byKey(const Key('online-mismatch-billa')), findsNothing);
    expect(find.byKey(const Key('online-row-spar')), findsOneWidget);
    expect(remote.fetchCalls, 1, reason: 'beim Oeffnen werden die Preise geholt');
  });

  sectionTest('Feed aelter als 7 Tage: "zuletzt bekannt" mit dem Stand, Preis bleibt sichtbar', (tester) async {
    await onlinePriceRepo(db, remote, now: () => today).link('p1', onlineArticle(externalId: '00-2'));
    await pump(tester, now: DateTime.utc(2026, 10, 12, 9)); // Feed vom 02.10. ist 10 Tage alt
    expect(tester.widget<Text>(find.byKey(const Key('online-status-billa'))).data, 'zuletzt bekannt, Stand vom 02.10.2026');
    expect(tester.widget<Text>(find.byKey(const Key('online-price-billa'))).data, '1,32 €');
  });

  sectionTest('Artikel nicht mehr im Sortiment: Hinweis, letzter Preis bleibt', (tester) async {
    await onlinePriceRepo(db, remote, now: () => today).link('p1', onlineArticle(externalId: '00-2'));
    remote.articles = [];
    await pump(tester);
    expect(tester.widget<Text>(find.byKey(const Key('online-status-billa'))).data, 'nicht mehr im Online-Sortiment, zuletzt bekannt');
    expect(tester.widget<Text>(find.byKey(const Key('online-price-billa'))).data, '1,32 €');
  });

  sectionTest('kein Netz beim Oeffnen: der zuletzt bekannte Preis steht da, Stand unbekannt statt Absturz', (tester) async {
    await onlinePriceRepo(db, remote, now: () => today).link('p1', onlineArticle(externalId: '00-2'));
    remote.fail = true;
    await pump(tester);
    expect(tester.widget<Text>(find.byKey(const Key('online-price-billa'))).data, '1,32 €');
    expect(tester.widget<Text>(find.byKey(const Key('online-status-billa'))).data, 'Stand unbekannt');
  });

  sectionTest('Einheiten passen nicht zusammen: Hinweis am Grundpreis', (tester) async {
    await onlinePriceRepo(db, remote, now: () => today).link('p1', onlineArticle(externalId: '00-7', name: 'Schogetten Vollmilch', priceCents: 199, quantity: 100, unit: 'g', baseUnit: 'kg', unitPriceNormCents: 1990));
    await pump(tester); // Produkt zaehlt in Litern
    expect(find.byKey(const Key('online-mismatch-billa')), findsOneWidget);
    expect(find.textContaining('je kg'), findsWidgets);
  });

  sectionTest('Menue: Zuordnung loesen bringt "Noch kein Artikel zugeordnet" zurueck', (tester) async {
    await onlinePriceRepo(db, remote, now: () => today).link('p1', onlineArticle(externalId: '00-2'));
    await pump(tester);
    await tester.tap(find.byKey(const Key('online-menu-billa')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zuordnung lösen'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('online-link-billa')), findsOneWidget);
    expect(find.text('Noch kein Artikel zugeordnet'), findsNWidgets(2));
    expect((await db.select(db.productOnlineLinks).get()).single.deletedAt, isNotNull);
  });

  sectionTest('Menue: anderen Artikel waehlen stellt die Zuordnung um', (tester) async {
    await onlinePriceRepo(db, remote, now: () => today).link('p1', onlineArticle(externalId: '00-2'));
    await pump(tester);
    await tester.tap(find.byKey(const Key('online-menu-billa')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anderen Artikel wählen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('online-result-billa-00-1')));
    await tester.pumpAndSettle();

    expect(find.text('Billa · Ja! Natürlich Bio-Vollmilch 3,5%'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('online-price-billa'))).data, '1,89 €');
    expect(await (db.select(db.productOnlineLinks)..where((l) => l.deletedAt.isNull())).get(), hasLength(1));
  });

  sectionTest('Stueckprodukt: die Suche bevorzugt Artikel in Stueck', (tester) async {
    await pump(tester, product: _product(baseUnit: 'piece'));
    await tester.tap(find.byKey(const Key('online-link-spar')));
    await tester.pumpAndSettle();
    expect(remote.searches.single.preferBase, 'stk');
  });
}
