import '../../domain/nutrition/drink_mix.dart';
import '../../domain/nutrition/fluid_intake.dart';
import '../../domain/nutrition/ingredient_nutrition.dart';
import '../../domain/nutrition/micros.dart';
import '../../domain/nutrition/nutrient_scaling.dart';
import '../../domain/products/packaging.dart';
import '../local/database.dart';
import 'meal_repository.dart';

/// Traegt Getraenke ein (ADR-048): eine normale Mahlzeit vom Typ `drink` je Mischung. Kalorien, FEFO-Abzug, Bilanz, Sync und Bearbeiten kommen damit
/// von [MealRepository], und "Rueckgaengig" ist dessen `delete`, das auch den Bestand zurueckbucht.
class DrinkRepository {
  DrinkRepository(this._meals);

  final MealRepository _meals;

  /// Bucht die Mischung. Vom Bestand geht nur ab, was dort liegt ([inStock], Q-32); alles andere zaehlt nur fuer die Naehrwerte.
  Future<Meal> book(DrinkDraft drink, {required DateTime at, required Set<String> inStock}) => _meals.create(MealDraft(
        title: drink.title.trim(),
        eatenAt: at,
        mealType: 'drink',
        ingredients: [
          for (final p in drink.parts)
            IngredientDraft(
              productId: p.productId,
              freeText: p.productId == null ? p.name : null,
              quantity: p.amount,
              entryUnit: p.unit,
              per100: p.productId == null ? p.per100 : null,
              per100Basis: p.productId == null && p.per100 != null ? 'g' : null,
              manualNutrients: p.manual,
              blsCode: p.productId == null ? p.blsCode : null,
              nutrientBasis: p.manual != null ? 'manual' : (p.productId == null ? p.nutrientBasis : null),
              microsPer100: p.productId == null ? p.microsPer100 : null,
              unitWeightG: p.unit == EntryUnit.piece ? p.unitWeightG : null,
              deduct: p.productId != null && inStock.contains(p.productId),
            ),
        ],
      ));

  /// Nimmt einen Eintrag zurueck, samt Abzug vom Bestand.
  Future<void> undo(String mealId) => _meals.delete(mealId);
}

/// Wie viel eine Getraenke-Mahlzeit in ml ist. Bearbeitete Eintraege koennen Portionen haben, deshalb der gegessene Anteil.
double drinkMealMl(Meal meal, Iterable<MealIngredient> ingredients) {
  final ml = ingredients.where((i) => i.deletedAt == null).fold<double>(0, (sum, i) => sum + drinkIngredientMl(unit: i.unit, quantity: i.quantity, amountG: i.amountG));
  return meal.servingsMade > 0 ? ml * meal.servingsEaten / meal.servingsMade : ml;
}

/// Der erste Eintrag eines Produkts: bei einer Mehrfachpackung ein Stueck (65 ml Yakult), sonst ein Glas, bei Stueckware eines mit bekanntem Volumen.
/// `null`, wenn sich das Volumen nicht kennen laesst: Dann muss der Nutzer es einmal angeben.
DrinkDraft? drinkFromProduct(Product p) {
  final packaging = Packaging(baseUnit: p.baseUnit, rawPackSize: p.packSize, rawPiecesPerPack: p.piecesPerPack, pieceLabel: p.pieceLabel);
  final double? ml = switch (p.baseUnit) {
    'piece' => p.unitWeightG,
    _ when packaging.isMultipack && packaging.contentPerPiece != null => (packaging.contentPerPiece! * 1000).roundToDouble(),
    _ => drinkGlassMl,
  };
  if (ml == null || ml <= 0) return null;
  return DrinkDraft(title: p.name, parts: [DrinkPart(name: p.name, amount: ml, productId: p.id)]);
}

/// Die Mischung eines frueheren Eintrags. Ein geloeschtes Produkt bleibt als Freitext mit seinem Snapshot erhalten, wie im Mahlzeit-Formular.
DrinkDraft drinkFromMeal(Meal meal, List<MealIngredient> ingredients, Map<String, Product> products) => DrinkDraft(
      title: meal.title,
      parts: [
        for (final i in ingredients)
          if (i.deletedAt == null) _partFrom(i, products[i.productId]),
      ],
    );

DrinkPart _partFrom(MealIngredient i, Product? product) {
  final (amount, unit) = switch (i.unit) {
    'l' => ((i.quantity * 1000).roundToDouble(), EntryUnit.ml),
    'kg' => ((i.quantity * 1000).roundToDouble(), EntryUnit.g),
    _ => (i.quantity, EntryUnit.piece),
  };
  final weight = unit == EntryUnit.piece && i.amountG != null && i.quantity > 0 ? i.amountG! / i.quantity : null;
  if (product != null && product.deletedAt == null) {
    return DrinkPart(name: product.name, amount: amount, unit: unit, productId: product.id, unitWeightG: weight);
  }
  final basis = i.amountG;
  final hasBasis = basis != null && basis > 0;
  double? per(double? v) => v == null || !hasBasis ? null : v * 100 / basis;
  final absolute = [i.kcal, i.proteinG, i.fatG, i.carbsG, i.sugarG, i.fiberG, i.saltG].any((v) => v != null);
  return DrinkPart(
    name: i.freeText ?? product?.name ?? 'Getränk',
    amount: amount,
    unit: unit,
    blsCode: i.blsCode,
    nutrientBasis: i.nutrientBasis,
    unitWeightG: weight,
    microsPer100: micros100From(parseMicros(i.micros), i.amountG),
    per100: hasBasis
        ? NutrientsPer100(kcal: per(i.kcal), proteinG: per(i.proteinG), fatG: per(i.fatG), carbsG: per(i.carbsG), sugarG: per(i.sugarG), fiberG: per(i.fiberG), saltG: per(i.saltG))
        : null,
    manual: !hasBasis && absolute
        ? NutrientAmounts(kcal: i.kcal, proteinG: i.proteinG, fatG: i.fatG, carbsG: i.carbsG, sugarG: i.sugarG, fiberG: i.fiberG, saltG: i.saltG)
        : null,
  );
}
