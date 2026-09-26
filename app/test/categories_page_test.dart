import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/data/local/database.dart';
import 'package:einkaufstracker/features/categories/categories_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('Der letzte Eintrag laesst sich bedienen: Menue-Knopf liegt nicht unter dem "+ Kategorie"-Knopf', (tester) async {
    final db = memoryDb();
    addTearDown(db.close);
    final cats = [
      for (var i = 0; i < 30; i++)
        Category(id: 'c$i', householdId: 'h', name: 'Kategorie $i', sortOrder: i, isStorable: true, updatedAt: DateTime.utc(2026)),
    ];

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        categoriesStreamProvider.overrideWith((ref) => Stream.value(cats)),
        // feste Werte statt Drift-Stroeme: in Widget-Tests blockieren deren Aufraeum-Timer das Beenden
        pendingChangesProvider.overrideWith((ref) => Stream.value(0)),
      ],
      child: const MaterialApp(home: CategoriesPage()),
    ));
    await tester.pumpAndSettle();

    // ganz nach unten scrollen
    await tester.drag(find.byType(ListView), const Offset(0, -6000));
    await tester.pumpAndSettle();

    final fab = tester.getRect(find.byType(FloatingActionButton));
    final lastMenu = tester.getRect(find.byType(PopupMenuButton<String>).last);
    expect(fab.overlaps(lastMenu), isFalse, reason: 'FAB $fab verdeckt Menue $lastMenu');
    expect(find.text('Kategorie 29'), findsOneWidget);
  });
}
