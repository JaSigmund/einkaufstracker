import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../domain/nutrition/journal.dart';
import '../../domain/receipt/vienna_time.dart';
import 'meal_form_page.dart';
import 'meal_labels.dart';
import 'meal_photo.dart';

/// Journal (Phase 7e, Doku 15 §3.6): Monats-Mosaik mit den Fotos der Tage, darunter der gewaehlte Tag und der
/// Rueckblick auf seine Woche. Tage ohne Eintrag bleiben leer: "nicht erfasst", nicht "0 kcal" (FR-15).
class JournalPage extends ConsumerStatefulWidget {
  const JournalPage({super.key, this.now});

  /// Aktueller Zeitpunkt (UTC), austauschbar fuer Tests.
  final DateTime? now;

  @override
  ConsumerState<JournalPage> createState() => _JournalPageState();
}

class _JournalPageState extends ConsumerState<JournalPage> {
  late DateTime _month; // erster Tag des angezeigten Monats
  DateTime? _selected;
  var _initialSelectionDone = false;

  DateTime get _today {
    final l = utcToViennaLocal(widget.now ?? DateTime.now().toUtc());
    return DateTime(l.year, l.month, l.day);
  }

  @override
  void initState() {
    super.initState();
    _month = DateTime(_today.year, _today.month);
  }

  bool get _isCurrentMonth => _month.year == _today.year && _month.month == _today.month;

  void _shiftMonth(int delta) => setState(() {
        _month = DateTime(_month.year, _month.month + delta);
        _selected = null;
        _initialSelectionDone = false;
      });

  /// Gewaehlt ist heute (im laufenden Monat), sonst der letzte erfasste Tag des Monats.
  DateTime? _defaultSelection(List<JournalDay> days) {
    if (_isCurrentMonth) return _today;
    return days.lastWhere((d) => d.logged, orElse: () => days.first).day;
  }

