import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../inventory/inventory_page.dart';
import '../receipt_import/scan_page.dart';
import '../receipts/receipts_overview.dart';
import '../report/report_page.dart';
import '../shopping_list/shopping_list_page.dart';

/// Rahmen mit Navigation. Die Inhalte der Tabs kommen in spaeteren Phasen (siehe Roadmap).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _tabs =
      <({String label, IconData icon, IconData selected, String hint})>[
        (
          label: 'Übersicht',
          icon: Icons.home_outlined,
          selected: Icons.home,
          hint: 'Monatssumme und bald ablaufende Produkte (Phase 2/3)',
        ),
        (
          label: 'Inventar',
          icon: Icons.kitchen_outlined,
          selected: Icons.kitchen,
          hint: 'Vorräte mit Haltbarkeit (Phase 3)',
        ),
        (
          label: 'Scan',
          icon: Icons.document_scanner_outlined,
          selected: Icons.document_scanner,
          hint: 'Bons und Barcodes (Phase 2/3)',
        ),
        (
          label: 'Liste',
          icon: Icons.checklist_outlined,
          selected: Icons.checklist,
          hint: 'Einkaufsliste (Phase 3)',
        ),
        (
          label: 'Auswertung',
          icon: Icons.bar_chart_outlined,
          selected: Icons.bar_chart,
          hint: 'Ausgaben nach Kategorie (Phase 2)',
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final tab = _tabs[_index];
    return Scaffold(
      appBar: AppBar(
        title: Text(tab.label),
        actions: [
          if (_index == 1)
            IconButton(
              tooltip: 'Rezeptvorschläge',
              icon: const Icon(Icons.restaurant_menu_outlined),
              onPressed: () => context.push('/recipe-suggestions'),
            ),
          if (_index == 4)
            IconButton(
              tooltip: 'Trend über Monate',
              icon: const Icon(Icons.show_chart),
              onPressed: () => context.push('/trend'),
            ),
          IconButton(
            tooltip: 'Einstellungen',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: _index == 0
          ? const ReceiptsOverview()
          : _index == 1
          ? const InventoryPage()
          : _index == 2
          ? const ScanPage()
          : _index == 3
          ? const ShoppingListPage()
          : _index == 4
          ? const ReportPage()
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      tab.selected,
                      size: 48,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Noch nicht gebaut',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(tab.hint, textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/categories'),
                      icon: const Icon(Icons.category_outlined),
                      label: const Text('Kategorien verwalten'),
                    ),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final t in _tabs)
            NavigationDestination(
              icon: Icon(t.icon),
              selectedIcon: Icon(t.selected),
              label: t.label,
            ),
        ],
      ),
    );
  }
}
