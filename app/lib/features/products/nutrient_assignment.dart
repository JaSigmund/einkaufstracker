import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../data/nutrition/bls_food_search.dart';
import '../../data/products/off_client.dart';
import '../../domain/nutrition/food_match.dart';
import '../../domain/nutrition/nutrient_scaling.dart';
import '../diary/ingredient_picker.dart';

/// Woher das Profil eines Produkts stammt, in Worten.
String nutrientSourceLabel(String? source) => switch (source) {
      'off' => 'Open Food Facts',
      'bls' => 'Lebensmitteldatenbank',
      _ => 'Eigene Werte',
    };

/// Das gespeicherte Profil eines Produkts, `null` ohne oder unlesbar.
NutrientsPer100? nutrientsOf(Product product) {
  final raw = product.nutrientsPer100;
  if (raw == null) return null;
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? NutrientsPer100.fromMap(decoded) : null;
  } catch (_) {
    return null;
  }
}

/// Uebernimmt [food] als Profil des Produkts, auch ueber ein vorhandenes. Bisherige Mahlzeiten behalten ihre Werte, weil ihre Zutaten
/// einen Snapshot tragen. [learn] merkt den Namen fuer Fotos und Handsuche: Das soll nur eine echte Entsprechung, denn eine Naeherung
/// wie "Knoppers als Schokoriegel" verfaelscht sonst kuenftige Zuordnungen (Doku 25, Q-38). Liefert `false` bei einem Eintrag ohne Werte.
Future<bool> applyNutrients(WidgetRef ref, Product product, BlsFood food, {required bool learn}) async {
  final updated = await ref.read(productRepositoryProvider).setBlsProfile(product.id, food, overwrite: true);
  if (updated == null) return false;
  if (learn) {
    try {
      await ref.read(foodLinkRepositoryProvider).learn(product.name, food.code);
    } catch (_) {
      // das Gedaechtnis ist eine Zugabe
    }
  }
  return true;
}

/// Eintrag von Hand waehlen: Suche in der Lebensmitteldatenbank, dann Bestaetigung mit dem Schalter fuers Gedaechtnis.
Future<void> changeNutrients(BuildContext context, WidgetRef ref, Product product) async {
  final picked = await showIngredientPicker(context, initialQuery: product.name, foodsOnly: true);
  final food = picked?.bls;
  if (food == null || !context.mounted) return;
  final learn = await showDialog<bool>(context: context, builder: (_) => _ConfirmNutrientsDialog(product: product, food: food));
  if (learn == null) return;
  final ok = await applyNutrients(ref, product, food, learn: learn);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dieser Eintrag hat keine Nährwerte.')));
  }
}

/// "Nicht nötig": das Produkt zaehlt nicht mehr als offen, auf allen Geraeten. Ein vorhandenes Profil wird nach Rueckfrage entfernt,
/// sonst liesse sich ein irrtuemlich zugeordneter Muellbeutel nie wieder korrigieren.
Future<void> markNutrientsNotNeeded(BuildContext context, WidgetRef ref, Product product) async {
  if (product.nutrientsPer100 != null) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nährwerte entfernen?'),
        content: Text('„${product.name}“ hat dann keine Nährwerte mehr und zählt im Tagebuch nicht mit. Bisherige Mahlzeiten behalten ihre Werte.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(key: const Key('nutrients-remove-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Entfernen')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(productRepositoryProvider).clearNutrients(product.id);
  }
  await ref.read(householdPrefsRepositoryProvider).setNutrientsNotNeeded(product.id, true);
}

/// Ein Barcode wurde an ein bestehendes Produkt gehaengt und Open Food Facts kennt Naehrwerte (Doku 27 Etappe E3): anbieten, wenn das
/// Produkt keine oder nur Werte aus der Lebensmitteldatenbank hat. Automatisch wird nichts ueberschrieben.
Future<void> offerOffNutrients(BuildContext context, WidgetRef ref, Product product, OffProduct? off) async {
  final per100 = off?.nutrientsPer100;
  if (per100 == null || per100.isEmpty || product.nutrientsSource == 'off' || product.nutrientsSource == 'manual') return;
  if (product.nutrientsPer100 != null && product.nutrientsSource != 'bls') return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Nährwerte übernehmen?'),
      content: Text(
        'Open Food Facts kennt die Nährwerte dieser Packung${per100['kcal'] != null ? ' (${formatKcal(per100['kcal']!)} je 100 ${off!.nutrientsBasis ?? 'g'})' : ''}. '
        '${product.nutrientsPer100 == null ? '„${product.name}“ hat noch keine.' : 'Sie ersetzen die Werte aus der Lebensmitteldatenbank.'}',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Nein')),
        FilledButton(key: const Key('off-nutrients-accept'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Übernehmen')),
      ],
    ),
  );
  if (ok == true) await ref.read(productRepositoryProvider).setOffProfile(product.id, per100, basis: off!.nutrientsBasis);
}

class _ConfirmNutrientsDialog extends StatefulWidget {
  const _ConfirmNutrientsDialog({required this.product, required this.food});
  final Product product;
  final BlsFood food;

  @override
  State<_ConfirmNutrientsDialog> createState() => _ConfirmNutrientsDialogState();
}

class _ConfirmNutrientsDialogState extends State<_ConfirmNutrientsDialog> {
  late var _learn = widget.food.trust == MatchTrust.sure;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final food = widget.food;
    final hasProfile = widget.product.nutrientsPer100 != null;
    return AlertDialog(
      title: Text(widget.product.name),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${food.nameDe}${food.per100.kcal != null ? ' · ${formatKcal(food.per100.kcal!)} je 100 g' : ''}', key: const Key('nutrients-confirm-food')),
        if (widget.product.nutrientsSource == 'off')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Die bisherigen Werte stammen von Open Food Facts und sind packungsgenau.',
              key: const Key('nutrients-confirm-off'),
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.error),
            ),
          ),
        if (hasProfile)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Gilt für neue Einträge, bisherige Mahlzeiten behalten ihre Werte.', style: t.textTheme.bodySmall),
          ),
        SwitchListTile(
          key: const Key('nutrients-confirm-learn'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Genau dieses Lebensmittel, für Fotos merken'),
          subtitle: const Text('Aus lassen, wenn der Eintrag nur eine Näherung ist.'),
          value: _learn,
          onChanged: (v) => setState(() => _learn = v),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(key: const Key('nutrients-confirm-ok'), onPressed: () => Navigator.pop(context, _learn), child: const Text('Übernehmen')),
      ],
    );
  }
}
