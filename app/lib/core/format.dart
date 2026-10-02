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

/// Uhrzeit eines UTC-Zeitpunkts in Wiener Ortszeit als "19:05".
String formatViennaTime(DateTime utc) {
  final d = utcToViennaLocal(utc);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.hour)}:${two(d.minute)}';
}
