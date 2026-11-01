import 'unit_price.dart';

/// Wie viel von einem Artikel gekauft wurde, fuer die Monatsauswertung: Packungen je Inhalt, gewogene Ware und
/// die Gesamtmenge daraus ("4× je 500 g · 2 kg gesamt").
///
/// Der Inhalt je Packung kommt zuerst aus dem Bon-Text, weil ein Produkt in mehreren Packungsgroessen gekauft
/// werden kann (siehe [computeUnitPriceNormCents]), sonst aus dem Produkt (`packSize` in der Basiseinheit).
/// Anders als beim Grundpreis gilt der Bon-Text auch bei abweichender Basiseinheit: Hier steht die Menge nur da,
/// sie geht in keinen Preisvergleich ein.
class PurchasedAmount {
  final Map<ReceiptPackSize, double> _packs = {};
  final Map<String, double> _weighed = {};
  double _unknownPacks = 0;
  int _weighedLines = 0;

  /// Nimmt eine Artikelzeile auf. Bon-Menge in Stueck zaehlt Packungen, in `kg`/`l` ist sie schon die Menge.
  void add({
    required double quantity,
    required String quantityUnit,
    required String rawText,
    String? productBaseUnit,
    double? productPackSize,
  }) {
    if (quantityUnit != 'piece') {
      _weighed[quantityUnit] = (_weighed[quantityUnit] ?? 0) + quantity;
      _weighedLines++;
      return;
    }
    final content = _contentPerPack(rawText, productBaseUnit, productPackSize);
    if (content == null) {
      _unknownPacks += quantity;
    } else {
      _packs[content] = (_packs[content] ?? 0) + quantity;
    }
  }

  /// `null` ohne bekannten Inhalt. Eine "Packung" mit einem Stueck sagt nichts aus und zaehlt als unbekannt.
  static ReceiptPackSize? _contentPerPack(String rawText, String? baseUnit, double? packSize) {
    final content = parsePackSizeFromReceiptText(rawText) ??
        (baseUnit == null || packSize == null ? null : (amount: packSize, unit: baseUnit));
    if (content == null || content.amount <= 0) return null;
    if (content.unit == 'piece' && content.amount <= 1) return null;
    // Gerundet, damit 150 × 0,001 und 0,15 dieselbe Packungsgroesse sind.
    return (amount: (content.amount * 1e6).round() / 1e6, unit: content.unit);
  }

  /// Text fuer die Artikelzeile, `null` wenn nichts aufgenommen wurde (Pfand, Rabatt-Sammelzeile).
  String? describe() {
    final packs = _packs.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) {
        final byUnit = a.key.unit.compareTo(b.key.unit);
        return byUnit != 0 ? byUnit : a.key.amount.compareTo(b.key.amount);
      });
    if (packs.isEmpty && _weighedLines == 0) {
      return _unknownPacks > 0 ? '${_formatCount(_unknownPacks)}× gekauft' : null;
    }

    final totals = <String, double>{..._weighed};
    for (final p in packs) {
      totals[p.key.unit] = (totals[p.key.unit] ?? 0) + p.key.amount * p.value;
    }
    final parts = [
      for (final p in packs)
        packs.length == 1 && _weighedLines == 0 && _unknownPacks <= 0 && p.value > 1
            ? '${_formatCount(p.value)}× je ${_formatAmount(p.key.amount, p.key.unit)}'
            : '${_formatCount(p.value)}× ${_formatAmount(p.key.amount, p.key.unit)}',
      if (_weighedLines > 0) '$_weighedLines× gewogen',
      if (_unknownPacks > 0) '${_formatCount(_unknownPacks)}× ohne Angabe',
    ];
    // Eine einzelne Packung ist ihre eigene Gesamtmenge.
    final single = packs.length == 1 && packs.single.value == 1 && _weighedLines == 0 && _unknownPacks <= 0;
    if (single) return parts.single;
    final units = totals.keys.toList()..sort();
    final total = units.map((u) => _formatAmount(totals[u]!, u)).join(' + ');
    return '${parts.join(', ')} · ${_unknownPacks > 0 ? 'mind. ' : ''}$total gesamt';
  }
}

String _formatCount(double v) => v == v.roundToDouble() ? v.round().toString() : _trimmed(v);

/// "500 g", "1,5 kg", "750 ml", "2 l", "3 Stk."
String _formatAmount(double amount, String unit) => switch (unit) {
      'kg' => amount < 1 ? '${(amount * 1000).round()} g' : '${_trimmed(amount)} kg',
      'l' => amount < 1 ? '${(amount * 1000).round()} ml' : '${_trimmed(amount)} l',
      'piece' => '${_trimmed(amount)} Stk.',
      _ => '${_trimmed(amount)} $unit',
    };

/// Hoechstens drei Nachkommastellen, ohne Nullen am Ende, mit Dezimalkomma.
String _trimmed(double v) =>
    v.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '').replaceAll('.', ',');
