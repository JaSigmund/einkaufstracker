/// Parser fuer den oeffentlichen JSON-Feed von `heisse-preise.io` (Projekt `badlogic/heissepreise`,
/// MIT-Lizenz, siehe [[12 Entscheidungen (ADR)]] ADR-019): ein Community-Projekt, das Preise grosser
/// oesterreichischer (und einiger deutscher) Haendler taeglich erfasst und als
/// `https://heisse-preise.io/data/latest-canonical.json` veroeffentlicht. Wir scrapen nicht selbst,
/// sondern konsumieren nur diesen bereits oeffentlichen Export.
///
/// **Gegen echte Feed-Daten verifiziert (2026-10-01, 276.875 Eintraege):**
/// - `id` ist je nach Haendler ein **String** (Billa: `"00-600283"`) oder eine **Zahl** (Hofer:
///   `547270`) — deshalb `Object` statt `String` im Rohtyp, erst beim Parsen vereinheitlicht.
/// - `price` ist eine **EUR-Dezimalzahl**, keine Cent-Ganzzahl wie sonst im Projekt ueblich.
/// - `unit` ist uneinheitlich: ueberwiegend `g`/`kg`/`ml`/`l`/`stk`, aber auch Sondereinheiten wie
///   `wg` (Waschgaenge, bei Waschmittel) oder kaputte Kodierung. Unbekannte Einheiten ergeben bewusst
///   `null` statt eines falschen Grundpreises (gleiches Prinzip wie `computeUnitPriceNormCents`).
/// - `isWeighted` aendert an der Rechnung nichts: sowohl bei Wiegeware als auch bei Stueckware gilt
///   `price` fuer `quantity` `unit`, die Grundpreis-Formel ist identisch.
/// - **Datenaktualitaet schwankt stark zwischen Haendlern** (Stand 2026-10-01): `billa` und `spar`
///   sind taggenau aktuell, `hofer`, `bipa`, `mpreis`, `unimarkt` und `sparSi` lieferten **keinen
///   einzigen verfuegbaren Eintrag** (alle `unavailable: true`, teils seit ueber einem Jahr nicht
///   aktualisiert — `hofer` zuletzt 2025-11-07). Der urspruengliche Feature-Wunsch nannte Hofer als
///   Beispiel, das ist ueber diese Quelle **aktuell nicht nutzbar** — ausserhalb unserer Kontrolle,
///   da `heisse-preise.io` ein Drittprojekt ist (siehe R-23).
library;

/// Ein roher Eintrag aus dem Feed, nur die fuer die Normalisierung noetigen Felder (der echte Feed hat
/// zusaetzlich `description`, `priceHistory`, `url`, `category`).
typedef RawHeissePreiseEntry = ({
  String store,
  Object id,
  String name,
  double price,
  String? unit,
  double? quantity,
  bool isWeighted,
  bool unavailable,
});

/// Von `price`/`unit`/`quantity` abgeleiteter Grundpreis, kompatibel mit dem Konzept aus
/// `unit_price.dart` (Cent je Basiseinheit kg/l/Stk).
class NormalizedOnlinePrice {
  const NormalizedOnlinePrice({
    required this.store,
    required this.externalId,
    required this.name,
    required this.priceCents,
    required this.baseUnit,
    required this.unitPriceNormCents,
  });

  final String store;

  /// `id` aus dem Feed, immer als String (siehe Klassenkommentar: Hofer liefert Zahlen, Billa Strings).
  final String externalId;
  final String name;

  /// Verkaufspreis in Cent (Feed liefert EUR als Dezimalzahl).
  final int priceCents;

  /// `'kg'`, `'l'` oder `'stk'` — `null`, wenn die Feed-Einheit nicht eindeutig einer Basiseinheit
  /// zugeordnet werden konnte (z.B. `wg`, kaputte Kodierung, leerer String).
  final String? baseUnit;

  /// Cent je Basiseinheit, `null` wenn [baseUnit] unbekannt ist oder `quantity` fehlt/0 ist.
  final int? unitPriceNormCents;
}

/// Normalisiert einen Feed-Eintrag, oder `null` wenn er nicht (mehr) im Sortiment ist (`unavailable`).
/// Nie geraten: unbekannte Einheiten liefern einen Preis ohne Grundpreis statt eines falschen Werts.
NormalizedOnlinePrice? normalizeHeissePreiseEntry(RawHeissePreiseEntry e) {
  if (e.unavailable) return null;

  final priceCents = (e.price * 100).round();
  final (baseUnit, factorToBaseUnit) = _resolveUnit(e.unit);

  int? unitPriceNormCents;
  if (baseUnit != null && e.quantity != null && e.quantity! > 0) {
    final baseUnitAmount = e.quantity! * factorToBaseUnit;
    unitPriceNormCents = (priceCents / baseUnitAmount).round();
  }

  return NormalizedOnlinePrice(
    store: e.store,
    externalId: e.id.toString(),
    name: e.name,
    priceCents: priceCents,
    baseUnit: baseUnit,
    unitPriceNormCents: unitPriceNormCents,
  );
}

/// Basiseinheit und Umrechnungsfaktor der Feed-Einheit auf diese Basiseinheit, oder `(null, 0)` wenn
/// unbekannt. Nur die am Feed real beobachteten, eindeutigen Einheiten (siehe Klassenkommentar).
(String?, double) _resolveUnit(String? unit) {
  return switch (unit) {
    'g' => ('kg', 0.001),
    'kg' => ('kg', 1.0),
    'ml' => ('l', 0.001),
    'l' => ('l', 1.0),
    'stk' => ('stk', 1.0),
    _ => (null, 0.0),
  };
}
