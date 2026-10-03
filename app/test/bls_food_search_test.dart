import 'package:einkaufstracker/data/nutrition/bls_food_search.dart';
import 'package:einkaufstracker/domain/nutrition/food_match.dart';
import 'package:einkaufstracker/domain/nutrition/nutrient_scaling.dart';
import 'package:flutter_test/flutter_test.dart';

/// Zeilen-Parsing der BLS-Suche (ADR-024, Phase N1). Die Reihung steckt seit N1 in der SQL-Funktion `search_bls_foods` und
/// wird dort mit der echten BLS getestet (Golden-Test in supabase/tests/run_schema_tests.py); die echte Abfrage braucht
/// Netz und wird hier nicht getestet.
void main() {
  group('blsFoodFromRow', () {
    test('liest Zahlen und Text-Zahlen, Unlesbares wird null', () {
      final f = blsFoodFromRow({
        'bls_code': 'E111100',
        'name_de': 'Huehnerei roh',
        'name_en': 'Hen egg raw',
        'kcal': 135,
        'protein_g': '13,18',
        'fat_g': 9.0,
        'sat_fat_g': 'viel',
        'carbs_g': null,
      });
      expect(f.code, 'E111100');
      expect(f.nameEn, 'Hen egg raw');
      expect(f.per100.kcal, 135);
      expect(f.per100.proteinG, closeTo(13.18, 1e-9));
      expect(f.per100.fatG, 9);
      expect(f.per100.satFatG, isNull);
      expect(f.per100.carbsG, isNull);
      expect(f.method, isNull);
      expect(f.confidence, isNull);
      expect(f.trust, MatchTrust.unknown);
    });

    test('liest Verfahren und Sicherheit der Zuordnungs-Suche', () {
      BlsFood row(String method, String confidence) =>
          blsFoodFromRow({'bls_code': 'C352000', 'name_de': 'Reis poliert, roh', 'kcal': 351, 'method': method, 'confidence': confidence});
      expect(row('synonym', 'sure').trust, MatchTrust.sure);
      expect(row('search', 'auto').trust, MatchTrust.auto);
      expect(row('search', 'unsure').trust, MatchTrust.unknown);
      expect(row('memory', 'sure').method, 'memory');
    });
  });

  group('BlsFood.toMatch', () {
    const food = BlsFood(code: 'C352000', nameDe: 'Reis poliert, roh', per100: NutrientsPer100(kcal: 351), method: 'synonym', confidence: 'sure');

    test('uebernimmt Code, Name, Naehrwerte, Verfahren und Sicherheit', () {
      final m = food.toMatch();
      expect(m.code, 'C352000');
      expect(m.name, 'Reis poliert, roh');
      expect(m.per100.kcal, 351);
      expect(m.method, 'synonym');
      expect(m.trust, MatchTrust.sure);
      expect(m.alreadyKnown, isTrue);
    });

    test('ein unsicherer Treffer wird, wenn der Nutzer ihn waehlt, ein automatischer; die Sicherheit laesst sich vorgeben', () {
      const unsure = BlsFood(code: 'X', nameDe: 'Y', per100: NutrientsPer100(kcal: 1), method: 'search', confidence: 'unsure');
      expect(unsure.toMatch().trust, MatchTrust.auto);
      expect(unsure.toMatch(trust: MatchTrust.sure).trust, MatchTrust.sure);
      expect(unsure.toMatch().alreadyKnown, isFalse);
    });
  });

  test('BlsSearchUnavailable zeigt seinen Text', () {
    expect(const BlsSearchUnavailable('Zeitueberschreitung').toString(), 'Zeitueberschreitung');
  });
}
