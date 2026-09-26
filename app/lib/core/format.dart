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
