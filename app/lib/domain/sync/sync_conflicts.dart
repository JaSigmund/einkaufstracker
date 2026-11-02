/// Text zu Sync-Konflikten (ADR-018, Phase 6): Eine Aenderung dieses Geraets hat beim Senden eine neuere Aenderung eines
/// anderen Geraets oder Haushaltsmitglieds ueberschrieben (Last-write-wins, aber sichtbar). Reine Funktionen.
library;

/// Bereich der App, zu dem eine Server-Tabelle gehoert, fuer die Anzeige. Unbekannte Tabellen heissen "Daten".
String conflictAreaLabel(String table) => switch (table) {
      'shopping_lists' || 'shopping_list_items' => 'Einkaufsliste',
      'inventory_items' || 'inventory_movements' => 'Inventar',
      'products' || 'product_barcodes' || 'product_aliases' || 'product_online_links' => 'Produkte',
      'receipts' || 'receipt_items' || 'receipt_files' || 'stores' => 'Bons',
      'categories' || 'category_aliases' => 'Kategorien',
      'meals' || 'meal_ingredients' || 'household_food_links' => 'Tagebuch',
      'nutrition_targets' => 'Richtwerte',
      'supplements' || 'supplement_intakes' => 'Nahrungsergänzung',
      'household_prefs' => 'Einstellungen',
      'meal_plan_entries' => 'Wochenplan',
      'cooking_sessions' => 'Kochzeiten',
      'bug_reports' => 'Rückmeldungen',
      _ => 'Daten',
    };

/// Eine Zeile fuer die Anzeige, `null` ohne Konflikte. Zaehlt die Aenderungen und nennt die betroffenen Bereiche in der
/// Reihenfolge ihres ersten Auftretens: "Deine Änderung hat eine neuere von jemand anderem überschrieben (Einkaufsliste)."
String? conflictSummary(List<({String table, String rowId})> conflicts) {
  if (conflicts.isEmpty) return null;
  final areas = <String>[];
  for (final c in conflicts) {
    final label = conflictAreaLabel(c.table);
    if (!areas.contains(label)) areas.add(label);
  }
  final where = areas.join(', ');
  return conflicts.length == 1
      ? 'Deine Änderung hat eine neuere von jemand anderem überschrieben ($where).'
      : '${conflicts.length} Änderungen von dir haben neuere von anderen überschrieben ($where).';
}

/// Fuegt neue Konflikte zu den noch nicht bestaetigten hinzu, ohne dieselbe Zeile doppelt zu fuehren.
List<({String table, String rowId})> mergeConflicts(
  List<({String table, String rowId})> existing,
  List<({String table, String rowId})> added,
) {
  final seen = {for (final c in existing) '${c.table}:${c.rowId}'};
  return [
    ...existing,
    for (final c in added)
      if (seen.add('${c.table}:${c.rowId}')) c,
  ];
}
