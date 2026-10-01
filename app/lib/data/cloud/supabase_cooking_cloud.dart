import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/recipes/recipe_suggestion.dart';
import '../../features/recipes/cooking_chat_panel.dart';
import 'cooking_cloud.dart';

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

  Exception _mapFunctionException(FunctionException e) {
    final details = e.details;
    if (e.status == 403 && details is Map && details['error'] == 'cloud_ocr_not_allowed') {
      return const CookingCloudNotAllowed();
    }
    return CookingCloudUnavailable('Fehler ${e.status}');
  }

  Exception _mapGenericError(Object e) {
    final text = e.toString();
    final network = e is SocketException || text.contains('ClientException') || text.contains('SocketException');
    return CookingCloudUnavailable(network ? 'kein Netz' : text);
  }
}
