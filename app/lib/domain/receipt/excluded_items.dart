/// Bon-Positionen, die jemand anderes bezahlt hat (Feature-Request "Rechnungen teilen", bestaetigt
/// 2026-10-01, siehe [[12 Entscheidungen (ADR)]] ADR-020): sie sollen nicht in die eigene
/// Monatsauswertung/Budget/Trend einfliessen, aber auf dem Bon sichtbar bleiben (Transparenz) und
/// weiterhin normal ins Inventar wandern (die Ware wurde ja trotzdem gekauft, nur nicht von einem
/// selbst bezahlt).
///
/// Bewusst **keine neue Kategorie**: Kategorien beschreiben, WAS gekauft wurde, nicht WER bezahlt hat
/// (ADR-020 Punkt 2). Stattdessen ein Ausschluss, der VOR `buildMonthReport` greift — die bestehende
/// Funktion bleibt unveraendert, nur ihre Eingabe wird gefiltert (gleiches Muster wie die bestehenden
/// Sentinel-Schluessel `billDiscountKey`/`unassignedKey` in `month_report.dart`, keine echte
/// `categories`-Zeile).
library;

import 'month_report.dart';

/// Eindeutiger Schluessel einer Bon-Position (Bon-ID + Zeilennummer, wie in `ReportItem`).
typedef ReceiptLineKey = ({String receiptId, int lineNo});

/// Teilt Bon-Positionen in eigene (zaehlen zur Auswertung) und ausgeschlossene (von jemand anderem
/// bezahlt) auf. `excludedLines` kommt von `receipt_items.excluded = true` (siehe
/// `supabase/planned/receipt_item_excluded_draft.sql`). Beide Listen lassen sich unveraendert an
/// `buildMonthReport`/`buildTrend` uebergeben: `own` fuer die normale Auswertung, `excluded` fuer eine
/// separate "Ausgeschlossen"-Anzeige (z.B. "12,40 € diesen Monat von anderen bezahlt").
({List<ReportItem> own, List<ReportItem> excluded}) splitExcludedItems(
  Iterable<ReportItem> items,
  Set<ReceiptLineKey> excludedLines,
) {
  final own = <ReportItem>[];
  final excluded = <ReportItem>[];
  for (final i in items) {
    final isExcluded = excludedLines.contains((receiptId: i.receiptId, lineNo: i.lineNo));
    (isExcluded ? excluded : own).add(i);
  }
  return (own: own, excluded: excluded);
}
