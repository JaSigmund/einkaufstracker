import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../domain/notifications/expiry_stages.dart';
import '../../domain/products/drinkable.dart';
import '../../domain/products/product_assignment.dart';
import '../../domain/receipt/price_history.dart';
import '../common/quantity_dialog.dart' show describeStock;
import '../inventory/inventory_item_detail_page.dart';
import '../report/online_price_section.dart';
import '../report/product_price_page.dart';
import '../settings/expiry_stages_dialog.dart';
import 'nutrient_assignment.dart';
import 'product_actions.dart';
import 'product_form_page.dart';

const _locationLabels = {'pantry': 'Vorrat', 'fridge': 'Kühlschrank', 'freezer': 'Tiefkühl', 'other': 'Sonstiges'};

/// Die Drehscheibe (Doku 27, ADR-050): alles, was zu einem Produkt gehoert, an einer Stelle. Das Formular kennt nur noch Stammdaten.
class ProductPage extends ConsumerWidget {
  const ProductPage({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productsStreamProvider).value;
    if (products == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final product = products.where((p) => p.id == productId).firstOrNull;
    if (product == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Dieses Produkt gibt es nicht mehr.', key: Key('product-not-found'))));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(product.name),
        actions: [
          IconButton(
            key: const Key('product-page-edit'),
            tooltip: 'Stammdaten bearbeiten',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.push('/product-form', extra: ProductFormArgs(existing: product)),
          ),
          PopupMenuButton<String>(
            key: const Key('product-page-menu'),
            onSelected: (v) async {
              if (v == 'merge') {
                await showProductMergeDialog(context, ref, product);
              } else if (await confirmDeleteProduct(context, ref, product) && context.mounted) {
                context.pop();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'merge', child: Text('Mit anderem Produkt zusammenführen')),
              PopupMenuItem(value: 'delete', child: Text('Löschen')),
            ],
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        _StockSection(product: product),
        _RecognitionSection(product: product),
        _NutrientsSection(product: product),
        _PriceSection(product: product),
        _ClassificationSection(product: product),
        _StorageSection(product: product),
      ]),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 4),
      child: Row(children: [
        Expanded(child: Text(text, style: t.textTheme.titleSmall?.copyWith(color: t.colorScheme.primary))),
        ?trailing,
      ]),
    );
  }
}

class _StockSection extends ConsumerWidget {
  const _StockSection({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = (ref.watch(activeInventoryStreamProvider).value ?? const <InventoryItem>[]).where((i) => i.productId == product.id).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Heading('Bestand'),
      if (items.isEmpty)
        const ListTile(key: Key('product-stock-empty'), dense: true, title: Text('Nicht im Bestand'))
      else
        for (final item in items)
          ListTile(
            key: Key('product-stock-${item.id}'),
            dense: true,
            title: Text(describeStock(item.quantity, item.unit, product)),
            subtitle: Text([_locationLabels[item.location] ?? item.location, if (item.status == 'opened') 'geöffnet'].join(' · ')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/inventory-item', extra: InventoryItemArgs(item: item, product: product)),
          ),
    ]);
  }
}

/// Erkennung: woran die App das Produkt erkennt. Barcodes verwalten kommt mit Etappe E3, hier stehen sie erst einmal.
class _RecognitionSection extends ConsumerWidget {
  const _RecognitionSection({required this.product});
  final Product product;

  Future<void> _removeAlias(BuildContext context, WidgetRef ref, ProductAlias alias) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zuordnung lösen?'),
        content: Text('„${alias.aliasText}“ wird beim nächsten Bon nicht mehr automatisch diesem Produkt zugeordnet.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lösen')),
        ],
      ),
    );
    if (ok == true) await ref.read(productRepositoryProvider).removeAlias(alias.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final muted = t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant);
    final barcodes = (ref.watch(allBarcodesStreamProvider).value ?? const <ProductBarcode>[]).where((b) => b.productId == product.id).toList();
    final aliases = ref.watch(productAliasesStreamProvider(product.id)).value ?? const <ProductAlias>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Heading('Erkennung'),
      Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 0), child: Text('Barcodes', style: t.textTheme.labelLarge)),
      if (barcodes.isEmpty)
        Padding(padding: const EdgeInsets.fromLTRB(16, 2, 16, 4), child: Text('Noch keiner', key: const Key('product-barcodes-empty'), style: muted))
      else
        for (final b in barcodes) ListTile(key: Key('product-barcode-${b.ean}'), dense: true, leading: const Icon(Icons.qr_code_2), title: Text(b.ean)),
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: Text('Bon-Texte', style: t.textTheme.labelLarge)),
      if (aliases.isEmpty)
        Padding(padding: const EdgeInsets.fromLTRB(16, 2, 16, 4), child: Text('Noch keiner', key: const Key('product-aliases-empty'), style: muted))
      else
        for (final a in aliases)
          ListTile(
            key: Key('alias-${a.id}'),
            dense: true,
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text(a.aliasText),
            trailing: IconButton(
              key: Key('alias-remove-${a.id}'),
              icon: const Icon(Icons.link_off),
              tooltip: 'Zuordnung lösen',
              onPressed: () => _removeAlias(context, ref, a),
            ),
          ),
    ]);
  }
}

