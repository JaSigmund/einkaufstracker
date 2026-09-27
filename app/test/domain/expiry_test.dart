import 'package:einkaufstracker/domain/inventory/expiry.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime _d(int y, int m, int d) => DateTime.utc(y, m, d);

void main() {
  group('computeExpiresOn (Doku 06 §3, Tabelle)', () {
    test('MHD 15.10., nicht geoeffnet -> Ablauf 15.10.', () {
      expect(computeExpiresOn(bestBefore: _d(2026, 10, 15)), _d(2026, 10, 15));
    });

    test('MHD 15.10., geoeffnet am 1.10., Frist 3 Tage -> Ablauf 04.10.', () {
      expect(computeExpiresOn(bestBefore: _d(2026, 10, 15), openedOn: _d(2026, 10, 1), openShelfLifeDays: 3), _d(2026, 10, 4));
    });

    test('kein MHD, geoeffnet am 1.10., Frist 3 Tage -> Ablauf 04.10.', () {
      expect(computeExpiresOn(openedOn: _d(2026, 10, 1), openShelfLifeDays: 3), _d(2026, 10, 4));
    });

    test('MHD 02.10., geoeffnet am 1.10., Frist 7 Tage -> Ablauf 02.10. (MHD zuerst)', () {
      expect(computeExpiresOn(bestBefore: _d(2026, 10, 2), openedOn: _d(2026, 10, 1), openShelfLifeDays: 7), _d(2026, 10, 2));
    });

    test('nichts bekannt -> null', () {
      expect(computeExpiresOn(), isNull);
    });

    test('geoeffnet, aber keine Frist hinterlegt -> nur MHD zaehlt', () {
      expect(computeExpiresOn(bestBefore: _d(2026, 10, 15), openedOn: _d(2026, 10, 1)), _d(2026, 10, 15));
    });

    test('Uhrzeitanteile werden ignoriert (reines Kalenderdatum)', () {
      final bb = DateTime.utc(2026, 10, 15, 23, 59);
      final opened = DateTime.utc(2026, 10, 1, 5);
      expect(computeExpiresOn(bestBefore: bb, openedOn: opened, openShelfLifeDays: 3), _d(2026, 10, 4));
    });
  });

  group('expiryLevel (Doku 06 §3.1)', () {
    final today = _d(2026, 10, 1);

    test('kein Ablaufdatum -> unknown', () {
      expect(expiryLevel(expiresOn: null, dateKind: 'best_before', today: today), ExpiryLevel.unknown);
    });

    test('MHD: rot ab dem Ablauftag, gelb innerhalb der Vorlaufzeit, sonst gruen', () {
      expect(expiryLevel(expiresOn: _d(2026, 9, 30), dateKind: 'best_before', today: today), ExpiryLevel.expired);
      expect(expiryLevel(expiresOn: today, dateKind: 'best_before', today: today), ExpiryLevel.soon);
      expect(expiryLevel(expiresOn: _d(2026, 10, 4), dateKind: 'best_before', today: today, leadDays: 3), ExpiryLevel.soon);
      expect(expiryLevel(expiresOn: _d(2026, 10, 5), dateKind: 'best_before', today: today, leadDays: 3), ExpiryLevel.ok);
    });

    test('Verbrauchsdatum: gelb schon einen Tag vorher, unabhaengig von leadDays', () {
      expect(expiryLevel(expiresOn: _d(2026, 10, 2), dateKind: 'use_by', today: today, leadDays: 7), ExpiryLevel.soon);
      expect(expiryLevel(expiresOn: _d(2026, 10, 3), dateKind: 'use_by', today: today, leadDays: 7), ExpiryLevel.ok);
      expect(expiryLevel(expiresOn: today, dateKind: 'use_by', today: today), ExpiryLevel.soon);
      expect(expiryLevel(expiresOn: _d(2026, 9, 30), dateKind: 'use_by', today: today), ExpiryLevel.expired);
    });
  });
}
