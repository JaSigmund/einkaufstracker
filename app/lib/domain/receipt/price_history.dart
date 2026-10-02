/// Kopfdaten eines Bons, wie sie fuer Preisverlauf/Haendlervergleich gebraucht werden.
typedef PriceHistoryReceipt = ({String id, String? storeId, DateTime purchasedAtUtc});

/// Ein Bon-Artikel mit bereits berechnetem Grundpreis (Doku 07 §3.1).
typedef PriceHistoryItem = ({String receiptId, String? productId, int? unitPriceNormCents, double quantity, String quantityUnit});

/// Ein Haendler (nur die fuer den Vergleich relevanten Felder).
typedef PriceHistoryStore = ({String id, String chain, String? branch});

/// Ein Kaufzeitpunkt eines Produkts, aufsteigend nach Datum (Doku 07 §2 "Artikel-Detail: Preisverlauf").
typedef PricePoint = ({DateTime purchasedAtUtc, int unitPriceNormCents, String storeChain, double quantity, String quantityUnit});

/// Preisverlauf eines Produkts ueber alle Haendler hinweg, chronologisch aufsteigend. Nur Positionen mit
/// berechnetem Grundpreis (Rabatte/Pfand und Packware ohne bekannten Inhalt haben keinen).
List<PricePoint> buildPriceHistory({
  required String productId,
  required Iterable<PriceHistoryItem> items,
  required Iterable<PriceHistoryReceipt> receipts,
  required Iterable<PriceHistoryStore> stores,
}) {
  final receiptById = {for (final r in receipts) r.id: r};
  final storeById = {for (final s in stores) s.id: s};

  final points = <PricePoint>[];
  for (final i in items) {
    if (i.productId != productId || i.unitPriceNormCents == null) continue;
    final receipt = receiptById[i.receiptId];
    if (receipt == null) continue;
    final store = storeById[receipt.storeId];
    points.add((
      purchasedAtUtc: receipt.purchasedAtUtc,
      unitPriceNormCents: i.unitPriceNormCents!,
      storeChain: store?.chain ?? 'Unbekannt',
      quantity: i.quantity,
      quantityUnit: i.quantityUnit,
    ));
  }
  points.sort((a, b) => a.purchasedAtUtc.compareTo(b.purchasedAtUtc));
  return points;
}

/// Der zuletzt bezahlte Grundpreis (Cent je Basiseinheit) je Produkt, ueber alle Haendler hinweg: der neueste Kauf
/// mit berechnetem Grundpreis gewinnt. [excludeReceiptId] laesst einen Bon aussen vor (der Vergleich "geschaetzt gegen
/// bezahlt" braucht den Preis VOR diesem Einkauf). Produkte ohne Kauf mit Grundpreis fehlen im Ergebnis.
Map<String, int> latestUnitPriceByProduct({
  required Iterable<PriceHistoryItem> items,
  required Iterable<PriceHistoryReceipt> receipts,
  String? excludeReceiptId,
}) {
  final receiptById = {for (final r in receipts) r.id: r};
  final latestAt = <String, DateTime>{};
  final latest = <String, int>{};
  for (final i in items) {
    final productId = i.productId;
    final price = i.unitPriceNormCents;
    if (productId == null || price == null || i.receiptId == excludeReceiptId) continue;
    final receipt = receiptById[i.receiptId];
    if (receipt == null) continue;
    final known = latestAt[productId];
    if (known == null || receipt.purchasedAtUtc.isAfter(known)) {
      latestAt[productId] = receipt.purchasedAtUtc;
      latest[productId] = price;
    }
  }
  return latest;
}

/// Grundpreis-Statistik eines Haendlers fuer den Vergleich (Doku 07 §3.2).
class StoreGrundpreis {
  StoreGrundpreis(this.chain)
      : purchaseCount = 0,
        _sumCents = 0,
        minCents = null,
        maxCents = null,
        firstPurchase = null,
        lastPurchase = null;

  final String chain;
  int purchaseCount;
  int _sumCents;
  int? minCents;
  int? maxCents;
  DateTime? firstPurchase;
  DateTime? lastPurchase;

  int get avgCents => purchaseCount == 0 ? 0 : (_sumCents / purchaseCount).round();

