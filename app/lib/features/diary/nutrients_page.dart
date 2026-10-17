import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../data/nutrition/bls_food_search.dart';
import '../../data/repositories/household_prefs_repository.dart' show microReferenceOnPref, microReferenceOverridesPref;
import '../../data/repositories/meal_repository.dart' show ingredientGrams;
import '../../domain/nutrition/micro_nutrition.dart';
import '../../domain/nutrition/micros.dart';
import '../../domain/nutrition/micros_backfill.dart';
import '../../domain/nutrition/nutrient_registry.dart';
import '../../domain/receipt/vienna_time.dart';

/// Frueherer lokaler KV-Speicher der Referenzmengen (bis 1.12). Seit 1.13 liegen sie als gemeinsame Einstellungen des Haushalts
/// (`household_prefs`, ADR-035); die alten Werte werden beim ersten Oeffnen dorthin uebernommen.
const microReferenceOnKey = 'micro_reference_on';
const microReferenceOverridesKey = 'micro_reference_overrides';

/// Hinweis zu den Tabellenwerten, im Info-Dialog der Seite und unter jeder Aufschluesselung ehrlich genannt (ADR-032).
const nutrientsLimitsText = 'Die Werte stammen aus dem Bundeslebensmittelschlüssel: Durchschnittswerte, zu rund drei Vierteln berechnet. '
    'Garverluste (besonders bei Vitamin C, B-Vitaminen und Folat) sind nur berücksichtigt, wenn du bei einer rohen Zutat die Zubereitung wählst (USDA-Durchschnittswerte für 15 Nährstoffe). Nahrungsergänzung zählt nur, was du unter „Nahrungsergänzung“ einträgst, und steht getrennt. '
    'Selen und Koffein fehlen in der Quelle. Die Zahlen sind kein Maßstab für deinen eigenen Bedarf.';

/// Hinweis zu den Referenzmengen: Kennzeichnungswerte, keine Empfehlung.
const nutrientsReferenceText = 'Referenzmengen laut Lebensmittelkennzeichnung (Verordnung (EU) Nr. 1169/2011) für einen durchschnittlichen Erwachsenen. '
    'Das ist keine Empfehlung für dich: Kinder, Schwangere, Sportler und ältere Menschen haben anderen Bedarf.';

/// Mikronaehrstoffe pro Tag und Woche (Phase N3, ADR-032): Gruppen, Datenabdeckung je Naehrstoff, "Woher kommt das?" und optional die
/// Kennzeichnungs-Referenzmengen. Keine Ampel, keine Bewertung.
class NutrientsPage extends ConsumerStatefulWidget {
  const NutrientsPage({super.key, this.now});

  /// Aktueller Zeitpunkt (UTC), austauschbar fuer Tests.
  final DateTime? now;

  @override
  ConsumerState<NutrientsPage> createState() => _NutrientsPageState();
}

class _NutrientsPageState extends ConsumerState<NutrientsPage> {
  late DateTime _day;
  var _week = false;
  var _showAll = false;
  var _backfilling = false;

  /// Gemeinsame Einstellungen des Haushalts, in [build] aus dem Stream gelesen (die Handler lesen nur dieses Feld).
  Map<String, Object?> _prefs = const {};

  bool get _referenceOn => _prefs[microReferenceOnPref] == true;

  Map<String, double> get _overrides {
    final raw = _prefs[microReferenceOverridesPref];
    final map = <String, double>{};
    if (raw is Map) {
      for (final e in raw.entries) {
        final v = e.value;
        if (e.key is String && v is num && v > 0 && nutrientDef(e.key as String) != null) map[e.key as String] = v.toDouble();
      }
    }
    return map;
  }

  DateTime get _today {
    final l = utcToViennaLocal(widget.now ?? DateTime.now().toUtc());
    return DateTime(l.year, l.month, l.day);
  }

  @override
  void initState() {
    super.initState();
    _day = _today;
    _loadSettings();
  }

