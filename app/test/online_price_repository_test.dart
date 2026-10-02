import 'dart:convert';

import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Online-Preise zu eigenen Produkten (ADR-019): Verknuepfen, Loesen, Abrufen, Zwischenspeichern, Sync.
void main() {
  late AppDatabase db;
  late FakeOnlinePriceRemote remote;
  late DateTime clock;

  setUp(() {
    db = memoryDb();
    clock = DateTime.utc(2026, 10, 2, 8);
    remote = FakeOnlinePriceRemote(feedLastModified: DateTime.utc(2026, 10, 2, 5, 5));
  });
  tearDown(() => db.close());

  repoOf() => onlinePriceRepo(db, remote, now: () => clock);

  Future<List<ProductOnlineLink>> activeLinks() => (db.select(db.productOnlineLinks)..where((l) => l.deletedAt.isNull())).get();
  Future<List<Map<String, dynamic>>> outbox() async =>
      [for (final e in await db.select(db.outbox).get()) {'table': e.remoteTable, 'row': e.rowId, 'payload': jsonDecode(e.payload) as Map<String, dynamic>}];

  group('verknuepfen', () {
    test('legt die Verknuepfung an, stellt sie in die Outbox und merkt sich den Preis sofort', () async {
      final repo = repoOf();
      await repo.link('p1', onlineArticle());

      final links = await activeLinks();
      expect(links, hasLength(1));
      expect(links.single.productId, 'p1');
      expect(links.single.store, 'billa');
      expect(links.single.externalId, '00-1');
      expect(links.single.linkedName, 'Clever Vollmilch');
      expect(links.single.householdId, 'h1');

      final queued = await outbox();
      expect(queued, hasLength(1));
      expect(queued.single['table'], 'product_online_links');
      expect(queued.single['payload']['external_id'], '00-1');
      expect(queued.single['payload']['deleted_at'], isNull);

      final cached = await db.select(db.onlinePriceCache).getSingle();
      expect(cached.priceCents, 132);
      expect(cached.unitPriceNormCents, 132);
      expect(cached.available, isTrue);
    });

    test('derselbe Haendler noch einmal: die Verknuepfung wird umgestellt, es bleibt eine aktive Zeile', () async {
      final repo = repoOf();
      await repo.link('p1', onlineArticle());
      final first = (await activeLinks()).single;
      await repo.link('p1', onlineArticle(externalId: '00-2', name: 'Ja! Natürlich Vollmilch', priceCents: 189, unitPriceNormCents: 189));

      final links = await activeLinks();
      expect(links, hasLength(1), reason: 'der Server erlaubt je Produkt und Haendler nur eine aktive Zeile');
      expect(links.single.id, first.id);
      expect(links.single.externalId, '00-2');
      expect(links.single.linkedName, 'Ja! Natürlich Vollmilch');
      expect((await outbox()).map((e) => e['row']).toSet(), {first.id}, reason: 'beide Aenderungen betreffen dieselbe Zeile');
    });

    test('anderer Haendler fuer dasselbe Produkt: zweite Verknuepfung; anderes Produkt: eigene', () async {
      final repo = repoOf();
      await repo.link('p1', onlineArticle());
      await repo.link('p1', onlineArticle(store: 'spar', externalId: '2020', name: 'A-zwei Vollmilch'));
      await repo.link('p2', onlineArticle(externalId: '00-9', name: 'Clever Butter'));
      expect(await activeLinks(), hasLength(3));
      expect((await repo.watchLinksFor('p1').first).map((l) => l.store).toSet(), {'billa', 'spar'});
      expect((await repo.watchLinksFor('p2').first), hasLength(1));
    });

    test('ruft onChanged, damit der Sync startet', () async {
      var calls = 0;
      final repo = onlinePriceRepo(db, remote, onChanged: () => calls++, now: () => clock);
      await repo.link('p1', onlineArticle());
      await repo.unlink((await activeLinks()).single.id);
      expect(calls, 2);
    });
  });

  group('loesen', () {
    test('Soft-Delete: die Zeile bleibt fuer den Sync, ist aber nicht mehr aktiv; neu verknuepfen geht danach', () async {
      final repo = repoOf();
      await repo.link('p1', onlineArticle());
      final link = (await activeLinks()).single;

      await repo.unlink(link.id);
      expect(await activeLinks(), isEmpty);
      expect(await repo.watchLinksFor('p1').first, isEmpty);
      final all = await db.select(db.productOnlineLinks).get();
      expect(all.single.deletedAt, isNotNull);
      expect((await outbox()).last['payload']['deleted_at'], isNotNull);

      await repo.link('p1', onlineArticle(externalId: '00-5'));
      final links = await activeLinks();
      expect(links, hasLength(1));
      expect(links.single.externalId, '00-5');
      expect(links.single.id, isNot(link.id), reason: 'nach dem Loesen entsteht eine neue Zeile (Unique-Index nur ueber aktive Zeilen)');
    });

    test('unbekannte ID: nichts passiert', () async {
      await repoOf().unlink('gibt-es-nicht');
      expect(await outbox(), isEmpty);
    });
  });

  group('abrufen', () {
    test('ohne Verknuepfungen kein Netzaufruf', () async {
      expect(await repoOf().refresh(force: true), isFalse);
      expect(remote.fetchCalls, 0);
    });

    test('aktualisiert Preis und Stand des Feeds im Zwischenspeicher', () async {
      remote.articles = [onlineArticle()];
      final repo = repoOf();
      await repo.link('p1', onlineArticle());

      remote.articles = [onlineArticle(priceCents: 139, unitPriceNormCents: 139)];
      expect(await repo.refresh(force: true), isTrue);

      final cached = await db.select(db.onlinePriceCache).getSingle();
      expect(cached.priceCents, 139);
      expect(cached.available, isTrue);
      expect(cached.feedUpdatedAt, DateTime.utc(2026, 10, 2, 5, 5));
      expect(cached.fetchedAt, clock);
    });

    test('Artikel aus dem Feed verschwunden: letzter Preis bleibt, aber als nicht verfuegbar markiert', () async {
      final repo = repoOf();
      await repo.link('p1', onlineArticle());
      remote.articles = [];
      await repo.refresh(force: true);

      final cached = await db.select(db.onlinePriceCache).getSingle();
      expect(cached.available, isFalse);
      expect(cached.priceCents, 132, reason: 'zuletzt bekannter Preis wird weiter gezeigt');
      expect(cached.name, 'Clever Vollmilch');
    });

    test('Artikel nie geholt und gleich verschwunden: Zeile ohne Preis mit dem Namen der Verknuepfung', () async {
      final repo = repoOf();
      await repo.link('p1', onlineArticle());
      await db.delete(db.onlinePriceCache).go();
      remote.articles = [];
      await repo.refresh(force: true);

      final cached = await db.select(db.onlinePriceCache).getSingle();
      expect(cached.available, isFalse);
      expect(cached.priceCents, isNull);
      expect(cached.name, 'Clever Vollmilch');
    });

    test('ohne force hoechstens alle 6 Stunden', () async {
      remote.articles = [onlineArticle()];
      final repo = repoOf();
      await repo.link('p1', onlineArticle());

      expect(await repo.refresh(), isTrue);
      expect(remote.fetchCalls, 1);

      clock = clock.add(const Duration(hours: 5, minutes: 59));
      expect(await repo.refresh(), isFalse);
      expect(remote.fetchCalls, 1);

      expect(await repo.refresh(force: true), isTrue, reason: 'force ueberspringt die Sperre');
      expect(remote.fetchCalls, 2);

      clock = clock.add(const Duration(hours: 6, minutes: 1));
      expect(await repo.refresh(), isTrue);
      expect(remote.fetchCalls, 3);
    });

    test('kein Netz: kein Fehler, Zwischenspeicher und Sperre bleiben unveraendert (naechster Versuch geht gleich wieder)', () async {
      remote.articles = [onlineArticle()];
      final repo = repoOf();
      await repo.link('p1', onlineArticle());
      final before = await db.select(db.onlinePriceCache).getSingle();

      remote.fail = true;
      expect(await repo.refresh(force: true), isFalse);
      expect(await db.select(db.onlinePriceCache).getSingle(), before);
      expect(await db.getKv('online_prices_refreshed_at'), isNull);

      remote.fail = false;
      expect(await repo.refresh(), isTrue, reason: 'nach einem Fehler wird nicht 6 Stunden gewartet');
    });

    test('Verknuepfungen mehrerer Produkte werden in einem Aufruf geholt', () async {
      remote.articles = [onlineArticle(), onlineArticle(store: 'spar', externalId: '2020', name: 'A-zwei Vollmilch', priceCents: 208)];
      final repo = repoOf();
      await repo.link('p1', onlineArticle());
      await repo.link('p2', onlineArticle(store: 'spar', externalId: '2020', name: 'A-zwei Vollmilch', priceCents: 208));
      await repo.refresh(force: true);
      expect(remote.fetchCalls, 1);
      expect(await db.select(db.onlinePriceCache).get(), hasLength(2));
    });
  });

  group('suchen', () {
    test('reicht die Basiseinheit des Produkts in der Schreibweise des Feeds weiter', () async {
      remote.articles = [onlineArticle(), onlineArticle(store: 'spar', externalId: '2020', name: 'A-zwei Vollmilch')];
      final repo = repoOf();

      final found = await repo.search('Vollmilch', stores: ['spar'], productBaseUnit: 'piece');
      expect(found.map((a) => a.store), ['spar']);
      expect(remote.searches.single.preferBase, 'stk');
      expect(remote.searches.single.stores, ['spar']);

      await repo.search('Vollmilch', productBaseUnit: 'l');
      expect(remote.searches.last.preferBase, 'l');
      await repo.search('Vollmilch');
      expect(remote.searches.last.preferBase, isNull);
    });
  });

  group('Sync', () {
    test('Verknuepfung und Loesen kommen ueber den Server auf ein zweites Geraet', () async {
      final fake = FakeRemoteStore();
      final other = memoryDb();
      addTearDown(other.close);

      final repo = repoOf();
      await repo.link('p1', onlineArticle());
      await repo.link('p1', onlineArticle(store: 'spar', externalId: '2020', name: 'A-zwei Vollmilch'));
      await SyncEngine(db, fake).sync();
      await SyncEngine(other, fake).sync();

      final onOther = await (other.select(other.productOnlineLinks)..where((l) => l.deletedAt.isNull())).get();
      expect(onOther.map((l) => '${l.store}/${l.externalId}').toSet(), {'billa/00-1', 'spar/2020'});
      expect(onOther.every((l) => l.productId == 'p1' && l.householdId == 'h1'), isTrue);

      await repo.unlink(onOther.firstWhere((l) => l.store == 'spar').id);
      await SyncEngine(db, fake).sync();
      await SyncEngine(other, fake).sync();
      final remaining = await (other.select(other.productOnlineLinks)..where((l) => l.deletedAt.isNull())).get();
      expect(remaining.map((l) => l.store), ['billa']);
    });

    test('der Preis-Zwischenspeicher wird nicht synchronisiert', () async {
      final fake = FakeRemoteStore();
      await repoOf().link('p1', onlineArticle());
      await SyncEngine(db, fake).sync();
      expect(fake.tables.keys, contains('product_online_links'));
      expect(fake.tables.keys.any((t) => t.contains('cache') || t == 'online_prices'), isFalse);
    });
  });
}
