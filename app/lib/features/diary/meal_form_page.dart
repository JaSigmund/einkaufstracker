import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../data/repositories/meal_repository.dart';
import '../../domain/nutrition/daily_nutrition.dart';
import '../../domain/nutrition/ingredient_nutrition.dart';
import '../../domain/nutrition/nutrient_scaling.dart';
import '../../domain/receipt/vienna_time.dart';
import 'ingredient_picker.dart';
import 'meal_labels.dart';

/// Argumente fuer `/meal-form`: ohne [existing] wird eine neue Mahlzeit angelegt, sonst diese bearbeitet.
class MealFormArgs {
  const MealFormArgs({this.existing});
  final Meal? existing;
}

/// Eine Zutat im Formular, noch nicht gespeichert.
class _Row {
  _Row({this.product, this.freeText, required this.quantity, required this.unit, this.per100, this.per100Basis, this.manual, this.deduct = false, this.source});

  Product? product;
  String? freeText;
  double quantity;
  EntryUnit unit;
  NutrientsPer100? per100;
  String? per100Basis;
  NutrientAmounts? manual;
  bool deduct;
  String? source;

  String get label => product?.name ?? freeText ?? 'Zutat';

  IngredientDraft toDraft() => IngredientDraft(
        productId: product?.id,
        freeText: product == null ? freeText : null,
        quantity: quantity,
        entryUnit: unit,
        source: source,
        per100: per100,
        per100Basis: per100Basis,
        manualNutrients: manual,
        deduct: deduct && product != null,
      );

  /// Naehrwerte dieser Zutat, wie sie beim Speichern berechnet wuerden; `null`, wenn unbekannt.
  NutrientAmounts? get nutrients {
    final profile = product != null ? productNutrientProfile(product!) : per100;
    final basis = product != null ? product!.nutrientsBasis : per100Basis;
    final amount = resolveIngredientAmount(
      quantity: quantity,
      entryUnit: unit,
      baseUnit: product?.baseUnit ?? unit.dimensionBaseUnit,
      nutrientsBasis: profile == null ? null : basis,
      unitWeightG: product?.unitWeightG,
    );
    return manual ?? ingredientNutrients(profile, amount);
  }
}

/// Mahlzeit erfassen oder bearbeiten (Doku 15 §3.1, Phase 7b): Titel, Zeitpunkt, Typ, Portionen und Zutaten aus
/// dem Inventar, aus der Lebensmitteldatenbank oder als Freitext. Beim Speichern wird der Bestand FEFO abgezogen,
/// beim Bearbeiten der alte Abzug per Gegenbuchung zurueckgenommen und neu gerechnet.
class MealFormPage extends ConsumerStatefulWidget {
  const MealFormPage({super.key, this.existing});

  final Meal? existing;

  @override
  ConsumerState<MealFormPage> createState() => _MealFormPageState();
}

