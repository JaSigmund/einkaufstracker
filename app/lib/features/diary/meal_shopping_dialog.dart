import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../domain/nutrition/food_unit.dart';
import '../../domain/nutrition/ingredient_nutrition.dart';
import '../../domain/nutrition/meal_shortage.dart';

/// Menge einer gespeicherten Zutat in der Basiseinheit des Produkts, `null`, wenn sie sich nicht umrechnen laesst (Stueck ohne Gewicht).
double? neededInBaseUnit(MealIngredient i, Product p) {
  // Bei Stueckmengen steckt das Gewicht einer Einheit im Snapshot (Menge in g durch Anzahl), sonst gilt das Gewicht am Produkt
  final weight = i.unit == 'piece' && i.amountG != null && i.quantity > 0 ? i.amountG! / i.quantity : null;
  return resolveIngredientAmount(
    quantity: i.quantity,
    entryUnit: EntryUnit.fromDb(i.unit),
    baseUnit: p.baseUnit,
    unitWeightG: weight,
    productPieceWeightG: p.unitWeightG,
    unitKey: FoodUnitKey.fromDb(i.unitKey),
  ).inventoryQuantity;
}

/// "Fehlende Zutaten auf die Einkaufsliste" zu einer erfassten Mahlzeit: prueft die Zutaten gegen den Bestand und die Liste, laesst
/// auswaehlen und setzt die Auswahl auf die Einkaufsliste. Liefert die Zahl der neu angelegten Eintraege (`null` bei Abbruch).
Future<int?> showMealShoppingDialog(BuildContext context, Meal meal, List<MealIngredient> ingredients) async {
  final container = ProviderScope.containerOf(context);
  final products = {for (final p in await container.read(productRepositoryProvider).allSnapshot()) p.id: p};
  final stock = <String, double>{};
  for (final i in await container.read(inventoryRepositoryProvider).activeSnapshot()) {
    stock.update(i.productId, (v) => v + i.quantity, ifAbsent: () => i.quantity);
  }
  final shopping = container.read(shoppingListRepositoryProvider);
  final open = await shopping.openItems();

  final inputs = <ShortageInput>[];
  for (final i in ingredients) {
    final p = i.productId == null ? null : products[i.productId];
    if (p != null) {
      inputs.add((productId: p.id, name: p.name, needed: neededInBaseUnit(i, p), baseUnit: p.baseUnit));
    } else {
      final name = i.freeText;
      if (name != null && name.trim().isNotEmpty) inputs.add((productId: null, name: name, needed: null, baseUnit: null));
    }
  }
  final candidates = findMealShortages(
    inputs,
    stock: stock,
    listedProductIds: {for (final i in open) if (i.productId != null) i.productId!},
    listedTexts: {for (final i in open) if (i.freeText != null) i.freeText!},
  );
  if (!context.mounted) return null;

  final selected = {for (var n = 0; n < candidates.length; n++) if (candidates[n].preselected) n};
  final result = await showDialog<Set<int>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final t = Theme.of(ctx);
        return AlertDialog(
          key: const Key('meal-shopping-dialog'),
          title: const Text('Fehlende Zutaten'),
          content: SizedBox(
            width: double.maxFinite,
            child: candidates.isEmpty
                ? Text(
                    ingredients.isEmpty ? 'Diese Mahlzeit hat keine Zutaten.' : 'Alles da: der Bestand deckt die Zutaten von „${meal.title}“.',
                    key: const Key('meal-shopping-empty'),
                  )
                : ListView(shrinkWrap: true, children: [
                    Text('Für „${meal.title}“. Vorausgewählt ist, was im Bestand fehlt.', style: t.textTheme.bodySmall),
                    for (var n = 0; n < candidates.length; n++)
                      CheckboxListTile(
                        key: Key('meal-shopping-item-$n'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: selected.contains(n),
                        onChanged: candidates[n].alreadyOnList ? null : (v) => setState(() => v == true ? selected.add(n) : selected.remove(n)),
                        title: Text(candidates[n].name),
                        subtitle: Text(_reason(candidates[n])),
                      ),
                  ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(candidates.isEmpty ? 'Schließen' : 'Abbrechen')),
            if (candidates.isNotEmpty)
              FilledButton(
                key: const Key('meal-shopping-add'),
                onPressed: selected.isEmpty ? null : () => Navigator.pop(ctx, selected),
                child: Text(selected.length == 1 ? '1 auf die Liste' : '${selected.length} auf die Liste'),
              ),
          ],
        );
      },
    ),
  );
  if (result == null) return null;
  final added = await shopping.addMany([
    for (final n in result.toList()..sort())
      (productId: candidates[n].productId, freeText: candidates[n].productId == null ? candidates[n].name : null, unit: candidates[n].baseUnit ?? 'piece'),
  ]);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(added == 0 ? 'Alles stand schon auf der Einkaufsliste.' : (added == 1 ? '1 Eintrag auf der Einkaufsliste' : '$added Einträge auf der Einkaufsliste')),
    ));
  }
  return added;
}

String _reason(ShoppingCandidate c) {
  if (c.alreadyOnList) return 'steht schon auf der Liste';
  final unit = switch (c.baseUnit) { 'kg' => 'kg', 'l' => 'l', _ => 'Stk' };
  return switch (c.kind) {
    ShortageKind.missing => 'nicht im Bestand',
    ShortageKind.insufficient => 'Bestand ${formatQuantity(c.available ?? 0)} $unit, gebraucht ${formatQuantity(c.needed ?? 0)} $unit',
    ShortageKind.unchecked => 'ohne Bestandsprüfung (kein Produkt)',
  };
}
