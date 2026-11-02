import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../core/clock.dart';
import '../../data/cloud/cooking_cloud.dart';
import '../../data/local/database.dart';
import '../../domain/app_update/app_update_gate.dart';
import '../../domain/recipes/recipe_search_url.dart';
import '../../domain/recipes/recipe_suggestion.dart';
import '../../domain/recipes/recipe_suggestion_context.dart';
import '../../domain/recipes/saved_recipe.dart';
import 'plan_recipe.dart';
import 'recipe_viewer_page.dart';

const _cloudNoticeKv = 'cooking_cloud_notice_seen';

/// Einstiegspunkt fuer KI-Rezeptvorschlaege aus dem Inventar (ADR-021). Erzeugt nur auf Tastendruck
/// (Q-21, kein taeglicher Automatismus).
class RecipeSuggestionsPage extends ConsumerStatefulWidget {
  const RecipeSuggestionsPage({super.key});

  @override
  ConsumerState<RecipeSuggestionsPage> createState() => _RecipeSuggestionsPageState();
}

class _RecipeSuggestionsPageState extends ConsumerState<RecipeSuggestionsPage> {
  bool _loading = false;
  bool _allowMissing = false;
  String? _error;
  List<RecipeSuggestion>? _suggestions;
  List<RecipeIngredient> _lastIngredients = const [];
  final _savedTitles = <String>{};
  final _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    // Beim Seitenaufruf, unabhaengig vom Button -- blockiert den eigentlichen Vorschlag-Abruf nicht
    // (Q-23: reiner Hinweis, keine zusaetzliche Einwilligungs-Huerde).
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowFirstUseNotice());
  }

  Future<void> _fetchSuggestions(List<InventoryItem> active, Map<String, Product> products) async {
    final ingredients = buildRecipeSuggestionContext(
      [
        for (final item in active)
          if (products[item.productId] case final product?)
            (
              productId: item.productId,
              productName: product.name,
              quantity: item.quantity,
              unit: product.baseUnit,
              expiresOn: item.expiresOn,
              dateKind: item.dateKind,
            ),
      ],
      today: appClock.now(),
    );

    if (ingredients.isEmpty) {
      setState(() => _error = 'Im Inventar ist nichts, woraus sich ein Rezept vorschlagen ließe.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _suggestions = null;
    });
    try {
      final result = await ref.read(cookingCloudProvider).suggestRecipes([
        for (final i in ingredients) (name: i.productName, quantity: i.quantity, unit: i.unit),
      ], allowMissing: _allowMissing);
      if (!mounted) return;
      setState(() {
        _suggestions = result;
        _lastIngredients = ingredients;
        _savedTitles.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyError(Object e) {
    if (e is CookingCloudNotAllowed || e is CookingCloudDailyLimit || e is AppUpdateRequiredException) return e.toString();
    if (e is CookingCloudUnavailable) return 'Vorschläge gerade nicht verfügbar (${e.message}).';
    return 'Vorschläge gerade nicht verfügbar.';
  }

  /// Q-23: dieselbe Cloud-Einstellung wie bei der Bon-Erkennung gilt auch hier, aber beim ersten
  /// Öffnen zeigt ein einmaliger Hinweis, was konkret gesendet wird (Transparenz ohne neuen Schalter).
  Future<void> _maybeShowFirstUseNotice() async {
    final db = ref.read(databaseProvider);
    final seen = await db.getKv(_cloudNoticeKv);
    if (seen == 'true') return;
    await db.setKv(_cloudNoticeKv, 'true');
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rezeptvorschläge aus der Cloud'),
        content: const Text(
          'Dafür werden dein Inventar und deine Chat-Nachrichten an die Cloud geschickt — wie bei der '
          'Foto-Erkennung von Bons. Die Einstellung "Cloud-Auswertung erlauben" gilt auch hierfür.',
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Verstanden'))],
      ),
    );
  }

  void _openRecipe(RecipeSuggestion s) {
    context.push('/recipe-viewer', extra: RecipeViewerArgs(title: s.title, ingredients: [...s.matchingIngredients, ...s.missingIngredients]));
  }

  /// Speichert einen Vorschlag (Jakobs Anforderung "Rezepte sollen auch gespeichert werden können").
  /// Zutatennamen werden gegen [_lastIngredients] (der tatsächlich gesendete Inventar-Kontext)
  /// gematcht, um `productId`/Einheit zu übernehmen — nur so kann `findMissingIngredients` später
  /// wieder automatisch gegen das Inventar abgleichen (siehe `saved_recipe.dart`). Keine Menge: siehe
  /// Dokumentation dort (Codereview-Fund 2026-10-01).
  Future<void> _saveRecipe(RecipeSuggestion s) async {
    final ingredients = _ingredientsOf(s);
    await ref.read(savedRecipeRepositoryProvider).save(SavedRecipe(
          id: _uuid.v4(),
          title: s.title,
          sourceUrl: buildRecipeSearchUrl(s.title),
          ingredients: ingredients,
          savedAt: appClock.now().toUtc(),
        ));
    if (!mounted) return;
    setState(() => _savedTitles.add(s.title));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('"${s.title}" gespeichert.')));
  }

  /// Alle Zutaten eines Vorschlags: vorhandene mit Produkt-Zuordnung, fehlende nur mit Namen.
  List<SavedIngredient> _ingredientsOf(RecipeSuggestion s) => [
        for (final name in [...s.matchingIngredients, ...s.missingIngredients])
          if (_matchByName(name) case final match?)
            SavedIngredient(productId: match.productId, name: name, unit: match.unit)
          else
            SavedIngredient(productId: null, name: name, unit: 'piece'),
      ];

  RecipeIngredient? _matchByName(String name) {
    for (final i in _lastIngredients) {
      if (i.productName == name) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    // ref.watch (nicht read): haelt beide Streams von Beginn an abonniert, damit ihr Wert schon
    // bereitsteht, sobald der Nutzer den Button antippt (sonst waere der erste Tastendruck nach dem
    // Oeffnen der Seite immer mit einem leeren, noch nicht angekommenen Inventar unterwegs).
    final active = ref.watch(activeInventoryStreamProvider).value ?? const <InventoryItem>[];
    final products = {for (final p in ref.watch(productsStreamProvider).value ?? const <Product>[]) p.id: p};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rezeptvorschläge'),
        actions: [
          IconButton(
            key: const Key('open-meal-plan'),
            tooltip: 'Wochenplan',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => context.push('/meal-plan'),
          ),
          IconButton(
            key: const Key('open-saved-recipes'),
            tooltip: 'Meine Rezepte',
            icon: const Icon(Icons.bookmarks_outlined),
            onPressed: () => context.push('/saved-recipes'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Schlägt Rezepte aus dem vor, was gerade im Haus ist — bevorzugt das, was bald abläuft.',
            style: t.textTheme.bodyMedium,
          ),
          SwitchListTile(
            key: const Key('suggestions-allow-missing'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Auch mit Zutaten, die noch fehlen'),
            subtitle: const Text('Für die Wochenplanung: Fehlendes lässt sich danach auf die Einkaufsliste setzen.'),
            value: _allowMissing,
            onChanged: _loading ? null : (v) => setState(() => _allowMissing = v),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('fetch-suggestions'),
            onPressed: _loading ? null : () => _fetchSuggestions(active, products),
            icon: _loading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome),
            label: const Text('Vorschläge erzeugen'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_error!, key: const Key('suggestions-error'), style: TextStyle(color: t.colorScheme.error)),
            ),
          if (_suggestions != null)
            for (final s in _suggestions!)
              Card(
                margin: const EdgeInsets.only(top: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                ListTile(
                  title: Text(s.title),
                  subtitle: Text([
                    s.reason.isEmpty ? s.matchingIngredients.join(', ') : s.reason,
                    if (s.missingIngredients.isNotEmpty) 'Fehlt: ${s.missingIngredients.join(', ')}',
                  ].join('\n')),
                  onTap: () => _openRecipe(s),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      key: Key('save-${s.title}'),
                      tooltip: _savedTitles.contains(s.title) ? 'Gespeichert' : 'Rezept speichern',
                      icon: Icon(_savedTitles.contains(s.title) ? Icons.bookmark : Icons.bookmark_outline),
                      onPressed: _savedTitles.contains(s.title) ? null : () => _saveRecipe(s),
                    ),
                    const Icon(Icons.chevron_right),
                  ]),
                ),
                OverflowBar(alignment: MainAxisAlignment.end, children: [
                  if (s.missingIngredients.isNotEmpty)
                    TextButton.icon(
                      key: Key('missing-to-list-${s.title}'),
                      onPressed: () => addMissingToList(context, ref, _ingredientsOf(s), active: active, products: products.values.toList()),
                      icon: const Icon(Icons.add_shopping_cart_outlined),
                      label: const Text('Fehlendes auf die Liste'),
                    ),
                  TextButton.icon(
                    key: Key('plan-${s.title}'),
                    onPressed: () => addRecipeToPlan(context, ref, title: s.title, ingredients: _ingredientsOf(s), sourceUrl: buildRecipeSearchUrl(s.title)),
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: const Text('In den Wochenplan'),
                  ),
                ]),
                ]),
              ),
        ],
      ),
    );
  }
}
