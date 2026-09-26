import 'dart:math' as math;
import 'dart:ui' show Rect;

/// Eine per OCR erkannte Textzeile mit Position im Bild.
class OcrLine {
  OcrLine(this.text, this.box, {this.confidence, this.secondPass = false});
  final String text;
  final Rect box;
  final double? confidence;

  /// true, wenn die Zeile erst im zweiten Durchgang (vergroesserte Preisspalte) erkannt wurde.
  final bool secondPass;

  Map<String, dynamic> toJson() => {
        'text': text,
        'l': box.left.round(),
        't': box.top.round(),
        'r': box.right.round(),
        'b': box.bottom.round(),
        if (confidence != null) 'conf': confidence,
        if (secondPass) 'second_pass': true,
      };
}

final _priceRe = RegExp(r'^[\s.]*(-)?\s*(\d{1,3})\s*[.,]\s*(\d{2})\s*$');

/// Liest einen Preis wie "2. 75", ".-0. 96" oder "23, 19" als Euro-Betrag, sonst null.
double? parsePrice(String text) {
  final m = _priceRe.firstMatch(text.trim());
  if (m == null) return null;
  final value = double.parse('${m.group(2)}.${m.group(3)}');
  return m.group(1) != null ? -value : value;
}

bool isPriceText(String text) => parsePrice(text) != null;

/// Fasst OCR-Zeilen zu visuellen Zeilen zusammen (Name links, Preis rechts).
///
/// [slope] ist die Steigung dy/dx der Bonzeilen im Bild (0 = gerade fotografiert). Fotos von
/// Bons sind fast immer leicht schraeg: Auf einem echten Billa-Bon lagen Preise rechts 20 bis
/// 45 px ueber ihrem Namen links. Die Zeilen werden nach `y - slope * x` geclustert.
List<List<OcrLine>> clusterRows(List<OcrLine> lines, {double slope = 0, double toleranceFactor = 0.5}) {
  if (lines.isEmpty) return [];
  final heights = lines.map((l) => l.box.height).toList()..sort();
  final tolerance = math.max(heights[heights.length ~/ 2] * toleranceFactor, 1.0);
  double yOf(OcrLine l) => l.box.center.dy - slope * l.box.center.dx;

  final sorted = [...lines]..sort((a, b) => yOf(a).compareTo(yOf(b)));
  final rows = <List<OcrLine>>[];
  double rowCenter = 0;
  for (final line in sorted) {
    if (rows.isNotEmpty && (yOf(line) - rowCenter).abs() <= tolerance) {
      rows.last.add(line);
      rowCenter += (yOf(line) - rowCenter) / rows.last.length;
    } else {
      rows.add([line]);
      rowCenter = yOf(line);
    }
  }
  for (final r in rows) {
    r.sort((a, b) => a.box.left.compareTo(b.box.left));
  }
  return rows;
}

/// Zeilen, die links Text und rechts einen Preis haben: Mass fuer eine gute Steigung.
int _nameAndPriceRows(List<List<OcrLine>> rows, double priceX) {
  var good = 0;
  for (final r in rows) {
    final hasPrice = r.any((l) => isPriceText(l.text) && l.box.center.dx >= priceX);
    final hasName = r.any((l) => !isPriceText(l.text) && l.box.center.dx < priceX);
    if (hasPrice && hasName) good++;
  }
  return good;
}

