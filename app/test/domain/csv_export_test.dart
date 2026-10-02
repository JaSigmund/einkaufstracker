import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/domain/receipt/csv_export.dart';
import 'package:flutter_test/flutter_test.dart';

Receipt _receipt(String id, String? storeId, DateTime purchasedAt) => Receipt(
      id: id, householdId: 'h', storeId: storeId, purchasedAt: purchasedAt, totalCents: 100, status: 'confirmed', source: 'pdf_text',
      sumMismatch: false, updatedAt: DateTime.utc(2026),
    );

Store _store(String id, String chain, {String? branch}) => Store(id: id, householdId: 'h', chain: chain, branch: branch, updatedAt: DateTime.utc(2026));

Product _product(String id, String name, {String? categoryId}) =>
    Product(id: id, householdId: 'h', name: name, categoryId: categoryId, baseUnit: 'piece', defaultDateKind: 'best_before', defaultLocation: 'pantry', restock: false, updatedAt: DateTime.utc(2026));

Category _cat(String id, String name) => Category(id: id, householdId: 'h', name: name, sortOrder: 0, isStorable: false, updatedAt: DateTime.utc(2026));

ReceiptItem _item(
  String rid,
  String id,
  int no,
  String text,
  int cents, {
  String? productId,
  String? categoryId,
  int? unitPriceNormCents,
  double quantity = 1,
  String quantityUnit = 'piece',
}) =>
    ReceiptItem(
      id: id, householdId: 'h', receiptId: rid, lineNo: no, kind: 'article', rawText: text, quantity: quantity, quantityUnit: quantityUnit,
      lineTotalCents: cents, productId: productId, categoryId: categoryId, unitPriceNormCents: unitPriceNormCents, needsReview: false,
      updatedAt: DateTime.utc(2026),
    );

void main() {
  group('buildReceiptItemsCsv (Doku 07 §5)', () {
    test('eine Zeile je Bon-Position mit Kopfzeile, chronologisch sortiert, je 10 Spalten', () {
      final csv = buildReceiptItemsCsv(
        receipts: [_receipt('r1', 's1', DateTime.utc(2026, 9, 10, 14, 30)), _receipt('r2', 's1', DateTime.utc(2026, 9, 5, 10, 0))],
        items: [
          _item('r1', 'i1', 1, 'Vollmilch', 129, productId: 'p1', unitPriceNormCents: 129),
          _item('r2', 'i2', 1, 'Paprika', 249, quantity: 0.62, quantityUnit: 'kg'),
        ],
        stores: [_store('s1', 'Billa', branch: '0643')],
        products: [_product('p1', 'Vollmilch 3,5%', categoryId: 'c1')],
        categories: [_cat('c1', 'Milch & Milchprodukte')],
      );
      // Codereview-Fund 2026-10-01: ';' statt ',' als Trennzeichen (das Dezimalkomma waere sonst
      // doppeldeutig, und Excel auf einem deutschsprachigen System erwartet beim Doppelklick-Oeffnen
      // ohnehin ';'), dazu ein UTF-8-BOM am Anfang der Datei.
      expect(csv, startsWith('﻿'));
      final lines = csv.substring(1).trim().split('\n');
      expect(lines, hasLength(3)); // Kopfzeile + 2 Positionen
      expect(lines[0], 'Datum;Händler;Bon-ID;Name;Produkt;Kategorie;Menge;Einheit;Preis;Grundpreis');
      // aeltere Position (r2, 5.9.) steht vor der juengeren (r1, 10.9.)
      final rIndex1 = lines.indexWhere((l) => l.contains('r1'));
      final rIndex2 = lines.indexWhere((l) => l.contains('r2'));
      expect(rIndex2, lessThan(rIndex1));

      expect(lines[rIndex1], contains('Billa 0643'));
      // Ein Komma (Dezimaltrennzeichen oder Teil des Produktnamens) macht kein Quoting mehr noetig, das
      // Trennzeichen ist jetzt ';'.
      expect(lines[rIndex1], contains('Vollmilch 3,5%'));
      expect(lines[rIndex1], contains('Milch & Milchprodukte'));
      expect(lines[rIndex1], contains('1,29'));

      expect(lines[rIndex2], contains('Paprika'));
      expect(lines[rIndex2], contains('0,62'));
      expect(lines[rIndex2], contains('kg'));
      expect(lines[rIndex2], contains('2,49'));
    });

    test('Position ohne Produkt-/Kategorie-Zuordnung und ohne Grundpreis: leere Felder statt Absturz', () {
      final csv = buildReceiptItemsCsv(
        receipts: [_receipt('r1', null, DateTime.utc(2026, 9, 10))],
        items: [_item('r1', 'i1', 1, 'Unbekannt', 99)],
        stores: const [],
        products: const [],
        categories: const [],
      );
      final line = csv.substring(1).trim().split('\n')[1];
      expect(line, contains('r1'));
      expect(line, contains('Unbekannt'));
      expect(line, contains('0,99'));
      expect(line, endsWith(';'), reason: 'kein Grundpreis: letztes Feld leer');
    });

    test('Codereview-Fund 2026-10-01: ein Name mit dem Trennzeichen (";") oder Anfuehrungszeichen wird weiterhin korrekt gequotet', () {
      final csv = buildReceiptItemsCsv(
        receipts: [_receipt('r1', null, DateTime.utc(2026, 9, 10))],
        items: [_item('r1', 'i1', 1, 'Wurst; Extra "scharf"', 99)],
        stores: const [],
        products: const [],
        categories: const [],
      );
      final line = csv.substring(1).trim().split('\n')[1];
      expect(line, contains('"Wurst; Extra ""scharf"""'));
    });

    test('Kategorie fehlt am Bon-Item, wird vom Produkt uebernommen', () {
      final csv = buildReceiptItemsCsv(
        receipts: [_receipt('r1', null, DateTime.utc(2026, 9, 10))],
        items: [_item('r1', 'i1', 1, 'Vollmilch', 129, productId: 'p1')],
        stores: const [],
        products: [_product('p1', 'Vollmilch', categoryId: 'c1')],
        categories: [_cat('c1', 'Milch & Milchprodukte')],
      );
      expect(csv, contains('Milch & Milchprodukte'));
    });
  });
}
