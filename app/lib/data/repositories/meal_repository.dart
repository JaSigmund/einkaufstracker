import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/nutrition/ingredient_nutrition.dart';
import '../../domain/nutrition/nutrient_scaling.dart';
import '../local/database.dart';
import '../sync/mappers.dart';
import 'inventory_repository.dart';

/// Naehrwertprofil je 100 g/ml eines Produkts (`products.nutrients_per_100`, JSON), `null` ohne oder mit unlesbarem
/// Profil. Gemeinsam fuer die Berechnung beim Speichern und die Vorschau im Formular.
NutrientsPer100? productNutrientProfile(Product p) {
  final raw = p.nutrientsPer100;
  if (raw == null || raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? NutrientsPer100.fromMap(decoded) : null;
  } on FormatException {
    return null;
  }
}

/// Eine Zutat, wie der Nutzer sie erfasst (Doku 15 §3.1): entweder ein Produkt aus dem Haushalt (Naehrwerte und
/// Stueckgewicht stehen am Produkt, der Bestand wird abgezogen) oder ein Freitext, etwa ein Treffer aus dem
/// Bundeslebensmittelschluessel mit eigenem Naehrwertprofil (kein Abzug, Doku 15 §3.4).
class IngredientDraft {
  const IngredientDraft({
    this.productId,
    this.freeText,
    required this.quantity,
    required this.entryUnit,
    this.source,
    this.per100,
    this.per100Basis,
    this.manualNutrients,
    this.deduct = true,
    this.confidence,
  }) : assert(productId != null || freeText != null, 'Eine Zutat braucht ein Produkt oder einen Text');

  final String? productId;
  final String? freeText;
  final double quantity;
  final EntryUnit entryUnit;

  /// `inventory` | `photo_ai` | `recipe` | `manual` | `estimate`. Ohne Angabe: `inventory` bei einem Produkt, dessen
  /// Bestand abgezogen wird, sonst `manual`.
  final String? source;

  /// Naehrwertprofil fuer Freitext-Zutaten (z.B. BLS), je 100 g oder 100 ml laut [per100Basis]. Bei Produkt-Zutaten
  /// wird stattdessen das Profil des Produkts gelesen.
  final NutrientsPer100? per100;
  final String? per100Basis;

  /// Absolute Naehrwerte der ganzen Zutatenmenge, etwa fuer Restaurantessen mit Handeingabe (Doku 15 §3.3). Hat
  /// Vorrang vor jeder Berechnung.
  final NutrientAmounts? manualNutrients;

  /// Bestand abziehen? Nur bei einem Produkt sinnvoll; `false` z.B. fuer Restaurantessen oder Reste.
  final bool deduct;
  final double? confidence;
}

/// Eine Mahlzeit samt Zutaten, wie sie gespeichert werden soll.
class MealDraft {
  const MealDraft({
    required this.title,
    required this.eatenAt,
    this.mealType = 'lunch',
    this.note,
    this.servingsEaten = 1,
    this.servingsMade = 1,
    this.isEstimate = false,
    this.source = 'manual',
    this.recipeId,
    this.photoPath,
    this.ingredients = const [],
  });

  final String title;
  final DateTime eatenAt;
  final String mealType;
  final String? note;
  final double servingsEaten;
  final double servingsMade;
  final bool isEstimate;
  final String source;
  final String? recipeId;
  final String? photoPath;
  final List<IngredientDraft> ingredients;
}

