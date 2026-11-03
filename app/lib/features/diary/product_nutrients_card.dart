import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/clock.dart';
import '../../data/local/database.dart';
import '../../domain/products/product_assignment.dart';

/// KV-Schluessel: bis wann die Karte ausgeblendet bleibt ("Später", ISO-Zeitpunkt).
const productsNutrientsCardHiddenUntilKey = 'products_nutrients_card_hidden_until';

/// Wie lange "Später" die Karte ausblendet.
const productsNutrientsCardHideFor = Duration(days: 14);

/// Hinweiskarte im Tagebuch (Phase N1, ADR-031): "35 Produkte ohne Nährwerte, jetzt zuordnen?". Sie erscheint, solange es
/// Produkte ohne Profil gibt, die nicht als "nicht nötig" markiert sind, und laesst sich fuer zwei Wochen ausblenden.
class ProductNutrientsCard extends ConsumerStatefulWidget {
  const ProductNutrientsCard({super.key, this.now});

  /// Aktueller Zeitpunkt (UTC), austauschbar fuer Tests.
  final DateTime? now;

  @override
  ConsumerState<ProductNutrientsCard> createState() => _ProductNutrientsCardState();
}

class _ProductNutrientsCardState extends ConsumerState<ProductNutrientsCard> {
  DateTime? _hiddenUntil;
  var _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    DateTime? until;
    try {
      until = DateTime.tryParse(await ref.read(databaseProvider).getKv(productsNutrientsCardHiddenUntilKey) ?? '');
      await ref.read(householdPrefsRepositoryProvider).adoptLocalNutrientSkips();
    } catch (_) {
      // ohne lesbare Ablage zeigt die Karte sich einfach
    }
    if (mounted) {
      setState(() {
        _hiddenUntil = until;
        _loaded = true;
      });
    }
  }

  Future<void> _later() async {
    final until = (widget.now ?? appClock.now()).toUtc().add(productsNutrientsCardHideFor);
    setState(() => _hiddenUntil = until);
    try {
      await ref.read(databaseProvider).setKv(productsNutrientsCardHiddenUntilKey, until.toIso8601String());
    } catch (_) {
      // nur eine Komfortfunktion
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final now = (widget.now ?? appClock.now()).toUtc();
    if (_hiddenUntil != null && now.isBefore(_hiddenUntil!)) return const SizedBox.shrink();
    final products = ref.watch(productsStreamProvider).value ?? const <Product>[];
    final prefs = ref.watch(householdPrefsProvider).value ?? const <String, Object?>{};
    final open = products.where((p) => p.deletedAt == null && p.nutrientsPer100 == null && !nutrientsNotNeeded(prefs, p.id)).length;
    if (open == 0) return const SizedBox.shrink();
    final t = Theme.of(context);
    return Card(
      key: const Key('products-nutrients-card'),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(open == 1 ? '1 Produkt ohne Nährwerte' : '$open Produkte ohne Nährwerte', style: t.textTheme.titleSmall),
          const SizedBox(height: 4),
          const Text('Produkte vom Bon haben keine Nährwerte, deshalb zählen sie im Tagebuch nicht mit. Die App schlägt dir passende Einträge vor.'),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(spacing: 8, children: [
              TextButton(key: const Key('products-nutrients-later'), onPressed: _later, child: const Text('Später')),
              FilledButton(key: const Key('products-nutrients-open'), onPressed: () => context.push('/products-nutrients'), child: const Text('Jetzt zuordnen')),
            ]),
          ),
        ]),
      ),
    );
  }
}