  void add(int cents, DateTime purchasedAtUtc) {
    purchaseCount++;
    _sumCents += cents;
    minCents = minCents == null ? cents : (cents < minCents! ? cents : minCents);
    maxCents = maxCents == null ? cents : (cents > maxCents! ? cents : maxCents);
    firstPurchase = firstPurchase == null || purchasedAtUtc.isBefore(firstPurchase!) ? purchasedAtUtc : firstPurchase;
    lastPurchase = lastPurchase == null || purchasedAtUtc.isAfter(lastPurchase!) ? purchasedAtUtc : lastPurchase;
  }
}

/// Ergebnis des Haendlervergleichs fuer ein Produkt (Doku 07 §2 "Haendlervergleich").
class StoreComparison {
  StoreComparison({required this.stores, required this.isMeaningful});

  /// Je Haendler mit mindestens einem Kauf in den letzten 180 Tagen, absteigend nach Kaufanzahl.
  final List<StoreGrundpreis> stores;

  /// True, wenn mindestens zwei Haendler je mindestens zwei Kaeufe in den letzten 180 Tagen haben
  /// (Doku 07 §3.2) — erst dann ist ein Vergleich aussagekraeftig statt Zufall.
  final bool isMeaningful;

  /// Nur Haendler, deren eigener Durchschnitt selbst schon auf mindestens zwei Kaeufen beruht (Codereview-
  /// Fund 2026-10-01): sonst koennte ein einzelner, nicht abgesicherter Kauf (z.B. ein einmaliger
  /// Rauemungsverkauf) als "guenstigster Haendler" erscheinen, obwohl [isMeaningful] nur verlangt, dass
  /// IRGENDWELCHE zwei Haendler die Schwelle erreichen, nicht der jeweils ausgewaehlte selbst.
  List<StoreGrundpreis> get _reliableStores => stores.where((s) => s.purchaseCount >= 2).toList();

  StoreGrundpreis? get cheapest {
    if (!isMeaningful) return null;
    final reliable = _reliableStores;
    if (reliable.isEmpty) return null;
    return reliable.reduce((a, b) => a.avgCents <= b.avgCents ? a : b);
  }

  /// Ersparnis je Kauf beim guenstigsten Haendler gegenueber dem teuersten, in Cent je Basiseinheit.
  int? get savingsPerPurchaseCents {
    if (!isMeaningful) return null;
    final reliable = _reliableStores;
    if (reliable.length < 2) return null;
    final sorted = [...reliable]..sort((a, b) => a.avgCents.compareTo(b.avgCents));
    return sorted.last.avgCents - sorted.first.avgCents;
  }
}

/// Vergleicht den Grundpreis eines Produkts ueber Haendler hinweg (Doku 07 §3.2): nur Kaeufe der letzten
/// 180 Tage, und nur aussagekraeftig, wenn mindestens zwei Haendler je mindestens zwei Kaeufe vorweisen.
StoreComparison buildStoreComparison({
  required String productId,
  required Iterable<PriceHistoryItem> items,
  required Iterable<PriceHistoryReceipt> receipts,
  required Iterable<PriceHistoryStore> stores,
  DateTime? now,
}) {
  final today = now ?? DateTime.now().toUtc();
  final cutoff = today.subtract(const Duration(days: 180));
  final receiptById = {for (final r in receipts) r.id: r};
  final storeById = {for (final s in stores) s.id: s};

  final byChain = <String, StoreGrundpreis>{};
  for (final i in items) {
    if (i.productId != productId || i.unitPriceNormCents == null) continue;
    final receipt = receiptById[i.receiptId];
    if (receipt == null || receipt.purchasedAtUtc.isBefore(cutoff)) continue;
    final chain = storeById[receipt.storeId]?.chain ?? 'Unbekannt';
    byChain.putIfAbsent(chain, () => StoreGrundpreis(chain)).add(i.unitPriceNormCents!, receipt.purchasedAtUtc);
  }

  final list = byChain.values.toList()..sort((a, b) => b.purchaseCount.compareTo(a.purchaseCount));
  final withEnoughData = list.where((s) => s.purchaseCount >= 2).length;
  return StoreComparison(stores: list, isMeaningful: withEnoughData >= 2);
}
