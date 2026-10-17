import 'parsed_receipt.dart';
import '../../core/vienna_time.dart';

/// Liest den Text eines digitalen Billa-Bons (PDF-Textebene, jö Bonus Club) ohne OCR und ohne Cloud.
///
/// Umsetzung des Prototyps `tools/parse_digital_billa.py` (Doku 05 §7.8), der auf allen sechs
/// Test-Bons Summe und Steuerblock exakt getroffen hat. Der Parser kennt nur das Textformat, er
/// liest keine PDF-Dateien.
class BillaTextParser {
  /// [lenient] fuer OCR-Text von Papierbons: Der Steuerbuchstabe hinter dem Artikelnamen darf fehlen
  /// (er wird bei Fotos oft nicht gelesen). Die Steuerpruefung laeuft dann ueber die Gesamtsumme des Steuerblocks.
  const BillaTextParser({this.lenient = false});

  final bool lenient;

  static const _price = r'-?\d{1,4}[.,]\d{2}';

  static final _dateTime = RegExp(r'Datum:\s*(\d{2})\.(\d{2})\.(\d{4})\s+Zeit:\s*(\d{2}):(\d{2})');
  static final _totalLine = RegExp(r'^\s*Summe\s+EUR\s+(' + _price + r')\s*$');
  static final _subtotalLine = RegExp(r'^\s*Zwischensumme\s+EUR\s+(' + _price + r')\s*$');
  static final _quantityLine = RegExp(
    r'^\s*(-?\d+(?:[.,]\d+)?)\s*(kg|g|l)?\s*(?:\(N\))?\s*[xX]\s+(' + _price + r')\s*(?:EUR/(kg|l))?\s*$',
  );
  static final _itemLine = RegExp(r'^\s*(.+?)\s+([A-Z])\s+(' + _price + r')\s*$');
  static final _itemLineLenient = RegExp(r'^\s*(.+?)(?:\s+([A-Z]))?\s+(' + _price + r')\s*$');
  static final _bonDiscountLine = RegExp(r'^\s*(.+?)\s+(?:(\d+)%\s+)?(-\d{1,4}[.,]\d{2})\s*$');
  static final _labelLine = RegExp(r'^\s*[A-Za-zÄÖÜäöüß .\-]+$');
  static final _taxLine = RegExp(
    r'^\s*([A-Z])\s*:\s*(?:([\d.,]+)\s*%\s*MwSt\s*von|nicht\s+steuerbar)\s*(' + _price + r')?\s*(?:=\s*(' + _price + r'))?',
  );
  static final _reNr = RegExp(r'Re-Nr:\s*(\d{4})-(\d{8})-(\d{2})-(\d+)');
  static final _deposit = RegExp(r'PFAND|LEERGUT|FLASCHENKASSEN', caseSensitive: false);

  static int _cents(String s) {
    final t = s.replaceAll(',', '.');
    final neg = t.startsWith('-');
    final parts = t.replaceFirst('-', '').split('.');
    final v = int.parse(parts[0]) * 100 + int.parse(parts[1]);
    return neg ? -v : v;
  }

