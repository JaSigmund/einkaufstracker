import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/domain/notifications/expiry_reminders.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime _d(int y, int m, int d) => DateTime.utc(y, m, d);

InventoryItem _item({required String productId, DateTime? expiresOn}) => InventoryItem(
      id: 'i-$productId-${expiresOn?.toIso8601String()}',
      householdId: 'h1',
      productId: productId,
      quantity: 1,
      unit: 'piece',
      location: 'pantry',
      dateKind: 'best_before',
      status: 'sealed',
      isSuggestion: false,
      expiresOn: expiresOn,
      updatedAt: DateTime.utc(2026),
    );

void main() {
  group('computeExpiryReminders (Doku 06 §5, Schritt 1-2)', () {
    final today = _d(2026, 9, 27);

    test('gruppiert Produkte, deren Erinnerungstag (Ablauf - Vorlaufzeit) zusammenfaellt', () {
      final items = [
        _item(productId: 'p1', expiresOn: _d(2026, 9, 28)), // Erinnerung heute + 1 Tag Vorlauf -> morgen
        _item(productId: 'p2', expiresOn: _d(2026, 9, 28)),
      ];
      final reminders = computeExpiryReminders(
        activeItems: items,
        productNameById: {'p1': 'Milch', 'p2': 'Joghurt'},
        leadDays: 1,
        today: today,
      );
      expect(reminders, hasLength(1));
      expect(reminders.single.date, _d(2026, 9, 27));
      expect(reminders.single.productNames, containsAll(['Milch', 'Joghurt']));
    });

    test('verschiedene Erinnerungstage landen in getrennten Eintraegen, sortiert', () {
      final items = [
        _item(productId: 'p1', expiresOn: _d(2026, 10, 5)),
        _item(productId: 'p2', expiresOn: _d(2026, 9, 29)),
      ];
      final reminders = computeExpiryReminders(
        activeItems: items,
        productNameById: {'p1': 'Käse', 'p2': 'Wurst'},
        leadDays: 1,
        today: today,
      );
      expect(reminders.map((r) => r.date), [_d(2026, 9, 28), _d(2026, 10, 4)]);
    });

    test('ohne bekanntes Ablaufdatum: kein Eintrag', () {
      final reminders = computeExpiryReminders(
        activeItems: [_item(productId: 'p1')],
        productNameById: {'p1': 'Konserve'},
        leadDays: 1,
        today: today,
      );
      expect(reminders, isEmpty);
    });

    test('ausserhalb des 14-Tage-Horizonts: kein Eintrag', () {
      final reminders = computeExpiryReminders(
        activeItems: [_item(productId: 'p1', expiresOn: today.add(const Duration(days: 30)))],
        productNameById: {'p1': 'Tiefkuehlware'},
        leadDays: 1,
        today: today,
      );
      expect(reminders, isEmpty);
    });

    test('verpasster Erinnerungstag (App zwischendurch nicht geoeffnet): wird auf heute nachgeholt statt verworfen', () {
      // Erinnerungstag waere vor 5 Tagen gewesen (Fehlerbericht "keine Push-Benachrichtigung",
      // zweiter Anlauf: das durfte nicht mehr stillschweigend verloren gehen).
      final reminders = computeExpiryReminders(
        activeItems: [_item(productId: 'p1', expiresOn: today.subtract(const Duration(days: 4)))],
        productNameById: {'p1': 'Alt'},
        leadDays: 1,
        today: today,
      );
      expect(reminders, hasLength(1));
      expect(reminders.single.date, today);
      expect(reminders.single.isOverdue, isTrue);
      expect(reminders.single.productNames, ['Alt']);
    });

    test('mehrere verpasste Tage landen gemeinsam im heutigen Eintrag', () {
      final reminders = computeExpiryReminders(
        activeItems: [
          _item(productId: 'p1', expiresOn: today.subtract(const Duration(days: 1))), // Erinnerungstag gestern (-1 Tag Vorlauf)
          _item(productId: 'p2', expiresOn: today.subtract(const Duration(days: 4))), // Erinnerungstag vor 5 Tagen
        ],
        productNameById: {'p1': 'Alt1', 'p2': 'Alt2'},
        leadDays: 1,
        today: today,
      );
      expect(reminders, hasLength(1));
      expect(reminders.single.date, today);
      expect(reminders.single.productNames, containsAll(['Alt1', 'Alt2']));
    });

    test('laenger als der Horizont ueberfaellig: kein Eintrag (kein endloses Nachholen uralter Posten)', () {
      final reminders = computeExpiryReminders(
        activeItems: [_item(productId: 'p1', expiresOn: today.subtract(const Duration(days: 40)))],
        productNameById: {'p1': 'Uralt'},
        leadDays: 1,
        today: today,
      );
      expect(reminders, isEmpty);
    });

    test('genau heute faelliger Erinnerungstag ist NICHT ueberfaellig', () {
      final reminders = computeExpiryReminders(
        activeItems: [_item(productId: 'p1', expiresOn: today.add(const Duration(days: 1)))], // Erinnerung heute, leadDays=1
        productNameById: {'p1': 'Frisch'},
        leadDays: 1,
        today: today,
      );
      expect(reminders.single.isOverdue, isFalse);
    });

    test('unbekanntes Produkt (kein Name gefunden): wird uebersprungen statt Absturz', () {
      final reminders = computeExpiryReminders(
        activeItems: [_item(productId: 'ghost', expiresOn: _d(2026, 9, 28))],
        productNameById: const {},
        leadDays: 1,
        today: today,
      );
      expect(reminders, isEmpty);
    });
  });

  group('expiryReminderBody', () {
    test('ein Artikel, Vorlaufzeit 1 Tag: "X läuft morgen ab."', () {
      expect(expiryReminderBody(['Milch'], 1), 'Milch läuft morgen ab.');
    });

    test('mehrere Artikel, Vorlaufzeit 0 Tage: "X, Y laufen heute ab."', () {
      expect(expiryReminderBody(['Milch', 'Joghurt'], 0), 'Milch, Joghurt laufen heute ab.');
    });

    test('Vorlaufzeit > 1 Tag', () {
      expect(expiryReminderBody(['Käse'], 3), 'Käse läuft in 3 Tagen ab.');
    });

    test('nachgeholte (ueberfaellige) Erinnerung: ehrliche Formulierung statt falschem "laeuft morgen ab"', () {
      expect(expiryReminderBody(['Milch'], 1, isOverdue: true), 'Milch ist bereits fällig oder abgelaufen.');
    });

    test('nachgeholte Erinnerung, mehrere Artikel: Mehrzahl', () {
      expect(expiryReminderBody(['Milch', 'Joghurt'], 1, isOverdue: true), 'Milch, Joghurt sind bereits fällig oder abgelaufen.');
    });
  });
}
