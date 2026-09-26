import 'dart:math' as math;

import 'row_cluster.dart';

/// Macht aus geclusterten OCR-Zeilen einen Text im Format der digitalen Bons, damit derselbe
/// Parser beide Wege liest. Behebt die haeufigsten OCR-Eigenheiten:
/// - Preise mit Leerraum ("2. 75", "-0. 96") -> "2.75", "-0.96"
/// - Datum und Uhrzeit mit Leerraum ("24. 09. 2026") -> "24.09.2026"
/// - Mengenzeilen ("2 x 1.19", "-2_X 0.25", "0.986 kg (N) X 4.99 EUR/kg"): das x wird vereinheitlicht
/// - "EÜR" -> "EUR"
/// Zellen einer Zeile werden mit Leerzeichen verbunden (Name links, Preis rechts).
String ocrRowsToText(List<List<OcrLine>> rows) {
  return rows.map((r) => _normalizeRow(r.map((l) => l.text.trim()).where((t) => t.isNotEmpty).join(' '))).join('\n');
}

final _dateSpaces = RegExp(r'(\d{2})\s*\.\s*(\d{2})\s*\.\s*(\d{4})');
final _timeSpaces = RegExp(r'Zeit:\s*(\d{1,2})\s*:\s*(\d{2})');
final _trailingPrice = RegExp(r'(-\s*)?(\d{1,4})\s*[.,]\s*(\d{2})\s*$');
final _midPrice = RegExp(r'(\d{1,4})\s*[.,]\s*(\d{2})(?=\s*(?:=|EUR|E[ÜU]R|$))');
final _quantityStart = RegExp(r'^(\s*-?\d+(?:\s*[.,]\s*\d+)?\s*(?:kg|g|l)?\s*(?:\(N\))?\s*)(?:_\s*[xX]|[xX×_])\s*(?=\S)', caseSensitive: false);

String _normalizeRow(String row) {
  var s = row.replaceAll('�', '').replaceAll(RegExp(r'E[ÜU]R'), 'EUR');
  s = s.replaceAllMapped(_dateSpaces, (m) => '${m[1]}.${m[2]}.${m[3]}');
  s = s.replaceAllMapped(_timeSpaces, (m) => 'Zeit: ${m[1]}:${m[2]}');
  final q = _quantityStart.firstMatch(s);
  if (q != null) s = '${q[1]!.trimRight()} x ${s.substring(q.end)}';
  // Gleichheitszeichen im Steuerblock ("15.99 = 1.60") und Preise in der Zeilenmitte
  s = s.replaceAllMapped(_midPrice, (m) => '${m[1]}.${m[2]}');
  s = s.replaceAllMapped(_trailingPrice, (m) => '${m[1] == null ? '' : '-'}${m[2]}.${m[3]}');
  s = s.replaceAll(RegExp(r'\s+'), ' ');
  // Preisspalte wieder mit Abstand vom Namen absetzen ist nicht noetig: der Parser trennt an Leerzeichen
  return s.trim();
}

final _summe = RegExp(r'^\s*summe\b', caseSensitive: false);
final _paymentWords = RegExp(
  r'kundenbeleg|bezahlung|contactless|terminal-?id|trace-?nr|beleg-?nr|vu-?nr|visa|mastercard|maestro|girocard',
  caseSensitive: false,
);

/// Y-Koordinate (Bildpixel), oberhalb derer das Bild fuer die Cloud abgeschnitten wird, damit Kundenbeleg
/// und Zahlungsdaten (maskierte Kartennummer, Terminal-ID) das Geraet nie verlassen (Go/No-Go B4).
///
/// Der Schnitt liegt knapp unter der Zeile "Summe". Fehlt sie, unter der letzten Zeile vor dem ersten
/// Zahlungsstichwort. Null, wenn beides nicht gefunden wird: dann darf **nichts** hochgeladen werden.
double? paymentCutY(List<OcrLine> lines, {double slope = 0}) {
  if (lines.isEmpty) return null;
  final rows = clusterRows(lines, slope: slope);
  final heights = lines.map((l) => l.box.height).toList()..sort();
  final margin = heights[heights.length ~/ 2] * 0.5;

  double rowBottom(List<OcrLine> r) => r.map((l) => l.box.bottom).reduce(math.max);
  double rowTop(List<OcrLine> r) => r.map((l) => l.box.top).reduce(math.min);

  for (final r in rows) {
    if (r.isNotEmpty && _summe.hasMatch(r.first.text)) return rowBottom(r) + margin;
  }
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].any((l) => _paymentWords.hasMatch(l.text))) {
      final previous = i == 0 ? null : rows[i - 1];
      // Ohne Zeile davor gibt es nichts Sicheres zu senden
      return previous == null ? null : rowBottom(previous) + margin.clamp(0, rowTop(rows[i]) - rowBottom(previous));
    }
  }
  return null;
}