class _MealFormPageState extends ConsumerState<MealFormPage> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  final _eaten = TextEditingController(text: '1');
  final _made = TextEditingController(text: '1');
  late String _type;
  late DateTime _eatenAt;
  var _estimate = false;
  final _rows = <_Row>[];
  var _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final m = widget.existing;
    _eatenAt = m?.eatenAt.toUtc() ?? DateTime.now().toUtc();
    _type = m?.mealType ?? guessMealType(utcToViennaLocal(_eatenAt).hour);
    if (m != null) {
      _title.text = m.title;
      _note.text = m.note ?? '';
      _eaten.text = formatQuantity(m.servingsEaten);
      _made.text = formatQuantity(m.servingsMade);
      _estimate = m.isEstimate;
      _loadExistingIngredients(m);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _eaten.dispose();
    _made.dispose();
    super.dispose();
  }

  Future<void> _loadExistingIngredients(Meal m) async {
    final ingredients = await ref.read(mealRepositoryProvider).ingredientsOf(m.id);
    final products = {for (final p in await ref.read(productRepositoryProvider).allSnapshot()) p.id: p};
    final rows = <_Row>[];
    for (final i in ingredients) {
      final (qty, unit) = switch (i.unit) {
        'kg' => (i.quantity * 1000, EntryUnit.g),
        'l' => (i.quantity * 1000, EntryUnit.ml),
        _ => (i.quantity, EntryUnit.piece),
      };
      final product = i.productId == null ? null : products[i.productId];
      NutrientsPer100? per100;
      NutrientAmounts? manual;
      if (product == null) {
        // Ohne Produkt (Freitext, BLS oder geloeschtes Produkt) steht nur der Snapshot zur Verfuegung: daraus je 100 g
        // zurueckrechnen, damit die Menge noch aenderbar bleibt; ohne bekannte Menge bleiben die Werte absolut.
        final basis = i.amountG;
        double? per(double? v) => (v == null || basis == null || basis <= 0) ? null : v * 100 / basis;
        if (basis != null && basis > 0) {
          per100 = NutrientsPer100(
            kcal: per(i.kcal),
            proteinG: per(i.proteinG),
            fatG: per(i.fatG),
            carbsG: per(i.carbsG),
            sugarG: per(i.sugarG),
            fiberG: per(i.fiberG),
            saltG: per(i.saltG),
          );
        } else if ([i.kcal, i.proteinG, i.fatG, i.carbsG, i.sugarG, i.fiberG, i.saltG].any((v) => v != null)) {
          manual = NutrientAmounts(
            kcal: i.kcal, proteinG: i.proteinG, fatG: i.fatG, carbsG: i.carbsG, sugarG: i.sugarG, fiberG: i.fiberG, saltG: i.saltG,
          );
        }
      }
      rows.add(_Row(
        product: product,
        freeText: product == null ? (i.freeText ?? 'Gelöschtes Produkt') : null,
        quantity: qty,
        unit: unit,
        per100: per100,
        per100Basis: per100 == null ? null : 'g',
        manual: manual,
        deduct: i.source == 'inventory',
        source: i.source,
      ));
    }
    if (mounted) setState(() => _rows..clear()..addAll(rows));
  }

  Future<void> _pickDateTime() async {
    final local = utcToViennaLocal(_eatenAt);
    final date = await showDatePicker(
      context: context,
      initialDate: local,
      firstDate: DateTime(local.year - 2),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay(hour: local.hour, minute: local.minute));
    if (time == null || !mounted) return;
    setState(() => _eatenAt = viennaLocalToUtc(date.year, date.month, date.day, time.hour, time.minute));
  }

  String? _stockHint(Product p) {
    final active = ref.read(activeInventoryStreamProvider).value ?? const <InventoryItem>[];
    final total = active.where((i) => i.productId == p.id).fold<double>(0, (s, i) => s + i.quantity);
    return total <= 0 ? 'Nicht im Bestand: der Eintrag zählt trotzdem für die Nährwerte.' : 'Im Bestand: ${formatQuantity(total)} ${p.baseUnit}';
  }

  Future<void> _addIngredient() async {
    final picked = await showIngredientPicker(context);
    if (picked == null || !mounted) return;
    final product = picked.product;
    final bls = picked.bls;
    final label = product?.name ?? bls?.nameDe ?? picked.freeText!;
    final q = await askIngredientQuantity(
      context,
      label: label,
      initialUnit: product != null ? EntryUnit.naturalFor(product.baseUnit) : EntryUnit.g,
      canDeduct: product != null,
      stockHint: product == null ? null : _stockHint(product),
    );
    if (q == null || !mounted) return;
    setState(() => _rows.add(_Row(
          product: product,
          freeText: product == null ? label : null,
          quantity: q.quantity,
          unit: q.unit,
          per100: bls?.per100,
          per100Basis: bls == null ? null : 'g',
          deduct: q.deduct,
        )));
  }

  Future<void> _editIngredient(int index) async {
    final row = _rows[index];
    final q = await askIngredientQuantity(
      context,
      label: row.label,
      initialUnit: row.unit,
      initialQuantity: row.quantity,
      canDeduct: row.product != null,
      initialDeduct: row.deduct,
      stockHint: row.product == null ? null : _stockHint(row.product!),
    );
    if (q == null || !mounted) return;
    setState(() {
      row.quantity = q.quantity;
      row.unit = q.unit;
      row.deduct = q.deduct;
    });
  }

  double? _parsePositive(String text) {
    final v = double.tryParse(text.replaceAll(',', '.').trim());
    return (v == null || v <= 0) ? null : v;
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final eaten = _parsePositive(_eaten.text);
    final made = _parsePositive(_made.text);
    if (title.isEmpty) return setState(() => _error = 'Bitte einen Titel eingeben.');
    if (eaten == null || made == null) return setState(() => _error = 'Portionen müssen größer als 0 sein.');
    setState(() {
      _saving = true;
      _error = null;
    });
    final draft = MealDraft(
      title: title,
      eatenAt: _eatenAt,
      mealType: _type,
      note: _note.text,
      servingsEaten: eaten,
      servingsMade: made,
      isEstimate: _estimate,
      source: widget.existing?.source ?? 'manual',
      ingredients: [for (final r in _rows) r.toDraft()],
    );
    try {
      final repo = ref.read(mealRepositoryProvider);
      if (_isEdit) {
        await repo.update(widget.existing!.id, draft);
      } else {
        await repo.create(draft);
      }
      if (mounted) context.pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Speichern nicht möglich: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mahlzeit löschen?'),
        content: const Text('Der Eintrag verschwindet aus dem Tagebuch. Was vom Bestand abgezogen wurde, wird zurückgebucht.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(key: const Key('meal-delete-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(mealRepositoryProvider).delete(widget.existing!.id);
    if (mounted) context.pop(true);
  }

  /// Summe der Zutaten und der Anteil, der tatsaechlich gegessen wurde (FR-13).
  ({NutrientTotals all, NutrientTotals eaten, int unknown}) _totals() {
    var sum = const NutrientTotals();
    var unknown = 0;
    for (final r in _rows) {
      final n = r.nutrients;
      if (n == null) {
        unknown++;
        continue;
      }
      sum = sum +
          NutrientTotals(
            kcal: n.kcal ?? 0, proteinG: n.proteinG ?? 0, fatG: n.fatG ?? 0, carbsG: n.carbsG ?? 0,
            sugarG: n.sugarG ?? 0, fiberG: n.fiberG ?? 0, saltG: n.saltG ?? 0,
          );
    }
    final eaten = _parsePositive(_eaten.text) ?? 1;
    final made = _parsePositive(_made.text) ?? 1;
    return (all: sum, eaten: sum.scaled(eaten / made), unknown: unknown);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final totals = _totals();
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Mahlzeit bearbeiten' : 'Neue Mahlzeit'),
        actions: [
          if (_isEdit) IconButton(key: const Key('meal-delete'), tooltip: 'Löschen', icon: const Icon(Icons.delete_outline), onPressed: _delete),
          // In der App-Leiste statt am Listenende: das Formular ist lang, Speichern soll immer erreichbar sein.
          TextButton(key: const Key('meal-save'), onPressed: _saving ? null : _save, child: Text(_saving ? 'Speichert…' : 'Speichern')),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // Ganz oben, damit eine Fehlermeldung beim Speichern nicht unterhalb des sichtbaren Bereichs verschwindet.
        if (_error != null)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, key: const Key('meal-error'), style: TextStyle(color: t.colorScheme.error))),
        TextField(
          key: const Key('meal-title'),
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Was gab es?', hintText: 'z.B. Gemüsepfanne mit Reis'),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final e in mealTypeLabels.entries)
            ChoiceChip(
              key: Key('meal-type-${e.key}'),
              avatar: Icon(mealTypeIcon(e.key), size: 18),
              label: Text(e.value),
              selected: _type == e.key,
              onSelected: (_) => setState(() => _type = e.key),
            ),
        ]),
        ListTile(
          key: const Key('meal-datetime'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule),
          title: Text(formatViennaDateTime(_eatenAt)),
          trailing: const Icon(Icons.edit_outlined, size: 18),
          onTap: _pickDateTime,
        ),
        Row(children: [
          Expanded(
            child: TextField(
              key: const Key('meal-servings-eaten'),
              controller: _eaten,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Portionen gegessen'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              key: const Key('meal-servings-made'),
              controller: _made,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Portionen gekocht'),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        Text('Zutaten', style: t.textTheme.titleMedium),
        if (_rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Noch keine Zutat. Aus dem Inventar, der Lebensmitteldatenbank oder als Freitext.', style: t.textTheme.bodySmall),
          ),
        for (var i = 0; i < _rows.length; i++) _ingredientTile(i, t),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(key: const Key('meal-add-ingredient'), onPressed: _addIngredient, icon: const Icon(Icons.add), label: const Text('Zutat hinzufügen')),
        ),
        if (_rows.isNotEmpty) _totalsCard(t, totals),
        SwitchListTile(
          key: const Key('meal-estimate'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Nur geschätzt'),
          subtitle: const Text('z.B. Restaurant: wird in der Auswertung als Schätzung gekennzeichnet'),
          value: _estimate,
          onChanged: (v) => setState(() => _estimate = v),
        ),
        TextField(key: const Key('meal-note'), controller: _note, decoration: const InputDecoration(labelText: 'Notiz (optional)'), maxLines: 2),
      ]),
    );
  }

  Widget _ingredientTile(int i, ThemeData t) {
    final r = _rows[i];
    final n = r.nutrients;
    final amount = '${formatQuantity(r.quantity)} ${r.unit.label}';
    final parts = <String>[
      amount,
      if (n?.kcal != null) formatKcal(n!.kcal!) else 'Nährwerte unbekannt',
      if (r.deduct && r.product != null) 'vom Bestand',
    ];
    return ListTile(
      key: Key('ingredient-row-$i'),
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(r.product != null ? Icons.kitchen_outlined : Icons.eco_outlined, size: 20),
      title: Text(r.label),
      subtitle: Text(parts.join(' · ')),
      trailing: IconButton(key: Key('ingredient-remove-$i'), tooltip: 'Entfernen', icon: const Icon(Icons.close), onPressed: () => setState(() => _rows.removeAt(i))),
      onTap: () => _editIngredient(i),
    );
  }

  Widget _totalsCard(ThemeData t, ({NutrientTotals all, NutrientTotals eaten, int unknown}) totals) {
    final e = totals.eaten;
    final sharing = (_parsePositive(_made.text) ?? 1) != (_parsePositive(_eaten.text) ?? 1);
    return Card(
      key: const Key('meal-totals'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(sharing ? 'Dein Anteil' : 'Nährwerte', style: t.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            '${formatKcal(e.kcal)} · ${formatNutrientGrams(e.proteinG)} Eiweiß · ${formatNutrientGrams(e.fatG)} Fett · ${formatNutrientGrams(e.carbsG)} Kohlenhydrate',
            key: const Key('meal-totals-text'),
          ),
          if (sharing) Text('Ganzes Gericht: ${formatKcal(totals.all.kcal)}', style: t.textTheme.bodySmall),
          if (totals.unknown > 0)
            Text(
              totals.unknown == 1 ? 'Für 1 Zutat sind keine Nährwerte bekannt.' : 'Für ${totals.unknown} Zutaten sind keine Nährwerte bekannt.',
              key: const Key('meal-totals-unknown'),
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline),
            ),
        ]),
      ),
    );
  }
}
