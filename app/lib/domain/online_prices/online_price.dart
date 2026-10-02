/// Online-Preise von Billa und Spar (ADR-019): reine Rechen- und Anzeigelogik ohne Datenbank und Netz.
///
/// Die Preise stammen aus dem oeffentlichen Feed von heisse-preise.io und werden vom Server taeglich in die Tabelle
/// `online_prices` geschrieben. Sie sind Regalpreise aus dem Webshop, keine eigenen Kaeufe: die App zeigt sie
/// **getrennt** von der Kaufhistorie und mischt sie nie in Grundpreis-Statistik oder Haendlervergleich.
library;

/// Haendler, die der Feed aktuell pflegt (Stand 2026-10-02). Die uebrigen (Hofer, Bipa, MPreis, Unimarkt) liefern
/// veraltete Daten und werden vom Server gar nicht erst gespeichert.
const onlineStores = <String, String>{'billa': 'Billa', 'spar': 'Spar'};

String onlineStoreLabel(String store) => onlineStores[store] ?? store;

/// Ab diesem Alter des Feed-Stands gilt ein Preis als "zuletzt bekannt" statt als aktuell.
const onlinePriceStaleAfter = Duration(days: 7);

/// Ein Artikel aus `online_prices` (Suchergebnis oder Abruf).
class OnlineArticle {
  const OnlineArticle({
    required this.store,
    required this.externalId,
    required this.name,
    required this.priceCents,
    this.quantity,
    this.unit,
    this.baseUnit,
    this.unitPriceNormCents,
  });

  final String store;
  final String externalId;
  final String name;
  final int priceCents;
  final double? quantity;

  /// Einheit roh aus dem Feed (`g`, `ml`, `l`, `stk`, ...).
  final String? unit;

  /// `kg`, `l` oder `stk`; `null`, wenn die Feed-Einheit nicht eindeutig war (dann gibt es auch keinen Grundpreis).
  final String? baseUnit;
  final int? unitPriceNormCents;
}

/// Liest eine Zeile von `online_prices` bzw. das Ergebnis von `search_online_prices`. PostgREST liefert `numeric` als
/// Zahl, anders konfigurierte Server auch als Text: beides wird gelesen. Eine Zeile ohne Pflichtfelder ergibt `null`.
OnlineArticle? onlineArticleFromRow(Map<String, dynamic> row) {
  double? number(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v.replaceAll(',', '.')) : null);
  final store = row['store'];
  final id = row['external_id'];
  final name = row['name'];
  final price = row['price_cents'];
  if (store is! String || id is! String || name is! String || price is! num) return null;
  final base = row['base_unit'];
  final unitPrice = row['unit_price_norm_cents'];
  return OnlineArticle(
    store: store,
    externalId: id,
    name: name,
    priceCents: price.toInt(),
    quantity: number(row['quantity']),
    unit: row['unit'] is String ? row['unit'] as String : null,
    baseUnit: base is String && const {'kg', 'l', 'stk'}.contains(base) ? base : null,
    unitPriceNormCents: unitPrice is num ? unitPrice.toInt() : null,
  );
}

/// Basiseinheit eines Produkts (`kg`, `l`, `piece`) in der Schreibweise des Feeds (`kg`, `l`, `stk`).
String onlineBaseUnitOf(String productBaseUnit) => productBaseUnit == 'piece' ? 'stk' : productBaseUnit;

/// Menge und Einheit eines Online-Artikels fuer die Anzeige ("500 g", "1 l", "6 Stk"). Ohne Menge leer.
String formatOnlineQuantity(double? quantity, String? unit) {
  if (quantity == null || quantity <= 0) return '';
  final number = quantity == quantity.roundToDouble() ? quantity.toInt().toString() : quantity.toString().replaceAll('.', ',');
  final label = switch (unit?.trim().toLowerCase()) {
    'stk' || 'stück' => 'Stk',
    null || '' => '',
    final u => u,
  };
  return label.isEmpty ? number : '$number $label';
}

/// Wie aktuell ein angezeigter Online-Preis ist.
enum OnlinePriceFreshness {
  /// Der Feed ist hoechstens [onlinePriceStaleAfter] alt und der Artikel war beim letzten Abruf verfuegbar.
  fresh,

  /// Der Feed ist aelter (er wird nicht mehr gepflegt, oder der Abruf auf dem Server schlaegt seit Tagen fehl).
  stale,

  /// Der Artikel ist nicht mehr im Online-Sortiment; der Preis ist der zuletzt bekannte.
  discontinued,
}

OnlinePriceFreshness onlinePriceFreshness({required bool available, required DateTime? feedUpdatedAt, required DateTime now}) {
  if (!available) return OnlinePriceFreshness.discontinued;
  if (feedUpdatedAt == null || now.difference(feedUpdatedAt) > onlinePriceStaleAfter) return OnlinePriceFreshness.stale;
  return OnlinePriceFreshness.fresh;
}

/// Beide Preise lassen sich nur vergleichen, wenn sie dieselbe Basiseinheit haben (kg mit kg, l mit l, Stk mit Stk).
bool onlineUnitsComparable(String productBaseUnit, String? onlineBaseUnit) =>
    onlineBaseUnit != null && onlineBaseUnitOf(productBaseUnit) == onlineBaseUnit;

/// Ein einem Produkt zugeordneter Online-Artikel mit seinem zuletzt bekannten Preis. Ein Produkt kann mehrere haben, auch beim
/// selben Haendler: Bio-Paprika und normale Paprika sind bei Billa zwei Artikel, fuer den Einkauf aber dasselbe Produkt.
class LinkedOnlinePrice {
  const LinkedOnlinePrice({
    required this.store,
    required this.externalId,
    required this.name,
    required this.priceCents,
    required this.baseUnit,
    required this.unitPriceNormCents,
    required this.freshness,
  });

  final String store;
  final String externalId;
  final String name;
  final int? priceCents;
  final String? baseUnit;
  final int? unitPriceNormCents;
  final OnlinePriceFreshness freshness;
}

/// Der guenstigste Artikel nach Grundpreis. Es zaehlen nur Artikel mit berechnetem Grundpreis in der Basiseinheit des Produkts
/// (kg mit kg), die noch im Online-Sortiment sind. Bei gleichem Grundpreis gewinnt der niedrigere Preis, dann der erste.
/// `null`, wenn kein Artikel vergleichbar ist.
LinkedOnlinePrice? cheapestOnlinePrice(Iterable<LinkedOnlinePrice> items, String productBaseUnit) {
  LinkedOnlinePrice? best;
  for (final i in items) {
    if (i.freshness == OnlinePriceFreshness.discontinued) continue;
    if (i.unitPriceNormCents == null || !onlineUnitsComparable(productBaseUnit, i.baseUnit)) continue;
    if (best == null ||
        i.unitPriceNormCents! < best.unitPriceNormCents! ||
        (i.unitPriceNormCents == best.unitPriceNormCents && (i.priceCents ?? 1 << 30) < (best.priceCents ?? 1 << 30))) {
      best = i;
    }
  }
  return best;
}
