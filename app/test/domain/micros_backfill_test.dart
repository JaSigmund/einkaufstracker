import 'package:einkaufstracker/domain/nutrition/micros_backfill.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mikronaehrstoffe aelterer Mahlzeiten nachrechnen (Phase N4).
BackfillIngredient ing(String id, {String? productId, String? blsCode, double? grams = 100, bool hasMicros = false}) =>
    (id: id, productId: productId, blsCode: blsCode, grams: grams, hasMicros: hasMicros);

void main() {
  final bls = {
    'F1': {'vit_c_mg': 50.0, 'iron_mg': 2.0},
    'F2': {'vit_d_ug': 10.0},
  };

  test('BLS-Zeile: Profil je 100 g auf die gespeicherte Menge', () {
    final plan = planMicrosBackfill([ing('a', blsCode: 'F1', grams: 250)], blsMicros100: bls);
    expect(plan.updates['a']!['vit_c_mg'], closeTo(125, 1e-9));
    expect(plan.updates['a']!['iron_mg'], closeTo(5, 1e-9));
    expect([plan.withoutAmount, plan.withoutData], [0, 0]);
  });

  test('eine Zutat mit Snapshot bleibt unberuehrt, es wird nur ergaenzt', () {
    final plan = planMicrosBackfill([ing('a', blsCode: 'F1', hasMicros: true)], blsMicros100: bls);
    expect(plan.updates, isEmpty);
    expect(backfillCandidateCount([ing('a', blsCode: 'F1', hasMicros: true)]), 0);
    expect(backfillBlsCodes([ing('a', blsCode: 'F1', hasMicros: true)]), isEmpty);
  });

  test('Produkt mit eigenen Mikronaehrstoffen geht dem BLS-Eintrag der Zeile vor', () {
    final plan = planMicrosBackfill(
      [ing('a', productId: 'p1', blsCode: 'F1', grams: 200)],
      productMicros100: {'p1': {'vit_c_mg': 10.0}},
      blsMicros100: bls,
    );
    expect(plan.updates['a'], {'vit_c_mg': 20.0});
    expect(backfillBlsCodes([ing('a', productId: 'p1', blsCode: 'F1')], productMicros100: {'p1': {'vit_c_mg': 10.0}}), isEmpty, reason: 'nichts vom Server noetig');
  });

  test('Produkt ohne eigenes Profil: BLS-Eintrag der Zeile, sonst der des Produkts', () {
    final viaRow = planMicrosBackfill([ing('a', productId: 'p1', blsCode: 'F1')], blsMicros100: bls, productBlsCodes: {'p1': 'F2'});
    expect(viaRow.updates['a']!.containsKey('vit_c_mg'), isTrue, reason: 'die Zeile gewinnt');
    final viaProduct = planMicrosBackfill([ing('b', productId: 'p1')], blsMicros100: bls, productBlsCodes: {'p1': 'F2'});
    expect(viaProduct.updates['b'], {'vit_d_ug': 10.0});
    expect(backfillBlsCodes([ing('a', productId: 'p1', blsCode: 'F1'), ing('b', productId: 'p1')], productBlsCodes: {'p1': 'F2'}), {'F1', 'F2'});
  });

  test('Handwerte ohne BLS-Eintrag und ohne Produkt gibt es nichts nachzurechnen, sie zaehlen auch nicht als Fehler', () {
    final plan = planMicrosBackfill([ing('a')], blsMicros100: bls);
    expect(plan.updates, isEmpty);
    expect([plan.withoutAmount, plan.withoutData], [0, 0]);
    expect(backfillCandidateCount([ing('a')]), 0);
  });

  test('ohne bekannte Menge kein Snapshot, aber gezaehlt', () {
    final plan = planMicrosBackfill([ing('a', blsCode: 'F1', grams: null), ing('b', blsCode: 'F1', grams: 0)], blsMicros100: bls);
    expect(plan.updates, isEmpty);
    expect(plan.withoutAmount, 2);
  });

  test('Quelle ohne Mikronaehrstoffe oder Code ohne Eintrag: "ohne Daten", nichts wird erfunden', () {
    final plan = planMicrosBackfill([ing('a', blsCode: 'F9'), ing('b', blsCode: 'F3')], blsMicros100: {...bls, 'F3': <String, double>{}});
    expect(plan.updates, isEmpty);
    expect(plan.withoutData, 2);
  });

  test('Kandidaten: alle Zutaten ohne Snapshot, fuer die es eine Quelle gibt', () {
    final list = [
      ing('a', blsCode: 'F1'),
      ing('b', productId: 'p1'),
      ing('c', productId: 'p2'),
      ing('d'),
      ing('e', blsCode: 'F1', hasMicros: true),
    ];
    expect(backfillCandidateCount(list, productMicros100: {'p1': {'iron_mg': 1.0}}, productBlsCodes: const {}), 2);
    expect(backfillCandidateCount(list, productMicros100: {'p1': {'iron_mg': 1.0}}, productBlsCodes: {'p2': 'F2'}), 3);
  });
}
