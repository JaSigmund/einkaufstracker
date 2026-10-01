import '../inventory/expiry.dart';

/// Ein aktiver Inventar-Posten (Status `sealed`/`opened`, siehe Doku 06 §1), wie er fuer die
/// Rezeptvorschlag-Zusammenstellung gebraucht wird. Nur aktive Posten uebergeben — dieselbe Erwartung
/// wie bei `computeExpiryReminders` (`notification_scheduler.dart`), kein eigener Status-Filter hier.
typedef InventoryIngredient = ({
  String productId,
  String productName,
  double quantity,
  String unit, // 'piece' | 'kg' | 'l'
  DateTime? expiresOn,
  String dateKind, // 'best_before' | 'use_by'
});

/// Eine Zutat fuer den Rezeptvorschlag-Prompt: Menge, Einheit und wie dringend sie verwertet werden
/// sollte (Ampel aus `expiry.dart`). `productId` bleibt erhalten, damit ein spaeter gespeichertes
/// Rezept (`SavedRecipe`) die Zutat wieder auf das Produkt zurueckfuehren kann (fuer den
/// Inventar-Abgleich beim Hinzufuegen fehlender Zutaten zur Einkaufsliste, siehe `recipe_shopping_gap.dart`).
class RecipeIngredient {
  const RecipeIngredient({required this.productId, required this.productName, required this.quantity, required this.unit, required this.urgency});

  final String productId;
  final String productName;
  final double quantity;
  final String unit;
  final ExpiryLevel urgency;
}

/// Baut die Zutatenliste fuer einen Rezeptvorschlag aus dem aktiven Inventar (Feature-Request
/// "Rezeptvorschläge", bestätigt 2026-10-01, siehe [[12 Entscheidungen (ADR)]] ADR-021): bald
/// ablaufende Zutaten zuerst, damit Vorschläge bevorzugt das verwerten, was sonst verdirbt — dieselbe
/// Ampel-Priorität, die im Inventar-UI schon etabliert ist (Doku 06 §3.1).
///
/// Zwei bewusste Entscheidungen:
/// 1. **Abgelaufene `use_by`-Posten (Verbrauchsdatum) werden ausgeschlossen** — das ist ein
///    Sicherheitshinweis, kein Richtwert, ein Rezeptvorschlag darf so etwas nicht verwerten wollen.
///    Abgelaufene `best_before`-Posten (Mindesthaltbarkeitsdatum) bleiben dagegen drin und werden am
///    höchsten priorisiert — "oft noch genießbar, aber jetzt wirklich verwerten" ist genau der Zweck
///    des Features.
/// 2. **Gleiche Produkte werden zusammengeführt** (z.B. zwei offene Packungen desselben Joghurts),
///    damit der Vorschlag nicht künstlich nach Duplikaten aussieht; die Menge wird addiert, die
///    höhere Dringlichkeit gewinnt.
List<RecipeIngredient> buildRecipeSuggestionContext(
  Iterable<InventoryIngredient> activeItems, {
  required DateTime today,
  int leadDays = 3,
}) {
  final byProduct = <String, (String name, double quantity, String unit, ExpiryLevel urgency)>{};

  for (final item in activeItems) {
    final level = expiryLevel(expiresOn: item.expiresOn, dateKind: item.dateKind, today: today, leadDays: leadDays);
    if (item.dateKind == 'use_by' && level == ExpiryLevel.expired) continue;

    final existing = byProduct[item.productId];
    if (existing == null) {
      byProduct[item.productId] = (item.productName, item.quantity, item.unit, level);
    } else {
      final (name, quantity, unit, urgency) = existing;
      byProduct[item.productId] = (name, quantity + item.quantity, unit, _moreUrgent(urgency, level));
    }
  }

  final list = [
    for (final entry in byProduct.entries)
      RecipeIngredient(productId: entry.key, productName: entry.value.$1, quantity: entry.value.$2, unit: entry.value.$3, urgency: entry.value.$4),
  ];
  list.sort((a, b) => _urgencyRank(a.urgency).compareTo(_urgencyRank(b.urgency)));
  return list;
}

int _urgencyRank(ExpiryLevel level) => switch (level) {
      ExpiryLevel.expired => 0,
      ExpiryLevel.soon => 1,
      ExpiryLevel.ok => 2,
      ExpiryLevel.unknown => 3,
    };

ExpiryLevel _moreUrgent(ExpiryLevel a, ExpiryLevel b) => _urgencyRank(a) <= _urgencyRank(b) ? a : b;
