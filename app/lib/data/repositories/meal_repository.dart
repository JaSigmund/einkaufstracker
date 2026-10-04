import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/nutrition/ingredient_nutrition.dart';
import '../../domain/nutrition/micros.dart';
import '../../domain/nutrition/nutrient_scaling.dart';
import '../../domain/nutrition/retention.dart';
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

/// Menge einer gespeicherten Zutat in g (oder ml), wie sie fuer Schaetzungen gilt: der Snapshot, sonst bei kg und l die erfasste
/// Menge. Stueckmengen ohne Gewicht haben keine bekannte Menge.
double? ingredientGrams(MealIngredient i) {
  if (i.amountG != null && i.amountG! > 0) return i.amountG;
  return switch (i.unit) {
    'kg' || 'l' => i.quantity > 0 ? i.quantity * 1000 : null,
    _ => null,
  };
}

/// Mikronaehrstoffe je 100 g aus dem Profil eines Produkts (`nutrients_per_100`, Phase N3), `null` ohne.
Micros? productMicros(Product p) => parseMicros(p.nutrientsPer100);

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
    this.blsCode,
    this.nutrientBasis,
    this.unitWeightG,
    this.microsPer100,
    this.preparation,
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

  /// BLS-Eintrag, aus dem [per100] stammt (Phase N1), und wie sicher die Zuordnung ist (`bls_exact`, `bls_matched`, ...).
  /// Ohne Angabe von [nutrientBasis] leitet das Repository sie ab (Produktprofil: `product`, Handwerte: `manual`).
  final String? blsCode;
  final String? nutrientBasis;

  /// Gewicht einer Einheit ("1 Stk", "1 Scheibe", "1 EL") in g, wenn die Menge in [entryUnit] = Stueck erfasst ist und das
  /// Produkt kein eigenes Gewicht hat (Phase N2). Es geht dem Gewicht des Produkts vor, weil die Oberflaeche die Kette
  /// Haushalt > Produkt > Tabelle schon aufgeloest hat.
  final double? unitWeightG;

  /// Mikronaehrstoffe je 100 g des zugeordneten BLS-Eintrags (Phase N3). Bei einem Produkt mit eigenem Profil gilt dessen Profil.
  final Micros? microsPer100;

  /// Zubereitung fuer die Garfaktoren (Phase N4, ADR-037), `kategorie:zubereitung` wie in [RetentionFactors.storageKey]. Die Mikronaehrstoffe
  /// der Zeile werden dann um die Verluste gemindert; [microsPer100] bleibt das rohe Profil. Nur mit einem BLS-Profil ohne Produkt
  /// sinnvoll; bei einem unbekannten Wert wird nichts gemindert und nichts gespeichert.
  final String? preparation;
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

  /// Die letzten [limit] Mahlzeiten samt Zutaten, juengste zuerst (Grundlage fuer "Fehlt etwas?"). [excludeMealId] laesst die
  /// Mahlzeit aus, die gerade bearbeitet wird.
  Future<List<(Meal, List<MealIngredient>)>> recentHistory({int limit = 80, String? excludeMealId}) async {
    final recent = await (_db.select(_db.meals)
          ..where((m) => m.deletedAt.isNull())
          ..orderBy([(m) => OrderingTerm.desc(m.eatenAt)])
          ..limit(limit + (excludeMealId == null ? 0 : 1)))
        .get();
    final meals = [for (final m in recent) if (m.id != excludeMealId) m].take(limit).toList();
    if (meals.isEmpty) return const [];
    final ings = await (_db.select(_db.mealIngredients)
          ..where((i) => i.mealId.isIn([for (final m in meals) m.id]) & i.deletedAt.isNull())
          ..orderBy([(i) => OrderingTerm.asc(i.updatedAt)]))
        .get();
    final byMeal = <String, List<MealIngredient>>{};
    for (final i in ings) {
      byMeal.putIfAbsent(i.mealId, () => []).add(i);
    }
    return [for (final m in meals) (m, byMeal[m.id] ?? const <MealIngredient>[])];
  }

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

  /// Setzt den Mikronaehrstoff-Snapshot von Zutaten, die noch keinen haben (Nachrechnen aelterer Mahlzeiten, Phase N4). Ueberschreibt nie
  /// einen vorhandenen Snapshot und aendert weder Menge noch Makros. Liefert die Zahl der ergaenzten Zutaten.
  Future<int> applyMicros(Map<String, Micros> byIngredientId) async {
    if (byIngredientId.isEmpty) return 0;
    var changed = 0;
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      for (final e in byIngredientId.entries) {
        final row = await (_db.select(_db.mealIngredients)..where((i) => i.id.equals(e.key))).getSingleOrNull();
        final encoded = encodeMicros(e.value);
        if (row == null || row.deletedAt != null || row.micros != null || encoded == null) continue;
        final updated = row.copyWith(micros: Value(encoded), updatedAt: now);
        await _put('meal_ingredients', row.id, mealIngredientToRemote(updated),
            () => _db.into(_db.mealIngredients).insertOnConflictUpdate(updated.toCompanion(false)));
        changed++;
      }
    });
    if (changed > 0) onChanged?.call();
    return changed;
  }

  Future<void> _writeIngredients(Meal meal, List<IngredientDraft> drafts) async {
    final hid = meal.householdId;
    for (final d in drafts) {
      final product = d.productId == null
          ? null
          : await (_db.select(_db.products)..where((p) => p.id.equals(d.productId!))).getSingleOrNull();
      // Ein Produkt mit eigenen Naehrwerten gilt zuerst; hat es keine (35 von 39 Produkten vom Bon), springt das Profil des
      // zugeordneten BLS-Eintrags ein (Phase N1), das die Zeile mitbringt.
      final productProfile = product == null ? null : productNutrientProfile(product);
      final per100 = productProfile ?? d.per100;
      final basis = productProfile != null ? product!.nutrientsBasis : (per100 == null ? null : d.per100Basis);
      final String? nutrientBasis = d.nutrientBasis ??
          (productProfile != null ? 'product' : (d.manualNutrients != null ? 'manual' : (per100 != null && d.blsCode != null ? 'bls_exact' : null)));
      // Mikronaehrstoffe wie die Makros: das Profil des Produkts zuerst, sonst das der Zeile (BLS), nur mit bekannter Menge in g/ml
      final microsPer100 = productProfile != null ? productMicros(product!) : d.microsPer100;
      final amount = resolveIngredientAmount(
        quantity: d.quantity,
        entryUnit: d.entryUnit,
        baseUnit: product?.baseUnit ?? d.entryUnit.dimensionBaseUnit,
        nutrientsBasis: basis,
        unitWeightG: d.unitWeightG ?? product?.unitWeightG,
      );
      final nutrients = d.manualNutrients ?? ingredientNutrients(per100, amount);
      // Garfaktoren: nur fuer ein BLS-Profil der Zeile (kein Produkt, keine Handwerte) und nur mit bekannter Kategorie und Zubereitung
      final retention = (productProfile == null && d.manualNutrients == null) ? retentionFromStorage(d.preparation) : null;
      final micros = d.manualNutrients != null ? null : applyRetention(scaleMicros(microsPer100, amount.nutrientBasisAmount), retention);

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
        blsCode: productProfile != null || d.manualNutrients != null ? null : d.blsCode,
        nutrientBasis: nutrientBasis,
        micros: encodeMicros(micros),
        preparation: retention?.storageKey,
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
