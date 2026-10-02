import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/nutrition/nutrient_scaling.dart';

/// Ein Lebensmittel aus dem Bundeslebensmittelschluessel (Tabelle `bls_foods`, ADR-024) mit Naehrwerten je 100 g.
class BlsFood {
  const BlsFood({required this.code, required this.nameDe, this.nameEn, required this.per100});

  final String code;
  final String nameDe;
  final String? nameEn;
  final NutrientsPer100 per100;
}

/// Die Lebensmitteldatenbank ist gerade nicht erreichbar (kein Netz, Serverfehler). Die Eingabe einer Zutat
/// blockiert das nie: Produkte aus dem Haushalt und Freitext funktionieren weiter (LH-NF-09).
class BlsSearchUnavailable implements Exception {
  const BlsSearchUnavailable([this.message = 'nicht erreichbar']);
  final String message;
  @override
  String toString() => message;
}

abstract class BlsFoodSearch {
  /// Sucht Lebensmittel nach deutschem Namen. Bei zu kurzer Eingabe leer, ohne Anfrage.
  Future<List<BlsFood>> search(String query);
}

const blsSearchMinChars = 2;
const blsSearchMaxResults = 25;

/// Sortiert Treffer so, dass das Naheliegende oben steht: Namen, die mit der Eingabe beginnen, vor Namen, in
/// denen ein Wort damit beginnt, vor sonstigen Treffern; innerhalb einer Stufe kuerzere Namen zuerst ("Apfel roh"
/// vor "Apfelkuchen mit Streuseln"), dann alphabetisch. Begrenzt auf [blsSearchMaxResults].
List<BlsFood> rankBlsFoods(Iterable<BlsFood> foods, String query) {
  final q = query.trim().toLowerCase();
  int rank(BlsFood f) {
    final name = f.nameDe.toLowerCase();
    if (name.startsWith(q)) return 0;
    if (RegExp('(^|[\\s,(/-])${RegExp.escape(q)}').hasMatch(name)) return 1;
    return 2;
  }

  final sorted = foods.toList()
    ..sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      final byLength = a.nameDe.length.compareTo(b.nameDe.length);
      return byLength != 0 ? byLength : a.nameDe.compareTo(b.nameDe);
    });
  return sorted.take(blsSearchMaxResults).toList();
}

/// Liest eine Zeile von `bls_foods`. PostgREST liefert `numeric` als Zahl, aelterer oder anders konfigurierter Server
/// auch als Text: beides wird gelesen, Unlesbares wird `null`.
BlsFood blsFoodFromRow(Map<String, dynamic> row) {
  double? n(String key) {
    final v = row[key];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '.'));
    return null;
  }

  return BlsFood(
    code: row['bls_code'] as String,
    nameDe: row['name_de'] as String,
    nameEn: row['name_en'] as String?,
    per100: NutrientsPer100(
      kcal: n('kcal'),
      proteinG: n('protein_g'),
      fatG: n('fat_g'),
      satFatG: n('sat_fat_g'),
      carbsG: n('carbs_g'),
      sugarG: n('sugar_g'),
      fiberG: n('fiber_g'),
      saltG: n('salt_g'),
    ),
  );
}

/// Sucht online in `bls_foods` (nur lesbar fuer angemeldete Nutzer, Migration 0014).
class SupabaseBlsFoodSearch implements BlsFoodSearch {
  SupabaseBlsFoodSearch(this._client);
  final SupabaseClient _client;

  static const _columns = 'bls_code,name_de,name_en,kcal,protein_g,fat_g,sat_fat_g,carbs_g,sugar_g,fiber_g,salt_g';

  @override
  Future<List<BlsFood>> search(String query) async {
    final q = query.trim();
    if (q.length < blsSearchMinChars) return const [];
    try {
      // Mehr holen als angezeigt, weil erst clientseitig sinnvoll sortiert wird (alphabetisch waere "Apfelkuchen" vor "Apfel roh").
      final rows = await _client.from('bls_foods').select(_columns).ilike('name_de', '%$q%').limit(150).timeout(const Duration(seconds: 15));
      return rankBlsFoods([for (final r in rows) blsFoodFromRow(r)], q);
    } catch (e) {
      throw BlsSearchUnavailable(e.toString());
    }
  }
}
