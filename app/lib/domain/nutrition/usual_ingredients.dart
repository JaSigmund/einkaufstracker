/// "Fehlt etwas?" (Phase 7c, offener Rest, Doku 15 §6): Auf einem Foto sieht man Oel, Butter, Gewuerze und die Basis einer Sosse nicht. Wer
/// ein aehnliches Gericht schon oefter erfasst hat, hatte diese Zutaten meist dabei. Die App schlaegt sie vor, wenn sie in der
/// Mehrzahl der aehnlichen frueheren Mahlzeiten vorkamen und in der aktuellen fehlen. Nichts wird ohne Antippen uebernommen.
///
/// Reine Funktionen ohne Datenbankzugriff. Regeln (alle gegen Zufallstreffer):
/// - Eine fruehere Mahlzeit ist **aehnlich**, wenn sie mindestens zwei der aktuellen Zutaten enthaelt (bei nur einer aktuellen Zutat
///   diese eine) und mindestens die Haelfte der aktuellen Zutaten.
/// - Vorgeschlagen wird erst, wenn es mindestens **zwei** aehnliche Mahlzeiten gibt (ein Muster, kein Einzelfall) und die Zutat in
///   mindestens zwei davon und in mindestens der Haelfte davon vorkam.
/// - Hoechstens vier Vorschlaege, die haeufigsten zuerst.
library;

import '../categorization/normalize_name.dart';
import 'micros.dart';

/// Eine Zutat einer frueheren Mahlzeit mit ihrem Snapshot (absolute Werte fuer [grams]).
typedef PastIngredient = ({
  String label,
  String? productId,
  String? blsCode,
  double? grams,
  double? kcal,
  double? proteinG,
  double? fatG,
  double? carbsG,
  double? sugarG,
  double? fiberG,
  double? saltG,
  Micros? micros,
});

typedef PastMeal = ({String id, List<PastIngredient> ingredients});

/// Schluessel einer Zutat fuer den Vergleich: Produkt, sonst BLS-Eintrag, sonst der normalisierte Name.
String ingredientKey({String? productId, String? blsCode, required String name}) {
  if (productId != null) return 'p:$productId';
  if (blsCode != null) return 'b:$blsCode';
  return 'n:${normalizeItemName(name)}';
}

/// Ein Vorschlag mit dem, was zum Anlegen der Zeile gebraucht wird (Menge und Profile je 100 g aus dem juengsten Vorkommen).
class UsualIngredient {
  const UsualIngredient({
    required this.key,
    required this.label,
    required this.meals,
    required this.similarMeals,
    this.productId,
    this.blsCode,
    this.medianGrams,
    this.per100,
    this.micros100,
  });

  final String key;
  final String label;
  final String? productId;
  final String? blsCode;

  /// In wie vielen der [similarMeals] die Zutat vorkam.
  final int meals;
  final int similarMeals;

  /// Typische Menge in g (Median ueber die Vorkommen mit bekannter Menge), `null` ohne.
  final double? medianGrams;

  /// Makros je 100 g aus dem juengsten Vorkommen mit Menge und Werten, `null` ohne (dann bleibt die Zutat ohne Naehrwerte).
  final Map<String, double>? per100;
  final Micros? micros100;
}

double? _median(List<double> v) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

Map<String, double>? _per100Of(PastIngredient i) {
  final g = i.grams;
  if (g == null || !(g > 0)) return null;
  final out = <String, double>{
    if (i.kcal != null) 'kcal': i.kcal! * 100 / g,
    if (i.proteinG != null) 'protein_g': i.proteinG! * 100 / g,
    if (i.fatG != null) 'fat_g': i.fatG! * 100 / g,
    if (i.carbsG != null) 'carbs_g': i.carbsG! * 100 / g,
    if (i.sugarG != null) 'sugar_g': i.sugarG! * 100 / g,
    if (i.fiberG != null) 'fiber_g': i.fiberG! * 100 / g,
    if (i.saltG != null) 'salt_g': i.saltG! * 100 / g,
  };
  return out.isEmpty ? null : out;
}

/// Die Zutaten, die in aehnlichen frueheren Mahlzeiten ueblich waren und in der aktuellen fehlen.
///
/// [current] sind die Schluessel der aktuellen Zutaten (siehe [ingredientKey]), [history] frueheren Mahlzeiten, die juengste zuerst
/// (die juengste Fassung einer Zutat liefert Profil und Namen). Die aktuelle Mahlzeit selbst gehoert nicht in [history].
///
/// Eine Zutat gilt auch dann als vorhanden, wenn nur ihr **Name** zu einer aktuellen passt ([currentNames]: `ingredientKey(name:)` der
/// aktuellen Zutaten). Das faengt ab, dass die Foto-Analyse "Olivenöl" ohne BLS-Zuordnung liefert, die fruehere Mahlzeit aber mit.
List<UsualIngredient> suggestMissingIngredients({
  required Set<String> current,
  required Iterable<PastMeal> history,
  Set<String> currentNames = const {},
  int limit = 4,
}) {
  if (current.isEmpty) return const [];
  final need = current.length == 1 ? 1 : 2;
  String keyOf(PastIngredient i) => ingredientKey(productId: i.productId, blsCode: i.blsCode, name: i.label);
  bool isCurrent(PastIngredient i) {
    final nameKey = ingredientKey(name: i.label);
    return current.contains(keyOf(i)) || current.contains(nameKey) || currentNames.contains(nameKey);
  }

  final similar = <PastMeal>[];
  for (final m in history) {
    final common = {for (final i in m.ingredients) if (isCurrent(i)) keyOf(i)}.length;
    if (common >= need && common >= current.length / 2) similar.add(m);
  }
  if (similar.length < 2) return const [];

  final seen = <String, List<PastIngredient>>{};
  for (final m in similar) {
    final once = <String>{};
    for (final i in m.ingredients) {
      final key = keyOf(i);
      if (isCurrent(i) || !once.add(key)) continue;
      seen.putIfAbsent(key, () => []).add(i);
    }
  }
  final out = <UsualIngredient>[];
  for (final e in seen.entries) {
    final n = e.value.length;
    if (n < 2 || n < similar.length / 2) continue;
    final latest = e.value.first; // history ist juengste zuerst
    final withProfile = e.value.firstWhere((i) => _per100Of(i) != null, orElse: () => latest);
    final withMicros = e.value.firstWhere((i) => i.micros != null && i.grams != null && i.grams! > 0, orElse: () => latest);
    out.add(UsualIngredient(
      key: e.key,
      label: latest.label,
      productId: latest.productId,
      blsCode: latest.blsCode,
      meals: n,
      similarMeals: similar.length,
      medianGrams: _median([for (final i in e.value) if (i.grams != null && i.grams! > 0) i.grams!]),
      per100: _per100Of(withProfile),
      micros100: micros100From(withMicros.micros, withMicros.grams),
    ));
  }
  out.sort((a, b) {
    final byCount = b.meals.compareTo(a.meals);
    return byCount != 0 ? byCount : a.label.compareTo(b.label);
  });
  return out.take(limit).toList();
}
