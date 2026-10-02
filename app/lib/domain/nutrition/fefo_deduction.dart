/// FEFO-Abzug (First Expired, First Out) fuers Essenstagebuch (Doku 15 Essenstagebuch und
/// Naehrwerte, §3.4, FR-10/FR-11).
///
/// Reine Funktion ohne Datenbankzugriff, damit sie unabhaengig von drift/Repository getestet werden kann. Der
/// Aufrufer liefert die aktiven Bestaende (Status `sealed`/`opened`) eines Produkts, die Reihenfolge ist egal,
/// die Funktion sortiert selbst nach Ablaufdatum.
library;

/// Ein verfuegbarer Inventar-Posten eines Produkts, aus dem abgezogen werden kann.
class FefoCandidate {
  const FefoCandidate({required this.inventoryItemId, required this.availableQuantity, this.expiresOn});

  final String inventoryItemId;
  final double availableQuantity;

  /// Ablaufdatum, fehlt es, wird der Posten zuletzt abgezogen (Doku 06: unbekannt zuletzt).
  final DateTime? expiresOn;
}

/// Wie viel von welchem Posten abgezogen wird.
class FefoAllocation {
  const FefoAllocation({required this.inventoryItemId, required this.quantity});
  final String inventoryItemId;
  final double quantity;
}

class FefoResult {
  const FefoResult({required this.allocations, required this.shortfall});

  final List<FefoAllocation> allocations;

  /// Menge, die nicht gedeckt werden konnte (FR-11: Bestand wird nie negativ, der Rest gilt als
  /// "nicht im Bestand" und wird nicht abgezogen, zaehlt aber weiter zu den Naehrwerten).
  final double shortfall;
}

/// Zieht [requiredQuantity] von [candidates] ab, aelteste Ablaufdaten zuerst (FR-10).
FefoResult allocateFefo(List<FefoCandidate> candidates, double requiredQuantity) {
  final sorted = [...candidates]..sort((a, b) {
    if (a.expiresOn == null && b.expiresOn == null) return 0;
    if (a.expiresOn == null) return 1;
    if (b.expiresOn == null) return -1;
    return a.expiresOn!.compareTo(b.expiresOn!);
  });

  var remaining = requiredQuantity;
  final allocations = <FefoAllocation>[];
  for (final c in sorted) {
    if (remaining <= 0) break;
    if (c.availableQuantity <= 0) continue;
    final take = remaining < c.availableQuantity ? remaining : c.availableQuantity;
    allocations.add(FefoAllocation(inventoryItemId: c.inventoryItemId, quantity: take));
    remaining -= take;
  }
  return FefoResult(allocations: allocations, shortfall: remaining > 0 ? remaining : 0);
}
