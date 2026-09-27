import 'package:einkaufstracker/domain/inventory/shelf_life_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('suggestShelfLife (Doku 06 §3.2, Roadmap Phase 3)', () {
    test('Frischmilch: 3 Tage, Kuehlschrank', () {
      final s = suggestShelfLife('H-VOLLMILCH 1L');
      // "vollmilch" matcht vor dem generischen "milch"
      expect(s!.openedShelfLifeDays, 3);
      expect(s.location, 'fridge');
      expect(s.dateKind, 'best_before');
    });

    test('H-Milch wird vor der generischen Milch-Regel erkannt', () {
      final s = suggestShelfLife('Ja! Natuerlich H-Milch 3,5%');
      expect(s, isNotNull);
      expect(s!.location, 'fridge');
    });

    test('Joghurt: 4 Tage', () {
      expect(suggestShelfLife('Danone Joghurt Erdbeer')!.openedShelfLifeDays, 4);
    });

    test('Hartkaese: 12 Tage', () {
      expect(suggestShelfLife('Bergkaese am Stueck')!.openedShelfLifeDays, 12);
    });

    test('Hackfleisch: Verbrauchsdatum statt MHD', () {
      final s = suggestShelfLife('Rindfleisch Hackfleisch')!;
      expect(s.dateKind, 'use_by');
      expect(s.openedShelfLifeDays, 1);
    });

    test('Honig: kein Ablauf nach dem Oeffnen (praktisch unbegrenzt)', () {
      final s = suggestShelfLife('Blütenhonig')!;
      expect(s.openedShelfLifeDays, isNull);
      expect(s.location, 'pantry');
    });

    test('Eier: "ei" nur als eigenes Wort, nicht als Teilstring', () {
      expect(suggestShelfLife('Seife Kernseife'), isNull); // enthaelt "ei", ist aber kein Ei-Produkt
      expect(suggestShelfLife('Eier aus Freilandhaltung 10 Stk'), isNotNull);
    });

    test('Brot: Vorrat statt Kuehlschrank', () {
      final s = suggestShelfLife('Bauernbrot')!;
      expect(s.location, 'pantry');
    });

    test('kein bekannter Produkttyp: null statt Rateversuch', () {
      expect(suggestShelfLife('Klopapier 8 Rollen'), isNull);
      expect(suggestShelfLife(''), isNull);
    });
  });
}