/// Schaetzt die Schraeglage (dy/dx) des Bons: probiert Steigungen von -0.12 bis +0.12 durch
/// und nimmt diejenige, bei der die meisten Zeilen Name links und Preis rechts vereinen.
double estimateSlope(List<OcrLine> all) {
  var lines = all;
  // Nur den Positionsbereich (zwischen "Datum" und "Summe") betrachten: Kopf und Zahlungsblock
  // haben andere Layouts und verfaelschen die Schaetzung.
  final datum = all.where((l) => l.text.toLowerCase().contains('datum')).toList()
    ..sort((a, b) => a.box.top.compareTo(b.box.top));
  final summe = all.where((l) => l.text.toLowerCase().startsWith('summe')).toList();
  if (datum.isNotEmpty && summe.isNotEmpty && summe.first.box.top > datum.first.box.bottom) {
    final top = datum.first.box.center.dy;
    final bottom = summe.first.box.center.dy;
    final body = all.where((l) => l.box.center.dy > top && l.box.center.dy < bottom + l.box.height).toList();
    if (body.length >= 6) lines = body;
  }
  if (lines.length < 6) return 0;
  final maxRight = lines.map((l) => l.box.right).reduce(math.max);
  final priceX = maxRight * 0.7;
  // Alle Steigungen mit dem besten Wert sammeln und die Mitte des Plateaus nehmen
  // (robuster als der erste oder kleinste Treffer).
  var bestScore = -1;
  var plateau = <double>[];
  for (var i = -120; i <= 120; i += 2) {
    final s = i / 1000;
    final score = _nameAndPriceRows(clusterRows(lines, slope: s), priceX);
    if (score > bestScore) {
      bestScore = score;
      plateau = [s];
    } else if (score == bestScore) {
      plateau.add(s);
    }
  }
  return plateau[plateau.length ~/ 2];
}

/// Ergebnis des Summenchecks (Plausibilitaet aus Doku 05 §3.5).
class SumCheck {
  SumCheck(this.pricesSum, this.pricesFound, this.billTotal);
  final double pricesSum;
  final int pricesFound;
  final double? billTotal;
  double? get difference => billTotal == null ? null : billTotal! - pricesSum;
  bool get ok => difference != null && difference!.abs() < 0.005;
}

// "2 x 1.19", "2x 1. 19", "-2_X 0. 25" (OCR macht aus x oft _ oder X), "0.986 kg (N) x 4.99 EUR/kg"
final _quantityRe = RegExp(r'^\s*-?\d+(?:\s*[.,]\s*\d+)?\s*(?:kg|g|l)?\s*(?:\(N\))?\s*[xX×_]', caseSensitive: false);

/// Mengenzeile: gehoert zur Position darunter, ihr Betrag ist ein Einzelpreis.
bool isQuantityRow(List<OcrLine> row) {
  final text = row.map((l) => l.text.trim()).join(' ');
  return _quantityRe.hasMatch(text) || RegExp(r'EUR\s*/\s*(kg|l)', caseSensitive: false).hasMatch(text);
}

bool isSubtotalRow(List<OcrLine> row) => row.any((l) => l.text.toLowerCase().startsWith('zwischensumme'));

/// Summiert alle Preise zwischen der Datumszeile und der Zeile "Summe" und vergleicht mit der Bon-Summe.
SumCheck checkSum(List<List<OcrLine>> rows) {
  final start = rows.indexWhere((r) => r.any((l) => l.text.toLowerCase().contains('datum')));
  final end = rows.indexWhere((r) => r.any((l) => l.text.toLowerCase().startsWith('summe')));
  if (end < 0) return SumCheck(0, 0, null);
  var sum = 0.0;
  var n = 0;
  for (var i = start + 1; i < end; i++) {
    // Mengenzeilen ("2 x 1.19", "0.986 kg x 4.99 EUR/kg") tragen nur den Einzelpreis, nicht den Zeilenpreis;
    // die Zwischensumme ist keine Position. Beides zaehlt nicht zur Summe.
    if (isQuantityRow(rows[i]) || isSubtotalRow(rows[i])) continue;
    // Preise stehen rechts; der letzte Preis der Zeile ist der Zeilenpreis
    final prices = rows[i].map((l) => parsePrice(l.text)).whereType<double>().toList();
    if (prices.isNotEmpty) {
      sum += prices.last;
      n++;
    }
  }
  final totalPrices = rows[end].map((l) => parsePrice(l.text)).whereType<double>().toList();
  return SumCheck(sum, n, totalPrices.isEmpty ? null : totalPrices.last);
}

/// Rendert Zeilen als Text: Spalten mit " | " getrennt, Zeilen aus dem zweiten Durchgang mit *.
String renderRows(List<List<OcrLine>> rows) => rows
    .map((r) => r.map((l) => '${l.secondPass ? '*' : ''}${l.text.trim()}').join(' | '))
    .join('\n');
