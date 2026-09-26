import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/data/remote/remote_store.dart';
import 'package:einkaufstracker/data/repositories/auth_repository.dart';
import 'package:einkaufstracker/data/repositories/category_repository.dart';

AppDatabase memoryDb() {
  // Mehrere In-Memory-Datenbanken je Test sind gewollt (simulieren mehrere Geraete)
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

/// Server-Attrappe im Speicher. Verhaelt sich wie Supabase: ein Trigger setzt updated_at bei jedem
/// Schreiben (streng monoton), Unique-Verletzung auf (household_id, name) bei categories.
class FakeRemoteStore implements RemoteStore {
  final Map<String, Map<String, Map<String, dynamic>>> tables = {};
  int _tick = 0;

  /// true = naechster Aufruf wirft einen Netzfehler
  bool offline = false;

  int upsertCalls = 0;

  Map<String, Map<String, dynamic>> table(String name) => tables.putIfAbsent(name, () => {});

  @override
  Future<List<Map<String, dynamic>>> fetchChanges(String tableName, {String? since, int limit = 500}) async {
    if (offline) throw const SocketException('offline');
    final rows = table(tableName).values.where((r) => since == null || (r['updated_at'] as String).compareTo(since) >= 0).toList()
      ..sort((a, b) => (a['updated_at'] as String).compareTo(b['updated_at'] as String));
    return rows.take(limit).map((r) => Map<String, dynamic>.from(r)).toList();
  }

  @override
  Future<void> upsert(String tableName, Map<String, dynamic> row) async {
    if (offline) throw const SocketException('offline');
    upsertCalls++;
    if (tableName == 'categories') {
      final clash = table(tableName).values.any((r) =>
          r['id'] != row['id'] && r['household_id'] == row['household_id'] && r['name'] == row['name']);
      if (clash) throw RemoteDataException('23505: duplicate key value violates unique constraint');
    }
    final stored = Map<String, dynamic>.from(row);
    stored['updated_at'] = DateTime.utc(2026, 9, 26, 12).add(Duration(seconds: ++_tick)).toIso8601String();
    table(tableName)[row['id'] as String] = stored;
  }
}

class FakeAuth implements AuthRepository {
  FakeAuth({this.failWith});
  final String? failWith;
  final signIns = <(String, String)>[];

  @override
  String? get currentEmail => 'test@example.com';

  @override
  Future<void> signIn(String email, String password) async {
    signIns.add((email, password));
    if (failWith != null) throw SignInFailure(failWith!);
  }

  @override
  Future<void> signOut() async {}
}

CategoryRepository categoryRepo(AppDatabase db, {String household = 'h1', void Function()? onChanged}) =>
    CategoryRepository(db, householdId: () async => household, onChanged: onChanged);
