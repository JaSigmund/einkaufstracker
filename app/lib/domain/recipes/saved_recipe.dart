/// Eine Zutat eines gespeicherten Rezepts. `productId` ist `null` bei Zutaten ohne bekannte
/// Produkt-Zuordnung (z.B. wenn die KI einen Namen nannte, der nicht im Inventar-Kontext vorkam) --
/// solche Zutaten koennen nicht automatisch gegen das Inventar abgeglichen werden
/// (`findMissingIngredients` erwartet eine `productId`) und gelten deshalb immer als fehlend.
///
/// Bewusst OHNE Mengenangabe (Codereview-Fund 2026-10-01): eine fruehere Fassung speicherte hier den
/// Inventar-Bestand zum Speicherzeitpunkt und behandelte ihn spaeter als "vom Rezept benoetigte Menge"
/// -- aber wie viel ein Rezept tatsaechlich braucht, kennt das System nie: `suggest-recipes` ist
/// angewiesen, keine Mengen zu erfinden (Lebensmittelsicherheit), und der Nutzer wird beim Speichern
/// nicht danach gefragt. Ein Lagerbestand ist keine Rezept-Menge, auch wenn beide Zahlen sind. Siehe
/// `recipe_shopping_gap.dart`: "fehlt" heisst deshalb nur noch "kein aktiver Bestand vorhanden".
class SavedIngredient {
  const SavedIngredient({required this.productId, required this.name, required this.unit});

  final String? productId;
  final String name;
  final String unit;

  factory SavedIngredient.fromJson(Map<String, dynamic> json) => SavedIngredient(
        productId: json['productId'] as String?,
        name: json['name'] as String,
        unit: json['unit'] as String? ?? 'piece',
      );

  Map<String, dynamic> toJson() => {'productId': productId, 'name': name, 'unit': unit};
}

/// Ein gespeichertes Rezept (ADR-021, Jakobs Anforderung "Rezepte sollen auch gespeichert werden
/// koennen"). Nur Titel, die eigene (nicht kopierte) Zutatenliste und der Link zur echten Rezeptseite
/// -- keine Kochanleitung (Urheberrecht, siehe ADR-021). [notes] ist die einzige Ausnahme: eine Zubereitung, die der Nutzer selbst schreibt
/// (ADR-044). Eigene Rezepte haben einen leeren [sourceUrl].
///
/// **Vorerst rein lokal** (kein Sync): die Server-Tabelle dafuer ist nur als Entwurf vorhanden
/// (`supabase/planned/recipes_draft.sql`), noch nicht eingespielt. Gespeichert wird deshalb ueber den
/// bestehenden lokalen Schluessel-Wert-Speicher (`AppDatabase.getKv`/`setKv`, gleiches Muster wie z.B.
/// die ausstehenden Datei-Uploads in `receipt_file_service.dart`), nicht als eigene Drift-Tabelle --
/// sobald die Migration eingespielt ist, kann das 1:1 auf eine echte, synchronisierte Tabelle
/// umgestellt werden, ohne dass sich dieses Modell aendern muss.
class SavedRecipe {
  const SavedRecipe({required this.id, required this.title, required this.sourceUrl, required this.ingredients, required this.savedAt, this.notes = ''});

  final String id;
  final String title;
  final String sourceUrl;
  final List<SavedIngredient> ingredients;
  final DateTime savedAt;
  final String notes;

  factory SavedRecipe.fromJson(Map<String, dynamic> json) => SavedRecipe(
        id: json['id'] as String,
        title: json['title'] as String,
        sourceUrl: json['sourceUrl'] as String? ?? '',
        ingredients: [for (final i in (json['ingredients'] as List? ?? const [])) SavedIngredient.fromJson(i as Map<String, dynamic>)],
        savedAt: DateTime.parse(json['savedAt'] as String),
        notes: json['notes'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'sourceUrl': sourceUrl,
        'ingredients': [for (final i in ingredients) i.toJson()],
        'savedAt': savedAt.toIso8601String(),
        if (notes.isNotEmpty) 'notes': notes,
      };
}
