import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../common/app_update_banner.dart';
import '../diary/diary_page.dart';
import '../inventory/inventory_page.dart';
import '../receipt_import/scan_page.dart';
import '../receipts/receipts_overview.dart';
import '../report/report_page.dart';
import '../shopping_list/shopping_list_page.dart';

/// Ein Ziel der Hauptnavigation mit eigener URL (Deep-Link, Zurueck-Taste im Browser).
typedef HomeTab = ({String path, String label, IconData icon, IconData selected, Widget Function() page});

/// Fuenf Ziele, wie Material sie hoechstens empfiehlt (Codereview 2026-10-16, X1). Scannen ist kein Tab mehr, sondern
/// eine eigene Seite (`/scan`), die der Knopf "Scannen" oeffnet.
final homeTabs = <HomeTab>[
  (path: '/', label: 'Übersicht', icon: Icons.home_outlined, selected: Icons.home, page: () => const ReceiptsOverview()),
  (path: '/inventory', label: 'Inventar', icon: Icons.kitchen_outlined, selected: Icons.kitchen, page: () => const InventoryPage()),
  (path: '/list', label: 'Liste', icon: Icons.checklist_outlined, selected: Icons.checklist, page: () => const ShoppingListPage()),
  (path: '/report', label: 'Auswertung', icon: Icons.bar_chart_outlined, selected: Icons.bar_chart, page: () => const ReportPage()),
  (path: '/diary', label: 'Tagebuch', icon: Icons.restaurant_menu_outlined, selected: Icons.restaurant_menu, page: () => const DiaryPage()),
];

/// Die Tabs als eigene Navigatoren: jeder behaelt Scrollposition, Filter und Eingaben, waehrend ein anderer offen ist.
StatefulShellRoute homeShellRoute() => StatefulShellRoute(
      builder: (_, _, shell) => HomeShell(shell: shell),
      // Wie StatefulShellRoute.indexedStack, nur mit abgeschalteten Heroes in den verdeckten Tabs: Inventar und Tagebuch
      // haben je einen FAB mit demselben Standard-Hero-Tag, das gaebe beim Oeffnen einer Seite einen Konflikt.
      navigatorContainerBuilder: (_, shell, children) => IndexedStack(
        index: shell.currentIndex,
        children: [
          for (var i = 0; i < children.length; i++)
            HeroMode(enabled: i == shell.currentIndex, child: TickerMode(enabled: i == shell.currentIndex, child: children[i])),
        ],
      ),
      branches: [
        for (final t in homeTabs) StatefulShellBranch(routes: [GoRoute(path: t.path, builder: (_, _) => t.page())]),
      ],
    );

/// Bons und Barcodes erfassen; frueher der dritte Tab.
GoRoute scanRoute() => GoRoute(
      path: '/scan',
      builder: (_, _) => Scaffold(
        appBar: AppBar(title: const Text('Scannen')),
        body: const Column(children: [AppUpdateBanner(), Expanded(child: ScanPage())]),
      ),
    );

/// Rahmen mit Navigation: unten auf dem Handy, seitlich (NavigationRail) ab [railBreakpoint].
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  /// Ab hier (Material: "medium") Navigation an der Seite statt unten.
  static const railBreakpoint = 600.0;

  /// Breiter laufen die Listen nicht, auf Tablet und Desktop steht der Inhalt mittig (Codereview 2026-10-16, U5).
  static const maxContentWidth = 840.0;

  void _select(int i) => shell.goBranch(i, initialLocation: i == shell.currentIndex);

  List<Widget> _actions(BuildContext context, String path) => [
        if (path == '/inventory')
          IconButton(
            tooltip: 'Rezeptvorschläge',
            icon: const Icon(Icons.soup_kitchen_outlined),
            onPressed: () => context.push('/recipe-suggestions'),
          ),
        if (path == '/list')
          IconButton(
            key: const Key('shell-meal-plan'),
            tooltip: 'Wochenplan',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => context.push('/meal-plan'),
          ),
        if (path == '/diary')
          IconButton(
            tooltip: 'Journal',
            icon: const Icon(Icons.auto_stories_outlined),
            onPressed: () => context.push('/journal'),
          ),
        if (path == '/diary')
          IconButton(
            tooltip: 'Richtwerte',
            icon: const Icon(Icons.tune),
            onPressed: () => context.push('/nutrition-targets'),
          ),
        if (path == '/report')
          IconButton(
            tooltip: 'Trend über Monate',
            icon: const Icon(Icons.show_chart),
            onPressed: () => context.push('/trend'),
          ),
      ];

  @override
  Widget build(BuildContext context) {
    final tab = homeTabs[shell.currentIndex];
    final wide = MediaQuery.sizeOf(context).width >= railBreakpoint;
    void scan() => context.push('/scan');

    final body = Column(
      children: [
        const AppUpdateBanner(),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxContentWidth),
              child: SizedBox.expand(child: shell),
            ),
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(tab.label),
        actions: [
          ..._actions(context, tab.path),
          IconButton(
            key: const Key('shell-quick-intake'),
            tooltip: 'Schnell eintragen',
            icon: const Icon(Icons.water_drop_outlined),
            onPressed: () => context.push('/quick-intake'),
          ),
          // Auf dem Handy von jedem Tab aus erreichbar; breit steht der Knopf oben in der Seitenleiste
          if (!wide)
            IconButton(
              key: const Key('shell-scan'),
              tooltip: 'Scannen',
              icon: const Icon(Icons.document_scanner_outlined),
              onPressed: scan,
            ),
          IconButton(
            tooltip: 'Einstellungen',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      // Auf der Uebersicht ist Scannen die Hauptaktion; Inventar und Tagebuch haben ihren eigenen FAB. Eigener Hero-Tag:
      // beim Wechsel auf einen dieser Tabs stehen kurz beide FABs im Baum (der alte blendet aus).
      floatingActionButton: !wide && tab.path == '/'
          ? FloatingActionButton.extended(
              key: const Key('overview-scan-fab'),
              heroTag: 'overview-scan-fab',
              onPressed: scan,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Scannen'),
            )
          : null,
      body: wide
          ? Row(
              children: [
                _ScrollableRail(
                  rail: NavigationRail(
                    labelType: NavigationRailLabelType.all,
                    selectedIndex: shell.currentIndex,
                    onDestinationSelected: _select,
                    leading: FloatingActionButton(
                      key: const Key('shell-scan'),
                      heroTag: 'rail-scan-fab',
                      tooltip: 'Scannen',
                      elevation: 0,
                      onPressed: scan,
                      child: const Icon(Icons.document_scanner_outlined),
                    ),
                    destinations: [
                      for (final t in homeTabs)
                        NavigationRailDestination(icon: Icon(t.icon), selectedIcon: Icon(t.selected), label: Text(t.label)),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            )
          : body,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              // Fuenf Ziele passen auch auf schmale Handys mit Beschriftung
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              selectedIndex: shell.currentIndex,
              onDestinationSelected: _select,
              destinations: [
                for (final t in homeTabs)
                  NavigationDestination(icon: Icon(t.icon), selectedIcon: Icon(t.selected), label: t.label),
              ],
            ),
    );
  }
}

/// Die Seitenleiste scrollt, wenn sie nicht in die Hoehe passt (Handy quer, grosse Schrift).
class _ScrollableRail extends StatelessWidget {
  const _ScrollableRail({required this.rail});

  final Widget rail;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: IntrinsicHeight(child: rail),
          ),
        ),
      );
}
