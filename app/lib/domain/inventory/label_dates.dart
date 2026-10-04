/// Datumserkennung fuer das MHD-Foto (Ausbau 1.14): Aus dem Text, den die Texterkennung auf dem Geraet von einem Etikett liest, werden
/// Datumsangaben gezogen, mit der Art ("mindestens haltbar bis" oder "zu verbrauchen bis"), soweit der Text davor sie verraet.
/// Reine Funktion ohne Plattformzugriff.
///
/// Wie bei jeder Texterkennung gilt: **nichts wird ungesehen uebernommen.** Die Oberflaeche zeigt die Funde zur Bestaetigung. Damit
/// Fehlgriffe selten sind, gelten strenge Regeln:
/// - nur vollstaendige Angaben (Tag, Monat, Jahr, auch "12 MAR 2027" oder "03.2027"; bei Monat und Jahr gilt der letzte Tag des Monats),
///   nie "12.03." ohne Jahr, das waere geraten;
/// - das Datum muss plausibel sein: hoechstens gut ein Jahr abgelaufen und hoechstens zehn Jahre in der Zukunft;
/// - Daten nach "hergestellt", "produziert" oder "abgepackt" sind keine Haltbarkeit und fallen weg;
/// - Funde mit Stichwort ("MHD", "mindestens haltbar bis", "best before", "verbrauchen bis" ...) stehen vor Funden ohne.
library;

/// Ein erkanntes Datum. [kind] ist `best_before` oder `use_by`, `null` ohne erkennbares Stichwort.
class LabelDate {
  const LabelDate({required this.date, required this.kind, required this.source});

  /// Kalendertag (UTC, Mitternacht).
  final DateTime date;
  final String? kind;

  /// Die Textstelle, aus der das Datum stammt, fuer die Anzeige ("MHD 12.03.2027").
  final String source;

  @override
  String toString() => 'LabelDate($date, $kind, "$source")';
}

const _months = {
  'JAN': 1, 'FEB': 2, 'MAR': 3, 'MÄR': 3, 'MAER': 3, 'APR': 4, 'MAI': 5, 'MAY': 5, 'JUN': 6, 'JUL': 7, 'AUG': 8, 'SEP': 9,
  'OKT': 10, 'OCT': 10, 'NOV': 11, 'DEZ': 12, 'DEC': 12,
};

final _fullNumeric = RegExp(r'(?<!\d)(\d{1,2})\s*[./\-]\s*(\d{1,2})\s*[./\-]\s*(\d{4}|\d{2})(?!\d)');
final _iso = RegExp(r'(?<!\d)(20\d{2})-(\d{1,2})-(\d{1,2})(?!\d)');
final _monthName = RegExp(r'(?<![A-ZÄÖÜ0-9])(?:(\d{1,2})\s*[.\-/]?\s*)?(JAN|FEB|MAR|MÄR|MAER|APR|MAI|MAY|JUN|JUL|AUG|SEP|OKT|OCT|NOV|DEZ|DEC)[A-ZÄÖÜ]*\.?\s*[.\-/]?\s*(\d{4}|\d{2})(?!\d)');
final _monthYear = RegExp(r'(?<![\d./\-])(\d{1,2})\s*[./]\s*(\d{4}|\d{2})(?![\d./\-])');

final _bestBeforeWord = RegExp(r'mhd|mindestens\s*haltbar|mindesthaltbarkeit|min\.?\s*haltbar|best[\s\-]*before|\bbbe?\b|\bexp(?:iry|ires?)?\b|haltbar\s*bis|ablaufdatum');
final _useByWord = RegExp(r'verbrauchen\s*bis|zu\s*verbrauchen|verbrauchsdatum|use[\s\-]*by|verbrauchen\s*(?:am|vor)');
final _productionWord = RegExp(r'hergestellt|herstellungs|produziert|produktions|prod\.?\s*date|\bprod\b|abgepackt|verpackt\s*am|packed|mfd|manufactured');

DateTime? _validDate(int y, int m, int d) {
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  final date = DateTime.utc(y, m, d);
  return date.month == m && date.day == d ? date : null;
}

