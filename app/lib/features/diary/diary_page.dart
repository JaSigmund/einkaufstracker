import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/clock.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../data/repositories/drink_repository.dart' show drinkMealMl;
import '../../domain/nutrition/daily_nutrition.dart';
import '../../domain/nutrition/frequent_meals.dart';
import '../../domain/nutrition/nutrition_targets.dart';
import '../../core/vienna_time.dart';
import 'balance_card.dart';
import 'meal_form_page.dart';
import 'meal_labels.dart';
import 'meal_photo.dart';
import 'meal_shopping_dialog.dart';
import 'nutrients_page.dart';
import 'product_nutrients_card.dart';
import 'target_rows.dart';

/// Inhalt des Tabs "Tagebuch" (Doku 15 §3.5, Phase 7b/7d): Mahlzeiten nach Tagen, je Tag mit Naehrwertsumme,
/// oben der Durchschnitt der laufenden Woche. Tage ohne Eintrag stehen nicht da: sie gelten als "nicht erfasst",
/// nicht als 0 kcal (FR-15).
class DiaryPage extends ConsumerWidget {
  const DiaryPage({super.key, this.now});

  /// Aktueller Zeitpunkt (UTC). Austauschbar fuer Tests.
  final DateTime? now;

  NutritionMeal _toMeal(Meal m) =>
      (id: m.id, eatenAtUtc: m.eatenAt, servingsEaten: m.servingsEaten, servingsMade: m.servingsMade, isEstimate: m.isEstimate);

  NutritionIngredient _toIngredient(MealIngredient i) => (
        mealId: i.mealId,
        kcal: i.kcal,
        proteinG: i.proteinG,
        fatG: i.fatG,
        carbsG: i.carbsG,
        sugarG: i.sugarG,
        fiberG: i.fiberG,
        saltG: i.saltG,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meals = ref.watch(mealsStreamProvider);
    final ingredients = ref.watch(mealIngredientsStreamProvider);
    // Richtwerte sind optional: bis sie geladen sind (oder falls das Laden scheitert) zeigt die Seite sie einfach nicht
    final targets = ref.watch(nutritionTargetsProvider).value ?? const NutritionTargets();
    final t = Theme.of(context);

    final Widget body;
    if (meals.isLoading || ingredients.isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (meals.hasError || ingredients.hasError) {
      body = Center(child: Text('Fehler: ${meals.error ?? ingredients.error}'));
    } else {
      body = _content(context, t, meals.value!, ingredients.value!, targets);
    }

    return Scaffold(
      body: body,
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('diary-add'),
        onPressed: () => context.push('/meal-form', extra: const MealFormArgs()),
        icon: const Icon(Icons.add),
        label: const Text('Mahlzeit'),
      ),
    );
  }

