import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_page.dart';
import '../features/categories/categories_page.dart';
import '../features/diary/balance_page.dart';
import '../features/diary/journal_page.dart';
import '../features/diary/nutrients_page.dart';
import '../features/diary/quick_intake_page.dart';
import '../features/diary/supplement_form_page.dart';
import '../features/diary/supplements_page.dart';
import '../features/diary/meal_form_page.dart';
import '../features/diary/targets_page.dart';
import '../features/home/home_shell.dart';
import '../features/recipes/meal_plan_page.dart';
import '../features/household/accept_invite_page.dart';
import '../features/household/household_page.dart';
import '../features/receipt_import/import_review_page.dart';
import '../features/receipt_import/receipt_edit_page.dart';
import '../features/receipt_import/receipt_import_service.dart';
import '../data/local/database.dart';
import '../features/receipts/receipt_detail_page.dart';
import '../features/receipts/receipt_file_page.dart';
import '../domain/products/product_assignment.dart';
import '../features/products/product_form_page.dart';
import '../features/products/product_page.dart';
import '../features/products/learned_terms_page.dart';
import '../features/products/products_list_page.dart';
import '../features/report/product_price_page.dart';
import '../features/bugreport/bug_report_list_page.dart';
import '../features/bugreport/bug_report_page.dart';
import '../features/bugreport/feature_request_page.dart';
import '../features/changelog/changelog_page.dart';
import '../features/inventory/inventory_item_detail_page.dart';
import '../features/products/manual_stock_page.dart';
import '../features/products/stock_entry_page.dart';
import '../features/recipes/recipe_form_page.dart';
import '../features/recipes/recipe_suggestions_page.dart';
import '../features/recipes/recipe_viewer_page.dart';
import '../features/recipes/saved_recipes_page.dart';
import '../domain/recipes/recipe_search_url.dart';
import '../domain/recipes/saved_recipe.dart';
import '../features/report/trend_page.dart';
import '../features/settings/settings_page.dart';
import '../features/shopping_list/aisle_order_page.dart';
import '../features/shopping_list/shopping_archive_page.dart';
import 'providers.dart';

