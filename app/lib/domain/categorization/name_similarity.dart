/// Unscharfer Vergleich normalisierter Namen (ADR-023), zusaetzlich zum exakten Alias-Treffer in
/// `ProductRepository.findOrCreateForReceiptItem`: ein einzelnes OCR-Leerzeichen mitten im Wort
/// ("Faschiertes" -> "Faschi ertes") aendert den normalisierten Schluessel, obwohl es derselbe Artikel
/// ist. `normalizeItemName` (siehe dort) kann das nicht abfangen, weil es ganze Tokens vergleicht.
library;

/// Levenshtein-Distanz: Anzahl Einfuege-/Loesch-/Ersetzoperationen, um [a] in [b] zu verwandeln.
int levenshteinDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  var previous = List<int>.generate(b.length + 1, (j) => j);
  var current = List<int>.filled(b.length + 1, 0);

  for (var i = 1; i <= a.length; i++) {
    current[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      current[j] = [
        current[j - 1] + 1, // Einfuegen
        previous[j] + 1, // Loeschen
        previous[j - 1] + cost, // Ersetzen/Treffer
      ].reduce((x, y) => x < y ? x : y);
    }
    final tmp = previous;
    previous = current;
    current = tmp;
  }
  return previous[b.length];
}

/// Konservative Fehlertoleranz je nach Schluessellaenge: je kuerzer der normalisierte Name, desto eher
/// waere derselbe Zeichen-Abstand ein ganz anderes Wort (z.B. "ei" vs. "el") statt eines Tippfehlers.
/// Kurze Namen muessen deshalb exakt treffen.
int maxFuzzyDistance(String normalizedKey) {
  final len = normalizedKey.length;
  if (len >= 10) return 2;
  if (len >= 5) return 1;
  return 0;
}

/// Der naechstgelegene Kandidat aus [candidates], wenn er innerhalb der konservativen Toleranz von [key]
/// liegt — sonst `null`. Exakte Treffer werden uebersprungen, die laufen bereits ueber den normalen
/// Alias-Lookup vor diesem Aufruf.
String? closestWithinTolerance(String key, Iterable<String> candidates) {
  final tolerance = maxFuzzyDistance(key);
  if (tolerance == 0) return null;

  String? best;
  var bestDistance = tolerance + 1;
  for (final candidate in candidates) {
    if (candidate == key) continue;
    final d = levenshteinDistance(key, candidate);
    if (d < bestDistance) {
      bestDistance = d;
      best = candidate;
    }
  }
  return bestDistance <= tolerance ? best : null;
}

/// Indexpaare aus [normalizedKeys], deren Abstand knapp ausserhalb der automatischen Toleranz liegt
/// (`maxFuzzyDistance` < Abstand <= `maxFuzzyDistance + 2`) — zu unsicher fuer eine stille Automatik,
/// aber nah genug fuer einen Zusammenfuehren-Vorschlag (ADR-023). O(n^2), bei ueblichen Haushalts-
/// Produktzahlen (niedrige zweistellige bis wenige hundert) unproblematisch fuer einen Seitenaufruf.
List<(int, int)> likelyDuplicatePairs(List<String> normalizedKeys) {
  final result = <(int, int)>[];
  for (var i = 0; i < normalizedKeys.length; i++) {
    final keyI = normalizedKeys[i];
    if (keyI.isEmpty) continue;
    final autoTolerance = maxFuzzyDistance(keyI);
    final suggestTolerance = autoTolerance + 2;
    for (var j = i + 1; j < normalizedKeys.length; j++) {
      final keyJ = normalizedKeys[j];
      if (keyJ.isEmpty || keyI == keyJ) continue;
      final d = levenshteinDistance(keyI, keyJ);
      if (d > autoTolerance && d <= suggestTolerance) {
        result.add((i, j));
      }
    }
  }
  return result;
}
