import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../diary/ingredient_picker.dart';

/// Gelernte Begriffe (Doku 27 Etappe E4): die zwei Zuordnungen, die keinem Produkt gehoeren. Bis hierher waren beide unsichtbar.
/// Zutatenname -> Lebensmittel (Gedaechtnis fuer Fotos und Handsuche, ADR-031) und Bon-Text -> Kategorie (Vorbelegung beim Import).
class LearnedTermsPage extends ConsumerWidget {
  const LearnedTermsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final links = ref.watch(foodLinksStreamProvider).value ?? const <HouseholdFoodLink>[];
    final aliases = ref.watch(categoryAliasesStreamProvider).value ?? const <CategoryAlias>[];
    final categories = {for (final c in ref.watch(categoriesStreamProvider).value ?? const <Category>[]) c.id: c};
    final codes = ({for (final l in links) l.blsCode}.toList()..sort()).join(',');
    final names = ref.watch(blsNamesProvider(codes)).value ?? const <String, String>{};
    final muted = t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant);

    return Scaffold(
      appBar: AppBar(title: const Text('Gelernte Begriffe')),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('Zutaten und Lebensmittel', style: t.textTheme.titleSmall?.copyWith(color: t.colorScheme.primary)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('So ordnet die App Zutaten aus Fotos und der Suche zu.', style: muted),
        ),
        if (links.isEmpty)
          const ListTile(key: Key('learned-food-empty'), dense: true, title: Text('Noch nichts gelernt'))
        else
          for (final l in links)
            ListTile(
              key: Key('learned-food-${l.id}'),
              title: Text(l.nameNorm),
              subtitle: Text([
                names[l.blsCode] ?? l.blsCode,
                if (l.unitWeightG != null) '1 Stück = ${formatQuantity(l.unitWeightG!)} g',
              ].join(' · ')),
              trailing: PopupMenuButton<String>(
                key: Key('learned-food-menu-${l.id}'),
                onSelected: (v) async {
                  final repo = ref.read(foodLinkRepositoryProvider);
                  if (v == 'forget') {
                    await repo.forget(l.id);
                    return;
                  }
                  final picked = await showIngredientPicker(context, initialQuery: l.nameNorm, foodsOnly: true);
                  final food = picked?.bls;
                  if (food != null) await repo.learn(l.nameNorm, food.code);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'change', child: Text('Anderes Lebensmittel')),
                  PopupMenuItem(value: 'forget', child: Text('Vergessen')),
                ],
              ),
            ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
          child: Text('Bon-Texte und Kategorien', style: t.textTheme.titleSmall?.copyWith(color: t.colorScheme.primary)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('Diese Kategorie bekommt ein Bon-Artikel, solange sein Produkt keine eigene hat.', style: muted),
        ),
        if (aliases.isEmpty)
          const ListTile(key: Key('learned-category-empty'), dense: true, title: Text('Noch nichts gelernt'))
        else
          for (final a in aliases)
            ListTile(
              key: Key('learned-category-${a.id}'),
              title: Text(a.aliasText),
              subtitle: Text(categories[a.categoryId]?.name ?? 'Gelöschte Kategorie'),
              onTap: () => _pickCategory(context, ref, a, categories.values.where((c) => c.deletedAt == null).toList()),
              trailing: IconButton(
                key: Key('learned-category-forget-${a.id}'),
                tooltip: 'Vergessen',
                icon: const Icon(Icons.close),
                onPressed: () => ref.read(receiptRepositoryProvider).forgetCategoryAlias(a.id),
              ),
            ),
      ]),
    );
  }

  Future<void> _pickCategory(BuildContext context, WidgetRef ref, CategoryAlias alias, List<Category> categories) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
          child: ListView(shrinkWrap: true, children: [
            ListTile(title: Text(alias.aliasText, style: Theme.of(ctx).textTheme.titleMedium), subtitle: const Text('Kategorie für künftige Bons')),
            for (final c in categories)
              ListTile(
                key: Key('learned-pick-${c.id}'),
                title: Text(c.name),
                trailing: c.id == alias.categoryId ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, c.id),
              ),
          ]),
        ),
      ),
    );
    if (picked != null) await ref.read(receiptRepositoryProvider).setCategoryAlias(alias.id, picked);
  }
}
