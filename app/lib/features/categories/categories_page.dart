import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repositories/category_repository.dart';
import '../common/sync_status_banner.dart';

class CategoriesPage extends ConsumerWidget {
  const CategoriesPage({super.key});

  Future<String?> _askName(BuildContext context, {String title = 'Neue Kategorie', String initial = ''}) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Speichern')),
        ],
      ),
    );
  }

  Future<void> _run(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } on DuplicateCategoryException catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } on ArgumentError {
      // leere Eingabe: nichts tun
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesStreamProvider);
    final repo = ref.watch(categoryRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Kategorien')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final name = await _askName(context);
          if (name != null && context.mounted) await _run(context, () => repo.add(name));
        },
        icon: const Icon(Icons.add),
        label: const Text('Kategorie'),
      ),
      body: Column(
        children: [
          const SyncStatusBanner(),
          const Divider(height: 1),
          Expanded(
            child: categories.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Fehler: $e')),
              data: (list) => list.isEmpty
                  ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Noch keine Kategorien. Ziehe oben zum Synchronisieren oder lege eine an.')))
                  : RefreshIndicator(
                      onRefresh: () => ref.read(syncControllerProvider.notifier).sync(),
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        // Platz unter dem letzten Eintrag, damit der Knopf "+ Kategorie" das Menue nicht verdeckt
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final c = list[i];
                          return ListTile(
                            title: Text(c.name),
                            subtitle: Text(c.isStorable ? 'Lagerbar (Inventarvorschläge)' : 'Nicht lagerbar'),
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) async {
                                switch (v) {
                                  case 'rename':
                                    final n = await _askName(context, title: 'Umbenennen', initial: c.name);
                                    if (n != null && context.mounted) await _run(context, () => repo.rename(c.id, n));
                                  case 'storable':
                                    await _run(context, () => repo.setStorable(c.id, !c.isStorable));
                                  case 'delete':
                                    await _run(context, () => repo.softDelete(c.id));
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'rename', child: Text('Umbenennen')),
                                PopupMenuItem(value: 'storable', child: Text(c.isStorable ? 'Als nicht lagerbar markieren' : 'Als lagerbar markieren')),
                                const PopupMenuItem(value: 'delete', child: Text('Löschen')),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
