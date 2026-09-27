import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../local/database.dart';
import '../sync/mappers.dart';

/// Fehlerberichte: lokal zuerst, wie die anderen Repositories (offline-first, Doku 03 §2.3). Der Nutzer soll
/// auch offline melden koennen, der Bericht geht beim naechsten Sync raus.
class BugReportRepository {
  BugReportRepository(this._db, {required this.householdId, this.onChanged, Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Future<String> Function() householdId;
  final void Function()? onChanged;
  final Uuid _uuid;

  Stream<List<BugReport>> watchAll() => (_db.select(_db.bugReports)
        ..where((b) => b.deletedAt.isNull())
        ..orderBy([(b) => OrderingTerm.desc(b.createdAt)]))
      .watch();

  Future<BugReport> create({
    required String title,
    String? description,
    required Map<String, dynamic> appInfo,
    Map<String, dynamic>? dataSnapshot,
  }) async {
    final t = title.trim();
    if (t.isEmpty) throw ArgumentError('Titel darf nicht leer sein');
    final hid = await householdId();
    final now = DateTime.now().toUtc();
    final report = BugReport(
      id: _uuid.v4(),
      householdId: hid,
      title: t,
      description: description?.trim().isEmpty == true ? null : description?.trim(),
      appInfo: jsonEncode(appInfo),
      dataSnapshot: dataSnapshot == null ? null : jsonEncode(dataSnapshot),
      createdAt: now,
      updatedAt: now,
    );
    await _put('bug_reports', report.id, bugReportToRemote(report), () => _db.into(_db.bugReports).insertOnConflictUpdate(report.toCompanion(false)));
    onChanged?.call();
    return report;
  }

  Future<void> _put(String remoteTable, String rowId, Map<String, dynamic> payload, Future<void> Function() writeLocal) async {
    await writeLocal();
    await _db.into(_db.outbox).insert(OutboxCompanion.insert(
          remoteTable: remoteTable,
          rowId: rowId,
          payload: jsonEncode(payload),
          createdAt: DateTime.now().toUtc(),
        ));
  }
}
