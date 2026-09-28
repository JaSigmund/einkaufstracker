import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/sync/sync_engine.dart';
import 'package:einkaufstracker/domain/diagnostics/app_info.dart';
import 'package:einkaufstracker/domain/diagnostics/data_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  group('create', () {
    test('speichert Titel, Beschreibung und technischen Stand, landet in der Outbox', () async {
      var changed = 0;
      final repo = bugReportRepo(db, onChanged: () => changed++);
      final report = await repo.create(
        title: '  Scan legt Duplikat an  ',
        description: 'War passiert...',
        appInfo: {'platform': 'android', 'pending_changes': 0},
      );
      expect(report.title, 'Scan legt Duplikat an');
      expect(report.status, 'new'); // Bearbeitungsstatus wird von der Entwicklung gesetzt, nicht vom Melder
      expect(report.kind, 'bug'); // Standard, sofern nicht anders angegeben
      expect(changed, 1);
      expect(jsonDecode(report.appInfo)['platform'], 'android');
      expect((await db.select(db.outbox).get()).map((o) => o.remoteTable), contains('bug_reports'));
    });

    test('leerer Titel wird abgelehnt', () {
      expect(() => bugReportRepo(db).create(title: '   ', appInfo: const {}), throwsArgumentError);
    });

    test('leere Beschreibung wird zu null', () async {
      final report = await bugReportRepo(db).create(title: 'x', description: '   ', appInfo: const {});
      expect(report.description, isNull);
    });

    test('mit Datenausschnitt (jsonb-taugliche verschachtelte Struktur)', () async {
      final report = await bugReportRepo(db).create(
        title: 'x',
        appInfo: const {'platform': 'android'},
        dataSnapshot: const {
          'receipts': [
            {'id': 'r1', 'total_cents': 1234},
          ],
        },
      );
      final decoded = jsonDecode(report.dataSnapshot!);
      expect(decoded['receipts'][0]['total_cents'], 1234);
    });
  });

  group('kind (Gesamtkonzept Feedback-Warteschlange, 2026-09-28)', () {
    test('Feature-Vorschlag bekommt kind=feature statt des Standards bug', () async {
      final report = await bugReportRepo(db).create(title: 'Trend-Export als CSV', appInfo: const {}, kind: 'feature');
      expect(report.kind, 'feature');
    });

    test('watchPlanningList zeigt nur angenommene Feature-Vorschlaege, aelteste zuerst', () async {
      final repo = bugReportRepo(db);
      final bug = await repo.create(title: 'Ein Bug', appInfo: const {});
      final newFeature = await repo.create(title: 'Neuer Vorschlag', appInfo: const {}, kind: 'feature');
      final confirmedOld = await repo.create(title: 'Alt angenommen', appInfo: const {}, kind: 'feature');
      final confirmedNew = await repo.create(title: 'Neu angenommen', appInfo: const {}, kind: 'feature');
      final inProgress = await repo.create(title: 'Schon in Umsetzung', appInfo: const {}, kind: 'feature');

      // Status setzen, wie es sonst per SQL durch die Entwicklung passiert (siehe Sync-Test oben)
      Future<void> setStatus(String id, String status) => (db.update(db.bugReports)..where((b) => b.id.equals(id))).write(
            BugReportsCompanion(status: Value(status)),
          );
      await setStatus(bug.id, 'confirmed');
      await setStatus(confirmedOld.id, 'confirmed');
      await setStatus(confirmedNew.id, 'confirmed');
      await setStatus(inProgress.id, 'in_progress');

      final planning = await repo.watchPlanningList().first;
      expect(planning.map((r) => r.id), [confirmedOld.id, confirmedNew.id]);
      expect(planning.any((r) => r.id == bug.id), isFalse); // kein Bug, auch wenn confirmed
      expect(planning.any((r) => r.id == newFeature.id), isFalse); // noch nicht angenommen
      expect(planning.any((r) => r.id == inProgress.id), isFalse); // schon in Umsetzung, nicht mehr "geplant"
    });
  });

  test('watchAll zeigt die juengsten zuerst', () async {
    final repo = bugReportRepo(db);
    await repo.create(title: 'Erster', appInfo: const {});
    await repo.create(title: 'Zweiter', appInfo: const {});
    final list = await repo.watchAll().first;
    expect(list.map((r) => r.title), ['Zweiter', 'Erster']);
  });

  test('Sync: der Bericht (inkl. verschachteltem JSON) kommt auf einem zweiten Geraet an', () async {
    final remote = FakeRemoteStore();
    await bugReportRepo(db).create(
      title: 'Sync-Test',
      appInfo: const {'platform': 'android', 'route': 'Inventar'},
      dataSnapshot: const {
        'inventory_items': [
          {'id': 'i1', 'quantity': 2.5},
        ],
      },
    );
    await SyncEngine(db, remote).sync();
    final remoteRow = remote.table('bug_reports').values.single;
    expect(remoteRow['app_info'], {'platform': 'android', 'route': 'Inventar'}); // echtes JSON, kein String

    final db2 = memoryDb();
    addTearDown(db2.close);
    await SyncEngine(db2, remote).sync();
    final synced = await db2.select(db2.bugReports).getSingle();
    expect(jsonDecode(synced.appInfo)['route'], 'Inventar');
    expect(jsonDecode(synced.dataSnapshot!)['inventory_items'][0]['quantity'], 2.5);
  });

  group('Sync uebernimmt einen von der Entwicklung gesetzten Status', () {
    test('Status, Schweregrad, Loesung und Version kommen auf einem zweiten Geraet an', () async {
      final remote = FakeRemoteStore();
      final report = await bugReportRepo(db).create(title: 'x', appInfo: const {});
      await SyncEngine(db, remote).sync();
      // wie ein SQL-Update durch die Entwicklung (siehe supabase/tests): der Server kennt den Fehlerbericht
      // schon mit Status, das simulieren wir hier direkt im Fake-Remote-Store.
      final row = Map<String, dynamic>.from(remote.table('bug_reports')[report.id]!);
      row['status'] = 'fixed';
      row['severity'] = 'medium';
      row['resolution'] = 'Behoben in PR #20.';
      row['fixed_in_version'] = '1.1.0';
      row['status_updated_at'] = DateTime.utc(2026, 9, 28).toIso8601String();
      await remote.upsert('bug_reports', row);

      final db2 = memoryDb();
      addTearDown(db2.close);
      await SyncEngine(db2, remote).sync();
      final synced = await db2.select(db2.bugReports).getSingle();
      expect((synced.status, synced.severity, synced.resolution, synced.fixedInVersion), ('fixed', 'medium', 'Behoben in PR #20.', '1.1.0'));
    });
  });

  group('collectAppInfo', () {
    test('enthaelt Plattform, Route, ausstehende Aenderungen und Sync-Stand', () {
      final info = collectAppInfo(route: 'Inventar', pendingChanges: 3, lastSyncError: 'kein Netz', lastSyncAt: DateTime.utc(2026, 9, 27, 10));
      expect(info['route'], 'Inventar');
      expect(info['pending_changes'], 3);
      expect(info['last_sync_error'], 'kein Netz');
      expect(info['last_sync_at'], DateTime.utc(2026, 9, 27, 10).toIso8601String());
      expect(info['platform'], isNotEmpty);
      expect(info['reported_at_utc'], isNotEmpty);
    });

    test('ohne Sync-Fehler bleibt das Feld null', () {
      final info = collectAppInfo(route: 'Scan', pendingChanges: 0);
      expect(info['last_sync_error'], isNull);
    });
  });

  group('buildDataSnapshot', () {
    test('enthaelt die wichtigsten Tabellen, begrenzt und ohne geloeschte Zeilen', () async {
      await db.into(db.receipts).insert(Receipt(
            id: 'r1', householdId: 'h1', purchasedAt: DateTime.utc(2026, 9, 1), totalCents: 100, status: 'confirmed',
            source: 'manual', sumMismatch: false, updatedAt: DateTime.utc(2026, 9, 1),
          ));
      await db.into(db.receipts).insert(Receipt(
            id: 'r2', householdId: 'h1', purchasedAt: DateTime.utc(2026, 9, 2), totalCents: 200, status: 'confirmed',
            source: 'manual', sumMismatch: false, updatedAt: DateTime.utc(2026, 9, 2), deletedAt: DateTime.utc(2026, 9, 3),
          ));
      final snapshot = await buildDataSnapshot(db);
      expect(snapshot['receipts'], hasLength(1));
      expect(snapshot['receipts'].single['id'], 'r1');
      expect(snapshot.containsKey('inventory_items'), isTrue);
      expect(snapshot.containsKey('pending_outbox'), isTrue);
    });
  });
}
