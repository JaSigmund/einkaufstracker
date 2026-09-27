import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/local/database.dart';
import '../../data/repositories/product_repository.dart';
import 'product_form_page.dart';
import 'stock_entry_page.dart';

/// Scannt einen Barcode und fuehrt zur passenden Seite: bekanntes Produkt -> Bestand erfassen, unbekanntes
/// Produkt -> anlegen und danach Bestand erfassen. Abbruch im Scanner oder ohne Treffer: kehrt still zurueck.
/// Gemeinsame Logik fuer den Scan-Tab und den FAB im Inventar, damit "schnell einen Artikel erfassen" von
/// ueberall in einem Zug geht (Doku 06 §3.5).
Future<void> startBarcodeScan(
  BuildContext context,
  WidgetRef ref, {
  void Function(String status)? onStatus,
  VoidCallback? onLookupDone,
}) async {
  onStatus?.call('Scanner wird geöffnet …');
  String? ean;
  BarcodeLookupResult? result;
  try {
    ean = await ref.read(barcodeScannerProvider).scan(context);
    if (ean != null) {
      onStatus?.call('Produkt wird gesucht …');
      result = await ref.read(productRepositoryProvider).lookup(ean);
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Barcode-Scan nicht möglich: $e')));
    }
  } finally {
    onLookupDone?.call();
  }
  if (ean == null || result == null || !context.mounted) return;
  if (result.isKnown) {
    await context.push('/stock-entry', extra: StockEntryArgs(product: result.product!, ean: ean));
  } else {
    final created = await context.push('/product-form', extra: ProductFormArgs(ean: ean, suggestion: result.offSuggestion));
    if (created is Product && context.mounted) {
      await context.push('/stock-entry', extra: StockEntryArgs(product: created, ean: ean));
    }
  }
}
