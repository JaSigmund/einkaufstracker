/// Mikronaehrstoffe fuer aeltere Mahlzeiten nachrechnen (Phase N4, ADR-035): Zutaten, die vor Version 1.11 erfasst wurden, kennen ihren
/// BLS-Eintrag (oder ihr Produkt), haben aber keinen Mikronaehrstoff-Snapshot. Aus dem Profil des Eintrags und der gespeicherten Menge
/// laesst sich dieser Snapshot nachtraeglich bilden, ohne dass der Nutzer etwas neu erfassen muss.
///
/// Reine Funktionen ohne Datenbank- und Netzzugriff. Regeln (dieselben wie beim Speichern einer Zutat in `MealRepository`):
/// - Das Profil eines **Produkts** mit Mikronaehrstoffen gilt zuerst, sonst das des BLS-Eintrags der Zeile, sonst das des BLS-Eintrags des
///   Produkts. Handwerte (ohne BLS-Eintrag und ohne Produkt) bleiben unberuehrt: dort gibt es nichts nachzurechnen.
/// - Es wird nur ergaenzt, nie ueberschrieben: eine Zutat mit Snapshot bleibt wie sie ist.
/// - Ohne bekannte Menge (Stueck ohne Gewicht) gibt es keinen Snapshot, nichts wird geraten.
library;

import 'micros.dart';

/// Eine gespeicherte Zutat fuer die Nachrechnung (unabhaengig von der Datenbank-Klasse). [grams] ist die Menge, auf die sich die
/// Naehrwerte der Zeile beziehen (g oder ml), `null` ohne bekannte Menge.
typedef BackfillIngredient = ({String id, String? productId, String? blsCode, double? grams, bool hasMicros});

/// Ergebnis: die neuen Snapshots je Zutat-ID und was nicht ging.
class BackfillPlan {
  const BackfillPlan({required this.updates, required this.withoutAmount, required this.withoutData});

  /// Neue Snapshots (absolute Menge fuer die gespeicherte Menge), nur fuer Zutaten ohne bisherigen Snapshot.
  final Map<String, Micros> updates;

  /// Zutaten mit Profil, aber ohne bekannte Menge.
  final int withoutAmount;

  /// Zutaten, deren Quelle (BLS-Eintrag, Produkt) keine Mikronaehrstoffe liefert.
  final int withoutData;
}

/// Der BLS-Code, dessen Profil fuer die Zutat gilt, `null`, wenn das Profil vom Produkt selbst kommt oder es keine Quelle gibt.
String? _blsCodeFor(BackfillIngredient i, Map<String, Micros> productMicros100, Map<String, String> productBlsCodes) {
  final p = i.productId;
  if (p != null && productMicros100.containsKey(p)) return null;
  return i.blsCode ?? (p == null ? null : productBlsCodes[p]);
}

bool _hasSource(BackfillIngredient i, Map<String, Micros> productMicros100, Map<String, String> productBlsCodes) {
  final p = i.productId;
  return (p != null && productMicros100.containsKey(p)) || _blsCodeFor(i, productMicros100, productBlsCodes) != null;
}

/// Zutaten ohne Snapshot, fuer die es eine Quelle gibt (Produkt mit Mikronaehrstoffen oder BLS-Eintrag): so viele koennen nachgerechnet
/// werden, sofern die Quelle Werte hat und die Menge bekannt ist.
int backfillCandidateCount(
  Iterable<BackfillIngredient> ingredients, {
  Map<String, Micros> productMicros100 = const {},
  Map<String, String> productBlsCodes = const {},
}) =>
    ingredients.where((i) => !i.hasMicros && _hasSource(i, productMicros100, productBlsCodes)).length;

/// Die BLS-Codes, deren Mikronaehrstoffe vom Server geholt werden muessen.
Set<String> backfillBlsCodes(
  Iterable<BackfillIngredient> ingredients, {
  Map<String, Micros> productMicros100 = const {},
  Map<String, String> productBlsCodes = const {},
}) =>
    {
      for (final i in ingredients)
        if (!i.hasMicros) ?_blsCodeFor(i, productMicros100, productBlsCodes),
    };

/// Bildet die fehlenden Snapshots. [blsMicros100] sind die vom Server geholten Profile je 100 g (ein Code ohne Eintrag oder ohne Werte
/// zaehlt als "ohne Daten").
BackfillPlan planMicrosBackfill(
  Iterable<BackfillIngredient> ingredients, {
  Map<String, Micros> productMicros100 = const {},
  Map<String, String> productBlsCodes = const {},
  required Map<String, Micros> blsMicros100,
}) {
  final updates = <String, Micros>{};
  var noAmount = 0;
  var noData = 0;
  for (final i in ingredients) {
    if (i.hasMicros || !_hasSource(i, productMicros100, productBlsCodes)) continue;
    final code = _blsCodeFor(i, productMicros100, productBlsCodes);
    final profile = code == null ? productMicros100[i.productId] : blsMicros100[code];
    if (profile == null || profile.isEmpty) {
      noData++;
      continue;
    }
    final scaled = scaleMicros(profile, i.grams);
    if (scaled == null) {
      noAmount++;
      continue;
    }
    updates[i.id] = scaled;
  }
  return BackfillPlan(updates: updates, withoutAmount: noAmount, withoutData: noData);
}
