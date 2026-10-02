import 'parsed_receipt.dart';
import 'vienna_time.dart';

/// Liest den Text eines Hofer-Kassenbons (Fotoscan, OCR).
///
/// Erste Version, gebaut anhand eines einzelnen echten Bons (Fehlerbericht "Scan nicht möglich", 2026-09-28,
/// `testdata/receipts/hofer_01.webp`) statt eines vollen Golden Sets wie bei [BillaTextParser] (Doku 11
/// Roadmap, B3 "Hofer-Bons") — noch nicht gegen mehrere Bons gehaertet, sollte mit weiteren echten Bons
/// nachgeschaerft werden.
///
/// Anders als [BillaTextParser] prueft dieser Parser nur die Bon-Summe gegen die Positionen (wie die
/// Cloud-Erkennung, siehe `cloud_receipt.dart`), nicht den Steuerblock je Klasse: Hofer-Bons weisen je
/// Steuerklasse nur den gerundeten MwSt-Betrag aus (nicht Netto und Brutto wie bei Billa), wodurch ein
/// exakter Abgleich haeufig an Rundungsdifferenzen von 1-2 Cent scheitern wuerde, auch wenn alle Positionen
/// richtig gelesen wurden.
class HoferTextParser {
  const HoferTextParser({this.lenient = false});

  /// Bislang ohne Wirkung (anders als bei [BillaTextParser]): der Steuerbuchstabe steht bei Hofer direkt auf
  /// der Artikelzeile, es gibt keine strengere/lockerere Variante. Nur der Vollstaendigkeit halber vorhanden,
  /// damit ein gemeinsamer Dispatcher (`parseReceiptText`) beide Parser gleich aufrufen kann.
  final bool lenient;

  static const _price = r'-?\d{1,4}[.,]\d{2}';

  static final _dateTime = RegExp(r'(\d{2})\.(\d{2})\.(\d{4})/(\d{2}):(\d{2})');
  static final _totalLine = RegExp(r'Total-EFT\s*EUR\s*:?\s*(' + _price + r')');
  static final _paymentTotalLine = RegExp(r'^\s*(?:Visa|Mastercard|Maestro|Bar|girocard|EC-Karte)\s+(' + _price + r')\s*$');
  static final _itemLine = RegExp(r'^\s*\d{5,7}\s+(.+?)\s+(' + _price + r')\s+([A-Z])\s*$');
  static final _netWeightLine = RegExp(r'^\s*\(N\)\s*(\d+(?:[.,]\d+)?)\s*kg\s*[xX]\s*(' + _price + r')\s*EUR/kg\s*$');
  static final _weightDetailLine = RegExp(r'^\s*\((B|PT|N)\)');
  static final _kassenId = RegExp(r'Kassenidentifikationsnummer:\s*(\d+)/(\d+)');
  static final _fiskal = RegExp(r'Fiskalsequenz-Nummer:\s*(\d+)');
  static final _deposit = RegExp(r'PFAND|LEERGUT|FLASCHENKASSEN', caseSensitive: false);

  static int _cents(String s) {
    final t = s.replaceAll(',', '.');
    final neg = t.startsWith('-');
    final parts = t.replaceFirst('-', '').split('.');
    final v = int.parse(parts[0]) * 100 + int.parse(parts[1]);
    return neg ? -v : v;
  }

  ParsedReceipt parse(String text) {
    final lines = text.replaceAll('\r', '').split('\n');

    final dtIdx = lines.indexWhere(_dateTime.hasMatch);
    if (dtIdx < 0) return const ParsedReceipt.failed(['Datum und Uhrzeit nicht gefunden']);
    final dt = _dateTime.firstMatch(lines[dtIdx])!;
    final purchasedAt = viennaLocalToUtc(
      int.parse(dt.group(3)!),
      int.parse(dt.group(2)!),
      int.parse(dt.group(1)!),
      int.parse(dt.group(4)!),
      int.parse(dt.group(5)!),
    );

    int? totalCents;
    final totalIdx = lines.indexWhere(_totalLine.hasMatch);
    if (totalIdx >= 0) {
      totalCents = _cents(_totalLine.firstMatch(lines[totalIdx])!.group(1)!);
    } else {
      final payIdx = lines.lastIndexWhere(_paymentTotalLine.hasMatch);
      if (payIdx >= 0) totalCents = _cents(_paymentTotalLine.firstMatch(lines[payIdx])!.group(1)!);
    }
    if (totalCents == null) return const ParsedReceipt.failed(['Summe ("Total-EFT") nicht gefunden']);

    final items = <ParsedItem>[];
    for (final l in lines) {
      final t = l.trim();
      if (t.isEmpty) continue;

      if (_weightDetailLine.hasMatch(t)) {
        // Zusatzzeile zu einer Waegware (Brutto/Tara/Netto): verfeinert die Menge der zuletzt gelesenen
        // Position, legt keine neue Position an (der Preis stand schon auf deren Artikelzeile).
        final mn = _netWeightLine.firstMatch(t);
        if (mn != null && items.isNotEmpty) {
          final last = items.removeLast();
          items.add(ParsedItem(
            rawText: last.rawText,
            kind: last.kind,
            lineTotalCents: last.lineTotalCents,
            taxCode: last.taxCode,
            quantity: double.parse(mn.group(1)!.replaceAll(',', '.')),
            quantityUnit: 'kg',
            unitPriceCents: _cents(mn.group(2)!),
          ));
        }
        continue;
      }

      final mi = _itemLine.firstMatch(l);
      if (mi != null) {
        final name = mi.group(1)!.trim();
        final cents = _cents(mi.group(2)!);
        var kind = ReceiptItemKind.article;
        // Codereview-Fund 2026-10-01, siehe billa_text_parser.dart: ein echter Rabatt ist immer negativ
        // bepreist, der Name-Abgleich erzeugte sonst Fehlklassifikationen bei positiv bepreisten
        // Aktionsartikeln.
        if (cents < 0) kind = ReceiptItemKind.discount;
        if (_deposit.hasMatch(name)) kind = ReceiptItemKind.deposit;
        items.add(ParsedItem(rawText: name, kind: kind, lineTotalCents: cents, taxCode: mi.group(3)));
      }
    }

    String? externalId;
    final kassenMatch = lines.map(_kassenId.firstMatch).whereType<RegExpMatch>().firstOrNull;
    final fiskalMatch = lines.map(_fiskal.firstMatch).whereType<RegExpMatch>().firstOrNull;
    if (kassenMatch != null && fiskalMatch != null) {
      externalId = 'hofer-${kassenMatch.group(1)}-${kassenMatch.group(2)}-${fiskalMatch.group(1)}';
    }

    final itemsSum = items.fold<int>(0, (s, i) => s + i.lineTotalCents);
    final checks = ReceiptChecks(
      itemsSumCents: itemsSum,
      bonDiscountSumCents: 0,
      totalCents: totalCents,
      subtotalCents: null,
      taxBlockGrossSumCents: 0,
      classDifferences: const {},
      missingTaxClasses: const [],
    );

    return ParsedReceipt(
      chain: 'Hofer',
      externalId: externalId,
      purchasedAtUtc: purchasedAt,
      totalCents: totalCents,
      items: items,
      bonDiscounts: const [],
      taxBlock: const {},
      warnings: items.isEmpty ? const ['Keine Positionen erkannt'] : const [],
      checks: checks,
    );
  }
}
