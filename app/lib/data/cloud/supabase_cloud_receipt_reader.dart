import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/receipt/parsed_receipt.dart';
import 'cloud_receipt.dart';

/// Ordnet die Fehlerantwort von `parse-receipt` (HTTP-Status und JSON-Fehlerdetails) der passenden Ausnahme zu, wie
/// `cookingCloudExceptionFor` bei den Rezept-Functions. Reine Funktion, damit sie ohne Netzwerk testbar ist.
Exception cloudReceiptExceptionFor(int status, Object? details) {
  final error = details is Map ? details['error'] : null;
  if (status == 403 && error == 'cloud_ocr_not_allowed') return const CloudNotAllowed();
  // Tageslimit aller KI-Funktionen des Haushalts (Codereview-Fund 2026-10-16: gilt jetzt auch fuer die Bon-Erkennung)
  if (status == 429 && error == 'daily_limit_reached') return const CloudUnavailable('Tageslimit erreicht, morgen wieder möglich');
  return CloudUnavailable('Fehler $status');
}

/// Ruft die Edge Function `parse-receipt` auf (Claude Vision, Variante v3 mit einer Nachfrage bei Summenabweichung).
class SupabaseCloudReceiptReader implements CloudReceiptReader {
  SupabaseCloudReceiptReader(this._client, this._householdId);

  final SupabaseClient _client;
  final Future<String> Function() _householdId;

  @override
  Future<ParsedReceipt> read(List<Uint8List> jpegs, {String storeHint = 'Billa'}) async {
    final household = await _householdId();
    try {
      final response = await _client.functions
          .invoke(
            'parse-receipt',
            body: {'household_id': household, 'images': [for (final j in jpegs) base64Encode(j)], 'store_hint': storeHint},
          )
          .timeout(const Duration(seconds: 60));
      final data = response.data;
      if (data is! Map<String, dynamic>) throw const CloudUnavailable('unerwartete Antwort');
      return parsedReceiptFromCloud(data);
    } on FunctionException catch (e) {
      throw cloudReceiptExceptionFor(e.status, e.details);
    } on TimeoutException {
      throw const CloudUnavailable('Zeitüberschreitung');
    } on CloudUnavailable {
      rethrow;
    } catch (e) {
      final text = e.toString();
      final network = e is SocketException || text.contains('ClientException') || text.contains('SocketException');
      throw CloudUnavailable(network ? 'kein Netz' : text);
    }
  }
}
