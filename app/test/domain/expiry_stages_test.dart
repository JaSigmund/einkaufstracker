import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/domain/notifications/expiry_reminders.dart';
import 'package:einkaufstracker/domain/notifications/expiry_stages.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mehrstufige Ablauf-Erinnerungen (Ausbau 1.14).
DateTime _d(int y, int m, int d) => DateTime.utc(y, m, d);

InventoryItem _item(String productId, DateTime expiresOn, {String dateKind = 'best_before'}) => InventoryItem(
      id: 'i-$productId',
      householdId: 'h1',
      productId: productId,
      quantity: 1,
      unit: 'piece',
      location: 'pantry',
      dateKind: dateKind,
      status: 'sealed',
      isSuggestion: false,
      expiresOn: expiresOn,
      updatedAt: DateTime.utc(2026),
    );

void main() {
  group('parseExpiryStages', () {
    test('liest Zahlen, auch als Text, ohne Doppelte, groesste zuerst', () {
      expect(parseExpiryStages([1, 3, '0', 3]), [3, 1, 0]);
    });

    test('nur 0 bis 13, hoechstens vier, alles andere faellt weg', () {
      expect(parseExpiryStages([20, -1, 2, 'x', null, 1.5]), [2, 1], reason: '1.5 wird zu 1');
      expect(parseExpiryStages([7, 5, 3, 2, 1, 0]), [7, 5, 3, 2]);
    });

    test('nichts Brauchbares ist null (dann gilt der Standard), auch bei einem Nicht-Array', () {
      expect(parseExpiryStages(const []), isNull);
      expect(parseExpiryStages([99, 'x']), isNull);
      expect(parseExpiryStages(null), isNull);
      expect(parseExpiryStages('3'), isNull);
      expect(parseExpiryStages({'a': 1}), isNull);
    });
  });

  group('effectiveExpiryStages', () {
    test('Mindesthaltbarkeit behaelt die Stufen', () {
      expect(effectiveExpiryStages('best_before', [3, 1, 0]), [3, 1, 0]);
    });

    test('ein Verbrauchsdatum erinnert nie frueher als einen Tag vorher', () {
      expect(effectiveExpiryStages('use_by', [3, 1, 0]), [1, 0]);
      expect(effectiveExpiryStages('use_by', [7]), [1]);
      expect(effectiveExpiryStages('use_by', [0]), [0]);
    });
  });

  test('describeExpiryStages', () {
    expect(describeExpiryStages([3, 1, 0]), '3 Tage und 1 Tag vorher, am Tag selbst');
    expect(describeExpiryStages([1]), '1 Tag vorher');
    expect(describeExpiryStages([0]), 'am Tag selbst');
    expect(describeExpiryStages([5, 2]), '5 Tage und 2 Tage vorher');
    expect(describeExpiryStages([0, 3]), '3 Tage vorher, am Tag selbst', reason: 'Reihenfolge egal');
  });

  test('der Schluessel je Produkt bleibt unter 64 Zeichen (Grenze der Einstellungen)', () {
    expect(expiryStagesPrefFor('12345678-1234-1234-1234-123456789012').length, lessThanOrEqualTo(64));
  });

  group('computeExpiryReminders mit Stufen', () {
    final today = _d(2026, 9, 27);
    List<ExpiryReminderDay> run(List<InventoryItem> items, {List<int>? stages, int lead = 1}) => computeExpiryReminders(
          activeItems: items,
          productNameById: {for (final i in items) i.productId: 'Produkt ${i.productId}'},
          leadDays: lead,
          today: today,
          stagesFor: stages == null ? null : (_) => stages,
        );

    test('ohne Stufen bleibt es bei der einen Vorlaufzeit (Verhalten wie vorher)', () {
      final r = run([_item('a', _d(2026, 10, 5))], lead: 2);
      expect(r.map((x) => x.date), [_d(2026, 10, 3)]);
    });

    test('mehrere Stufen ergeben mehrere Erinnerungstage fuer denselben Posten', () {
      final r = run([_item('a', _d(2026, 10, 5))], stages: [3, 0]);
      expect(r.map((x) => x.date), [_d(2026, 10, 2), _d(2026, 10, 5)]);
      expect(r.map((x) => x.leadDays), [3, 0]);
      expect(r.every((x) => x.productIds.single == 'a' && !x.isOverdue), isTrue);
    });

    test('Stufen mehrerer Produkte am selben Tag werden gebuendelt, der Text nennt die dringendere Vorlaufzeit', () {
      final r = run([_item('a', _d(2026, 10, 5)), _item('b', _d(2026, 10, 2))], stages: [3, 0]);
      // a: 2.10. (3 Tage vorher) und 5.10. (am Tag); b: 29.9. (3 vorher) und 2.10. (am Tag)
      expect(r.map((x) => x.date), [_d(2026, 9, 29), _d(2026, 10, 2), _d(2026, 10, 5)]);
      final shared = r[1];
      expect(shared.productIds.toSet(), {'a', 'b'});
      expect(shared.leadDays, 0, reason: '0 ist dringender als 3');
    });

    test('eine schon verstrichene Stufe wird nicht nachgeholt, solange eine spaetere bevorsteht', () {
      // Ablauf in 2 Tagen, Stufen 7 und 3 schon vorbei, 0 steht noch aus
      final r = run([_item('a', _d(2026, 9, 29))], stages: [7, 3, 0]);
      expect(r.map((x) => x.date), [_d(2026, 9, 29)]);
      expect(r.single.isOverdue, isFalse);
    });

    test('ist keine Stufe mehr zu erwarten, wird einmal nachgeholt (wie bisher), als faellig', () {
      final r = run([_item('a', _d(2026, 9, 25))], stages: [3, 0]);
      expect(r.single.date, today);
      expect(r.single.isOverdue, isTrue);
    });

    test('ein Verbrauchsdatum bekommt hoechstens die Stufen 1 und 0', () {
      final r = run([_item('a', _d(2026, 10, 5), dateKind: 'use_by')], stages: [3, 1, 0]);
      expect(r.map((x) => x.date), [_d(2026, 10, 4), _d(2026, 10, 5)]);
    });

    test('eine Stufe ausserhalb des Planungshorizonts wird nicht geplant, die naeheren schon', () {
      final r = run([_item('a', _d(2026, 10, 15))], stages: [5, 0]);
      // 5 Tage vorher = 10.10. (Offset 13, innerhalb), am Tag = 15.10. (Offset 18, ausserhalb)
      expect(r.map((x) => x.date), [_d(2026, 10, 10)]);
    });

    test('ohne Ablaufdatum nichts, auch mit Stufen', () {
      final noDate = InventoryItem(
        id: 'i-x', householdId: 'h1', productId: 'x', quantity: 1, unit: 'piece', location: 'pantry', dateKind: 'best_before', status: 'sealed',
        isSuggestion: false, updatedAt: DateTime.utc(2026),
      );
      expect(run([noDate], stages: [3, 0]), isEmpty);
    });
  });
}
