import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/recipes/recipe_suggestion.dart';
import '../../domain/recipes/cooking_chat.dart';
import 'cooking_cloud.dart';

/// Ordnet die Antwort einer Edge Function (HTTP-Status und JSON-Fehlerdetails) der passenden Ausnahme zu:
/// 403 `cloud_ocr_not_allowed` = vom Nutzer ausgeschaltet, 429 `daily_limit_reached` = Tageslimit, alles
/// andere = vorerst nicht verfuegbar. Reine Funktion, damit sie ohne Netzwerk testbar ist.
Exception cookingCloudExceptionFor(int status, Object? details) {
  final error = details is Map ? details['error'] : null;
  if (status == 403 && error == 'cloud_ocr_not_allowed') return const CookingCloudNotAllowed();
  if (status == 429 && error == 'daily_limit_reached') return const CookingCloudDailyLimit();
  return CookingCloudUnavailable('Fehler $status');
}

/// Ruft die Edge Functions `suggest-recipes` und `cooking-chat` auf (ADR-021).
class SupabaseCookingCloud implements CookingCloud {
  SupabaseCookingCloud(this._client, this._householdId);

  final SupabaseClient _client;
  final Future<String> Function() _householdId;

  @override
  Future<List<RecipeSuggestion>> suggestRecipes(List<SuggestionIngredient> ingredients) async {
    final household = await _householdId();
    try {
      final response = await _client.functions
          .invoke('suggest-recipes', body: {
            'household_id': household,
            'ingredients': [for (final i in ingredients) {'name': i.name, if (i.quantity != null) 'quantity': i.quantity, if (i.unit != null) 'unit': i.unit}],
          })
          .timeout(const Duration(seconds: 30));
      final data = response.data;
      if (data is! Map<String, dynamic>) throw const CookingCloudUnavailable('unerwartete Antwort');
      return parseRecipeSuggestions(data['suggestions']);
    } on FunctionException catch (e) {
      throw _mapFunctionException(e);
    } on TimeoutException {
      throw const CookingCloudUnavailable('Zeitüberschreitung');
    } on CookingCloudUnavailable {
      rethrow;
    } catch (e) {
      throw _mapGenericError(e);
    }
  }

  @override
  Future<String> chat(String message, CookingChatContext context) async {
    final household = await _householdId();
    try {
      final response = await _client.functions
          .invoke('cooking-chat', body: {
            'household_id': household,
            'message': message,
            'recipe_title': context.recipeTitle,
            'ingredients': context.ingredients,
            'history': [for (final m in context.history) {'text': m.text, 'from_user': m.fromUser}],
          })
          .timeout(const Duration(seconds: 30));
      final data = response.data;
      if (data is! Map<String, dynamic> || data['reply'] is! String) {
        throw const CookingCloudUnavailable('unerwartete Antwort');
      }
      return data['reply'] as String;
    } on FunctionException catch (e) {
      throw _mapFunctionException(e);
    } on TimeoutException {
      throw const CookingCloudUnavailable('Zeitüberschreitung');
    } on CookingCloudUnavailable {
      rethrow;
    } catch (e) {
      throw _mapGenericError(e);
    }
  }

  Exception _mapFunctionException(FunctionException e) => cookingCloudExceptionFor(e.status, e.details);

  Exception _mapGenericError(Object e) {
    final text = e.toString();
    final network = e is SocketException || text.contains('ClientException') || text.contains('SocketException');
    return CookingCloudUnavailable(network ? 'kein Netz' : text);
  }
}