class _NutrientsSection extends ConsumerWidget {
  const _NutrientsSection({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final n = nutrientsOf(product);
    final code = product.blsCode;
    final name = code == null ? null : ref.watch(blsNamesProvider(code)).value?[code];
    final prefs = ref.watch(householdPrefsProvider).value ?? const <String, Object?>{};
    final notNeeded = n == null && nutrientsNotNeeded(prefs, product.id);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Heading(
        'Nährwerte',
        trailing: TextButton(
          key: const Key('product-nutrients-change'),
          onPressed: () => changeNutrients(context, ref, product),
          child: Text(n == null ? 'Zuordnen' : 'Ändern'),
        ),
      ),
      if (n != null) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(name ?? nutrientSourceLabel(product.nutrientsSource), key: const Key('product-nutrients-name'), style: t.textTheme.bodyLarge),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
          child: Text(
            [
              if (n.kcal != null) formatKcal(n.kcal!),
              if (n.proteinG != null) '${formatQuantity(n.proteinG!)} g Eiweiß',
              if (n.fatG != null) '${formatQuantity(n.fatG!)} g Fett',
              if (n.carbsG != null) '${formatQuantity(n.carbsG!)} g Kohlenhydrate',
            ].join(' · '),
            key: const Key('product-nutrients-values'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
          child: Text(
            [
              'je 100 ${product.nutrientsBasis ?? 'g'}',
              if (name != null) nutrientSourceLabel(product.nutrientsSource),
              if (product.unitWeightG != null) '1 Stück = ${formatQuantity(product.unitWeightG!)} g',
            ].join(' · '),
            style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
          ),
        ),
      ] else if (notNeeded)
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Nicht nötig', key: Key('product-nutrients-not-needed')))
      else
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Noch keine', key: Key('product-nutrients-empty'))),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: notNeeded
            ? TextButton(
                key: const Key('product-nutrients-needed'),
                onPressed: () => ref.read(householdPrefsRepositoryProvider).setNutrientsNotNeeded(product.id, false),
                child: const Text('Zurücknehmen'),
              )
            : TextButton(
                key: const Key('product-nutrients-not-needed-action'),
                onPressed: () => markNutrientsNotNeeded(context, ref, product),
                child: const Text('Nicht nötig'),
              ),
      ),
    ]);
  }
}

class _PriceSection extends ConsumerWidget {
  const _PriceSection({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(allItemsStreamProvider).value ?? const <ReceiptItem>[];
    final receipts = ref.watch(receiptsStreamProvider).value ?? const <Receipt>[];
    final stores = ref.watch(storesStreamProvider).value ?? const <Store>[];
    final history = buildPriceHistory(
      productId: product.id,
      items: [for (final i in items) (receiptId: i.receiptId, productId: i.productId, unitPriceNormCents: i.unitPriceNormCents, quantity: i.quantity, quantityUnit: i.quantityUnit)],
      receipts: [for (final r in receipts) (id: r.id, storeId: r.storeId, purchasedAtUtc: r.purchasedAt)],
      stores: [for (final s in stores) (id: s.id, chain: s.chain, branch: s.branch)],
    );
    final last = history.isEmpty ? null : history.last;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Heading('Preise'),
      ListTile(
        key: const Key('product-price-open'),
        dense: true,
        title: const Text('Preisverlauf und Händlervergleich'),
        subtitle: Text(
          last == null
              ? 'Noch kein Kauf mit Grundpreis'
              : 'Zuletzt ${formatEuro(last.unitPriceNormCents)}/${priceBaseUnitLabel(product.baseUnit)} bei ${last.storeChain}, ${formatViennaDateTime(last.purchasedAtUtc)}',
          key: const Key('product-price-last'),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/product-price', extra: product),
      ),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: OnlinePriceSection(product: product)),
    ]);
  }
}

class _ClassificationSection extends ConsumerWidget {
  const _ClassificationSection({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesStreamProvider).value ?? const <Category>[];
    final categoryName = categories.where((c) => c.id == product.categoryId).firstOrNull?.name;
    final repo = ref.read(productRepositoryProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Heading('Einordnung'),
      ListTile(
        key: const Key('product-category'),
        dense: true,
        title: const Text('Kategorie'),
        subtitle: Text(categoryName ?? 'Keine'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => pickProductCategory(context, ref, product),
      ),
      SwitchListTile(
        key: const Key('product-page-drink'),
        dense: true,
        title: const Text('Trinkbar'),
        value: isDrinkable(flag: product.isDrink, name: product.name, baseUnit: product.baseUnit, packSize: product.packSize, categoryName: categoryName),
        onChanged: (v) => repo.setIsDrink(product.id, v),
      ),
      SwitchListTile(
        key: const Key('product-page-restock'),
        dense: true,
        title: const Text('Nachkaufen'),
        subtitle: const Text('Vorschlag auf der Einkaufsliste, wenn der Bestand ausgeht'),
        value: product.restock,
        onChanged: (v) => repo.update(product.copyWith(restock: v)),
      ),
    ]);
  }
}

class _StorageSection extends ConsumerWidget {
  const _StorageSection({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(householdPrefsOnceProvider).value ?? const <String, Object?>{};
    final own = parseExpiryStages(prefs[expiryStagesPrefFor(product.id)]);
    final standard = parseExpiryStages(prefs[expiryStagesPref]) ?? const [1];
    final days = product.openedShelfLifeDays;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Heading('Lagerung'),
      ListTile(
        key: const Key('product-storage'),
        dense: true,
        title: Text(_locationLabels[product.defaultLocation] ?? product.defaultLocation),
        subtitle: days == null ? null : Text('Nach dem Öffnen $days ${days == 1 ? 'Tag' : 'Tage'}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/product-form', extra: ProductFormArgs(existing: product)),
      ),
      ListTile(
        key: const Key('product-stages'),
        dense: true,
        title: const Text('Erinnerungen'),
        subtitle: Text(own == null ? 'Wie Standard' : describeExpiryStages(own)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => editProductExpiryStages(context, ref, product.id, standard: standard, own: own),
      ),
    ]);
  }
}
