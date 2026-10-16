// Statische Regeln fuer den Quellcode (Codereview 2026-10-16): Schichten, Sicherheit und Barrierefreiheit, die sich am
// Quelltext pruefen lassen, ohne die App zu starten. Die Regeln sind ein "Sperrklinken"-Prinzip: bestehende Ausnahmen
// stehen namentlich in einer Liste (mit Grund), jede NEUE Verletzung laesst den Test scheitern. Wird eine Ausnahme
// behoben, muss sie auch aus der Liste verschwinden (sonst schlaegt der Test ebenfalls an, damit die Liste aktuell bleibt).
//
// Schichten (siehe README, Doku 03):
//   domain/   reine Fachlogik: kein Flutter, kein Supabase, keine Oberflaeche
//   data/     Datenbank, Server, Dateien: keine Oberflaeche (features/) und kein App-Rahmen (app/)
//   features/ Oberflaeche: spricht ueber Repositories mit dem Server, nie direkt mit Supabase
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Alle Dart-Dateien unter [dir] ohne generierten Code.
List<File> _dartFiles(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

String _rel(File f) => f.path.replaceAll('\\', '/');

/// Import-Ziele einer Datei, relativ aufgeloest auf einen Pfad unter lib/ ("lib/data/local/database.dart") bzw. als
/// Paketname ("package:flutter/material.dart").
List<String> _imports(File f) {
  final dir = File(f.path).parent.uri;
  final result = <String>[];
  for (final m in RegExp(r'''^\s*(?:import|export)\s+'([^']+)'(?:\s|;)''', multiLine: true).allMatches(f.readAsStringSync())) {
    final target = m.group(1)!;
    if (target.startsWith('package:einkaufstracker/')) {
      result.add('lib/${target.substring('package:einkaufstracker/'.length)}');
    } else if (target.startsWith('package:') || target.startsWith('dart:')) {
      result.add(target);
    } else {
      final resolved = dir.resolve(target).toFilePath().replaceAll('\\', '/');
      final i = resolved.lastIndexOf('lib/');
      result.add(i < 0 ? resolved : resolved.substring(i));
    }
  }
  return result;
}

/// Verletzungen einer Regel als "datei -> ziel".
Set<String> _violations(String layer, bool Function(String target) forbidden) => {
      for (final f in _dartFiles(layer))
        for (final t in _imports(f))
          if (forbidden(t)) '${_rel(f)} -> $t',
    };

void _expectRatchet(Set<String> actual, Set<String> allowed, String rule) {
  final added = actual.difference(allowed);
  final fixed = allowed.difference(actual);
  expect(added, isEmpty, reason: 'Neue Verletzung der Regel "$rule". Bitte die Abhaengigkeit umdrehen statt sie hier zu erlauben.');
  expect(fixed, isEmpty, reason: 'Diese Ausnahmen von "$rule" gibt es nicht mehr: bitte aus der Liste im Test entfernen.');
}

void main() {
  group('Schichten', () {
    test('domain/ haengt nicht von Oberflaeche, App-Rahmen, Flutter oder Supabase ab', () {
      // Bekannte Ausnahmen: die Fachlogik arbeitet hier noch direkt mit den von drift erzeugten Zeilenklassen. Sauberer
      // waeren eigene Fachtypen; bis dahin bleibt es bei diesen drei Dateien.
      const allowed = {
        'lib/domain/diagnostics/data_snapshot.dart -> package:drift/drift.dart',
        'lib/domain/diagnostics/data_snapshot.dart -> lib/data/local/database.dart',
        'lib/domain/notifications/expiry_reminders.dart -> lib/data/local/database.dart',
        'lib/domain/receipt/csv_export.dart -> lib/data/local/database.dart',
      };
      final actual = _violations('lib/domain', (t) =>
          t.startsWith('lib/features/') ||
          t.startsWith('lib/app/') ||
          t.startsWith('lib/data/') ||
          t.startsWith('package:flutter/') ||
          t.startsWith('package:flutter_riverpod/') ||
          t.startsWith('package:supabase_flutter/') ||
          t.startsWith('package:drift/'));
      _expectRatchet(actual, allowed, 'domain ist rein');
    });

    test('data/ haengt nicht von der Oberflaeche (features/) oder dem App-Rahmen (app/) ab', () {
      // Bekannte Ausnahmen: Schnittstellen bzw. Datentypen, die in Seiten-Dateien definiert sind und in die Datenschicht
      // (oder domain/) gehoeren: CookingChatContext/ChatMessage (cooking_chat_panel.dart) und ReceiptScanner/ScannedPage
      // (photo_receipt_service.dart).
      const allowed = {
        'lib/data/cloud/cooking_cloud.dart -> lib/features/recipes/cooking_chat_panel.dart',
        'lib/data/cloud/supabase_cooking_cloud.dart -> lib/features/recipes/cooking_chat_panel.dart',
        'lib/data/ocr/mlkit_receipt_scanner.dart -> lib/features/receipt_import/photo_receipt_service.dart',
      };
      final actual = _violations('lib/data', (t) => t.startsWith('lib/features/') || t.startsWith('lib/app/'));
      _expectRatchet(actual, allowed, 'data kennt keine Oberflaeche');
    });

    test('features/ sprechen nie direkt mit Supabase (nur ueber Repositories in data/)', () {
      final actual = _violations('lib/features', (t) => t.startsWith('package:supabase_flutter/') || t.startsWith('package:supabase/'));
      _expectRatchet(actual, const {}, 'Oberflaeche ohne direkten Serverzugriff');
    });

    test('core/ ist die unterste Schicht', () {
      // Bekannte Ausnahme: format.dart formatiert Fachtypen und bildet mit domain/receipt/csv_export.dart einen Kreis
      // (core -> domain -> core). Die Formatierer gehoeren eigentlich neben die Fachtypen oder in die Oberflaeche.
      const allowed = {
        'lib/core/format.dart -> lib/domain/nutrition/nutrition_targets.dart',
        'lib/core/format.dart -> lib/domain/receipt/vienna_time.dart',
        'lib/core/format.dart -> lib/domain/shopping_list/list_price_estimate.dart',
      };
      final actual = _violations('lib/core', (t) => t.startsWith('lib/') && !t.startsWith('lib/core/'));
      _expectRatchet(actual, allowed, 'core haengt von nichts ab');
    });
  });

  group('Sicherheit', () {
    final sources = {for (final f in _dartFiles('lib')) _rel(f): f.readAsStringSync()};

    test('keine Schluessel oder Tokens im App-Code (gehoeren in dart_defines.local.json bzw. Secrets der Functions)', () {
      final patterns = <String, RegExp>{
        'Anthropic-API-Key': RegExp(r'sk-ant-[A-Za-z0-9_-]{10,}'),
        'JWT (z.B. Service-Role-Key)': RegExp(r'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.'),
        'Service-Role erwaehnt': RegExp(r'service_role', caseSensitive: false),
        'Supabase-Secret-Key': RegExp(r'sb_secret_[A-Za-z0-9_-]{10,}'),
        'privater Schluessel': RegExp(r'-----BEGIN [A-Z ]*PRIVATE KEY-----'),
      };
      final hits = [
        for (final MapEntry(key: path, value: text) in sources.entries)
          for (final MapEntry(key: what, value: re) in patterns.entries)
            if (re.hasMatch(text)) '$path: $what',
      ];
      expect(hits, isEmpty);
    });

    test('Projekt-URL und Client-Schluessel kommen nur aus --dart-define, nie als Literal', () {
      final hardcoded = [
        for (final MapEntry(key: path, value: text) in sources.entries)
          if (RegExp(r'https://[a-z0-9]{20}\.supabase\.co').hasMatch(text) || RegExp(r'sb_publishable_[A-Za-z0-9_-]{10,}').hasMatch(text)) path,
      ];
      expect(hardcoded, isEmpty);
      expect(sources['lib/core/config.dart'], contains("String.fromEnvironment('SUPABASE_URL')"));
    });

    test('kein unverschluesseltes http:// im App-Code', () {
      final hits = [
        for (final MapEntry(key: path, value: text) in sources.entries)
          for (final m in RegExp(r'''['"]http://(?!localhost|127\.0\.0\.1)''').allMatches(text)) '$path:${text.substring(0, m.start).split('\n').length}',
      ];
      expect(hits, isEmpty);
    });

    test('kein print() im App-Code (debugPrint landet nur im Geraete-Log und wird im Release gedrosselt)', () {
      final hits = [
        for (final MapEntry(key: path, value: text) in sources.entries)
          for (final m in RegExp(r'(?<![A-Za-z_.])print\(').allMatches(text)) '$path:${text.substring(0, m.start).split('\n').length}',
      ];
      expect(hits, isEmpty);
    });
  });

  group('Barrierefreiheit im Quelltext', () {
    test('jeder IconButton hat einen tooltip (Screenreader lesen ihn vor, sonst nur "Schaltflaeche")', () {
      final missing = <String>[];
      for (final f in _dartFiles('lib')) {
        final text = f.readAsStringSync();
        for (final m in RegExp(r'IconButton(?:\.\w+)?\(').allMatches(text)) {
          var depth = 1, i = m.end;
          while (depth > 0 && i < text.length) {
            final c = text[i++];
            if (c == '(') depth++;
            if (c == ')') depth--;
          }
          if (!text.substring(m.start, i).contains('tooltip:')) {
            missing.add('${_rel(f)}:${text.substring(0, m.start).split('\n').length}');
          }
        }
      }
      expect(missing, isEmpty);
    });
  });
}
