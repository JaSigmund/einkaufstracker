import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/clock.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../data/repositories/drink_repository.dart';
import '../../domain/nutrition/drink_mix.dart';
import '../../domain/products/drinkable.dart';
import '../products/product_form_page.dart';
import 'drink_sheet.dart';
import 'ingredient_picker.dart';

/// Getraenke unter "Schnell eintragen" (ADR-048): Der Plus-Knopf bucht, was in dieser Zeile zuletzt getrunken wurde, ein Tipp auf die Zeile oeffnet
/// Menge und Mischverhaeltnis.
class DrinksSection extends ConsumerWidget {
  const DrinksSection({super.key, this.now});

  /// Aktueller Zeitpunkt (UTC), austauschbar fuer Tests.
  final DateTime? now;

  DateTime get _at => now ?? appClock.now().toUtc();

  Future<void> _book(BuildContext context, WidgetRef ref, DrinkDraft drink, Set<String> inStock) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(drinkRepositoryProvider);
    try {
      final meal = await repo.book(drink, at: _at, inStock: inStock);
      final missing = drink.parts.any((p) => p.productId != null && !inStock.contains(p.productId));
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('${drink.title}: ${formatQuantity(drink.totalMl)} ml eingetragen${missing ? ' · nicht im Bestand' : ''}'),
          // mit Aktion bliebe die SnackBar sonst stehen, bis man sie wegwischt
          persist: false,
          action: SnackBarAction(label: 'Rückgängig', onPressed: () => repo.undo(meal.id)),
        ));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Eintragen nicht möglich.')));
    }
  }

  /// Oeffnet Menge und Mischverhaeltnis und bucht das Ergebnis. Ein neues Stueckvolumen merkt sich das Produkt.
  Future<void> _edit(BuildContext context, WidgetRef ref, DrinkDraft drink, Map<String, Product> products, Set<String> inStock, {Product? unknownPiece}) async {
    final result = await showDrinkSheet(context, drink: drink, unknownPiece: unknownPiece, products: products);
    if (result == null || !context.mounted) return;
    final piece = result.pieceMl;
    if (unknownPiece != null && piece != null) {
      await ref.read(productRepositoryProvider).setUnitWeight(unknownPiece.id, piece);
    }
    if (context.mounted) await _book(context, ref, result.drink, inStock);
  }

  /// Ein Produkt: mit bekanntem Volumen gleich vorbelegt, sonst fragt das Fenster danach.
  Future<void> _editProduct(BuildContext context, WidgetRef ref, Product p, Map<String, Product> products, Set<String> inStock) {
    final known = drinkFromProduct(p);
    return _edit(
      context,
      ref,
      known ?? DrinkDraft(title: p.name, parts: [DrinkPart(name: p.name, amount: 0, productId: p.id)]),
      products,
      inStock,
      unknownPiece: known == null ? p : null,
    );
  }

  /// "Anderes Getraenk": Suche ueber Produkte und Lebensmitteldatenbank.
  Future<void> _other(BuildContext context, WidgetRef ref, Map<String, Product> products, Set<String> inStock) async {
    final picked = await showIngredientPicker(context);
    if (picked == null || !context.mounted) return;
    if (picked.product != null) return _editProduct(context, ref, picked.product!, products, inStock);
    final part = drinkPartFromPicked(picked);
    await _edit(context, ref, DrinkDraft(title: part.name, parts: [part]), products, inStock);
  }

  /// Barcode: ein bekanntes Produkt direkt, ein unbekanntes erst anlegen. Wer unter Getraenke scannt, meint ein Getraenk, deshalb wird es als trinkbar markiert.
  Future<void> _scan(BuildContext context, WidgetRef ref, Map<String, Product> products, Set<String> inStock, bool Function(Product) drinkable) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(productRepositoryProvider);
    try {
      final ean = await ref.read(barcodeScannerProvider).scan(context);
      if (ean == null || !context.mounted) return;
      final result = await repo.lookup(ean);
      if (!context.mounted) return;
      Product? product = result.product;
      if (!result.isKnown) {
        final created = await context.push('/product-form', extra: ProductFormArgs(ean: ean, suggestion: result.offSuggestion));
        product = created is Product ? created : null;
      }
      if (product == null || !context.mounted) return;
      if (!drinkable(product)) {
        await repo.setIsDrink(product.id, true);
      }
      if (context.mounted) await _editProduct(context, ref, product, products, inStock);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Barcode-Scan nicht möglich: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    // ref.watch, nicht read: haelt die Streams abonniert, damit ihr Wert schon beim ersten Tippen bereitsteht
    final meals = ref.watch(mealsStreamProvider).value ?? const <Meal>[];
    final ingredients = ref.watch(mealIngredientsStreamProvider).value ?? const <MealIngredient>[];
    final products = {for (final p in ref.watch(productsStreamProvider).value ?? const <Product>[]) p.id: p};
    final active = ref.watch(activeInventoryStreamProvider).value ?? const <InventoryItem>[];
    final categories = {for (final c in ref.watch(categoriesStreamProvider).value ?? const <Category>[]) c.id: c.name};

    final inStock = {for (final i in active) if (i.quantity > 0) i.productId};
    bool drinkable(Product p) => isDrinkable(flag: p.isDrink, name: p.name, baseUnit: p.baseUnit, packSize: p.packSize, categoryName: categories[p.categoryId]);

    final drinkMeals = [for (final m in meals) if (m.mealType == 'drink' && m.deletedAt == null) m];
    final mealsById = {for (final m in drinkMeals) m.id: m};
    final byMeal = <String, List<MealIngredient>>{};
    for (final i in ingredients) {
      if (i.deletedAt == null && mealsById.containsKey(i.mealId)) (byMeal[i.mealId] ??= []).add(i);
    }
    final rows = rankDrinkRows(
      drinkMeals: [for (final m in drinkMeals) (id: m.id, title: m.title, eatenAtUtc: m.eatenAt)],
      inStock: [for (final p in products.values) if (p.deletedAt == null && inStock.contains(p.id) && drinkable(p)) (id: p.id, name: p.name)],
      pureProductOf: (id) {
        final own = byMeal[id] ?? const <MealIngredient>[];
        return own.length == 1 ? own.single.productId : null;
      },
      now: _at,
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.only(top: 12, bottom: 4), child: Text('Getränke', style: t.textTheme.titleMedium)),
      for (final (i, row) in rows.indexed) _rowTile(context, ref, i, row, mealsById, byMeal, products, inStock),
      Wrap(spacing: 8, children: [
        TextButton.icon(
          key: const Key('drink-other'),
          onPressed: () => _other(context, ref, products, inStock),
          icon: const Icon(Icons.search),
          label: const Text('Anderes Getränk'),
        ),
        TextButton.icon(
          key: const Key('drink-scan'),
          onPressed: () => _scan(context, ref, products, inStock, drinkable),
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Scannen'),
        ),
      ]),
    ]);
  }

  Widget _rowTile(
    BuildContext context,
    WidgetRef ref,
    int i,
    DrinkRow row,
    Map<String, Meal> mealsById,
    Map<String, List<MealIngredient>> byMeal,
    Map<String, Product> products,
    Set<String> inStock,
  ) {
    final template = row.templateMealId == null ? null : mealsById[row.templateMealId];
    final product = row.productId == null ? null : products[row.productId];
    final drink = template != null ? drinkFromMeal(template, byMeal[template.id] ?? const [], products) : (product == null ? null : drinkFromProduct(product));
    return Card(
      key: Key('drink-row-$i'),
      child: ListTile(
        leading: const Icon(Icons.local_drink_outlined),
        title: Text(row.title),
        subtitle: Text(drink == null ? 'Menge beim ersten Mal angeben' : _describe(drink), key: Key('drink-row-info-$i')),
        onTap: () {
          if (drink != null) {
            _edit(context, ref, drink, products, inStock);
          } else if (product != null) {
            _editProduct(context, ref, product, products, inStock);
          }
        },
        trailing: FilledButton.tonal(
          key: Key('drink-take-$i'),
          onPressed: () {
            // Ohne bekanntes Volumen laesst sich nichts mit einem Tipp buchen
            if (drink != null && drink.isBookable) {
              _book(context, ref, drink, inStock);
            } else if (product != null) {
              _editProduct(context, ref, product, products, inStock);
            }
          },
          child: Text(drink == null ? 'Menge' : '+ ${formatQuantity(drink.totalMl)} ml'),
        ),
      ),
    );
  }

  /// "Saft 125 ml + Wasser 125 ml"; bei nur einem Teil steht die Menge schon im Knopf.
  static String _describe(DrinkDraft d) {
    if (d.parts.length == 1) return d.parts.single.productId == null ? 'Pur' : 'Pur · aus dem Inventar';
    return [for (final p in d.parts) '${p.name} ${formatQuantity(p.amount)} ${p.unit.label}'].join(' + ');
  }
}
