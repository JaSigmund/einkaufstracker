import 'package:einkaufstracker/data/nutrition/bls_food_search.dart';
import 'package:einkaufstracker/domain/nutrition/nutrient_scaling.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ranking und Zeilen-Parsing der BLS-Suche (ADR-024); die echte Abfrage braucht Netz und wird nicht getestet.
BlsFood food(String name) => BlsFood(code: name, nameDe: name, per100: const NutrientsPer100(kcal: 1));

void main() {
  group('rankBlsFoods', () {
    test('Namen, die mit der Eingabe beginnen, kommen vor Wortanfang-Treffern und sonstigen', () {
      final ranked = rankBlsFoods([food('Birne Apfel Mix'), food('Pfannkuchen mit Apfel'), food('Apfelkuchen'), food('Ananas')], 'apfel');
      // rankBlsFoods sortiert nur, es filtert nicht (der Server liefert ohnehin nur Treffer): Nicht-Treffer stehen zuletzt
      expect(ranked.map((f) => f.nameDe), ['Apfelkuchen', 'Birne Apfel Mix', 'Pfannkuchen mit Apfel', 'Ananas']);
    });

    test('innerhalb einer Stufe kuerzere Namen zuerst: "Apfel roh" vor "Apfelkuchen mit Streuseln"', () {
      final ranked = rankBlsFoods([food('Apfelkuchen mit Streuseln'), food('Apfel roh')], 'Apfel');
      expect(ranked.first.nameDe, 'Apfel roh');
    });

    test('gleiche Stufe, gleiche Laenge: alphabetisch', () {
      final ranked = rankBlsFoods([food('Apfel B'), food('Apfel A')], 'Apfel');
      expect(ranked.map((f) => f.nameDe), ['Apfel A', 'Apfel B']);
    });

    test('Gross-/Kleinschreibung und Leerraum der Eingabe spielen keine Rolle', () {
      expect(rankBlsFoods([food('Reis roh')], '  REIS ').single.nameDe, 'Reis roh');
    });

    test('Sonderzeichen in der Eingabe brechen die Sortierung nicht (Regex wird escaped)', () {
      expect(() => rankBlsFoods([food('Milch (3,5 %)')], '(3'), returnsNormally);
    });

    test('begrenzt auf die Maximalzahl der Treffer', () {
      final many = [for (var i = 0; i < 100; i++) food('Apfel $i')];
      expect(rankBlsFoods(many, 'apfel'), hasLength(blsSearchMaxResults));
    });
  });

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
    });
  });

  test('BlsSearchUnavailable zeigt seinen Text', () {
    expect(const BlsSearchUnavailable('Zeitueberschreitung').toString(), 'Zeitueberschreitung');
  });
}
