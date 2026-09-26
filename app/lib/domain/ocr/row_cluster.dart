import 'dart:math' as math;
import 'dart:ui' show Rect;

/// Eine per OCR erkannte Textzeile mit Position im Bild (Bildkoordinaten in Pixeln).
class OcrLine {
  const OcrLine(this.text, this.box);
  final String text;
  final Rect box;
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
