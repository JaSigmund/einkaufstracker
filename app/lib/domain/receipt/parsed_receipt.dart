/// Ergebnis des Einlesens eines Bons (unabhaengig vom Weg: PDF-Text, spaeter OCR oder Cloud).
/// Geld wird durchgehend als ganze Cent gefuehrt (Doku 02 FR-01).
library;

enum ReceiptItemKind { article, deposit, discount }

class ParsedItem {
  const ParsedItem({
    required this.rawText,
    required this.kind,
    required this.lineTotalCents,
    this.taxCode,
    this.quantity = 1,
    this.quantityUnit = 'piece',
    this.unitPriceCents,
  });

  /// Artikelname genau wie auf dem Bon gedruckt.
  final String rawText;
  final ReceiptItemKind kind;

  /// Zeilenbetrag in Cent, Rabatte und Pfandrueckgaben sind negativ.
  final int lineTotalCents;

  /// Steuerbuchstabe des Bons (B, C, D, H ...).
  final String? taxCode;

  /// Menge aus der Mengenzeile darueber ("2 x 1.19"), sonst 1.
  final double quantity;

  /// 'piece', 'kg' oder 'l'.
  final String quantityUnit;

  /// Einzelpreis aus der Mengenzeile in Cent (je Stueck bzw. je kg/l).
  final int? unitPriceCents;

  @override
  String toString() => 'ParsedItem($rawText, $kind, $lineTotalCents)';
}

/// Rabatt auf Bon-Ebene (nach der Zwischensumme, ohne Steuerbuchstaben),
/// z.B. "jö Rabattsammler 20%  -4,51".
class BonDiscount {
  const BonDiscount({required this.name, required this.cents, this.percent});
  final String name;
  final int cents;
  final int? percent;
}

/// Eine Zeile des Steuerblocks am Bon-Ende ("B: 10.00% MwSt von 19.22 = 1.92").
class TaxBlockEntry {
  const TaxBlockEntry({required this.code, required this.grossCents, this.ratePercent, this.netCents, this.vatCents});
  final String code;

  /// Ausgewiesener Satz; null bei "nicht steuerbar". Wird nur gelesen, nie angenommen.
  final double? ratePercent;
  final int? netCents;
  final int? vatCents;

  /// Bruttosumme dieser Steuerklasse laut Bon.
  final int grossCents;
}

/// Ergebnis der Plausibilitaetspruefungen aus Doku 05 §3.5 und §7.3.
class ReceiptChecks {
  const ReceiptChecks({
    required this.itemsSumCents,
    required this.bonDiscountSumCents,
    required this.totalCents,
    required this.subtotalCents,
    required this.taxBlockGrossSumCents,
    required this.classDifferences,
    required this.missingTaxClasses,
  });

  final int itemsSumCents;
  final int bonDiscountSumCents;
  final int? totalCents;
  final int? subtotalCents;
  final int taxBlockGrossSumCents;

  /// Steuerklasse -> Abweichung (Positionen minus Steuerblock) in Cent. Nur ohne Bon-Rabatt aussagekraeftig.
  final Map<String, int> classDifferences;

  /// Steuerklassen, die bei Positionen vorkommen, aber im Steuerblock fehlen.
  final List<String> missingTaxClasses;

  /// Summe der Positionen plus Bon-Rabatte entspricht der Bon-Summe.
  bool get totalMatches => totalCents != null && itemsSumCents + bonDiscountSumCents == totalCents;

  /// Zwischensumme (falls vorhanden) entspricht der Summe der Positionen. Ohne Zwischensumme: null.
  bool? get subtotalMatches => subtotalCents == null ? null : subtotalCents == itemsSumCents;

  bool get taxMatches {
    if (missingTaxClasses.isNotEmpty) return false;
    if (bonDiscountSumCents != 0) {
      // Bon-Rabatte werden vom Bon anteilig auf die Klassen verteilt: nur die Gesamtsumme laesst sich pruefen
      return totalCents != null && taxBlockGrossSumCents == totalCents;
    }
    return classDifferences.isEmpty;
  }

  /// Alle Pruefungen bestanden.
  bool get allOk => totalMatches && (subtotalMatches ?? true) && taxMatches;

  /// Bon-Summe minus Summe der Positionen und Bon-Rabatte (positiv = es fehlt etwas).
  int? get differenceCents => totalCents == null ? null : totalCents! - (itemsSumCents + bonDiscountSumCents);
}

class ParsedReceipt {
  const ParsedReceipt({
    required this.chain,
    required this.items,
    required this.bonDiscounts,
    required this.taxBlock,
    required this.warnings,
    this.branchCode,
    this.externalId,
    this.purchasedAtUtc,
    this.totalCents,
    this.subtotalCents,
    this.checks,
  });

  const ParsedReceipt.failed(this.warnings)
      : chain = null,
        items = const [],
        bonDiscounts = const [],
        taxBlock = const {},
        branchCode = null,
        externalId = null,
        purchasedAtUtc = null,
        totalCents = null,
        subtotalCents = null,
        checks = null;

  final String? chain;

  /// Filialnummer, z.B. "0643".
  final String? branchCode;

  /// Eindeutige Kennung des Kaufs: die "Re-Nr" (Filiale-Datum-Kassa-Bonnummer). Auf Papier und digital gleich.
  final String? externalId;
  final DateTime? purchasedAtUtc;
  final int? totalCents;
  final int? subtotalCents;
  final List<ParsedItem> items;
  final List<BonDiscount> bonDiscounts;
  final Map<String, TaxBlockEntry> taxBlock;
  final List<String> warnings;
  final ReceiptChecks? checks;

  /// Konnte der Bon ueberhaupt gelesen werden (Datum und Summe gefunden)?
  bool get isParsed => checks != null;

  /// Gelesen und alle Pruefungen bestanden: kann ohne manuelle Kontrolle uebernommen werden.
  bool get isTrustworthy => isParsed && checks!.allOk;
}
