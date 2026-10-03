import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/nutrition/food_unit.dart';

/// Haushaltsmasse eines BLS-Lebensmittels aus der Tabelle `food_units` (Migration 0024, Phase N2). Wie die BLS-Suche online:
/// ohne Netz bleibt die Liste leer, und der Mengen-Dialog bietet nur Gramm, Milliliter und das eigene Stueckgewicht an.
abstract class FoodUnitsSource {
  /// Die bekannten Einheiten zu [blsCode], leer wenn es keine gibt oder die Abfrage scheitert (nie ein Fehler).
  Future<List<FoodUnit>> unitsFor(String blsCode);
}

class SupabaseFoodUnitsSource implements FoodUnitsSource {
  SupabaseFoodUnitsSource(this._client);
  final SupabaseClient _client;

  /// Die Tabelle aendert sich nur mit einem Import, deshalb genuegt ein Zwischenspeicher fuer die Laufzeit der App.
  final _cache = <String, List<FoodUnit>>{};

  @override
  Future<List<FoodUnit>> unitsFor(String blsCode) async {
    final cached = _cache[blsCode];
    if (cached != null) return cached;
    try {
      final rows = await _client
          .from('food_units')
          .select('bls_code, unit_key, size, grams_edible, source')
          .eq('bls_code', blsCode)
          .timeout(const Duration(seconds: 10));
      final units = <FoodUnit>[];
      for (final r in rows as List) {
        final unit = foodUnitFromRow(Map<String, dynamic>.from(r as Map));
        if (unit != null) units.add(unit);
      }
      return _cache[blsCode] = units;
    } catch (_) {
      return const [];
    }
  }
}