/// Essenstagebuch (Doku 15): Mahlzeiten mit Zutaten, Naehrwert-Snapshot und Inventarabzug. Jede Aenderung laeuft
/// in einer Transaktion und schreibt in der Reihenfolge Mahlzeit, Zutaten, Bestand, Ledger, denn so landen die
/// Outbox-Eintraege beim Sync in einer Reihenfolge, die den Fremdschluesseln auf dem Server genuegt.
class MealRepository {
  MealRepository(this._db, {required this.householdId, required this.inventory, this.onChanged, Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Future<String> Function() householdId;
  final InventoryRepository inventory;
  final void Function()? onChanged;
  final Uuid _uuid;

  /// Nicht geloeschte Mahlzeiten, neueste zuerst.
  Stream<List<Meal>> watchMeals() => (_db.select(_db.meals)
        ..where((m) => m.deletedAt.isNull())
        ..orderBy([(m) => OrderingTerm.desc(m.eatenAt)]))
      .watch();

  /// Alle nicht geloeschten Zutaten (Grundlage der Tages- und Wochenwerte, die rein clientseitig berechnet werden).
  Stream<List<MealIngredient>> watchIngredients() =>
      (_db.select(_db.mealIngredients)..where((i) => i.deletedAt.isNull())).watch();

  Future<Meal?> get(String id) => (_db.select(_db.meals)..where((m) => m.id.equals(id))).getSingleOrNull();

  Future<List<MealIngredient>> ingredientsOf(String mealId) => (_db.select(_db.mealIngredients)
        ..where((i) => i.mealId.equals(mealId) & i.deletedAt.isNull())
        ..orderBy([(i) => OrderingTerm.asc(i.updatedAt)]))
      .get();

  Future<Meal> create(MealDraft draft) async {
    _validate(draft);
    final hid = await householdId();
    final now = DateTime.now().toUtc();
    final meal = Meal(
      id: _uuid.v4(),
      householdId: hid,
      eatenAt: draft.eatenAt.toUtc(),
      mealType: draft.mealType,
      title: draft.title.trim(),
      note: _blankToNull(draft.note),
      photoPath: draft.photoPath,
      recipeId: draft.recipeId,
      servingsEaten: draft.servingsEaten,
      servingsMade: draft.servingsMade,
      source: draft.source,
      isEstimate: draft.isEstimate,
      updatedAt: now,
    );
    await _db.transaction(() async {
      await _putMeal(meal);
      await _writeIngredients(meal, draft.ingredients);
    });
    onChanged?.call();
    return meal;
  }

  /// Ersetzt Kopfdaten und Zutaten einer Mahlzeit. Der alte Abzug wird per Gegenbuchung zurueckgenommen und der neue
  /// frisch berechnet (FR-12): das Ledger zeigt beide Schritte, nichts wird ueberschrieben.
  Future<Meal> update(String mealId, MealDraft draft) async {
    _validate(draft);
    final existing = await get(mealId);
    if (existing == null || existing.deletedAt != null) throw StateError('Mahlzeit nicht gefunden');
    final now = DateTime.now().toUtc();
    final meal = existing.copyWith(
      eatenAt: draft.eatenAt.toUtc(),
      mealType: draft.mealType,
      title: draft.title.trim(),
      note: Value(_blankToNull(draft.note)),
      photoPath: Value(draft.photoPath ?? existing.photoPath),
      recipeId: Value(draft.recipeId ?? existing.recipeId),
      servingsEaten: draft.servingsEaten,
      servingsMade: draft.servingsMade,
      source: draft.source,
      isEstimate: draft.isEstimate,
      updatedAt: now,
    );
    await _db.transaction(() async {
      await inventory.restoreForMeal(mealId);
      await _softDeleteIngredients(mealId, now);
      await _putMeal(meal);
      await _writeIngredients(meal, draft.ingredients);
    });
    onChanged?.call();
    return meal;
  }

  /// Loescht eine Mahlzeit (Soft-Delete) und stellt den Bestand ueber Gegenbuchungen wieder her (LH-MEAL-04).
  Future<void> delete(String mealId) async {
    final existing = await get(mealId);
    if (existing == null || existing.deletedAt != null) return;
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      await inventory.restoreForMeal(mealId);
      await _softDeleteIngredients(mealId, now);
      await _putMeal(existing.copyWith(deletedAt: Value(now), updatedAt: now));
    });
    onChanged?.call();
  }

  /// Setzt oder entfernt den Storage-Pfad des Fotos (`{household_id}/{meal_id}.jpg`). Eigene Methode statt ueber
  /// [update], weil ein Foto auch nachtraeglich dazukommt oder wegfaellt, ohne dass Zutaten neu gerechnet oder
  /// Bestaende zurueck- und neu gebucht werden duerfen.
  Future<void> setPhotoPath(String mealId, String? path) async {
    final existing = await get(mealId);
    if (existing == null || existing.deletedAt != null || existing.photoPath == path) return;
    await _putMeal(existing.copyWith(photoPath: Value(path), updatedAt: DateTime.now().toUtc()));
    onChanged?.call();
  }

