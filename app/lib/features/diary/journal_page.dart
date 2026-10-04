import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../data/repositories/meal_repository.dart';
import '../../domain/nutrition/daily_nutrition.dart';
import '../../domain/nutrition/journal.dart';
import '../../domain/nutrition/journal_report.dart';
import '../../domain/nutrition/nutrition_targets.dart';
import '../../domain/nutrition/unrecorded_estimate.dart';
import '../../domain/receipt/vienna_time.dart';
import 'journal_pdf.dart';
import 'meal_form_page.dart';
import 'meal_labels.dart';
import 'meal_photo.dart';
import 'target_rows.dart';

/// KV-Schluessel: Schaetzung des Nicht-Erfassten im Journal (`true`/`false`, Standard aus).
const journalEstimateKey = 'journal_estimate_unrecorded';

/// Ring um einen Anteil (0 bis 1) in einer Farbe, ohne Bewertung (keine Ampel).
class _RingPainter extends CustomPainter {
  _RingPainter({required this.fraction, required this.color, required this.track, this.stroke = 3});

  final double fraction;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inner = rect.deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(inner, 0, 6.2831853, false, base);
    if (fraction <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(inner, -1.5707963, 6.2831853 * fraction, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.fraction != fraction || old.color != color || old.track != track || old.stroke != stroke;
}

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
  var _estimateOn = false;
  var _exporting = false;

  DateTime get _today {
    final l = utcToViennaLocal(widget.now ?? DateTime.now().toUtc());
    return DateTime(l.year, l.month, l.day);
  }

  @override
  void initState() {
    super.initState();
    _month = DateTime(_today.year, _today.month);
    _loadEstimateSetting();
  }

  Future<void> _loadEstimateSetting() async {
    try {
      final on = await ref.read(databaseProvider).getKv(journalEstimateKey) == 'true';
      if (mounted && on != _estimateOn) setState(() => _estimateOn = on);
    } catch (_) {
      // ohne lesbare Ablage bleibt die Schaetzung aus
    }
  }

  Future<void> _setEstimate(bool on) async {
    setState(() => _estimateOn = on);
    try {
      await ref.read(databaseProvider).setKv(journalEstimateKey, on.toString());
    } catch (_) {
      // nur eine Komfortfunktion
    }
  }

  /// Den angezeigten Monat als PDF teilen (Teilen-Menue, im Browser Download). Fotos kommen mit, soweit sie erreichbar sind.
  Future<void> _exportPdf(List<Meal> meals, List<MealIngredient> ingredients) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final report = buildJournalReport(
        year: _month.year,
        month: _month.month,
        meals: [
          for (final m in meals)
            (
              id: m.id,
              eatenAtUtc: m.eatenAt,
              title: m.title,
              mealType: m.mealType,
              servingsEaten: m.servingsEaten,
              servingsMade: m.servingsMade,
              isEstimate: m.isEstimate,
              hasPhoto: m.photoPath != null,
            ),
        ],
        ingredients: [
          for (final i in ingredients)
            (mealId: i.mealId, kcal: i.kcal, proteinG: i.proteinG, fatG: i.fatG, carbsG: i.carbsG, sugarG: i.sugarG, fiberG: i.fiberG, saltG: i.saltG),
        ],
      );
      if (report == null) {
        messenger.showSnackBar(const SnackBar(content: Text('In diesem Monat wurde nichts erfasst.')));
        return;
      }
      final byId = {for (final m in meals) m.id: m};
      final photoService = ref.read(mealPhotoServiceProvider);
      final photos = <String, Uint8List>{};
      for (final d in report.days) {
        final meal = d.photoMealId == null ? null : byId[d.photoMealId!];
        if (meal == null) continue;
        try {
          // ein nicht erreichbares Foto (kein Netz, anderes Geraet) laesst nur dieses Foto weg, nicht den Export
          final bytes = await photoService.bytes(meal).timeout(const Duration(seconds: 8));
          final small = bytes == null ? null : shrinkPhotoForPdf(bytes);
          if (small != null) photos[meal.id] = small;
        } catch (_) {}
      }
      final regular = (await rootBundle.load('assets/fonts/Roboto-Regular.ttf')).buffer.asUint8List();
      final bold = (await rootBundle.load('assets/fonts/Roboto-Bold.ttf')).buffer.asUint8List();
      final pdf = await buildJournalPdf(report, regularFont: regular, boldFont: bold, createdAtUtc: widget.now ?? DateTime.now().toUtc(), photos: photos);
      final name = 'Essenstagebuch ${_month.year}-${_month.month.toString().padLeft(2, '0')}.pdf';
      await ref.read(shareFileProvider)(bytes: pdf, fileName: name, mimeType: 'application/pdf', text: 'Essenstagebuch ${formatMonthTitle(_month.year, _month.month)}');
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('PDF-Export nicht möglich.')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
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
    // Richtwerte sind optional: bis sie geladen sind (oder falls das Laden scheitert) zeigt die Seite sie einfach nicht
    final targets = ref.watch(nutritionTargetsProvider).value ?? const NutritionTargets();
    final t = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Journal')),
      body: (mealsAsync.isLoading || ingredientsAsync.isLoading)
          ? const Center(child: CircularProgressIndicator())
          : (mealsAsync.hasError || ingredientsAsync.hasError)
              ? Center(child: Text('Fehler: ${mealsAsync.error ?? ingredientsAsync.error}'))
              : _content(context, t, mealsAsync.value!, ingredientsAsync.value!, targets),
    );
  }

  Widget _content(BuildContext context, ThemeData t, List<Meal> meals, List<MealIngredient> ingredients, NutritionTargets targets) {
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
    // Tageswerte fuer die Tageskarte (Makros gegen Richtwerte) und die Energiedichte des Verlaufs fuer die Schaetzung
    final nutritionByDay = {
      for (final d in buildDailyNutrition(
        [for (final m in meals) (id: m.id, eatenAtUtc: m.eatenAt, servingsEaten: m.servingsEaten, servingsMade: m.servingsMade, isEstimate: m.isEstimate)],
        nutritionIngredients,
      ))
        d.day: d,
    };
    final unrecorded = [for (final i in ingredients) (mealId: i.mealId, grams: ingredientGrams(i), kcal: i.kcal)];
    final historyDensity = kcalPerGram(unrecorded);
    final kcalRef = targets[NutrientKey.kcal]?.reference;
    final monthMaxKcal = days.fold<double>(0, (m, d) => (d.kcal ?? 0) > m ? d.kcal! : m);
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
      _grid(t, days, byId, kcalRef, monthMaxKcal),
      const SizedBox(height: 4),
      Text('Leere Tage sind nicht erfasst, das ist nicht dasselbe wie 0 kcal.', key: const Key('journal-hint'), style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
      if (days.any((d) => d.logged))
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('journal-export-pdf'),
            onPressed: _exporting ? null : () => _exportPdf(meals, ingredients),
            icon: _exporting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf_outlined),
            label: Text(_exporting ? 'PDF wird erstellt …' : 'Monat als PDF teilen'),
          ),
        ),
      const SizedBox(height: 12),
      if (selectedDay != null)
        _dayCard(context, t, selectedDay, byId,
            targets: targets,
            totals: nutritionByDay[selectedDay.day],
            estimate: estimateUnrecorded(
              [for (final m in meals) if (selectedDay.mealIds.contains(m.id)) (id: m.id, eatenAtUtc: m.eatenAt, servingsEaten: m.servingsEaten, servingsMade: m.servingsMade, isEstimate: m.isEstimate)],
              unrecorded,
              historyKcalPerGram: historyDensity,
            )),
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

  Widget _grid(ThemeData t, List<JournalDay> days, Map<String, Meal> byId, double? kcalRef, double monthMaxKcal) {
    final offset = DateTime(_month.year, _month.month, 1).weekday - 1;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 7,
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      children: [
        for (var i = 0; i < offset; i++) const SizedBox.shrink(),
        for (final d in days) _cell(t, d, byId, kcalRef, monthMaxKcal),
      ],
    );
  }

  Widget _cell(ThemeData t, JournalDay d, Map<String, Meal> byId, double? kcalRef, double monthMaxKcal) {
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

    // Ring (gegen den kcal-Richtwert) oder, ohne Richtwert, ein Balken relativ zum Tag mit den meisten kcal des Monats; nur bei
    // bekannten kcal. Ein Tag ohne bekannte Werte bekommt weder Ring noch Balken (unbekannt ist nicht 0).
    final ringFrac = ringFraction(d.kcal, kcalRef);
    final barFrac = kcalRef == null ? ringFraction(d.kcal, monthMaxKcal > 0 ? monthMaxKcal : null) : null;
    final Widget? marker = ringFrac != null
        ? Positioned(
            right: 3,
            bottom: 3,
            child: SizedBox(
              key: Key('journal-ring-${d.day.day}'),
              width: 16,
              height: 16,
              child: CustomPaint(painter: _RingPainter(fraction: ringFrac, color: t.colorScheme.primary, track: t.colorScheme.surface.withValues(alpha: 0.8), stroke: 3)),
            ),
          )
        : barFrac != null
            ? Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: FractionallySizedBox(
                    key: Key('journal-bar-${d.day.day}'),
                    widthFactor: barFrac,
                    child: Container(height: 4, color: t.colorScheme.primary),
                  ),
                ),
              )
            : null;

    final Widget face = photoMeal != null
        ? Stack(fit: StackFit.expand, children: [
            MealPhoto(meal: photoMeal, placeholder: const Icon(Icons.restaurant, size: 18), fit: BoxFit.cover),
            Positioned(left: 4, top: 2, child: number),
            ?marker,
          ])
        : Container(
            color: d.logged ? t.colorScheme.primaryContainer : null,
            alignment: Alignment.center,
            child: Stack(fit: StackFit.expand, alignment: Alignment.center, children: [
              Center(
                child: d.logged
                    ? Column(mainAxisSize: MainAxisSize.min, children: [number, Icon(mealTypeIcon(byId[d.mealIds.first]?.mealType ?? ''), size: 14, color: t.colorScheme.onPrimaryContainer)])
                    : number,
              ),
              ?marker,
            ]),
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

  Widget _dayCard(
    BuildContext context,
    ThemeData t,
    JournalDay d,
    Map<String, Meal> byId, {
    required NutritionTargets targets,
    required DayNutrition? totals,
    required UnrecordedEstimate? estimate,
  }) {
    final kcal = d.kcal;
    final kcalRef = targets[NutrientKey.kcal]?.reference;
    final ringFrac = ringFraction(kcal, kcalRef);
    final partial = totals != null && totals.dataQuality < 1;
    return Card(
      key: const Key('journal-day-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(formatDayHeading(d.day, _today), style: t.textTheme.titleSmall),
          if (!d.logged)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text('Nichts erfasst.', key: const Key('journal-day-empty'), style: t.textTheme.bodyMedium))
          else ...[
            Row(children: [
              if (ringFrac != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12, top: 4),
                  child: SizedBox(
                    key: const Key('journal-day-ring'),
                    width: 44,
                    height: 44,
                    child: Stack(alignment: Alignment.center, children: [
                      CustomPaint(
                        size: const Size(44, 44),
                        painter: _RingPainter(fraction: ringFrac, color: t.colorScheme.primary, track: t.colorScheme.surfaceContainerHighest, stroke: 5),
                      ),
                      Text('${(ringFrac * 100).round()} %', style: t.textTheme.labelSmall),
                    ]),
                  ),
                ),
              Expanded(
                child: Text(
                  [if (kcal != null) formatKcal(kcal) else 'Nährwerte unbekannt', if (d.hasEstimates) 'enthält Schätzwerte'].join(' · '),
                  key: const Key('journal-day-totals'),
                  style: t.textTheme.bodySmall,
                ),
              ),
            ]),
            if (totals != null) TargetRows(totals: totals.totals, targets: targets, keyPrefix: 'journal-${d.day.year}-${d.day.month}-${d.day.day}', partial: partial),
            if (estimate != null) ...[
              SwitchListTile(
                key: const Key('journal-estimate-toggle'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Nicht Erfasstes schätzen'),
                subtitle: const Text('Zutaten ohne Nährwerte, aber mit Menge, grob dazurechnen (getrennt und als Schätzung)'),
                value: _estimateOn,
                onChanged: _setEstimate,
              ),
              if (_estimateOn)
                Text(
                  _estimateText(estimate),
                  key: const Key('journal-estimate-text'),
                  style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline),
                ),
            ],
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

  String _estimateText(UnrecordedEstimate e) {
    final basis = switch (e.basis) {
      DensityBasis.day => 'nach dem Durchschnitt dieses Tages',
      DensityBasis.history => 'nach dem Durchschnitt deiner erfassten Tage',
      DensityBasis.fallback => 'nach einem Faustwert für ein durchschnittliches Essen',
    };
    final parts = <String>[
      if (e.ingredients > 0)
        'Dazu etwa ${formatKcal(e.kcal)} aus ${e.ingredients == 1 ? '1 Zutat' : '${e.ingredients} Zutaten'} ohne Nährwerte (${formatMassG(e.grams)}), geschätzt $basis.'
      else
        'Keine Zutat ohne Nährwerte hat eine bekannte Menge, deshalb gibt es nichts zu schätzen.',
      if (e.withoutAmount > 0) '${e.withoutAmount == 1 ? '1 weitere Zutat' : '${e.withoutAmount} weitere Zutaten'} ohne Nährwerte und ohne Menge ${e.withoutAmount == 1 ? 'bleibt' : 'bleiben'} unberücksichtigt.',
    ];
    return parts.join(' ');
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
