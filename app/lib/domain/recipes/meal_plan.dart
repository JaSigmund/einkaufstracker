import 'dart:convert';

import 'saved_recipe.dart';

/// Wochenplan (ADR-042): reine Regeln, ohne Datenbank.

/// Tageszeiten, die man planen kann; Getraenke plant niemand.
const mealPlanSlots = ['breakfast', 'lunch', 'dinner', 'snack'];

/// Der Montag der Woche von [day], als UTC-Mitternacht wie `meal_plan_entries.planned_on`.
DateTime weekStartOf(DateTime day) {
  final d = DateTime.utc(day.year, day.month, day.day);
  return d.subtract(Duration(days: d.weekday - DateTime.monday));
}

/// Liest die Zutaten eines Plan-Eintrags. Beschaedigte Eintraege werden uebersprungen statt den ganzen Plan mitzureissen.
List<SavedIngredient> decodePlanIngredients(String raw) {
  final Object? list;
  try {
    list = jsonDecode(raw);
  } on FormatException {
    return const [];
  }
  if (list is! List) return const [];
  return [
    for (final e in list)
      if (e is Map<String, dynamic> && e['name'] is String) SavedIngredient.fromJson(e),
  ];
}

String encodePlanIngredients(Iterable<SavedIngredient> ingredients) => jsonEncode([for (final i in ingredients) i.toJson()]);

/// Zutaten aus einer Texteingabe ("Reis, Linsen, Kokosmilch"), getrennt durch Komma oder Zeilenumbruch, doppelte einmal.
List<SavedIngredient> parseIngredientText(String text) {
  final seen = <String>{};
  return [
    for (final part in text.split(RegExp(r'[,\n]')))
      if (part.trim() case final name when name.isNotEmpty && seen.add(name.toLowerCase())) SavedIngredient(productId: null, name: name, unit: 'piece'),
  ];
}

/// Ein Produkt, soweit es fuer den Abgleich zaehlt.
typedef PlanProduct = ({String id, String name, String baseUnit});

/// Eine Zutat, die eingekauft werden muss. Genau eines von [productId] und [freeText] ist gesetzt.
typedef MissingForPlan = ({String? productId, String? freeText, String unit});

/// Was von [ingredients] fehlt. "Fehlt" heisst wie bei den Rezepten: gar kein Bestand (`recipe_shopping_gap.dart`), Mengen kennt die App nicht.
///
/// Eine Zutat ohne Produkt-Zuordnung wird ueber den Namen einem Produkt des Haushalts zugeordnet (ohne Gross- und Kleinschreibung).
/// Gelingt das nicht, fehlt sie als freier Text. Dieselbe Zutat aus mehreren Gerichten steht nur einmal im Ergebnis.
List<MissingForPlan> findMissingForPlan(Iterable<SavedIngredient> ingredients, {required Set<String> inStock, required Iterable<PlanProduct> products}) {
  final byId = {for (final p in products) p.id: p};
  final byName = {for (final p in products) p.name.trim().toLowerCase(): p};
  final seen = <String>{};
  final missing = <MissingForPlan>[];
  for (final i in ingredients) {
    final name = i.name.trim();
    final product = byId[i.productId] ?? byName[name.toLowerCase()];
    if (product != null) {
      if (!inStock.contains(product.id) && seen.add(product.id)) {
        missing.add((productId: product.id, freeText: null, unit: product.baseUnit));
      }
    } else if (name.isNotEmpty && seen.add(name.toLowerCase())) {
      missing.add((productId: null, freeText: name, unit: 'piece'));
    }
  }
  return missing;
}