  Future<void> _writeIngredients(Meal meal, List<IngredientDraft> drafts) async {
    final hid = meal.householdId;
    for (final d in drafts) {
      final product = d.productId == null
          ? null
          : await (_db.select(_db.products)..where((p) => p.id.equals(d.productId!))).getSingleOrNull();
      final per100 = product != null ? productNutrientProfile(product) : d.per100;
      final basis = product != null ? (per100 == null ? null : product.nutrientsBasis) : (per100 == null ? null : d.per100Basis);
      final amount = resolveIngredientAmount(
        quantity: d.quantity,
        entryUnit: d.entryUnit,
        baseUnit: product?.baseUnit ?? d.entryUnit.dimensionBaseUnit,
        nutrientsBasis: basis,
        unitWeightG: product?.unitWeightG,
      );
      final nutrients = d.manualNutrients ?? ingredientNutrients(per100, amount);

      String? inventoryItemId;
      var deducted = false;
      if (product != null && d.deduct && amount.inventoryQuantity != null) {
        final result = await inventory.deductForMeal(
          mealId: meal.id,
          productId: product.id,
          quantity: amount.inventoryQuantity!,
          unit: product.baseUnit,
          eatenAt: meal.eatenAt,
          openedShelfLifeDays: product.openedShelfLifeDays,
        );
        inventoryItemId = result.firstItemId;
        deducted = result.allocations.isNotEmpty;
      }

      final row = MealIngredient(
        id: _uuid.v4(),
        householdId: hid,
        mealId: meal.id,
        productId: product?.id,
        inventoryItemId: inventoryItemId,
        freeText: _blankToNull(d.freeText),
        quantity: amount.quantity,
        unit: amount.unit,
        amountG: amount.nutrientBasisAmount,
        source: d.source ?? (deducted ? 'inventory' : 'manual'),
        confidence: d.confidence,
        kcal: nutrients?.kcal,
        proteinG: nutrients?.proteinG,
        fatG: nutrients?.fatG,
        carbsG: nutrients?.carbsG,
        sugarG: nutrients?.sugarG,
        fiberG: nutrients?.fiberG,
        saltG: nutrients?.saltG,
        updatedAt: DateTime.now().toUtc(),
      );
      await _put('meal_ingredients', row.id, mealIngredientToRemote(row),
          () => _db.into(_db.mealIngredients).insertOnConflictUpdate(row.toCompanion(false)));
    }
  }

  Future<void> _softDeleteIngredients(String mealId, DateTime now) async {
    final rows = await (_db.select(_db.mealIngredients)..where((i) => i.mealId.equals(mealId) & i.deletedAt.isNull())).get();
    for (final r in rows) {
      final deleted = r.copyWith(deletedAt: Value(now), updatedAt: now);
      await _put('meal_ingredients', r.id, mealIngredientToRemote(deleted),
          () => _db.into(_db.mealIngredients).insertOnConflictUpdate(deleted.toCompanion(false)));
    }
  }

  Future<void> _putMeal(Meal m) =>
      _put('meals', m.id, mealToRemote(m), () => _db.into(_db.meals).insertOnConflictUpdate(m.toCompanion(false)));

  void _validate(MealDraft d) {
    if (d.title.trim().isEmpty) throw ArgumentError('Titel darf nicht leer sein');
    if (d.servingsEaten <= 0 || d.servingsMade <= 0) throw ArgumentError('Portionen muessen groesser als 0 sein');
    for (final i in d.ingredients) {
      if (i.quantity < 0) throw ArgumentError('Menge darf nicht negativ sein');
    }
  }

  String? _blankToNull(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

  Future<void> _put(String remoteTable, String rowId, Map<String, dynamic> payload, Future<void> Function() writeLocal) async {
    await writeLocal();
    await _db.into(_db.outbox).insert(OutboxCompanion.insert(
          remoteTable: remoteTable,
          rowId: rowId,
          payload: jsonEncode(payload),
          createdAt: DateTime.now().toUtc(),
        ));
  }
}
