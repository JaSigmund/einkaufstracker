import 'package:einkaufstracker/domain/nutrition/fefo_deduction.dart';
import 'package:flutter_test/flutter_test.dart';

/// Testet den FEFO-Abzug fuers Essenstagebuch (Doku 15 §3.4, FR-10/FR-11, Phase 7 Vorbereitung).
void main() {
  DateTime d(int day) => DateTime.utc(2026, 10, day);

  test('zieht zuerst vom Posten mit dem fruehesten Ablaufdatum ab', () {
    final result = allocateFefo([
      FefoCandidate(inventoryItemId: 'a', availableQuantity: 1, expiresOn: d(20)),
      FefoCandidate(inventoryItemId: 'b', availableQuantity: 1, expiresOn: d(10)),
    ], 0.5);

    expect(result.allocations.single.inventoryItemId, 'b');
    expect(result.allocations.single.quantity, 0.5);
    expect(result.shortfall, 0);
  });

  test('reicht ein Posten nicht, wird der naechste angebrochen (mehrere Allokationen)', () {
    final result = allocateFefo([
      FefoCandidate(inventoryItemId: 'fruehes', availableQuantity: 0.3, expiresOn: d(5)),
      FefoCandidate(inventoryItemId: 'spaetes', availableQuantity: 1, expiresOn: d(20)),
    ], 0.5);

    expect(result.allocations.map((a) => (a.inventoryItemId, a.quantity)), [('fruehes', 0.3), ('spaetes', 0.2)]);
    expect(result.shortfall, 0);
  });

  test('Posten ohne Ablaufdatum wird zuletzt abgezogen (unbekannt zuletzt, wie im Inventar)', () {
    final result = allocateFefo([
      const FefoCandidate(inventoryItemId: 'unbekannt', availableQuantity: 1, expiresOn: null),
      FefoCandidate(inventoryItemId: 'bekannt', availableQuantity: 1, expiresOn: d(15)),
    ], 1.5);

    expect(result.allocations.map((a) => a.inventoryItemId), ['bekannt', 'unbekannt']);
    expect(result.allocations[0].quantity, 1);
    expect(result.allocations[1].quantity, 0.5);
  });

  test('Bestand reicht nicht: Rest als shortfall, kein negativer Abzug (FR-11)', () {
    final result = allocateFefo([FefoCandidate(inventoryItemId: 'a', availableQuantity: 0.4, expiresOn: d(1))], 1.0);

    expect(result.allocations.single.quantity, 0.4);
    expect(result.shortfall, closeTo(0.6, 1e-9));
  });

  test('kein Bestand vorhanden: alles shortfall, keine Allokationen', () {
    final result = allocateFefo(const [], 1.0);
    expect(result.allocations, isEmpty);
    expect(result.shortfall, 1.0);
  });

  test('Menge von 0: keine Allokation, kein shortfall', () {
    final result = allocateFefo([FefoCandidate(inventoryItemId: 'a', availableQuantity: 1, expiresOn: d(1))], 0);
    expect(result.allocations, isEmpty);
    expect(result.shortfall, 0);
  });

  test('Posten mit 0 verfuegbarer Menge werden uebersprungen', () {
    final result = allocateFefo([
      FefoCandidate(inventoryItemId: 'leer', availableQuantity: 0, expiresOn: d(1)),
      FefoCandidate(inventoryItemId: 'voll', availableQuantity: 1, expiresOn: d(2)),
    ], 0.5);
    expect(result.allocations.single.inventoryItemId, 'voll');
  });
}
