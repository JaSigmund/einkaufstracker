import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/format.dart';
import '../../domain/nutrition/journal_report.dart';
import 'meal_labels.dart';

/// PDF des Monats aus dem Essenstagebuch (Ausbau 1.12): Zusammenfassung, Kalenderraster und je Tag die Mahlzeiten mit kcal, auf
/// Wunsch mit einem Foto je Tag. Gedacht zum Weitergeben, etwa an eine Ernaehrungsberaterin oder einen Arzt.
///
/// Die Zahlen kommen aus [JournalReport], also genau so wie im Journal der App: nicht erfasste Tage sind leer (nicht 0 kcal),
/// Tage ohne bekannte Naehrwerte tragen keine kcal-Angabe, der Durchschnitt geht nur ueber Tage mit bekannten kcal.

const _weekdayNames = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];
const _accent = PdfColor.fromInt(0xFF2E7D32);
const _accentLight = PdfColor.fromInt(0xFFE3F1E4);
const _grey = PdfColors.grey700;
const _greyLight = PdfColors.grey400;

String _two(int v) => v.toString().padLeft(2, '0');

String _dayHeading(DateTime d) => '${_weekdayNames[d.weekday - 1]}, ${_two(d.day)}.${_two(d.month)}.${d.year}';

String _kcalPlain(double kcal) => kcal.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');

/// Foto fuer das PDF verkleinern (Kantenlaenge hoechstens [maxEdge]) und als JPEG neu kodieren, damit ein Monat mit 30 Fotos das
/// PDF nicht auf zig Megabyte aufblaeht. `null`, wenn die Bytes kein lesbares Bild sind (dann bleibt das Foto weg).
Uint8List? shrinkPhotoForPdf(Uint8List bytes, {int maxEdge = 360}) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final longest = decoded.width > decoded.height ? decoded.width : decoded.height;
    final scaled = longest > maxEdge
        ? img.copyResize(decoded, width: decoded.width >= decoded.height ? maxEdge : null, height: decoded.height > decoded.width ? maxEdge : null)
        : decoded;
    return Uint8List.fromList(img.encodeJpg(scaled, quality: 78));
  } catch (_) {
    return null;
  }
}

/// Baut das PDF. [photos] sind schon verkleinerte Bilder (siehe [shrinkPhotoForPdf]) je Mahlzeit-ID, die den Tag vertreten.
/// [compress] nur fuer Tests (lesbarer Dateiaufbau).
Future<Uint8List> buildJournalPdf(
  JournalReport report, {
  required Uint8List regularFont,
  required Uint8List boldFont,
  required DateTime createdAtUtc,
  Map<String, Uint8List> photos = const {},
  bool compress = true,
}) async {
  final regular = pw.Font.ttf(ByteData.sublistView(regularFont));
  final bold = pw.Font.ttf(ByteData.sublistView(boldFont));
  final title = 'Essenstagebuch ${formatMonthTitle(report.year, report.month)}';
  final doc = pw.Document(title: title, author: 'Einkaufstracker', creator: 'Einkaufstracker', compress: compress);

  pw.TextStyle style({double size = 10, bool isBold = false, PdfColor? color}) =>
      pw.TextStyle(fontSize: size, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color);

  doc.addPage(pw.MultiPage(
    pageTheme: pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 48),
      theme: pw.ThemeData.withFont(base: regular, bold: bold, italic: regular, boldItalic: bold),
    ),
    footer: (ctx) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Text('Einkaufstracker · $title', style: style(size: 8, color: _grey)),
      pw.Text('Seite ${ctx.pageNumber} von ${ctx.pagesCount}', style: style(size: 8, color: _grey)),
    ]),
    build: (ctx) => [
      pw.Text(title, style: style(size: 22, isBold: true, color: _accent)),
      pw.SizedBox(height: 2),
      pw.Text('Erstellt am ${formatViennaDate(createdAtUtc)}', style: style(size: 9, color: _grey)),
      pw.SizedBox(height: 14),
      _summary(report, style),
      pw.SizedBox(height: 14),
      _calendar(report, style),
      pw.SizedBox(height: 4),
      pw.Text('Zahl im Feld: bekannte kcal des Tages. Leere Felder sind nicht erfasst, das ist nicht dasselbe wie 0 kcal.', style: style(size: 8, color: _grey)),
      pw.SizedBox(height: 18),
      pw.Text('Tag für Tag', style: style(size: 14, isBold: true)),
      pw.SizedBox(height: 6),
      for (final d in report.days) _day(d, photos[d.photoMealId], style),
      pw.SizedBox(height: 6),
      pw.Text(
        'Die kcal-Angaben beruhen auf den hinterlegten Nährwerten der Zutaten; Zutaten ohne Nährwerte sind nicht enthalten. '
        '„geschätzt“ markiert Mahlzeiten, deren Werte nur eine Schätzung sind (z. B. Restaurant).',
        style: style(size: 8, color: _grey),
      ),
    ],
  ));
  return doc.save();
}

