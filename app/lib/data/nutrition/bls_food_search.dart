import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/nutrition/food_match.dart';
import '../../domain/nutrition/micros.dart';
import '../../domain/nutrition/nutrient_scaling.dart';

/// Ein Lebensmittel aus dem Bundeslebensmittelschluessel (Tabelle `bls_foods`, ADR-024) mit Naehrwerten je 100 g.
///
/// Kommt es aus der Zuordnungs-Suche (SQL-Funktion `search_bls_foods`, Phase N1), steht dabei, woher der Treffer stammt
/// ([method]: `memory` | `synonym` | `search`) und wie sicher er ist ([confidence]: `sure` | `auto` | `unsure`, nur fuer
/// den ersten Treffer sinnvoll).
class BlsFood {
  const BlsFood({required this.code, required this.nameDe, this.nameEn, required this.per100, this.method, this.confidence, this.micros});

  final String code;
  final String nameDe;
  final String? nameEn;
  final NutrientsPer100 per100;
  final String? method;
  final String? confidence;

  /// Die 38 Mikronaehrstoffe je 100 g (Phase N3), `null`, wenn die Zeile keine mitbrachte.
  final Micros? micros;

  /// Als Treffer mit Sicherheit: sicher (Gedaechtnis, Synonym) oder automatisch, `unknown` bei `unsure`/ohne Angabe.
  MatchTrust get trust => confidence == 'sure' ? MatchTrust.sure : (confidence == 'auto' ? MatchTrust.auto : MatchTrust.unknown);

  FoodMatch toMatch({MatchTrust? trust}) => FoodMatch(
        code: code,
        name: nameDe,
        per100: per100,
        method: method ?? 'search',
        trust: trust ?? (this.trust == MatchTrust.unknown ? MatchTrust.auto : this.trust),
        micros: micros,
      );
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
  /// Handsuche nach einem Namen: auch Treffer, die nur einen Teil der Woerter enthalten, die besten zuerst (Gedaechtnis des
  /// Haushalts und Synonyme vor der Namenssuche). Bei zu kurzer Eingabe leer, ohne Anfrage.
  Future<List<BlsFood>> search(String query);

  /// Ordnet einen Namen zu: die besten [limit] Treffer, der erste mit Sicherheit ([BlsFood.confidence]). Leer, wenn nichts
  /// passt. Wirft [BlsSearchUnavailable] ohne Netz.
  Future<List<BlsFood>> resolve(String name, {int limit = 3});

  /// Die Eintraege zu diesen BLS-Codes (zum Nachrechnen der Mikronaehrstoffe aelterer Mahlzeiten, Phase N4). Unbekannte Codes fehlen in
  /// der Antwort. Wirft [BlsSearchUnavailable] ohne Netz.
  Future<List<BlsFood>> byCodes(Iterable<String> codes);
}

const blsSearchMinChars = 2;
const blsSearchMaxResults = 25;

/// Liest eine Zeile von `search_bls_foods` oder `bls_foods`. PostgREST liefert `numeric` als Zahl, aelter oder anders
/// konfigurierter Server auch als Text: beides wird gelesen, Unlesbares wird `null`.
BlsFood blsFoodFromRow(Map<String, dynamic> row) {
  double? n(String key) {
    final v = row[key];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '.'));
    return null;
  }

  final method = row['method'];
  final confidence = row['confidence'];
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
    method: method is String ? method : null,
    confidence: confidence is String ? confidence : null,
    micros: parseMicros(row['nutrients']),
  );
}

/// Sucht ueber die SQL-Funktion `search_bls_foods` (Migration 0022): Gedaechtnis des Haushalts, Synonyme, Namenssuche mit
/// Wertung. Die Reihung steckt im Server, damit App, Edge Function und Test dieselbe haben.
class SupabaseBlsFoodSearch implements BlsFoodSearch {
  SupabaseBlsFoodSearch(this._client);
  final SupabaseClient _client;

  Future<List<BlsFood>> _call(String query, {required int limit, required bool loose}) async {
    try {
      final rows = await _client
          .rpc('search_bls_foods', params: {'q': query.trim(), 'n': limit, 'p_loose': loose})
          .timeout(const Duration(seconds: 15));
      return [for (final r in rows as List) blsFoodFromRow(Map<String, dynamic>.from(r as Map))];
    } catch (e) {
      throw BlsSearchUnavailable(e.toString());
    }
  }

  @override
  Future<List<BlsFood>> search(String query) async {
    if (query.trim().length < blsSearchMinChars) return const [];
    return _call(query, limit: blsSearchMaxResults, loose: true);
  }

  @override
  Future<List<BlsFood>> resolve(String name, {int limit = 3}) async {
    if (name.trim().length < blsSearchMinChars) return const [];
    return _call(name, limit: limit, loose: false);
  }

  @override
  Future<List<BlsFood>> byCodes(Iterable<String> codes) async {
    final unique = codes.toSet().toList();
    final out = <BlsFood>[];
    try {
      // in Stuecken, damit die Anfrage-Adresse kurz bleibt
      for (var i = 0; i < unique.length; i += 80) {
        final chunk = unique.sublist(i, i + 80 > unique.length ? unique.length : i + 80);
        final rows = await _client.from('bls_foods').select().inFilter('bls_code', chunk).timeout(const Duration(seconds: 15));
        out.addAll([for (final r in rows as List) blsFoodFromRow(Map<String, dynamic>.from(r as Map))]);
      }
    } catch (e) {
      throw BlsSearchUnavailable(e.toString());
    }
    return out;
  }
}