int _year(String raw) {
  final y = int.parse(raw);
  return raw.length == 2 ? 2000 + y : y;
}

DateTime _lastDayOfMonth(int y, int m) => DateTime.utc(y, m + 1, 0);

/// Tippfehler der Texterkennung in Zahlengruppen berichtigen: ein "O" zwischen Ziffern ist eine Null, ein "l" oder "I" zwischen Ziffern eine Eins.
String _fixDigits(String text) {
  var out = text;
  for (var i = 0; i < 2; i++) {
    out = out.replaceAllMapped(RegExp(r'(?<=\d)[Oo](?=\d|[./\-])|(?<=[./\-])[Oo](?=\d)'), (_) => '0');
    out = out.replaceAllMapped(RegExp(r'(?<=\d)[lI](?=\d|[./\-])|(?<=[./\-])[lI](?=\d)|(?<![A-Za-z0-9])[lI](?=\d[./\-])'), (_) => '1');
  }
  return out;
}

/// Alle plausiblen Datumsangaben des Textes, die besten zuerst: erst mit Stichwort, dann ohne; innerhalb davon das spaetere Datum zuerst
/// (auf einer Packung steht meist neben dem Herstellungsdatum nur ein Haltbarkeitsdatum, und das liegt spaeter). Ohne Doppelte (gleicher Tag).
List<LabelDate> extractLabelDates(String text, {required DateTime today}) {
  final normalized = _fixDigits(text.replaceAll(RegExp(r'\s+'), ' ').trim());
  final upper = normalized.toUpperCase();
  final lower = normalized.toLowerCase();
  final lowest = DateTime.utc(today.year, today.month, today.day).subtract(const Duration(days: 400));
  final highest = DateTime.utc(today.year + 10, today.month, today.day);

  final found = <({DateTime date, int start, int end})>[];
  void add(DateTime? date, RegExpMatch m) {
    if (date == null || date.isBefore(lowest) || date.isAfter(highest)) return;
    found.add((date: date, start: m.start, end: m.end));
  }

  for (final m in _fullNumeric.allMatches(normalized)) {
    add(_validDate(_year(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!)), m);
  }
  for (final m in _iso.allMatches(normalized)) {
    add(_validDate(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!)), m);
  }
  for (final m in _monthName.allMatches(upper)) {
    final month = _months[m.group(2)!];
    if (month == null) continue;
    final year = _year(m.group(3)!);
    final day = m.group(1);
    add(day == null ? _lastDayOfMonth(year, month) : _validDate(year, month, int.parse(day)), m);
  }
  for (final m in _monthYear.allMatches(normalized)) {
    final month = int.parse(m.group(1)!);
    if (month < 1 || month > 12) continue;
    add(_lastDayOfMonth(_year(m.group(2)!), month), m);
  }

  final ranked = <({LabelDate d, int score})>[];
  final seen = <DateTime>{};
  for (final f in found) {
    final window = lower.substring((f.start - 45).clamp(0, lower.length), f.start);
    // das letzte Stichwort im Fenster gilt: es steht unmittelbar vor dem Datum
    int lastAt(RegExp r) => r.allMatches(window).fold(-1, (p, m) => m.start > p ? m.start : p);
    final production = lastAt(_productionWord);
    final useBy = lastAt(_useByWord);
    final bestBefore = lastAt(_bestBeforeWord);
    final keyword = useBy > bestBefore ? useBy : bestBefore;
    if (production >= 0 && production > keyword) continue; // Herstellungsdatum, keine Haltbarkeit
    final kind = keyword < 0 ? null : (useBy > bestBefore ? 'use_by' : 'best_before');
    if (!seen.add(f.date)) continue;
    final from = (f.start - (keyword < 0 ? 0 : (window.length - keyword))).clamp(0, normalized.length);
    ranked.add((d: LabelDate(date: f.date, kind: kind, source: normalized.substring(from, f.end).trim()), score: kind == null ? 1 : 2));
  }
  ranked.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    return byScore != 0 ? byScore : b.d.date.compareTo(a.d.date);
  });
  return [for (final r in ranked) r.d];
}