  ParsedReceipt parse(String text) {
    // Die PDF-Textebene enthaelt geschuetzte Leerzeichen (U+00A0), die einfache Textvergleiche brechen
    final lines = text.replaceAll(' ', ' ').replaceAll('\r', '').split('\n');
    final warnings = <String>[];

    final start = lines.indexWhere(_dateTime.hasMatch);
    final end = lines.indexWhere(_totalLine.hasMatch);
    if (start < 0) return const ParsedReceipt.failed(['Datum und Uhrzeit nicht gefunden']);
    if (end < 0 || end < start) return const ParsedReceipt.failed(['Zeile "Summe" nicht gefunden']);

    final dt = _dateTime.firstMatch(lines[start])!;
    final purchasedAt = viennaLocalToUtc(
      int.parse(dt.group(3)!),
      int.parse(dt.group(2)!),
      int.parse(dt.group(1)!),
      int.parse(dt.group(4)!),
      int.parse(dt.group(5)!),
    );
    final totalCents = _cents(_totalLine.firstMatch(lines[end])!.group(1)!);

    final items = <ParsedItem>[];
    final bonDiscounts = <BonDiscount>[];
    int? subtotal;
    var unlabeledItems = 0;

    // Menge aus der Mengenzeile, gilt fuer die naechste Artikelzeile
    double? pendingQty;
    String pendingUnit = 'piece';
    int? pendingUnitPrice;

    for (var i = start + 1; i < end; i++) {
      final l = lines[i];
      final t = l.trim();
      if (t.isEmpty || RegExp(r'^[-=]+$').hasMatch(t)) continue;

      final mq = _quantityLine.firstMatch(l);
      if (mq != null) {
        pendingQty = double.parse(mq.group(1)!.replaceAll(',', '.'));
        pendingUnit = mq.group(2) ?? mq.group(4) ?? 'piece';
        if (pendingUnit == 'g') pendingUnit = 'piece'; // Gramm-Angaben nicht umrechnen, Menge bleibt Zahl
        pendingUnitPrice = _cents(mq.group(3)!);
        continue;
      }

      final mz = _subtotalLine.firstMatch(l);
      if (mz != null) {
        subtotal = _cents(mz.group(1)!);
        continue;
      }

      var mi = _itemLine.firstMatch(l);
      var unlabeled = false;
      if (mi == null && lenient) {
        // Nach der Zwischensumme stehen Rabatte auf Bon-Ebene (ohne Steuerbuchstaben), keine Positionen
        final isBonLevel = subtotal != null && _bonDiscountLine.hasMatch(l);
        if (!isBonLevel) {
          mi = _itemLineLenient.firstMatch(l);
          unlabeled = mi != null && mi.group(2) == null;
        }
      }
      if (mi != null) {
        if (unlabeled) unlabeledItems++;
        final name = mi.group(1)!.trim();
        final cents = _cents(mi.group(3)!);
        var kind = ReceiptItemKind.article;
        // Codereview-Fund 2026-10-01: nicht zusaetzlich nach "AKTION"/"RABATT"/"NIMM MEHR" im Namen suchen --
        // ein normaler, positiv bepreister Aktionsartikel (reale Bon-Zeile, kein Rabatt) hiess damit
        // faelschlich "discount" und floss in month_report.dart in den vorherigen Artikel ein, statt als
        // eigene Position gezaehlt zu werden. Ein echter Rabatt ist immer negativ bepreist, das reicht.
        if (cents < 0) kind = ReceiptItemKind.discount;
        if (_deposit.hasMatch(name)) kind = ReceiptItemKind.deposit;
        items.add(ParsedItem(
          rawText: name,
          kind: kind,
          lineTotalCents: cents,
          taxCode: mi.group(2),
          quantity: pendingQty ?? 1,
          quantityUnit: pendingQty == null ? 'piece' : pendingUnit,
          unitPriceCents: pendingUnitPrice,
        ));
        pendingQty = null;
        pendingUnit = 'piece';
        pendingUnitPrice = null;
        continue;
      }

      // Rabatt auf Bon-Ebene: Name, optional "25%", negativer Betrag, aber KEIN Steuerbuchstabe
      final mb = _bonDiscountLine.firstMatch(l);
      if (mb != null && !RegExp(r'\s[A-Z]\s+-?\d').hasMatch(l)) {
        bonDiscounts.add(BonDiscount(
          name: mb.group(1)!.trim(),
          percent: mb.group(2) == null ? null : int.parse(mb.group(2)!),
          cents: _cents(mb.group(3)!),
        ));
        continue;
      }

      // Hinweiszeile ohne Betrag (z.B. nur "EXTREM AKTION")
      if (_labelLine.hasMatch(l)) continue;

      warnings.add('Nicht erkannt: $t');
    }

    // Steuerblock und Re-Nr stehen nach der Summe
    final tax = <String, TaxBlockEntry>{};
    String? reNr;
    String? branch;
    for (final l in lines) {
      final mt = _taxLine.firstMatch(l);
      if (mt != null) {
        final code = mt.group(1)!;
        if (l.contains('steuerbar')) {
          final m = RegExp(_price).firstMatch(l);
          if (m != null) tax[code] = TaxBlockEntry(code: code, grossCents: _cents(m.group(0)!));
        } else if (mt.group(3) != null && mt.group(4) != null) {
          final net = _cents(mt.group(3)!);
          final vat = _cents(mt.group(4)!);
          tax[code] = TaxBlockEntry(
            code: code,
            ratePercent: double.tryParse(mt.group(2)!.replaceAll(',', '.')),
            netCents: net,
            vatCents: vat,
            grossCents: net + vat,
          );
        }
        continue;
      }
      final mr = _reNr.firstMatch(l);
      if (mr != null) {
        reNr = '${mr.group(1)}-${mr.group(2)}-${mr.group(3)}-${mr.group(4)}';
        branch = mr.group(1);
      }
    }

    final itemsSum = items.fold<int>(0, (s, i) => s + i.lineTotalCents);
    final bonDiscountSum = bonDiscounts.fold<int>(0, (s, d) => s + d.cents);

    final perClass = <String, int>{};
    for (final i in items) {
      final c = i.taxCode;
      if (c != null) perClass[c] = (perClass[c] ?? 0) + i.lineTotalCents;
    }
    final differences = <String, int>{};
    final missing = <String>[];
    perClass.forEach((code, sum) {
      final block = tax[code];
      if (block == null) {
        missing.add(code);
      } else if (block.grossCents != sum) {
        differences[code] = sum - block.grossCents;
      }
    });

    final checks = ReceiptChecks(
      itemsSumCents: itemsSum,
      bonDiscountSumCents: bonDiscountSum,
      totalCents: totalCents,
      subtotalCents: subtotal,
      taxBlockGrossSumCents: tax.values.fold<int>(0, (s, e) => s + e.grossCents),
      classDifferences: differences,
      missingTaxClasses: missing,
      unlabeledItems: unlabeledItems,
    );

    return ParsedReceipt(
      chain: 'Billa',
      branchCode: branch,
      externalId: reNr,
      purchasedAtUtc: purchasedAt,
      totalCents: totalCents,
      subtotalCents: subtotal,
      items: items,
      bonDiscounts: bonDiscounts,
      taxBlock: tax,
      warnings: warnings,
      checks: checks,
    );
  }
}
