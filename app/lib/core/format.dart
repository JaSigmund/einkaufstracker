import '../domain/nutrition/nutrition_targets.dart';
import '../domain/receipt/vienna_time.dart';

/// Geldbetrag in Euro mit Komma und Tausenderpunkt, z.B. 123456 -> "1.234,56 €", -86 -> "-0,86 €".
String formatEuro(int cents) {
  final neg = cents < 0;
  final abs = cents.abs();
  final euros = (abs ~/ 100).toString();
  final grouped = euros.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  final rest = (abs % 100).toString().padLeft(2, '0');
  return '${neg ? '-' : ''}$grouped,$rest €';
}

/// Liest eine Eingabe wie "2,49", "-0.86", "1.234,56 €" oder "3" als ganze Cent. Null bei ungueltiger Eingabe.
int? parseEuroCents(String input) {
  var s = input.replaceAll('€', '').replaceAll(' ', '').trim();
  if (s.isEmpty) return null;
  // "1.234,56": Punkt als Tausendertrenner, wenn ein Komma folgt
  if (s.contains(',')) s = s.replaceAll('.', '').replaceAll(',', '.');
  final m = RegExp(r'^(-)?(\d+)(?:\.(\d{1,2}))?$').firstMatch(s);
  if (m == null) return null;
  final cents = int.parse(m.group(2)!) * 100 + int.parse((m.group(3) ?? '').padRight(2, '0'));
  return m.group(1) == null ? cents : -cents;
}

/// UTC-Zeitpunkt als "02.07.2026, 19:51 Uhr" in Wiener Ortszeit.
String formatViennaDateTime(DateTime utc) {
  final d = utcToViennaLocal(utc);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year}, ${two(d.hour)}:${two(d.minute)} Uhr';
}

/// Menge ohne unnoetige Nachkommastellen: 2 -> "2", 0.986 -> "0,986".
String formatQuantity(double q) {
  final s = q == q.roundToDouble() ? q.toInt().toString() : q.toString();
  return s.replaceAll('.', ',');
}

/// Energie ohne Nachkommastellen mit Tausenderpunkt: 1480.4 -> "1.480 kcal".
String formatKcal(double kcal) {
  final grouped = kcal.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return '$grouped kcal';
}

/// Gramm fuer Naehrwerte: unter 10 mit einer Nachkommastelle ("5,4 g"), sonst ganzzahlig ("62 g").
String formatNutrientGrams(double g) {
  final s = g < 10 ? g.toStringAsFixed(1) : g.round().toString();
  return '${s.replaceAll('.', ',')} g';
}

/// Ein Naehrwert mit Einheit: kcal mit Tausenderpunkt, alles andere in Gramm.
String formatNutrient(NutrientKey key, double value) => key == NutrientKey.kcal ? formatKcal(value) : formatNutrientGrams(value);

/// Richtwert als Text: "1.800–2.200 kcal", "mindestens 60 g" oder "höchstens 6 g".
String formatTarget(NutrientKey key, NutrientTarget target) {
  String n(double v) => key == NutrientKey.kcal ? formatKcal(v).replaceAll(' kcal', '') : formatQuantity(v);
  final unit = key.unit;
  if (target.min != null && target.max != null) return '${n(target.min!)}–${n(target.max!)} $unit';
  if (target.min != null) return 'mindestens ${n(target.min!)} $unit';
  return 'höchstens ${n(target.max!)} $unit';
}

const _weekdayNames = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];
const _monthNamesLong = [
  'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
];

/// Ueberschrift eines Kalendertags: "Heute", "Gestern" oder "Mittwoch, 22. September" (mit Jahr, wenn es nicht das
/// laufende ist). [day] und [today] sind Kalendertage in Wiener Ortszeit.
String formatDayHeading(DateTime day, DateTime today) {
  final d = DateTime(day.year, day.month, day.day);
  final t = DateTime(today.year, today.month, today.day);
  final diff = t.difference(d).inDays;
  if (diff == 0) return 'Heute';
  if (diff == 1) return 'Gestern';
  final base = '${_weekdayNames[d.weekday - 1]}, ${d.day}. ${_monthNamesLong[d.month - 1]}';
  return d.year == t.year ? base : '$base ${d.year}';
}

const _monthNamesShort = ['Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'];

/// Monat als Ueberschrift: "Oktober 2026".
String formatMonthTitle(int year, int month) => '${_monthNamesLong[month - 1]} $year';

/// Woche als Zeitraum: "28. Sep – 4. Okt" (Montag bis Sonntag), mit Jahr, wenn es nicht das laufende ist.
String formatWeekRange(DateTime monday, DateTime today) {
  final end = DateTime(monday.year, monday.month, monday.day + 6);
  String part(DateTime d) => '${d.day}. ${_monthNamesShort[d.month - 1]}';
  final range = '${part(monday)} – ${part(end)}';
  return end.year == today.year ? range : '$range ${end.year}';
}

/// Masse aus Gramm: unter 1 kg als "320 g", sonst "3,1 kg".
String formatMassG(double g) {
  if (g < 1000) return '${g.round()} g';
  return '${(g / 1000).toStringAsFixed(1).replaceAll('.', ',')} kg';
}

/// Uhrzeit eines UTC-Zeitpunkts in Wiener Ortszeit als "19:05".
String formatViennaTime(DateTime utc) {
  final d = utcToViennaLocal(utc);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.hour)}:${two(d.minute)}';
}
