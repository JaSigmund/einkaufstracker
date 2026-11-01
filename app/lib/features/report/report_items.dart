import '../../data/local/database.dart';
import '../../domain/receipt/excluded_items.dart';
import '../../domain/receipt/month_report.dart';

/// Bon-Positionen fuer Auswertung und Trend, aufgeteilt in eigene und ausgeschlossene (ADR-020 "Rechnungen
/// teilen"): `own` geht in Summen, Budget und Trend ein, `excluded` (von jemand anderem bezahlt) nur in die
/// separate "Ausgeschlossen"-Zeile. Preisverlauf und Haendlervergleich lesen weiter alle Positionen, weil sie
/// reale Marktpreise abbilden, unabhaengig davon, wer bezahlt hat.
///
/// [products] liefert optional Produktname und Packungsgroesse fuer die Artikelliste (Monatsauswertung); der Trend braucht sie nicht.
({List<ReportItem> own, List<ReportItem> excluded}) reportItemsOf(
  Iterable<ReceiptItem> rows, {
  Map<String, Product> products = const {},
}) {
  final all = <ReportItem>[
    for (final i in rows)
      (
        receiptId: i.receiptId,
        lineNo: i.lineNo,
        kind: i.kind,
        rawText: i.rawText,
        categoryId: i.categoryId,
        productId: i.productId,
        productName: i.productId == null ? null : products[i.productId]?.name,
        quantity: i.quantity,
        quantityUnit: i.quantityUnit,
        productBaseUnit: i.productId == null ? null : products[i.productId]?.baseUnit,
        productPackSize: i.productId == null ? null : products[i.productId]?.packSize,
        lineTotalCents: i.lineTotalCents,
      ),
  ];
  final excludedLines = <ReceiptLineKey>{
    for (final i in rows)
      if (i.excluded) (receiptId: i.receiptId, lineNo: i.lineNo),
  };
  return splitExcludedItems(all, excludedLines);
}
