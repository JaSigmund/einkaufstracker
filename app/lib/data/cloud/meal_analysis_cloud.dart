import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/nutrition/meal_analysis.dart';
import 'cooking_cloud.dart';
import 'supabase_cooking_cloud.dart';

/// Ein Produkt des Haushalts, das die KI Zutaten zuordnen darf.
typedef AnalysisProduct = ({String id, String name});

/// Ruft die Edge Function `analyze-meal` auf (Phase 7c). Fehler sind dieselben wie bei den Rezeptvorschlaegen
/// ([CookingCloudUnavailable], [CookingCloudNotAllowed], [CookingCloudDailyLimit]), weil beide dieselbe
/// Einwilligung (`allow_cloud_ocr`) und dasselbe Tageslimit teilen.
abstract class MealAnalysisCloud {
  /// Analysiert das (bereits verkleinerte) JPEG [photo]. [products] sind die Produkte des Haushalts, denen die KI
  /// Zutaten zuordnen darf. Nur auf Tastendruck aufrufen.
  Future<MealAnalysis> analyze(Uint8List photo, List<AnalysisProduct> products);
}

class SupabaseMealAnalysisCloud implements MealAnalysisCloud {
  SupabaseMealAnalysisCloud(this._client, this._householdId);

  final SupabaseClient _client;
  final Future<String> Function() _householdId;

  @override
  Future<MealAnalysis> analyze(Uint8List photo, List<AnalysisProduct> products) async {
    final household = await _householdId();
    try {
      final response = await _client.functions
          .invoke('analyze-meal', body: {
            'household_id': household,
            'image_base64': base64Encode(photo),
            'products': [for (final p in products) {'id': p.id, 'name': p.name}],
          })
          .timeout(const Duration(seconds: 60));
      final data = response.data;
      if (data is! Map<String, dynamic>) throw const CookingCloudUnavailable('unerwartete Antwort');
      return parseMealAnalysis(data['analysis']);
    } on FunctionException catch (e) {
      throw cookingCloudExceptionFor(e.status, e.details);
    } on TimeoutException {
      throw const CookingCloudUnavailable('Zeitüberschreitung');
    } on CookingCloudUnavailable {
      rethrow;
    } catch (e) {
      final text = e.toString();
      final network = e is SocketException || text.contains('ClientException') || text.contains('SocketException');
      throw CookingCloudUnavailable(network ? 'kein Netz' : text);
    }
  }
}
