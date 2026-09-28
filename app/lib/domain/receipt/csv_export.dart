import '../../core/format.dart';
import '../../data/local/database.dart';

const _csvHeader = ['Datum', 'Händler', 'Bon-ID', 'Name', 'Produkt', 'Kategorie', 'Menge', 'Einheit', 'Preis', 'Grundpreis'];

String _csvField(String value) {
  if (value.contains(',') || value.contains('"') || value.contains('\n')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

String _euroField(int cents) => formatEuro(cents).replaceAll(' €', '').replaceAll('.', '');

/// CSV mit einer Zeile je Bon-Position (Doku 07 §5), fuer Analysen ausserhalb der App (Excel, Obsidian).
/// Datum/Betraege im deutschsprachigen Format (Komma als Dezimaltrennzeichen), damit Excel es ohne
/// manuellen Import-Assistenten richtig erkennt.
String buildReceiptItemsCsv({
  required Iterable<Receipt> receipts,
  required Iterable<ReceiptItem> items,
  required Iterable<Store> stores,
  required Iterable<Product> products,
  required Iterable<Category> categories,
}) {
  final receiptById = {for (final r in receipts) r.id: r};
  final storeById = {for (final s in stores) s.id: s};
  final productById = {for (final p in products) p.id: p};
  final categoryById = {for (final c in categories) c.id: c};

  final rows = items.where((i) => receiptById.containsKey(i.receiptId)).toList()
    ..sort((a, b) {
      final da = receiptById[a.receiptId]!.purchasedAt;
      final db_ = receiptById[b.receiptId]!.purchasedAt;
      final cmp = da.compareTo(db_);
      return cmp != 0 ? cmp : a.lineNo.compareTo(b.lineNo);
    });

  final buffer = StringBuffer()..writeln(_csvHeader.join(','));
  for (final i in rows) {
    final receipt = receiptById[i.receiptId]!;
    final store = storeById[receipt.storeId];
    final product = i.productId == null ? null : productById[i.productId];
    final categoryId = i.categoryId ?? product?.categoryId;
    final category = categoryId == null ? null : categoryById[categoryId];

    final fields = [
      formatViennaDateTime(receipt.purchasedAt),
      store == null ? '' : '${store.chain}${store.branch == null ? '' : ' ${store.branch}'}',
      receipt.id,
      i.rawText,
      product?.name ?? '',
      category?.name ?? '',
      formatQuantity(i.quantity).replaceAll('.', ','),
      i.quantityUnit,
      _euroField(i.lineTotalCents),
      i.unitPriceNormCents == null ? '' : _euroField(i.unitPriceNormCents!),
    ];
    buffer.writeln(fields.map(_csvField).join(','));
  }
  return buffer.toString();
}