  @override
  Widget build(BuildContext context) {
    final mealsAsync = ref.watch(mealsStreamProvider);
    final ingredientsAsync = ref.watch(mealIngredientsStreamProvider);
    final t = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Journal')),
      body: (mealsAsync.isLoading || ingredientsAsync.isLoading)
          ? const Center(child: CircularProgressIndicator())
          : (mealsAsync.hasError || ingredientsAsync.hasError)
              ? Center(child: Text('Fehler: ${mealsAsync.error ?? ingredientsAsync.error}'))
              : _content(context, t, mealsAsync.value!, ingredientsAsync.value!),
    );
  }

  Widget _content(BuildContext context, ThemeData t, List<Meal> meals, List<MealIngredient> ingredients) {
    final nutritionIngredients = [
      for (final i in ingredients)
        (
          mealId: i.mealId,
          kcal: i.kcal,
          proteinG: i.proteinG,
          fatG: i.fatG,
          carbsG: i.carbsG,
          sugarG: i.sugarG,
          fiberG: i.fiberG,
          saltG: i.saltG,
        ),
    ];
    final journalMeals = [
      for (final m in meals)
        (
          id: m.id,
          eatenAtUtc: m.eatenAt,
          title: m.title,
          hasPhoto: m.photoPath != null,
          servingsEaten: m.servingsEaten,
          servingsMade: m.servingsMade,
          isEstimate: m.isEstimate,
        ),
    ];
    final byId = {for (final m in meals) m.id: m};
    final days = buildMonthJournal(year: _month.year, month: _month.month, meals: journalMeals, ingredients: nutritionIngredients);
    if (!_initialSelectionDone) {
      _selected = _defaultSelection(days);
      _initialSelectionDone = true;
    }
    final selected = _selected;
    final selectedDay = selected != null && selected.year == _month.year && selected.month == _month.month ? days[selected.day - 1] : null;
    final weekStart = selected == null ? null : DateTime(selected.year, selected.month, selected.day - (selected.weekday - 1));
    final review = weekStart == null ? null : buildWeekReview(weekStart: weekStart, meals: journalMeals, ingredients: nutritionIngredients);

    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
      _monthHeader(t),
      const SizedBox(height: 8),
      _weekdayRow(t),
      const SizedBox(height: 4),
      _grid(t, days, byId),
      const SizedBox(height: 4),
      Text('Leere Tage sind nicht erfasst, das ist nicht dasselbe wie 0 kcal.', key: const Key('journal-hint'), style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
      const SizedBox(height: 16),
      if (selectedDay != null) _dayCard(context, t, selectedDay, byId),
      const SizedBox(height: 12),
      if (weekStart != null) _weekCard(t, weekStart, review, byId),
    ]);
  }

  Widget _monthHeader(ThemeData t) => Row(children: [
        IconButton(key: const Key('journal-prev'), tooltip: 'Vorheriger Monat', icon: const Icon(Icons.chevron_left), onPressed: () => _shiftMonth(-1)),
        Expanded(child: Text(formatMonthTitle(_month.year, _month.month), key: const Key('journal-month'), textAlign: TextAlign.center, style: t.textTheme.titleMedium)),
        IconButton(
          key: const Key('journal-next'),
          tooltip: 'Nächster Monat',
          icon: const Icon(Icons.chevron_right),
          onPressed: _isCurrentMonth ? null : () => _shiftMonth(1),
        ),
      ]);

  Widget _weekdayRow(ThemeData t) => Row(children: [
        for (final d in const ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'])
          Expanded(child: Center(child: Text(d, style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.outline)))),
      ]);

  Widget _grid(ThemeData t, List<JournalDay> days, Map<String, Meal> byId) {
    final offset = DateTime(_month.year, _month.month, 1).weekday - 1;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 7,
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      children: [
        for (var i = 0; i < offset; i++) const SizedBox.shrink(),
        for (final d in days) _cell(t, d, byId),
      ],
    );
  }

  Widget _cell(ThemeData t, JournalDay d, Map<String, Meal> byId) {
    final isSelected = _selected != null && _selected!.year == d.day.year && _selected!.month == d.day.month && _selected!.day == d.day.day;
    final isToday = d.day == _today;
    final photoMeal = d.photoMealId == null ? null : byId[d.photoMealId!];
    final number = Text(
      '${d.day.day}',
      style: t.textTheme.labelMedium?.copyWith(
        fontWeight: isToday ? FontWeight.bold : null,
        color: photoMeal != null ? Colors.white : (d.logged ? t.colorScheme.onPrimaryContainer : t.colorScheme.outline),
        shadows: photoMeal != null ? const [Shadow(blurRadius: 3)] : null,
      ),
    );

    final Widget face = photoMeal != null
        ? Stack(fit: StackFit.expand, children: [
            MealPhoto(meal: photoMeal, placeholder: const Icon(Icons.restaurant, size: 18), fit: BoxFit.cover),
            Positioned(left: 4, top: 2, child: number),
          ])
        : Container(
            color: d.logged ? t.colorScheme.primaryContainer : null,
            alignment: Alignment.center,
            child: d.logged
                ? Column(mainAxisSize: MainAxisSize.min, children: [number, Icon(mealTypeIcon(byId[d.mealIds.first]?.mealType ?? ''), size: 14, color: t.colorScheme.onPrimaryContainer)])
                : number,
          );

    return InkWell(
      key: Key('journal-day-${d.day.day}'),
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _selected = d.day),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? t.colorScheme.primary : t.colorScheme.outlineVariant, width: isSelected ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: face,
      ),
    );
  }

  Widget _dayCard(BuildContext context, ThemeData t, JournalDay d, Map<String, Meal> byId) {
    final kcal = d.kcal;
    return Card(
      key: const Key('journal-day-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(formatDayHeading(d.day, _today), style: t.textTheme.titleSmall),
          if (!d.logged)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text('Nichts erfasst.', key: const Key('journal-day-empty'), style: t.textTheme.bodyMedium))
          else ...[
            Text(
              [if (kcal != null) formatKcal(kcal) else 'Nährwerte unbekannt', if (d.hasEstimates) 'enthält Schätzwerte'].join(' · '),
              key: const Key('journal-day-totals'),
              style: t.textTheme.bodySmall,
            ),
            for (final id in d.mealIds)
              if (byId[id] case final m?)
                ListTile(
                  key: Key('journal-meal-$id'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(mealTypeIcon(m.mealType)),
                  title: Text(m.title),
                  subtitle: Text('${formatViennaTime(m.eatenAt)} · ${mealTypeLabel(m.mealType)}'),
                  onTap: () => context.push('/meal-form', extra: MealFormArgs(existing: m)),
                ),
          ],
        ]),
      ),
    );
  }

  Widget _weekCard(ThemeData t, DateTime weekStart, WeekReview? r, Map<String, Meal> byId) {
    return Card(
      key: const Key('journal-week'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Wochenrückblick, ${formatWeekRange(weekStart, _today)}', style: t.textTheme.titleSmall),
          const SizedBox(height: 4),
          if (r == null)
            Text('In dieser Woche wurde nichts erfasst.', key: const Key('journal-week-empty'), style: t.textTheme.bodyMedium)
          else ...[
            Text(
              '${r.mealCount == 1 ? '1 Mahlzeit' : '${r.mealCount} Mahlzeiten'} an ${r.daysLogged} von 7 Tagen',
              key: const Key('journal-week-count'),
              style: t.textTheme.bodyMedium,
            ),
            if (r.averagePerDay.kcal > 0)
              Text(
                'Ø ${formatKcal(r.averagePerDay.kcal)} pro erfasstem Tag${r.hasEstimates ? ', enthält Schätzwerte' : ''}',
                key: const Key('journal-week-kcal'),
                style: t.textTheme.bodySmall,
              ),
            if (r.topMeals.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Am häufigsten: ${[for (final m in r.topMeals) m.count > 1 ? '${m.title} (${m.count}×)' : m.title].join(', ')}',
                  key: const Key('journal-week-top'),
                  style: t.textTheme.bodySmall,
                ),
              ),
            if (r.photoMealIds.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 64,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final id in r.photoMealIds)
                    if (byId[id] case final m?)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ClipRRect(
                          key: Key('journal-week-photo-$id'),
                          borderRadius: BorderRadius.circular(8),
                          child: MealPhoto(meal: m, size: 64, placeholder: Icon(mealTypeIcon(m.mealType))),
                        ),
                      ),
                ]),
              ),
            ],
          ],
        ]),
      ),
    );
  }
}
