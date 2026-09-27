import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_page.dart';
import '../features/categories/categories_page.dart';
import '../features/home/home_shell.dart';
import '../features/receipt_import/import_review_page.dart';
import '../features/receipt_import/receipt_edit_page.dart';
import '../features/receipt_import/receipt_import_service.dart';
import '../data/local/database.dart';
import '../features/receipts/receipt_detail_page.dart';
import '../features/receipts/receipt_file_page.dart';
import '../features/products/product_form_page.dart';
import '../features/bugreport/bug_report_list_page.dart';
import '../features/bugreport/bug_report_page.dart';
import '../features/changelog/changelog_page.dart';
import '../features/inventory/inventory_item_detail_page.dart';
import '../features/products/stock_entry_page.dart';
import '../features/settings/settings_page.dart';
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
      if (!loggedIn) return atLogin ? null : '/login';
      if (atLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/', builder: (_, _) => const HomeShell()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
      GoRoute(path: '/categories', builder: (_, _) => const CategoriesPage()),
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
      GoRoute(path: '/bug-report', builder: (_, _) => const BugReportPage()),
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
          return ProductFormPage(ean: a?.ean, suggestion: a?.suggestion, existing: a?.existing);
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
        path: '/stock-entry',
        builder: (_, state) {
          final a = state.extra as StockEntryArgs;
          return StockEntryPage(product: a.product, ean: a.ean);
        },
        redirect: (_, state) => state.extra is StockEntryArgs ? null : '/',
      ),
    ],
  );
});