class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Stream<dynamic> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }
  late final StreamSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(supabaseClientProvider).auth;
  final refresh = _AuthRefresh(auth.onAuthStateChange);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = auth.currentSession != null;
      final atLogin = state.matchedLocation == '/login';
      // Wer eingeladen wurde, hat noch kein Konto: die Seite zum Annehmen ist ohne Anmeldung erreichbar
      final atAccept = state.matchedLocation == '/accept-invite';
      if (!loggedIn) return (atLogin || atAccept) ? null : '/login';
      if (atLogin || atAccept) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/accept-invite', builder: (_, _) => const AcceptInvitePage()),
      GoRoute(path: '/household', builder: (_, _) => const HouseholdPage()),
      homeShellRoute(),
      scanRoute(),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
      GoRoute(path: '/categories', builder: (_, _) => const CategoriesPage()),
      GoRoute(
        path: '/products',
        builder: (_, state) => ProductsListPage(
          initialView: ProductView.fromParam(state.uri.queryParameters['view']),
          initialOpenOnly: state.uri.queryParameters['open'] == '1',
        ),
      ),
      GoRoute(path: '/learned-terms', builder: (_, _) => const LearnedTermsPage()),
      GoRoute(path: '/product/:id', builder: (_, state) => ProductPage(productId: state.pathParameters['id']!)),
      GoRoute(
        path: '/receipt-file',
        builder: (_, state) => ReceiptFilePage(file: state.extra as ReceiptFile),
        redirect: (_, state) => state.extra is ReceiptFile ? null : '/',
      ),
      GoRoute(path: '/receipt/:id', builder: (_, state) => ReceiptDetailPage(receiptId: state.pathParameters['id']!)),
      GoRoute(
        path: '/import-edit',
        builder: (_, state) => ReceiptEditPage(preview: state.extra as ImportPreview),
        redirect: (_, state) => state.extra is ImportPreview ? null : '/',
      ),
      GoRoute(
        path: '/import-review',
        builder: (_, state) => ImportReviewPage(preview: state.extra as ImportPreview),
        redirect: (_, state) => state.extra is ImportPreview ? null : '/',
      ),
      GoRoute(path: '/changelog', builder: (_, _) => const ChangelogPage()),
      GoRoute(path: '/trend', builder: (_, _) => const TrendPage()),
      GoRoute(path: '/bug-report', builder: (_, _) => const BugReportPage()),
      GoRoute(path: '/feature-request', builder: (_, _) => const FeatureRequestPage()),
      GoRoute(path: '/bug-reports', builder: (_, _) => const BugReportListPage()),
      GoRoute(
        path: '/bug-reports/detail',
        builder: (_, state) => BugReportDetailPage(report: state.extra as BugReport),
        redirect: (_, state) => state.extra is BugReport ? null : '/bug-reports',
      ),
      GoRoute(
        path: '/product-form',
        builder: (_, state) {
          final a = state.extra as ProductFormArgs?;
          return ProductFormPage(ean: a?.ean, suggestion: a?.suggestion, existing: a?.existing, initialName: a?.initialName);
        },
      ),
      GoRoute(
        path: '/inventory-item',
        builder: (_, state) {
          final a = state.extra as InventoryItemArgs;
          return InventoryItemDetailPage(item: a.item, product: a.product);
        },
        redirect: (_, state) => state.extra is InventoryItemArgs ? null : '/',
      ),
      GoRoute(
        path: '/product-price',
        builder: (_, state) => ProductPricePage(product: state.extra as Product),
        redirect: (_, state) => state.extra is Product ? null : '/',
      ),
      GoRoute(
        path: '/meal-form',
        builder: (_, state) {
          final args = state.extra as MealFormArgs?;
          return MealFormPage(existing: args?.existing, template: args?.template, leftover: args?.leftover ?? false, recipe: args?.recipe);
        },
      ),
      GoRoute(path: '/nutrition-targets', builder: (_, _) => const TargetsPage()),
      GoRoute(path: '/balance', builder: (_, _) => const BalancePage()),
      GoRoute(path: '/journal', builder: (_, _) => const JournalPage()),
      GoRoute(path: '/products-nutrients', redirect: (_, _) => '/products?view=nutrients&open=1'),
      GoRoute(path: '/nutrients', builder: (_, _) => const NutrientsPage()),
      GoRoute(path: '/aisle-order', builder: (_, state) => AisleOrderPage(initialStoreId: state.extra as String?)),
      GoRoute(path: '/shopping-archive', builder: (_, _) => const ShoppingArchivePage()),
      GoRoute(path: '/quick-intake', builder: (_, _) => const QuickIntakePage()),
      GoRoute(path: '/meal-plan', builder: (_, _) => const MealPlanPage()),
      GoRoute(path: '/supplements', builder: (_, _) => const SupplementsPage()),
      GoRoute(path: '/supplement-form', builder: (_, state) => SupplementFormPage(existing: state.extra as Supplement?)),
      GoRoute(
        path: '/stock-entry',
        builder: (_, state) {
          final a = state.extra as StockEntryArgs;
          return StockEntryPage(product: a.product, ean: a.ean, suggestion: a.suggestion);
        },
        redirect: (_, state) => state.extra is StockEntryArgs ? null : '/',
      ),
      GoRoute(path: '/stock-manual', builder: (_, _) => const ManualStockPage()),
      GoRoute(path: '/recipe-suggestions', builder: (_, _) => const RecipeSuggestionsPage()),
      GoRoute(
        path: '/recipe-viewer',
        builder: (_, state) {
          final a = state.extra as RecipeViewerArgs;
          return RecipeViewerPage(
            recipeTitle: a.title,
            url: buildRecipeSearchUrl(a.title),
            ingredients: a.ingredients,
            sendChatMessage: (message, chatContext) => ref.read(cookingCloudProvider).chat(message, chatContext),
          );
        },
        redirect: (_, state) => state.extra is RecipeViewerArgs ? null : '/',
      ),
      GoRoute(path: '/saved-recipes', builder: (_, _) => const SavedRecipesPage()),
      GoRoute(path: '/recipe-form', builder: (_, state) => RecipeFormPage(existing: state.extra as SavedRecipe?)),
    ],
  );
});