  /// Uebernimmt die lokal gespeicherten Referenzmengen aus Version 1.12 und frueher einmalig in die gemeinsamen Einstellungen, sofern
  /// dort noch nichts steht. Scheitert still (ohne Haushalt oder Ablage zeigt die Seite einfach keine Referenzen).
  Future<void> _loadSettings() async {
    try {
      final repo = ref.read(householdPrefsRepositoryProvider);
      final prefs = await repo.load();
      final db = ref.read(databaseProvider);
      if (!prefs.containsKey(microReferenceOnPref) && await db.getKv(microReferenceOnKey) == 'true') {
        await repo.set(microReferenceOnPref, true);
      }
      final raw = await db.getKv(microReferenceOverridesKey);
      if (!prefs.containsKey(microReferenceOverridesPref) && raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded.isNotEmpty) await repo.set(microReferenceOverridesPref, decoded);
      }
    } catch (_) {
      // ohne lesbare Ablage zeigt die Seite einfach keine Referenzen
    }
  }

  Future<void> _setReference(bool on) async {
    try {
      await ref.read(householdPrefsRepositoryProvider).set(microReferenceOnPref, on);
    } catch (_) {
      // nur eine Komfortfunktion
    }
  }

  Future<void> _setOverride(String key, double? value) async {
    final next = {..._overrides};
    if (value == null) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    try {
      await ref.read(householdPrefsRepositoryProvider).set(microReferenceOverridesPref, next);
    } catch (_) {
      // nur eine Komfortfunktion
    }
  }

  /// Referenzwert je Tag in der Einheit des Naehrstoffs: eigener Wert, sonst die Kennzeichnungsmenge. Ohne eingeschaltete
  /// Referenzmengen zeigt die Seite keine (auch keinen eigenen Wert): `null`.
  double? _referenceOf(NutrientDef def) => !_referenceOn ? null : (_overrides[def.key] ?? def.euReference);

  /// Zutaten aus Mahlzeiten vor 1.11 haben einen BLS-Eintrag oder ein Produkt, aber keinen Mikronaehrstoff-Snapshot: aus dem Profil und der
  /// gespeicherten Menge wird er nachgerechnet. Nur Ergaenzen, nie Ueberschreiben (ADR-035).
  List<BackfillIngredient> _backfillInput(List<MealIngredient> ingredients) => [
        for (final i in ingredients)
          (id: i.id, productId: i.productId, blsCode: i.blsCode, grams: ingredientGrams(i), hasMicros: i.micros != null),
      ];

  Future<void> _backfill(List<MealIngredient> ingredients, Map<String, Micros> productMicros, Map<String, String> productCodes) async {
    if (_backfilling) return;
    setState(() => _backfilling = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final input = _backfillInput(ingredients);
      final codes = backfillBlsCodes(input, productMicros100: productMicros, productBlsCodes: productCodes);
      final foods = codes.isEmpty ? const <BlsFood>[] : await ref.read(blsFoodSearchProvider).byCodes(codes);
      final plan = planMicrosBackfill(
        input,
        productMicros100: productMicros,
        productBlsCodes: productCodes,
        blsMicros100: {for (final f in foods) if (f.micros != null) f.code: f.micros!},
      );
      final done = await ref.read(mealRepositoryProvider).applyMicros(plan.updates);
      final rest = [
        if (plan.withoutAmount > 0) '${plan.withoutAmount} ohne bekannte Menge',
        if (plan.withoutData > 0) '${plan.withoutData} ohne Werte in der Quelle',
      ];
      messenger.showSnackBar(SnackBar(
        content: Text('${done == 1 ? '1 Zutat' : '$done Zutaten'} ergänzt${rest.isEmpty ? '' : ', ${rest.join(', ')}'}.'),
      ));
    } on BlsSearchUnavailable {
      messenger.showSnackBar(const SnackBar(content: Text('Die Nährwert-Datenbank ist gerade nicht erreichbar. Versuch es später noch einmal.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Nachrechnen nicht möglich.')));
    } finally {
      if (mounted) setState(() => _backfilling = false);
    }
  }

  Widget _backfillCard(ThemeData t, int count, List<MealIngredient> ingredients, Map<String, Micros> productMicros, Map<String, String> productCodes) => Card(
        key: const Key('nutrients-backfill'),
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Ältere Mahlzeiten ergänzen', style: t.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              '${count == 1 ? 'Eine Zutat' : '$count Zutaten'} aus früheren Mahlzeiten ${count == 1 ? 'hat' : 'haben'} einen Nährwert-Eintrag, aber noch keine '
              'Vitamine und Mineralstoffe (die gibt es erst seit Version 1.11). Die App kann sie aus dem Eintrag und der gespeicherten Menge nachrechnen. '
              'Bestehende Werte bleiben unverändert.',
              key: const Key('nutrients-backfill-text'),
              style: t.textTheme.bodySmall,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const Key('nutrients-backfill-run'),
                onPressed: _backfilling ? null : () => _backfill(ingredients, productMicros, productCodes),
                icon: _backfilling
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.calculate_outlined),
                label: Text(_backfilling ? 'Rechne nach …' : 'Jetzt nachrechnen'),
              ),
            ),
          ]),
        ),
      );

  void _shift(int days) => setState(() => _day = _week ? _day.add(Duration(days: 7 * days)) : DateTime(_day.year, _day.month, _day.day + days));

  String _title() {
    if (_week) {
      final monday = DateTime(_day.year, _day.month, _day.day - (_day.weekday - 1));
      return formatWeekRange(monday, _today);
    }
    return formatDayHeading(_day, _today);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final meals = ref.watch(mealsStreamProvider);
    final ingredients = ref.watch(mealIngredientsStreamProvider);
    _prefs = ref.watch(householdPrefsProvider).value ?? const {};
    final Widget body;
    if (meals.isLoading || ingredients.isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (meals.hasError || ingredients.hasError) {
      body = Center(child: Text('Fehler: ${meals.error ?? ingredients.error}'));
    } else {
      body = _content(context, t, meals.value!, ingredients.value!);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nährstoffe'),
        actions: [
          IconButton(
            key: const Key('nutrients-supplements'),
            tooltip: 'Nahrungsergänzung',
            icon: const Icon(Icons.medication_outlined),
            onPressed: () => context.push('/supplements'),
          ),
          IconButton(
            key: const Key('nutrients-info'),
            tooltip: 'Woher stammen die Werte?',
            icon: const Icon(Icons.info_outline),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Woher stammen die Werte?'),
                content: SingleChildScrollView(child: Text('$nutrientsLimitsText\n\n$nutrientsReferenceText')),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen'))],
              ),
            ),
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _content(BuildContext context, ThemeData t, List<Meal> meals, List<MealIngredient> ingredients) {
    final intakes = ref.watch(supplementIntakesStreamProvider).value ?? const <SupplementIntake>[];
    final micros = buildDailyMicros(
      [for (final m in meals) (id: m.id, title: m.title, eatenAtUtc: m.eatenAt, servingsEaten: m.servingsEaten, servingsMade: m.servingsMade)],
      [for (final i in ingredients) (mealId: i.mealId, name: i.freeText ?? 'Zutat', micros: parseMicros(i.micros))],
      isEstimate: (id) => meals.where((m) => m.id == id).any((m) => m.isEstimate),
      intakes: [
        for (final i in intakes)
          if (parseMicros(i.micros) case final m?) (id: i.id, name: i.name, takenAtUtc: i.takenAt, micros: m),
      ],
    );
    final byDay = {for (final d in micros) d.day: d};
    final monday = DateTime(_day.year, _day.month, _day.day - (_day.weekday - 1));
    final week = buildWeeklyMicros(micros).where((w) => w.weekStart == monday).firstOrNull;

    final hasData = _week ? week != null : byDay[_day] != null;
    final MicroValue Function(String key) valueOf = _week ? (k) => week!.valueOf(k) : (k) => byDay[_day]!.valueOf(k);
    final estimates = _week ? false : (byDay[_day]?.hasEstimates ?? false);

    // Produkte (Profil und BLS-Verknuepfung) fuer das Nachrechnen; ohne geladene Produkte gibt es nur die BLS-Zeilen
    final products = ref.watch(productsStreamProvider).value ?? const <Product>[];
    final productMicros = <String, Micros>{};
    for (final p in products) {
      final m = parseMicros(p.nutrientsPer100);
      if (m != null) productMicros[p.id] = m;
    }
    final productCodes = {for (final p in products) if (p.blsCode != null) p.id: p.blsCode!};
    final backfillCount = backfillCandidateCount(_backfillInput(ingredients), productMicros100: productMicros, productBlsCodes: productCodes);

    return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: SegmentedButton<bool>(
          key: const Key('nutrients-mode'),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, label: Text('Tag')),
            ButtonSegment(value: true, label: Text('Woche')),
          ],
          selected: {_week},
          onSelectionChanged: (s) => setState(() => _week = s.first),
        ),
      ),
      Row(children: [
        IconButton(key: const Key('nutrients-prev'), tooltip: 'Vorheriger Zeitraum', icon: const Icon(Icons.chevron_left), onPressed: () => _shift(-1)),
        Expanded(child: Text(_title(), key: const Key('nutrients-title'), textAlign: TextAlign.center, style: t.textTheme.titleMedium)),
        IconButton(key: const Key('nutrients-next'), tooltip: 'Nächster Zeitraum', icon: const Icon(Icons.chevron_right), onPressed: () => _shift(1)),
      ]),
      if (_week && week != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Ø pro erfasstem Tag, ${week.daysLogged} von 7 Tagen erfasst',
            key: const Key('nutrients-week-info'),
            textAlign: TextAlign.center,
            style: t.textTheme.bodySmall,
          ),
        ),
      if (backfillCount > 0) _backfillCard(t, backfillCount, ingredients, productMicros, productCodes),
      SwitchListTile(
        key: const Key('nutrients-reference'),
        title: const Text('Referenzmengen anzeigen'),
        subtitle: const Text('Kennzeichnungswerte für Erwachsene, keine Empfehlung'),
        value: _referenceOn,
        onChanged: _setReference,
      ),
      if (!hasData)
        Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _week ? 'In dieser Woche ist nichts erfasst.' : 'Für diesen Tag ist nichts erfasst.',
            key: const Key('nutrients-none'),
            textAlign: TextAlign.center,
          ),
        )
      else ...[
        if (estimates)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Enthält Schätzwerte', key: const Key('nutrients-estimates'), style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ),
        for (final g in NutrientGroup.values) ..._group(context, t, g, valueOf),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextButton(
              key: const Key('nutrients-show-all'),
              onPressed: () => setState(() => _showAll = !_showAll),
              child: Text(_showAll ? 'Nur die häufig gefragten zeigen' : 'Alle ${nutrientRegistry.length} Nährstoffe zeigen'),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(nutrientsLimitsText, key: const Key('nutrients-limits'), style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        ),
      ],
    ]);
  }

  List<Widget> _group(BuildContext context, ThemeData t, NutrientGroup g, MicroValue Function(String) valueOf) {
    final defs = [for (final n in nutrientRegistry) if (n.group == g && (_showAll || n.featured)) n];
    if (defs.isEmpty) return const [];
    return [
      Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0), child: Text(g.label, key: Key('nutrients-group-${g.name}'), style: t.textTheme.titleSmall)),
      for (final d in defs) _row(context, t, d, valueOf(d.key)),
    ];
  }

  Widget _row(BuildContext context, ThemeData t, NutrientDef def, MicroValue v) {
    final ref = _referenceOf(def);
    final fraction = v.unknown ? null : referenceFraction(v.total, ref);
    final valueText = v.unknown ? 'unbekannt' : '${v.complete ? '' : 'mindestens '}${formatMicro(def, v.total)}';
    return ListTile(
      key: Key('nutrient-row-${def.key}'),
      dense: true,
      title: Text(def.label),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (v.ingredients > 0 && !v.complete)
          Text(
            v.unknown ? 'keine Daten in ${v.ingredients} ${v.ingredients == 1 ? 'Zutat' : 'Zutaten'}' : 'aus ${v.withData} von ${v.ingredients} Zutaten mit Daten',
            key: Key('nutrient-coverage-${def.key}'),
            style: t.textTheme.bodySmall,
          ),
        if (v.supplementTotal > 0)
          Text('davon ${formatMicro(def, v.supplementTotal)} aus Nahrungsergänzung', key: Key('nutrient-supplement-${def.key}'), style: t.textTheme.bodySmall),
        if (fraction != null) ...[
          Text(referenceText(fraction), key: Key('nutrient-reference-${def.key}'), style: t.textTheme.bodySmall),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: LinearProgressIndicator(value: fraction.clamp(0.0, 1.0), minHeight: 4, color: t.colorScheme.outline, backgroundColor: t.colorScheme.surfaceContainerHighest),
          ),
        ],
      ]),
      trailing: Text(valueText, key: Key('nutrient-value-${def.key}'), style: t.textTheme.bodyMedium),
      onTap: () => _showSources(context, def, v),
    );
  }

  /// "Woher kommt das?": die groessten Beitraege, die Abdeckung und der Referenzwert.
  void _showSources(BuildContext context, NutrientDef def, MicroValue v) {
    final t = Theme.of(context);
    final ref = _referenceOf(def);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(def.label, key: const Key('nutrient-sheet-title'), style: t.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              v.unknown ? 'unbekannt' : '${v.complete ? '' : 'mindestens '}${formatMicro(def, v.total)}',
              key: const Key('nutrient-sheet-total'),
              style: t.textTheme.titleLarge,
            ),
            if (v.ingredients > 0)
              Text(
                v.unknown
                    ? 'Für keine der ${v.ingredients} Zutaten gibt es einen Wert.'
                    : v.complete
                        ? 'Alle ${v.ingredients} Zutaten haben einen Wert.'
                        : 'Aus ${v.withData} von ${v.ingredients} Zutaten mit Daten, der Rest ist unbekannt.',
                key: const Key('nutrient-sheet-coverage'),
                style: t.textTheme.bodySmall,
              ),
            const SizedBox(height: 12),
            if (v.contributions.isNotEmpty) Text('Woher kommt das?', style: t.textTheme.titleSmall),
            for (var i = 0; i < v.contributions.length && i < 3; i++)
              ListTile(
                key: Key('nutrient-contrib-$i'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(v.contributions[i].ingredient),
                subtitle: Text(v.contributions[i].mealTitle),
                trailing: Text(formatMicro(def, v.contributions[i].amount)),
              ),
            const Divider(),
            Text(
              def.euReference == null
                  ? 'Für diesen Wert gibt es keine Kennzeichnungs-Referenzmenge.'
                  : 'Kennzeichnungs-Referenzmenge: ${formatMicro(def, def.euReference!)} pro Tag${_overrides.containsKey(def.key) ? '. Du hast ${formatMicro(def, _overrides[def.key]!)} festgelegt' : ''}',
              key: const Key('nutrient-sheet-reference'),
              style: t.textTheme.bodySmall,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(spacing: 8, children: [
                TextButton(
                  key: const Key('nutrient-override-edit'),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final value = await _askOverride(context, def, _overrides[def.key] ?? def.euReference);
                    if (value != null) await _setOverride(def.key, value > 0 ? value : null);
                  },
                  child: Text(ref == null && !_referenceOn ? 'Eigenen Referenzwert festlegen' : 'Referenzwert ändern'),
                ),
                if (_overrides.containsKey(def.key))
                  TextButton(
                    key: const Key('nutrient-override-reset'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _setOverride(def.key, null);
                    },
                    child: const Text('Zurücksetzen'),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Future<double?> _askOverride(BuildContext context, NutrientDef def, double? initial) {
    final controller = TextEditingController(text: initial == null ? '' : formatQuantity(initial));
    return showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Referenzwert ${def.label}'),
        content: TextField(
          key: const Key('nutrient-override-field'),
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Pro Tag', suffixText: def.unit, helperText: 'Leer lassen oder 0: eigenen Wert entfernen'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(
            key: const Key('nutrient-override-ok'),
            onPressed: () => Navigator.pop(ctx, double.tryParse(controller.text.replaceAll(',', '.').trim()) ?? 0),
            child: const Text('Übernehmen'),
          ),
        ],
      ),
    );
  }
}

/// Mikronaehrstoffe einer Mahlzeit ("Mehr Nährwerte"), nur die Werte mit Daten, nach Gruppen.
Future<void> showMealMicros(BuildContext context, Meal meal, List<MealIngredient> ingredients) {
  final days = buildDailyMicros(
    [(id: meal.id, title: meal.title, eatenAtUtc: meal.eatenAt, servingsEaten: meal.servingsEaten, servingsMade: meal.servingsMade)],
    [for (final i in ingredients) (mealId: i.mealId, name: i.freeText ?? 'Zutat', micros: parseMicros(i.micros))],
  );
  final day = days.firstOrNull;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final t = Theme.of(ctx);
      final known = day == null ? const <NutrientDef>[] : [for (final n in nutrientRegistry) if (!day.valueOf(n.key).unknown) n];
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), shrinkWrap: true, children: [
            Text('Mehr Nährwerte', style: t.textTheme.titleMedium),
            Text(meal.title, style: t.textTheme.bodySmall),
            if (known.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                key: Key('meal-micros-none'),
                child: Text('Für diese Mahlzeit gibt es keine Mikronährstoffwerte.'),
              ),
            for (final g in NutrientGroup.values) ...[
              if (known.any((n) => n.group == g)) Padding(padding: const EdgeInsets.only(top: 12), child: Text(g.label, style: t.textTheme.titleSmall)),
              for (final n in known.where((n) => n.group == g))
                ListTile(
                  key: Key('meal-micro-${n.key}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(n.label),
                  subtitle: day!.valueOf(n.key).complete ? null : Text('aus ${day.valueOf(n.key).withData} von ${day.ingredients} Zutaten', style: t.textTheme.bodySmall),
                  trailing: Text('${day.valueOf(n.key).complete ? '' : 'mind. '}${formatMicro(n, day.valueOf(n.key).total)}'),
                ),
            ],
            const SizedBox(height: 8),
            Text(nutrientsLimitsText, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ]),
        ),
      );
    },
  );
}
