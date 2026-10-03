/// Ergebnis der Foto-Analyse einer Mahlzeit (Phase 7c, Doku 15 §6, Edge Function `analyze-meal`).
///
/// Immer nur ein **Vorschlag** zum Bearbeiten: Mengen aus einem Foto sind Schaetzungen mit hoher Streuung. Der
/// Server bereinigt die Antwort bereits, trotzdem wird sie hier defensiv gelesen: ein kaputter Eintrag verwirft nicht
/// die ganze Antwort (gleiches Prinzip wie `parseRecipeSuggestions`, ADR-008).
library;

import 'food_match.dart';
import 'food_unit.dart';

/// Eine erkannte Zutat. [inventoryProductId] ist nur gesetzt, wenn die Zutat eindeutig zu einem Produkt des Haushalts
/// passt, das die App vorab mitgeschickt hat.
class AnalyzedIngredient {
  const AnalyzedIngredient({
    required this.name,
    this.inventoryProductId,
    this.estimatedGrams,
    this.confidence = 0,
    this.kind = 'food',
    this.state,
    this.match,
    this.unit,
  });

  final String name;
  final String? inventoryProductId;

  /// Geschaetzte Menge in Gramm fuer das ganze Gericht, `null` = nicht schaetzbar.
  final double? estimatedGrams;

  /// 0 bis 1: Sicherheit des Modells bei dieser Zutat (erkannt UND Menge plausibel).
  final double confidence;

  /// `food` | `drink`. Getraenke fuehrt die App in ml.
  final String kind;

  /// `raw` | `cooked` | `ready_made`, `null` = nicht erkennbar. Die Menge gilt in diesem Zustand ("wie auf dem Teller").
  final String? state;

  /// Zugeordneter Eintrag der Lebensmitteldatenbank mit Naehrwerten, `null` = unbekannt (Phase N1).
  final FoodMatch? match;

  /// Bei Stueckware, deren Gewicht der Server kennt: "2 Stk a 59 g" (Phase N2). Dann ersetzt es die Gramm-Schaetzung.
  final AnalyzedUnit? unit;

  bool get isDrink => kind == 'drink';
}

class MealAnalysis {
  const MealAnalysis({this.dishTitle = '', this.mealType, this.servingsVisible, this.ingredients = const [], this.notes});

  final String dishTitle;

  /// `breakfast` | `lunch` | `dinner` | `snack` | `drink`, `null` wenn nicht erkennbar.
  final String? mealType;
  final double? servingsVisible;
  final List<AnalyzedIngredient> ingredients;
  final String? notes;

  /// Auf dem Foto war nichts Essbares zu erkennen (oder das Modell hat keine Zutat geliefert).
  bool get isEmpty => ingredients.isEmpty;
}

const _mealTypes = {'breakfast', 'lunch', 'dinner', 'snack', 'drink'};

/// Liest die Server-Antwort (`analysis`-Objekt). Alles Unlesbare wird zu "nicht bekannt".
MealAnalysis parseMealAnalysis(Object? json) {
  if (json is! Map) return const MealAnalysis();

  String? text(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
  double? positive(Object? v) => v is num && v.isFinite && v > 0 ? v.toDouble() : null;

  final ingredients = <AnalyzedIngredient>[];
  final raw = json['ingredients'];
  if (raw is List) {
    for (final item in raw) {
      if (item is! Map) continue;
      final name = text(item['name']);
      if (name == null) continue;
      final confidence = item['confidence'];
      final state = item['state'];
      ingredients.add(AnalyzedIngredient(
        name: name,
        inventoryProductId: text(item['inventory_product_id']),
        estimatedGrams: positive(item['est_amount_g']),
        confidence: confidence is num && confidence.isFinite ? confidence.toDouble().clamp(0.0, 1.0) : 0,
        kind: item['kind'] == 'drink' ? 'drink' : 'food',
        state: state is String && const {'raw', 'cooked', 'ready_made'}.contains(state) ? state : null,
        match: parseFoodMatch(item['match']),
        unit: parseAnalyzedUnit(item['unit']),
      ));
    }
  }
  final type = json['meal_type_guess'];
  return MealAnalysis(
    dishTitle: text(json['dish_title']) ?? '',
    mealType: type is String && _mealTypes.contains(type) ? type : null,
    servingsVisible: positive(json['servings_visible']),
    ingredients: ingredients,
    notes: text(json['notes']),
  );
}
