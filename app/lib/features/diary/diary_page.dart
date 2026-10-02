import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../domain/nutrition/daily_nutrition.dart';
import '../../domain/receipt/vienna_time.dart';
import 'meal_form_page.dart';
import 'meal_labels.dart';

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
    final t = Theme.of(context);

    final Widget body;
    if (meals.isLoading || ingredients.isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (meals.hasError || ingredients.hasError) {
      body = Center(child: Text('Fehler: ${meals.error ?? ingredients.error}'));
    } else {
      body = _content(context, t, meals.value!, ingredients.value!);
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

  Widget _content(BuildContext context, ThemeData t, List<Meal> meals, List<MealIngredient> ingredients) {
    if (meals.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
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
      );
    }

    final today = utcToViennaLocal(now ?? DateTime.now().toUtc());
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
      if (currentWeek != null) _weekCard(t, currentWeek),
      for (final day in dayKeys) ...[
        _dayHeader(t, day, today, dayInfo[day]),
        for (final m in (byDay[day]!..sort((a, b) => b.eatenAt.compareTo(a.eatenAt))))
          ListTile(
            key: Key('meal-${m.id}'),
            leading: Icon(mealTypeIcon(m.mealType)),
            title: Text(m.title),
            subtitle: Text([
              formatViennaTime(m.eatenAt),
              mealTypeLabel(m.mealType),
              _countText((ingredientsByMeal[m.id] ?? const []).length),
              if (m.isEstimate) 'geschätzt',
            ].join(' · ')),
            trailing: (ingredientsByMeal[m.id] ?? const []).any((i) => i.kcal != null) ? Text(formatKcal(perMeal[m.id]!.kcal)) : null,
            onTap: () => context.push('/meal-form', extra: MealFormArgs(existing: m)),
          ),
      ],
    ]);
  }

  String _countText(int n) => n == 1 ? '1 Zutat' : '$n Zutaten';

  Widget _weekCard(ThemeData t, WeekNutrition w) {
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
          const SizedBox(height: 4),
          Text(
            '${w.daysLogged == 1 ? '1 Tag' : '${w.daysLogged} Tage'} erfasst${w.hasEstimates ? ', enthält Schätzwerte' : ''}',
            style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline),
          ),
        ]),
      ),
    );
  }

  Widget _dayHeader(ThemeData t, DateTime day, DateTime today, DayNutrition? info) {
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
          if (info.dataQuality < 1 || info.hasEstimates)
            Text(
              [
                if (info.dataQuality < 1) 'Nährwerte für ${info.ingredientsWithNutrients} von ${info.ingredients} Zutaten bekannt',
                if (info.hasEstimates) 'enthält Schätzwerte',
              ].join(' · '),
              key: Key('day-quality-${day.year}-${day.month}-${day.day}'),
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline),
            ),
        ],
      ]),
    );
  }
}
