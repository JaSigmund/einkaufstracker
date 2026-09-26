import 'dart:typed_data';

import '../../domain/receipt/parsed_receipt.dart';
import '../../domain/receipt/vienna_time.dart';

/// Die Cloud ist nicht erreichbar oder hat nicht geantwortet (offline, Fehler, Zeitueberschreitung).
class CloudUnavailable implements Exception {
  const CloudUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Der Haushalt hat die Cloud-Erkennung nicht erlaubt (household_settings.allow_cloud_ocr).
class CloudNotAllowed implements Exception {
  const CloudNotAllowed();
  @override
  String toString() => 'Cloud-Erkennung ist in den Einstellungen ausgeschaltet.';
}

/// Liest einen Bon aus Fotos ueber die Edge Function parse-receipt (Claude Vision).
abstract class CloudReceiptReader {
  /// [jpegs] sind bereits verkleinert und ohne Zahlungsblock (siehe ImagePreparer).
  Future<ParsedReceipt> read(List<Uint8List> jpegs);
}

/// Bildet die Antwort der Edge Function auf das gemeinsame Bonmodell ab.
///
/// Die Cloud liefert keinen Steuerblock und keine Re-Nr. Das Pruef-Tor ist hier die Summe (Positionen gegen
/// "Summe"); die Steuerpruefung entfaellt. Unsicher gelesene Zeilen erscheinen als Hinweis.
ParsedReceipt parsedReceiptFromCloud(Map<String, dynamic> response) {
  final receipt = response['receipt'];
  if (receipt is! Map) return const ParsedReceipt.failed(['Die Cloud hat keinen Bon geliefert.']);
  final total = receipt['total_cents'];
  final purchasedAt = _parseTime(receipt['purchased_at']);
  if (total is! int) return const ParsedReceipt.failed(['Die Cloud hat keine Summe gefunden.']);
  if (purchasedAt == null) return const ParsedReceipt.failed(['Die Cloud hat kein Datum gefunden.']);

  final warnings = <String>[];
  final items = <ParsedItem>[];
  for (final raw in (receipt['items'] as List? ?? const [])) {
    if (raw is! Map) continue;
    final cents = raw['line_total_cents'];
    final name = (raw['raw_text'] as String?)?.trim() ?? '';
    if (cents is! int) {
      warnings.add('Position ohne Betrag ausgelassen: $name');
      continue;
    }
    final kind = switch (raw['kind']) {
      'deposit' => ReceiptItemKind.deposit,
      'discount' => ReceiptItemKind.discount,
      _ => ReceiptItemKind.article,
    };
    final unit = raw['quantity_unit'] == 'kg' || raw['quantity_unit'] == 'l' ? raw['quantity_unit'] as String : 'piece';
    items.add(ParsedItem(
      rawText: name,
      kind: kind,
      lineTotalCents: cents,
      quantity: (raw['quantity'] as num?)?.toDouble() ?? 1,
      quantityUnit: unit,
      unitPriceCents: raw['unit_price_cents'] as int?,
    ));
    if (raw['uncertain'] == true) warnings.add('Unsicher gelesen: $name');
  }

  final store = (receipt['store_name'] as String?)?.trim();
  final chain = store == null || store.isEmpty ? null : (RegExp('billa', caseSensitive: false).hasMatch(store) ? 'Billa' : store);

  return ParsedReceipt(
    chain: chain,
    items: items,
    bonDiscounts: const [],
    taxBlock: const {},
    warnings: warnings,
    purchasedAtUtc: purchasedAt,
    totalCents: total,
    checks: ReceiptChecks(
      itemsSumCents: items.fold<int>(0, (s, i) => s + i.lineTotalCents),
      bonDiscountSumCents: 0,
      totalCents: total,
      subtotalCents: null,
      taxBlockGrossSumCents: 0,
      classDifferences: const {},
      missingTaxClasses: const [],
    ),
  );
}

/// ISO-8601 mit oder ohne Zeitzone. Ohne Zeitzone gilt Wiener Ortszeit wie auf dem Bon gedruckt.
DateTime? _parseTime(Object? value) {
  if (value is! String) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::\d{2}(?:\.\d+)?)?\s*(Z|[+-]\d{2}:?\d{2})?$').firstMatch(value.trim());
  if (m == null) return null;
  if (m.group(6) != null) return DateTime.tryParse(value.trim())?.toUtc();
  return viennaLocalToUtc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), int.parse(m[4]!), int.parse(m[5]!));
}
