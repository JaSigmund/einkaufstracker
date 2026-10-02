import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/domain/app_update/app_update_gate.dart';
import 'package:einkaufstracker/features/recipes/cooking_chat_panel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Update-Sperre (ADR-022) fuer die Koch-Cloud (ADR-021): bei einer zu alten App-Version darf gar kein
/// Netzzugriff stattfinden. Der Client zeigt auf einen toten Port -- haette die Sperre nicht gegriffen,
/// kaeme statt der erwarteten Ausnahme ein Netzfehler (CookingCloudUnavailable) zurueck.
void main() {
  ProviderContainer container({required bool updateRequired}) {
    final c = ProviderContainer(overrides: [
      appUpdateRequiredProvider.overrideWithValue(updateRequired),
      supabaseClientProvider.overrideWithValue(SupabaseClient('http://127.0.0.1:1', 'anon-key')),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('suggestRecipes: zu alte Version wirft AppUpdateRequiredException, ohne ins Netz zu gehen', () {
    final cloud = container(updateRequired: true).read(cookingCloudProvider);
    expect(
      cloud.suggestRecipes([(name: 'Milch', quantity: 1.0, unit: 'l')]),
      throwsA(isA<AppUpdateRequiredException>()),
    );
  });

  test('chat: zu alte Version wirft AppUpdateRequiredException, ohne ins Netz zu gehen', () {
    final cloud = container(updateRequired: true).read(cookingCloudProvider);
    expect(
      cloud.chat('Hallo?', const CookingChatContext(recipeTitle: 'Suppe')),
      throwsA(isA<AppUpdateRequiredException>()),
    );
  });
}