  Widget _content(BuildContext context, ThemeData t, List<Meal> meals, List<MealIngredient> ingredients, NutritionTargets targets) {
    if (meals.isEmpty) {
      // Scrollbar: auf kleinen Handys mit grosser Schrift passt der Hinweis sonst nicht in die Hoehe
      return LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: Center(
              child: Padding(
                // unten Platz fuer den FAB
                padding: const EdgeInsets.fromLTRB(32, 32, 32, 96),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.restaurant_menu_outlined, size: 48, color: t.colorScheme.outline),
                  const SizedBox(height: 12),
                  Text('Noch keine Mahlzeit', style: t.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  const Text(
                    'Halte fest, was du gekocht oder gegessen hast. Die Zutaten werden vom Inventar abgezogen, die Nährwerte pro Tag berechnet.',
                    textAlign: TextAlign.center,
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
    }

    final today = utcToViennaLocal(now ?? appClock.now().toUtc());
    final days = buildDailyNutrition([for (final m in meals) _toMeal(m)], [for (final i in ingredients) _toIngredient(i)]);
    final dayInfo = {for (final d in days) d.day: d};
    final weeks = buildWeeklyNutrition(days);
    final currentMonday = DateTime(today.year, today.month, today.day - (today.weekday - 1));
    final currentWeek = weeks.where((w) => w.weekStart == currentMonday).firstOrNull;

    // Mahlzeiten je Kalendertag (Wiener Zeit), neueste Tage zuerst, innerhalb eines Tages die spaetere zuerst.
    final byDay = <DateTime, List<Meal>>{};
    for (final m in meals) {
      final l = utcToViennaLocal(m.eatenAt);
      byDay.putIfAbsent(DateTime(l.year, l.month, l.day), () => []).add(m);
    }
    final dayKeys = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    final perMeal = <String, NutrientTotals>{};
    final ingredientsByMeal = <String, List<MealIngredient>>{};
    for (final i in ingredients) {
      ingredientsByMeal.putIfAbsent(i.mealId, () => []).add(i);
    }
    for (final m in meals) {
      final own = ingredientsByMeal[m.id] ?? const <MealIngredient>[];
      final single = buildDailyNutrition([_toMeal(m)], [for (final i in own) _toIngredient(i)]);
      perMeal[m.id] = single.isEmpty ? const NutrientTotals() : single.first.totals;
    }

    return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
      if (currentWeek != null)
        _weekCard(t, currentWeek, targets, partial: days.any((d) => !d.day.isBefore(currentWeek.weekStart) && d.dataQuality < 1)),
      BalanceCard(now: now),
      ProductNutrientsCard(now: now),
      Card(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: ListTile(
          key: const Key('diary-nutrients'),
          leading: const Icon(Icons.science_outlined),
          title: const Text('Nährstoffe'),
          subtitle: const Text('Vitamine, Mineralstoffe, Fettsäuren pro Tag und Woche'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/nutrients'),
        ),
      ),
      _frequentChips(context, t, meals),
      for (final day in dayKeys) ...[
        _dayHeader(t, day, today, dayInfo[day], targets),
        ..._dayMeals(context, day, byDay[day]!..sort((a, b) => b.eatenAt.compareTo(a.eatenAt)), ingredientsByMeal, perMeal),
      ],
    ]);
  }

  /// Die Eintraege eines Tages. Ab zwei Getraenken stehen sie in einer aufklappbaren Zeile unter den Mahlzeiten (ADR-049), sonst schieben fuenf Glaeser
  /// die Mahlzeiten aus dem Blick; in den Tagessummen zaehlen sie normal mit.
  List<Widget> _dayMeals(BuildContext context, DateTime day, List<Meal> meals, Map<String, List<MealIngredient>> ingredients, Map<String, NutrientTotals> perMeal) {
    Widget tile(Meal m) => _mealTile(context, m, ingredients[m.id] ?? const <MealIngredient>[], perMeal[m.id]!);
    final drinks = [for (final m in meals) if (m.mealType == 'drink') m];
    if (drinks.length < 2) return [for (final m in meals) tile(m)];
    final ml = drinks.fold<double>(0, (sum, m) => sum + drinkMealMl(m, ingredients[m.id] ?? const []));
    final kcal = drinks.fold<double>(0, (sum, m) => sum + perMeal[m.id]!.kcal);
    return [
      for (final m in meals) if (m.mealType != 'drink') tile(m),
      ExpansionTile(
        key: Key('day-drinks-${day.year}-${day.month}-${day.day}'),
        leading: Icon(mealTypeIcon('drink')),
        title: Text('Getränke · ${drinks.length} · ${formatQuantity(ml.roundToDouble())} ml · ${formatKcal(kcal)}'),
        children: [for (final m in drinks) tile(m)],
      ),
    ];
  }

  Widget _mealTile(BuildContext context, Meal m, List<MealIngredient> own, NutrientTotals totals) => ListTile(
        key: Key('meal-${m.id}'),
        leading: m.photoPath == null
            ? Icon(mealTypeIcon(m.mealType))
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: MealPhoto(meal: m, size: 44, placeholder: Icon(mealTypeIcon(m.mealType))),
              ),
        title: Text(m.title),
        subtitle: Text([
          formatViennaTime(m.eatenAt),
          mealTypeLabel(m.mealType),
          _countText(own.length),
          if (m.isEstimate) 'geschätzt',
        ].join(' · ')),
        trailing: own.any((i) => i.kcal != null) ? Text(formatKcal(totals.kcal)) : null,
        onTap: () => context.push('/meal-form', extra: MealFormArgs(existing: m)),
        onLongPress: () => _showMealActions(context, m, own),
      );

  /// "Nochmal essen": die haeufigsten Mahlzeiten der letzten 60 Tage, ein Tipp oeffnet eine Kopie (Doku 15 §3.3).
  Widget _frequentChips(BuildContext context, ThemeData t, List<Meal> meals) {
    final since = (now ?? appClock.now().toUtc()).subtract(const Duration(days: 60));
    final frequent = frequentMeals(
      [for (final m in meals) (id: m.id, title: m.title, eatenAtUtc: m.eatenAt)],
      since: since,
    );
    if (frequent.isEmpty) return const SizedBox.shrink();
    final byId = {for (final m in meals) m.id: m};
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Nochmal essen', style: t.textTheme.titleSmall),
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (var i = 0; i < frequent.length; i++)
            ActionChip(
              key: Key('frequent-meal-$i'),
              avatar: Icon(mealTypeIcon(byId[frequent[i].latestId]?.mealType ?? ''), size: 18),
              label: Text(frequent[i].title),
              onPressed: () {
                final template = byId[frequent[i].latestId];
                if (template != null) context.push('/meal-form', extra: MealFormArgs(template: template));
              },
            ),
        ]),
      ]),
    );
  }

  /// Aktionen zu einer Mahlzeit per langem Druck: Kopie als neue Mahlzeit oder als Rest ohne Abzug (Doku 15 §3.2).
  Future<void> _showMealActions(BuildContext context, Meal m, List<MealIngredient> own) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(key: const Key('meal-action-repeat'), leading: const Icon(Icons.replay), title: const Text('Nochmal erfassen'), subtitle: const Text('Kopie mit denselben Zutaten, Bestand wird wieder abgezogen'), onTap: () => Navigator.pop(ctx, 'repeat')),
          ListTile(key: const Key('meal-action-leftover'), leading: const Icon(Icons.takeout_dining_outlined), title: const Text('Als Rest erfassen'), subtitle: const Text('Gleiche Nährwerte, ohne erneuten Abzug vom Bestand'), onTap: () => Navigator.pop(ctx, 'leftover')),
          ListTile(key: const Key('meal-action-shopping'), leading: const Icon(Icons.add_shopping_cart_outlined), title: const Text('Fehlende Zutaten einkaufen'), subtitle: const Text('Zutaten, die im Bestand fehlen, auf die Einkaufsliste setzen'), onTap: () => Navigator.pop(ctx, 'shopping')),
          ListTile(key: const Key('meal-action-micros'), leading: const Icon(Icons.science_outlined), title: const Text('Mehr Nährwerte'), subtitle: const Text('Vitamine, Mineralstoffe und Fettsäuren dieser Mahlzeit'), onTap: () => Navigator.pop(ctx, 'micros')),
          ListTile(key: const Key('meal-action-edit'), leading: const Icon(Icons.edit_outlined), title: const Text('Bearbeiten'), onTap: () => Navigator.pop(ctx, 'edit')),
        ])),
      ),
    );
    if (action == null || !context.mounted) return;
    if (action == 'micros') {
      await showMealMicros(context, m, own);
      return;
    }
    if (action == 'shopping') {
      await showMealShoppingDialog(context, m, own);
      return;
    }
    final args = switch (action) {
      'repeat' => MealFormArgs(template: m),
      'leftover' => MealFormArgs(template: m, leftover: true),
      _ => MealFormArgs(existing: m),
    };
    context.push('/meal-form', extra: args);
  }

  String _countText(int n) => n == 1 ? '1 Zutat' : '$n Zutaten';

  Widget _weekCard(ThemeData t, WeekNutrition w, NutritionTargets targets, {required bool partial}) {
    final a = w.averagePerDay;
    return Card(
      key: const Key('diary-week'),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Diese Woche', style: t.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text('Ø ${formatKcal(a.kcal)} pro erfasstem Tag', key: const Key('diary-week-kcal'), style: t.textTheme.titleLarge),
          Text(
            '${formatNutrientGrams(a.proteinG)} Eiweiß · ${formatNutrientGrams(a.fatG)} Fett · ${formatNutrientGrams(a.carbsG)} Kohlenhydrate',
            style: t.textTheme.bodySmall,
          ),
          TargetRows(totals: a, targets: targets, keyPrefix: 'week', partial: partial),
          const SizedBox(height: 4),
          Text(
            '${w.daysLogged == 1 ? '1 Tag' : '${w.daysLogged} Tage'} erfasst${w.hasEstimates ? ', enthält Schätzwerte' : ''}',
            style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
          ),
        ]),
      ),
    );
  }

  Widget _dayHeader(ThemeData t, DateTime day, DateTime today, DayNutrition? info, NutritionTargets targets) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(formatDayHeading(day, today), style: t.textTheme.titleMedium),
        if (info != null && info.ingredients > 0) ...[
          Text(
            '${formatKcal(info.totals.kcal)} · ${formatNutrientGrams(info.totals.proteinG)} Eiweiß · '
            '${formatNutrientGrams(info.totals.fatG)} Fett · ${formatNutrientGrams(info.totals.carbsG)} KH',
            key: Key('day-totals-${day.year}-${day.month}-${day.day}'),
            style: t.textTheme.bodySmall,
          ),
          TargetRows(totals: info.totals, targets: targets, keyPrefix: 'day-${day.year}-${day.month}-${day.day}', partial: info.dataQuality < 1),
          if (info.dataQuality < 1 || info.hasEstimates)
            Text(
              [
                if (info.dataQuality < 1) 'Nährwerte für ${info.ingredientsWithNutrients} von ${info.ingredients} Zutaten bekannt',
                if (info.hasEstimates) 'enthält Schätzwerte',
              ].join(' · '),
              key: Key('day-quality-${day.year}-${day.month}-${day.day}'),
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
            ),
        ],
      ]),
    );
  }
}
