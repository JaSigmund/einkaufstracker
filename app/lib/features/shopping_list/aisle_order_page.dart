import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/local/database.dart';
import '../../domain/shopping_list/aisle_order.dart';

/// Anzeigename eines Haendlers (Filiale): "Billa 0643", ohne Filialkennung nur die Kette.
String storeLabel(Store s) => s.branch == null || s.branch!.isEmpty ? s.chain : '${s.chain} ${s.branch}';

/// Regal-Reihenfolge je Haendler (Ausbau 1.14): die Kategorien so ziehen, wie der Markt sie im Gang fuehrt. Die Einkaufsliste kann
/// danach in dieser Reihenfolge sortiert werden. Gemeinsame Einstellung des Haushalts, wird auf allen Geraeten gleich angezeigt.
class AisleOrderPage extends ConsumerStatefulWidget {
  const AisleOrderPage({super.key, this.initialStoreId});

  /// Haendler, der beim Oeffnen gewaehlt ist (z.B. der in der Einkaufsliste gewaehlte).
  final String? initialStoreId;

  @override
  ConsumerState<AisleOrderPage> createState() => _AisleOrderPageState();
}

class _AisleOrderPageState extends ConsumerState<AisleOrderPage> {
  String? _storeId;
  List<AisleCategory> _items = const [];

  @override
  void initState() {
    super.initState();
    _storeId = widget.initialStoreId;
    if (_storeId != null) _load();
  }

  List<AisleCategory> _categories() => [
        for (final c in ref.read(categoriesStreamProvider).value ?? const <Category>[])
          if (c.deletedAt == null) (id: c.id, name: c.name),
      ];

  Future<void> _load() async {
    final storeId = _storeId;
    if (storeId == null) return;
    final prefs = await ref.read(householdPrefsRepositoryProvider).load().catchError((_) => <String, Object?>{});
    final saved = parseAisleOrder(prefs[aislePrefFor(storeId)]) ?? const <String>[];
    if (mounted && _storeId == storeId) setState(() => _items = orderedForEditing(saved, _categories()));
  }

  Future<void> _save() async {
    final storeId = _storeId;
    if (storeId == null) return;
    try {
      await ref.read(householdPrefsRepositoryProvider).set(aislePrefFor(storeId), [for (final c in _items) c.id]);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Speichern nicht möglich.')));
    }
  }

  Future<void> _reset() async {
    final storeId = _storeId;
    if (storeId == null) return;
    await ref.read(householdPrefsRepositoryProvider).set(aislePrefFor(storeId), <String>[]);
    if (mounted) setState(() => _items = orderedForEditing(const [], _categories()));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final stores = [for (final s in ref.watch(storesStreamProvider).value ?? const <Store>[]) if (s.deletedAt == null) s]
      ..sort((a, b) => storeLabel(a).toLowerCase().compareTo(storeLabel(b).toLowerCase()));
    ref.watch(categoriesStreamProvider); // neu aufbauen, wenn die Kategorien geladen sind
    return Scaffold(
      appBar: AppBar(
        title: const Text('Regal-Reihenfolge'),
        actions: [
          if (_storeId != null) TextButton(key: const Key('aisle-reset'), onPressed: _reset, child: const Text('Zurücksetzen')),
        ],
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            'Zieh die Kategorien in die Reihenfolge, in der du sie im Markt abgehst. Die Einkaufsliste lässt sich danach für diesen Markt sortieren.',
            key: const Key('aisle-hint'),
            style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
          ),
        ),
        if (stores.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(child: Text('Noch kein Markt bekannt. Der erste Bon legt ihn an.', key: const Key('aisle-no-store'), textAlign: TextAlign.center, style: t.textTheme.bodyMedium)),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: DropdownButtonFormField<String>(
              key: const Key('aisle-store'),
              initialValue: stores.any((s) => s.id == _storeId) ? _storeId : null,
              decoration: const InputDecoration(labelText: 'Markt'),
              items: [for (final s in stores) DropdownMenuItem(key: Key('aisle-store-${s.id}'), value: s.id, child: Text(storeLabel(s)))],
              onChanged: (v) {
                setState(() {
                  _storeId = v;
                  _items = const [];
                });
                _load();
              },
            ),
          ),
          if (_storeId == null)
            Padding(padding: const EdgeInsets.all(16), child: Text('Wähle einen Markt.', style: t.textTheme.bodyMedium))
          else
            Expanded(
              child: ReorderableListView.builder(
                key: const Key('aisle-list'),
                itemCount: _items.length,
                onReorderItem: (from, to) {
                  setState(() {
                    final moved = _items[from];
                    final list = [..._items]..removeAt(from);
                    list.insert(to, moved);
                    _items = list;
                  });
                  _save();
                },
                itemBuilder: (context, i) => ListTile(
                  key: Key('aisle-cat-${_items[i].id}'),
                  leading: Text('${i + 1}', style: t.textTheme.labelLarge),
                  title: Text(_items[i].name),
                  trailing: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
                ),
              ),
            ),
        ],
      ]),
    );
  }
}
