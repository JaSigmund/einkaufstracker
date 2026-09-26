/// Normalisiert einen Bon-Artikelnamen, damit gleiche Artikel unabhaengig von Schreibweise, Gross- und
/// Kleinschreibung, Umlauten, Gewichtsangaben und Bon-Praefixen denselben Schluessel bekommen.
///
/// Beispiele:
///   "IC DKIH Erdäpfel vofe 2kg"        -> "dkih erdaepfel vofe"
///   "DKIH Paprika Tricolore"           -> "dkih paprika tricolore"
///   "IC DKIH Paprika Tricolore"        -> "dkih paprika tricolore"  (gleicher Schluessel wie ohne "IC")
///   "SG RUCOLA SALAT 125G"             -> "sg rucola salat"
///
/// Der Schluessel dient sowohl der lernenden Zuordnung (Alias) als auch den Stichwortregeln.
library;

const _fold = {
  'ä': 'ae', 'ö': 'oe', 'ü': 'ue', 'ß': 'ss',
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'å': 'a',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ı': 'i',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u',
  'ñ': 'n', 'ç': 'c', 'ý': 'y',
};

/// "Inner-Clever-Preis" und typische OCR-Verwechslungen davon am Namensanfang ("1C", "IO", "IC" mit Punkt).
final _pricePrefix = RegExp(r'^(ic|1c|io|i0|lc)\s+');

/// Einzelne Woerter, die nur Mengen oder Einheiten sind.
const _unitTokens = {'kg', 'g', 'dag', 'l', 'ml', 'cl', 'stk', 'st', 'x'};

String normalizeItemName(String raw) {
  // Kombinierende Akzentzeichen (z.B. der Punkt aus "İ".toLowerCase()) entfernen
  var s = raw.toLowerCase().replaceAll(RegExp('[̀-ͯ]'), '');
  final b = StringBuffer();
  for (final ch in s.split('')) {
    b.write(_fold[ch] ?? ch);
  }
  s = b.toString();

  // Alles ausser Buchstaben und Ziffern wird zu Leerzeichen (auch das Ersatzzeichen U+FFFD kaputter Kodierungen)
  s = s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  s = s.replaceFirst(_pricePrefix, '');

  final tokens = <String>[];
  for (final t in s.split(' ')) {
    if (t.isEmpty) continue;
    if (_unitTokens.contains(t)) continue;
    if (RegExp(r'^\d+[a-z]{0,3}$').hasMatch(t)) continue; // "125g", "2kg", "500", "6er"
    tokens.add(t);
  }
  return tokens.join(' ');
}
