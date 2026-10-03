import 'package:einkaufstracker/domain/nutrition/food_match.dart';
import 'package:einkaufstracker/domain/nutrition/meal_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

/// Antwort der Edge Function analyze-meal (Phase 7c): defensiv gelesen, ein kaputter Eintrag verwirft nicht alles.
void main() {
  test('normale Antwort', () {
    final a = parseMealAnalysis({
      'dish_title': 'Reispfanne',
      'meal_type_guess': 'dinner',
      'servings_visible': 2,
      'ingredients': [
        {'name': 'Reis', 'inventory_product_id': 'p1', 'est_amount_g': 150, 'confidence': 0.8},
        {'name': 'Paprika', 'inventory_product_id': null, 'est_amount_g': 80.5, 'confidence': 0.4},
      ],
      'notes': 'Öl nicht sichtbar',
    });
    expect(a.dishTitle, 'Reispfanne');
    expect(a.mealType, 'dinner');
    expect(a.servingsVisible, 2);
    expect(a.notes, 'Öl nicht sichtbar');
    expect(a.ingredients, hasLength(2));
    expect(a.ingredients[0].inventoryProductId, 'p1');
    expect(a.ingredients[0].estimatedGrams, 150);
    expect(a.ingredients[0].confidence, 0.8);
    expect(a.ingredients[1].inventoryProductId, isNull);
    expect(a.ingredients[1].estimatedGrams, 80.5);
    expect(a.isEmpty, isFalse);
  });

  test('Nicht-Objekt ergibt eine leere Analyse', () {
    for (final v in [null, 'text', 5, <Object?>[]]) {
      final a = parseMealAnalysis(v);
      expect(a.isEmpty, isTrue, reason: '$v');
      expect(a.dishTitle, isEmpty);
      expect(a.mealType, isNull);
    }
  });

  test('kaputte Zutaten werden einzeln verworfen', () {
    final a = parseMealAnalysis({
      'ingredients': [
        null,
        'Reis',
        {'name': ''},
        {'name': 7},
        {'name': '  Karotte ', 'est_amount_g': 80, 'confidence': 0.6},
      ],
    });
    expect(a.ingredients.map((i) => i.name), ['Karotte']);
  });

  test('0, negative und nicht numerische Mengen bedeuten "nicht schaetzbar"', () {
    final a = parseMealAnalysis({
      'ingredients': [
        {'name': 'A', 'est_amount_g': 0},
        {'name': 'B', 'est_amount_g': -4},
        {'name': 'C', 'est_amount_g': 'viel'},
        {'name': 'D'},
      ],
    });
    expect(a.ingredients.map((i) => i.estimatedGrams), [null, null, null, null]);
  });

  test('Konfidenz wird auf 0 bis 1 begrenzt, fehlende ist 0', () {
    final a = parseMealAnalysis({
      'ingredients': [
        {'name': 'A', 'confidence': 5},
        {'name': 'B', 'confidence': -1},
        {'name': 'C', 'confidence': 'hoch'},
        {'name': 'D'},
      ],
    });
    expect(a.ingredients.map((i) => i.confidence), [1.0, 0.0, 0.0, 0.0]);
  });

  test('leerer Text als Produkt-ID bedeutet kein Produkt', () {
    final a = parseMealAnalysis({
      'ingredients': [
        {'name': 'Ei', 'inventory_product_id': ''},
      ],
    });
    expect(a.ingredients.single.inventoryProductId, isNull);
  });

  test('Mahlzeitentyp nur aus der bekannten Liste, "unknown" und Unbekanntes sind null', () {
    expect(parseMealAnalysis({'meal_type_guess': 'breakfast'}).mealType, 'breakfast');
    expect(parseMealAnalysis({'meal_type_guess': 'unknown'}).mealType, isNull);
    expect(parseMealAnalysis({'meal_type_guess': 'brunch'}).mealType, isNull);
    expect(parseMealAnalysis({'meal_type_guess': 3}).mealType, isNull);
  });

  test('Portionen: nur positive Zahlen', () {
    expect(parseMealAnalysis({'servings_visible': 3}).servingsVisible, 3);
    expect(parseMealAnalysis({'servings_visible': 0}).servingsVisible, isNull);
    expect(parseMealAnalysis({'servings_visible': -1}).servingsVisible, isNull);
    expect(parseMealAnalysis({'servings_visible': 'zwei'}).servingsVisible, isNull);
  });

  test('Art und Zustand: nur bekannte Werte, sonst Essen ohne Zustand', () {
    final a = parseMealAnalysis({
      'ingredients': [
        {'name': 'Cola', 'kind': 'drink', 'state': 'ready_made'},
        {'name': 'Reis', 'kind': 'food', 'state': 'cooked'},
        {'name': 'Ei', 'kind': 'snack', 'state': 'roh'},
        {'name': 'Brot'},
      ],
    });
    expect(a.ingredients.map((i) => i.kind), ['drink', 'food', 'food', 'food']);
    expect(a.ingredients.map((i) => i.state), ['ready_made', 'cooked', null, null]);
    expect(a.ingredients.map((i) => i.isDrink), [true, false, false, false]);
  });

  group('Treffer der Lebensmitteldatenbank (Phase N1)', () {
    Map<String, dynamic> match({Object? per100, Object? code = 'G543100', Object? name = 'Gemüsepaprika rot, roh', Object? method, Object? trust}) =>
        {'code': code, 'name': name, 'per100': per100 ?? {'kcal': 31, 'protein_g': 1.0}, 'method': method, 'trust': trust};

    test('wird gelesen: Code, Name, Werte, Herkunft und Sicherheit', () {
      final a = parseMealAnalysis({
        'ingredients': [
          {'name': 'Paprika', 'match': match(method: 'synonym', trust: 'sure')},
          {'name': 'Quark', 'match': match(code: 'M713300', name: 'Speisequark', method: 'llm')},
        ],
      });
      final m = a.ingredients[0].match!;
      expect(m.code, 'G543100');
      expect(m.name, 'Gemüsepaprika rot, roh');
      expect(m.per100.kcal, 31);
      expect(m.per100.proteinG, 1.0);
      expect(m.method, 'synonym');
      expect(m.trust, MatchTrust.sure);
      expect(m.alreadyKnown, isTrue);
      final q = a.ingredients[1].match!;
      expect(q.method, 'llm');
      expect(q.trust, MatchTrust.auto, reason: 'ohne "sure" gilt: automatisch zugeordnet');
      expect(q.alreadyKnown, isFalse);
    });

    test('unlesbare oder unvollstaendige Treffer werden zu "kein Treffer", die Zutat bleibt', () {
      final a = parseMealAnalysis({
        'ingredients': [
          {'name': 'A', 'match': 'Paprika'},
          {'name': 'B', 'match': match(code: '')},
          {'name': 'C', 'match': match(name: 7)},
          {'name': 'D', 'match': match(per100: <String, dynamic>{})},
          {'name': 'E', 'match': match(per100: 'viel')},
          {'name': 'F', 'match': null},
          {'name': 'G'},
        ],
      });
      expect(a.ingredients.map((i) => i.name), ['A', 'B', 'C', 'D', 'E', 'F', 'G']);
      expect(a.ingredients.map((i) => i.match), everyElement(isNull));
    });

    test('unbekannte Herkunft wird als Suche gelesen', () {
      final m = parseFoodMatch(match(method: 'zauberei'))!;
      expect(m.method, 'search');
    });

    test('confirmed() macht aus einem automatischen Treffer einen sicheren und behaelt alles andere', () {
      final auto = parseFoodMatch(match(method: 'search'))!;
      final sure = auto.confirmed();
      expect(sure.trust, MatchTrust.sure);
      expect(sure.code, auto.code);
      expect(sure.name, auto.name);
      expect(sure.method, 'search');
      expect(sure.per100.kcal, 31);
    });

    test('Herkunft fuer die Speicherung: sicher bls_exact, automatisch bls_matched, unbekannt unknown', () {
      expect(MatchTrust.sure.basis, 'bls_exact');
      expect(MatchTrust.auto.basis, 'bls_matched');
      expect(MatchTrust.unknown.basis, 'unknown');
    });
  });

  test('keine Zutaten: leer, auch wenn Titel und Hinweis da sind', () {
    final a = parseMealAnalysis({'dish_title': 'Teller', 'ingredients': [], 'notes': 'kein Essen erkennbar'});
    expect(a.isEmpty, isTrue);
    expect(a.notes, 'kein Essen erkennbar');
  });
}