pw.Widget _summary(JournalReport r, pw.TextStyle Function({double size, bool isBold, PdfColor? color}) style) {
  final avg = r.averagePerDay;
  final lines = <String>[
    '${r.daysLogged} von ${r.daysInMonth} Tagen erfasst · ${r.mealCount == 1 ? '1 Mahlzeit' : '${r.mealCount} Mahlzeiten'}',
    if (avg != null)
      'Ø pro Tag mit bekannten Nährwerten (${r.daysWithKnownKcal} ${r.daysWithKnownKcal == 1 ? 'Tag' : 'Tage'}): ${formatKcal(avg.kcal)}'
          ' · Eiweiß ${formatNutrientGrams(avg.proteinG)} · Fett ${formatNutrientGrams(avg.fatG)} · Kohlenhydrate ${formatNutrientGrams(avg.carbsG)}'
    else
      'An keinem Tag sind Nährwerte bekannt, daher gibt es keinen Durchschnitt.',
    if (r.hasEstimates) 'Enthält Schätzwerte.',
    if (r.topMeals.isNotEmpty)
      'Am häufigsten: ${[for (final m in r.topMeals) m.count > 1 ? '${m.title} (${m.count}×)' : m.title].join(', ')}',
  ];
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(color: _accentLight, borderRadius: pw.BorderRadius.circular(4)),
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      for (final l in lines) pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 1.5), child: pw.Text(l, style: style(size: 10))),
    ]),
  );
}

pw.Widget _calendar(JournalReport r, pw.TextStyle Function({double size, bool isBold, PdfColor? color}) style) {
  final offset = DateTime(r.year, r.month, 1).weekday - 1;
  final loggedDays = {for (final d in r.days) d.day.day};
  final cells = <pw.Widget>[
    for (var i = 0; i < offset; i++) pw.SizedBox(height: 34),
    for (var d = 1; d <= r.daysInMonth; d++)
      pw.Container(
        height: 34,
        padding: const pw.EdgeInsets.all(3),
        color: loggedDays.contains(d) ? _accentLight : null,
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('$d', style: style(size: 9, isBold: loggedDays.contains(d))),
          if (r.kcalByDay[d] case final kcal?) pw.Text(_kcalPlain(kcal), style: style(size: 7, color: _grey)),
        ]),
      ),
  ];
  while (cells.length % 7 != 0) {
    cells.add(pw.SizedBox(height: 34));
  }
  return pw.Table(
    border: pw.TableBorder.all(color: _greyLight, width: 0.5),
    columnWidths: {for (var i = 0; i < 7; i++) i: const pw.FlexColumnWidth()},
    children: [
      pw.TableRow(children: [
        for (final w in const ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'])
          pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3), child: pw.Center(child: pw.Text(w, style: style(size: 8, isBold: true, color: _grey)))),
      ]),
      for (var row = 0; row < cells.length ~/ 7; row++) pw.TableRow(children: cells.sublist(row * 7, row * 7 + 7)),
    ],
  );
}

pw.Widget _day(ReportDay d, Uint8List? photo, pw.TextStyle Function({double size, bool isBold, PdfColor? color}) style) {
  final kcal = d.kcal;
  return pw.Inseparable(
    child: pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(_dayHeading(d.day), style: style(size: 11, isBold: true, color: _accent)),
          pw.Text(
            [kcal == null ? 'Nährwerte unbekannt' : formatKcal(kcal), if (d.hasEstimates) 'enthält Schätzwerte'].join(' · '),
            style: style(size: 9, color: _grey),
          ),
        ]),
        pw.Divider(height: 6, thickness: 0.5, color: _greyLight),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          if (photo != null)
            pw.Padding(
              padding: const pw.EdgeInsets.only(right: 10, top: 2),
              child: pw.SizedBox(width: 64, height: 64, child: pw.Image(pw.MemoryImage(photo), fit: pw.BoxFit.cover)),
            ),
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              for (final m in d.meals)
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                  child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.SizedBox(width: 88, child: pw.Text('${formatViennaTime(m.eatenAtUtc)} · ${mealTypeLabel(m.mealType)}', style: style(size: 9, color: _grey))),
                    pw.Expanded(child: pw.Text(m.isEstimate ? '${m.title} (geschätzt)' : m.title, style: style(size: 10))),
                    pw.SizedBox(width: 8),
                    pw.Text(m.kcal == null ? '–' : formatKcal(m.kcal!), style: style(size: 9, color: _grey)),
                  ]),
                ),
            ]),
          ),
        ]),
      ]),
    ),
  );
}
