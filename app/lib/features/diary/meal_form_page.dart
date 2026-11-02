import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/clock.dart';
import '../../core/format.dart';
import '../common/quantity_dialog.dart' show describeStock;
import '../../data/cloud/cooking_cloud.dart';
import '../../data/local/database.dart';
import '../../data/repositories/meal_repository.dart';
import '../../domain/app_update/app_update_gate.dart';
import '../../domain/nutrition/daily_nutrition.dart';
import '../../domain/nutrition/food_match.dart';
import '../../domain/nutrition/food_unit.dart';
import '../../domain/nutrition/ingredient_nutrition.dart';
import '../../domain/nutrition/meal_analysis.dart';
import '../../domain/nutrition/micros.dart';
import '../../domain/nutrition/retention.dart';
import '../../domain/nutrition/usual_ingredients.dart';
import '../../domain/nutrition/nutrient_scaling.dart';
import '../../core/vienna_time.dart';
import '../../domain/recipes/cooking_timer.dart' show normalizeRecipeTitle;
import 'ingredient_picker.dart';
import 'manual_nutrients_dialog.dart';
import 'meal_labels.dart';
import 'meal_photo.dart';
import 'recipe_picker.dart';

/// Argumente fuer `/meal-form`: ohne [existing] wird eine neue Mahlzeit angelegt, sonst diese bearbeitet.
///
/// Mit [template] entsteht eine NEUE Mahlzeit als Kopie einer frueheren ("Nochmal essen", Doku 15 §3.2): Titel,
/// Portionen und Zutaten werden uebernommen, Zeitpunkt ist jetzt. Mit [leftover] ist es ein Rest vom Vortag: gleiche
/// Naehrwerte, aber ohne erneuten Abzug vom Bestand. Mit [recipe] entsteht sie aus einem Rezept oder geplanten Gericht (ADR-047).
class MealFormArgs {
  const MealFormArgs({this.existing, this.template, this.leftover = false, this.recipe});
  final Meal? existing;
  final Meal? template;
  final bool leftover;
  final RecipeForMeal? recipe;
}

/// Eine Zutat im Formular, noch nicht gespeichert.
class _Row {
  _Row({
    this.product,
    this.freeText,
    required this.quantity,
    required this.unit,
    this.per100,
    this.per100Basis,
    this.manual,
    this.deduct = false,
    this.source,
    this.confidence,
    this.blsCode,
    this.matchName,
    this.matchTrust = MatchTrust.sure,
    this.learn = false,
    this.unitKey,
    this.unitWeightG,
    this.learnWeight = false,
    this.microsPer100,
    this.preparation,
    this.inferred = false,
    this.lineProfileWins = false,
  });

  Product? product;
  String? freeText;
  double quantity;
  EntryUnit unit;
  NutrientsPer100? per100;
  String? per100Basis;
  NutrientAmounts? manual;
  bool deduct;
  String? source;

  /// Sicherheit der Foto-Analyse (0 bis 1), nur bei Zutaten aus einem KI-Vorschlag.
  double? confidence;

  /// KI-Vorschlag, den man auf dem Foto nicht sieht (Bratoel, Dressing): In der Zeile steht "vermutet".
  bool inferred;

  /// [per100] gilt, obwohl das Produkt ein eigenes Profil hat: Die Menge ist "wie gegessen" (Q-28), das Profil des Produkts gilt fuer die
  /// rohe Ware. 200 g gekochter Reis haben etwa 260 kcal, nicht die 700 kcal von 200 g rohem.
  bool lineProfileWins;

  /// BLS-Eintrag, aus dem [per100] stammt (Phase N1), sein Name und wie sicher die Zuordnung ist. [learn]: beim Speichern
  /// im Gedaechtnis des Haushalts vermerken (nur sinnvoll, wenn die Zuordnung dem Server noch nicht bekannt war).
  String? blsCode;
  String? matchName;
  MatchTrust matchTrust;
  bool learn;

  /// Haushaltseinheit ("Scheibe", "EL"), wenn die Menge als [EntryUnit.piece] erfasst ist, und das Gewicht von 1 Einheit in g
  /// (Phase N2, ADR-033). [learnWeight]: das Gewicht hat der Nutzer selbst eingetragen und wird beim Speichern gemerkt.
  FoodUnitKey? unitKey;
  double? unitWeightG;
  bool learnWeight;

  /// Mikronaehrstoffe je 100 g des zugeordneten BLS-Eintrags (Phase N3); bei Produkten mit eigenem Profil nimmt das Repository
  /// das Profil des Produkts.
  Micros? microsPer100;

  /// Zubereitung fuer die Garfaktoren (Phase N4, ADR-037): `kategorie:zubereitung`, `null` = roh. [microsPer100] bleibt das rohe Profil,
  /// das Repository mindert beim Speichern.
  String? preparation;

  /// Kategorie fuer die Garfaktoren, wenn es sie fuer diese Zeile gibt: nur ein roher BLS-Eintrag ohne Produkt und ohne Handwerte, dessen Name
  /// bekannt ist (oder eine schon gespeicherte Zubereitung). `null`: keine Auswahl anbieten.
  String? get retentionCategoryOfRow {
    if (product != null || manual != null || blsCode == null || microsPer100 == null) return null;
    final stored = retentionFromStorage(preparation)?.category;
    if (stored != null) return stored;
    final name = matchName;
    return name == null ? null : retentionCategory(blsCode: blsCode!, name: name, fatPer100: per100?.fatG);
  }

  String get label => product?.name ?? freeText ?? 'Zutat';

  /// Naehrwertprofil des Produkts, falls es eines hat (Produkte vom Bon haben meist keines).
  NutrientsPer100? get _productProfile => product == null || lineProfileWins ? null : productNutrientProfile(product!);

  /// Wie sicher die Naehrwerte dieser Zeile sind: Produkt mit eigenem Profil und Handwerte gelten als sicher, ein BLS-Treffer
  /// nach seiner Zuordnung, ohne Naehrwerte ist es unbekannt.
  MatchTrust get trust {
    if (manual != null) return MatchTrust.sure;
    if (_productProfile != null) return MatchTrust.sure;
    if (per100 == null) return MatchTrust.unknown;
    return blsCode != null ? matchTrust : MatchTrust.sure;
  }

  IngredientDraft toDraft() => IngredientDraft(
        productId: product?.id,
        freeText: product == null ? freeText : null,
        quantity: quantity,
        entryUnit: unit,
        source: source,
        per100: per100,
        per100Basis: per100Basis,
        manualNutrients: manual,
        deduct: deduct && product != null,
        confidence: confidence,
        blsCode: blsCode,
        nutrientBasis: manual != null ? 'manual' : (_productProfile != null ? 'product' : (blsCode != null && per100 != null ? trust.basis : null)),
        unitWeightG: unit == EntryUnit.piece ? unitWeightG : null,
        unitKey: unit == EntryUnit.piece ? unitKey : null,
        microsPer100: microsPer100,
        preparation: retentionCategoryOfRow == null ? null : preparation,
        lineProfileWins: lineProfileWins,
      );

  /// Das Naehrwertprofil, mit dem diese Zeile rechnet (Produkt vor BLS-Eintrag).
  NutrientsPer100? get profile => _productProfile ?? per100;

  /// "2 Scheiben", "1 Stk", "80 g": die Menge, wie der Nutzer sie sieht.
  String get quantityText => '${formatQuantity(quantity)} ${unit == EntryUnit.piece && unitKey != null ? unitKey!.labelFor(quantity) : unit.label}';

  /// Naehrwerte dieser Zutat, wie sie beim Speichern berechnet wuerden; `null`, wenn unbekannt. Ein Produkt ohne eigenes Profil
  /// nutzt das Profil des zugeordneten BLS-Eintrags (Phase N1).
  NutrientAmounts? get nutrients {
    final profile = _productProfile ?? per100;
    final basis = _productProfile != null ? product!.nutrientsBasis : per100Basis;
    return manual ?? ingredientNutrients(profile, _amount(profile == null ? null : basis));
  }

  /// Der Abzug ist gewuenscht, die Menge laesst sich aber nicht in die Einheit des Bestands umrechnen: Beim Speichern wird nichts abgezogen.
  bool get deductBlocked => deduct && product != null && _amount(null).inventoryQuantity == null;

  IngredientAmount _amount(String? nutrientsBasis) => resolveIngredientAmount(
        quantity: quantity,
        entryUnit: unit,
        baseUnit: product?.baseUnit ?? unit.dimensionBaseUnit,
        nutrientsBasis: nutrientsBasis,
        unitWeightG: unitWeightG,
        productPieceWeightG: product?.unitWeightG,
        unitKey: unitKey,
      );
}

/// Mahlzeit erfassen oder bearbeiten (Doku 15 §3.1, Phase 7b): Titel, Zeitpunkt, Typ, Portionen und Zutaten aus
/// dem Inventar, aus der Lebensmitteldatenbank oder als Freitext. Beim Speichern wird der Bestand FEFO abgezogen,
/// beim Bearbeiten der alte Abzug per Gegenbuchung zurueckgenommen und neu gerechnet.
class MealFormPage extends ConsumerStatefulWidget {
  const MealFormPage({super.key, this.existing, this.template, this.leftover = false, this.recipe, this.photosAvailable = !kIsWeb});

  final Meal? existing;
  final Meal? template;
  final bool leftover;
  final RecipeForMeal? recipe;

  /// Mahlzeitenfotos brauchen lokalen Dateispeicher (`MealPhotoService`), den es in der Web-Version (PWA) nicht gibt.
  /// Dort fehlt der Foto-Bereich samt Foto-Analyse, statt bei jedem Speichern zu scheitern. Als Parameter statt einer
  /// festverdrahteten `kIsWeb`-Abfrage, damit beide Faelle testbar sind.
  final bool photosAvailable;

  @override
  ConsumerState<MealFormPage> createState() => _MealFormPageState();
}

class _MealFormPageState extends ConsumerState<MealFormPage> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  final _eaten = TextEditingController(text: '1');
  final _made = TextEditingController(text: '1');
  late String _type;

  /// Der Nutzer hat den Mahlzeitentyp selbst gewaehlt: Die Foto-Analyse aendert ihn dann nicht mehr.
  var _typeChosen = false;
  late DateTime _eatenAt;
  var _estimate = false;
  final _rows = <_Row>[];

  /// Neu aufgenommenes oder gewaehltes Foto (bereits verkleinert), noch nicht gespeichert.
  Uint8List? _newPhoto;

  /// Das vorhandene Foto soll beim Speichern entfernt werden.
  var _photoRemoved = false;
  var _saving = false;

  /// Foto-Analyse laeuft, und der Hinweis nach einem angewendeten Vorschlag.
  var _analyzing = false;
  var _analysisApplied = false;
  String? _analysisNotes;

  /// "Fehlt etwas?": uebliche Zutaten aus aehnlichen frueheren Mahlzeiten, die auf dem Foto nicht zu sehen sind (Ausbau 1.12).
  List<UsualIngredient> _usual = const [];

  /// Ein Rezept wurde uebernommen (ADR-047), und wann dieses Gericht zuletzt gegessen wurde, falls die Mengen von dort stammen.
  var _recipeApplied = false;
  DateTime? _recipeAmountsFrom;

  /// `manual` | `photo_ai` | `recipe`: woher die Mahlzeit stammt. Nach einem angewendeten KI-Vorschlag `photo_ai`.
  late String _source = widget.existing?.source ?? widget.template?.source ?? 'manual';
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final m = widget.existing;
    _eatenAt = m?.eatenAt.toUtc() ?? appClock.now().toUtc();
    _type = m?.mealType ?? guessMealType(utcToViennaLocal(_eatenAt).hour);
    if (m != null) {
      _title.text = m.title;
      _note.text = m.note ?? '';
      _eaten.text = formatQuantity(m.servingsEaten);
      _made.text = formatQuantity(m.servingsMade);
      _estimate = m.isEstimate;
      _loadExistingIngredients(m);
    }
    final tpl = widget.template;
    if (tpl != null) {
      // Kopie einer frueheren Mahlzeit: Zeitpunkt ist jetzt, der Typ richtet sich nach der Uhrzeit (ein Muesli von
      // gestern Abend ist heute frueh ein Fruehstueck). Foto und Notiz werden nicht uebernommen.
      _title.text = tpl.title;
      _eaten.text = formatQuantity(tpl.servingsEaten);
      _made.text = formatQuantity(tpl.servingsMade);
      _estimate = tpl.isEstimate;
      _loadExistingIngredients(tpl, noDeduction: widget.leftover);
    }
    if (widget.recipe != null) _applyRecipe(widget.recipe!);
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _eaten.dispose();
    _made.dispose();
    super.dispose();
  }

  Future<void> _loadExistingIngredients(Meal m, {bool noDeduction = false}) async {
    final ingredients = await ref.read(mealRepositoryProvider).ingredientsOf(m.id);
    final products = {for (final p in await ref.read(productRepositoryProvider).allSnapshot()) p.id: p};
    final rows = _rowsFrom(ingredients, products, noDeduction: noDeduction);
    if (mounted) setState(() => _rows..clear()..addAll(rows));
    _resolveBlsNames();
  }

  /// Uebernimmt ein Rezept (ADR-047). Rezepte kennen bewusst keine Mengen (ADR-021). Gab es das Gericht schon einmal im Tagebuch, stehen dort die
  /// Mengen, die der Haushalt wirklich nimmt: deshalb die Zeilen der letzten Mahlzeit mit diesem Namen als Vorlage, dazu was im Rezept sonst noch steht.
  Future<void> _applyRecipe(RecipeForMeal recipe) async {
    final allProducts = await ref.read(productRepositoryProvider).allSnapshot();
    final products = {for (final p in allProducts) p.id: p};
    final history = await ref.read(mealRepositoryProvider).recentHistory(excludeMealId: widget.existing?.id);
    final key = normalizeRecipeTitle(recipe.title);
    final previous = history.where((h) => normalizeRecipeTitle(h.$1.title) == key).firstOrNull;
    // Aus initState heraus hat der Stream noch keinen Wert (siehe Kommentar in build), deshalb auf ihn warten
    final active = await ref.read(activeInventoryStreamProvider.future).timeout(const Duration(seconds: 3), onTimeout: () => const <InventoryItem>[]);
    final inStock = {for (final i in active) if (i.quantity > 0) i.productId};

    final added = previous == null ? <_Row>[] : _rowsFrom(previous.$2, products);
    final names = {for (final r in [..._rows, ...added]) r.label.trim().toLowerCase()};
    final productIds = {for (final r in [..._rows, ...added]) ?r.product?.id};
    for (final i in recipe.ingredients) {
      final lower = i.name.trim().toLowerCase();
      final byId = products[i.productId];
      final product = byId != null && byId.deletedAt == null ? byId : allProducts.where((p) => p.deletedAt == null && p.name.trim().toLowerCase() == lower).firstOrNull;
      if (lower.isEmpty || names.contains(lower) || (product != null && productIds.contains(product.id))) continue;
      names.add(lower);
      if (product != null) productIds.add(product.id);
      added.add(_Row(
        product: product,
        freeText: product == null ? i.name.trim() : null,
        quantity: 0,
        unit: product != null ? EntryUnit.naturalFor(product.baseUnit) : EntryUnit.g,
        deduct: product != null && inStock.contains(product.id),
      ));
    }
    await _fillKnownFoods(added);
    if (!mounted) return;
    setState(() {
      final firstRows = _rows.isEmpty;
      _rows.addAll(added);
      if (_title.text.trim().isEmpty) _title.text = recipe.title;
      if (recipe.mealType != null && !_typeChosen) _type = recipe.mealType!;
      if (previous != null && firstRows) {
        _eaten.text = formatQuantity(previous.$1.servingsEaten);
        _made.text = formatQuantity(previous.$1.servingsMade);
        _estimate = previous.$1.isEstimate;
      }
      _source = 'recipe';
      _recipeApplied = true;
      _recipeAmountsFrom = previous?.$1.eatenAt;
    });
    _resolveBlsNames();
  }

  /// Zutaten, deren Name dem Haushalt schon bekannt ist, bekommen ihre Naehrwerte sofort. Ohne Netz oder bei einem Fehler bleibt die Lupe in der Zeile.
  Future<void> _fillKnownFoods(List<_Row> rows) async {
    try {
      final links = {for (final l in await ref.read(foodLinkRepositoryProvider).all()) l.nameNorm.trim().toLowerCase(): l.blsCode};
      final open = [for (final r in rows) if (r.product == null && r.per100 == null && r.manual == null && links.containsKey(r.label.trim().toLowerCase())) r];
      if (open.isEmpty) return;
      final foods = {for (final f in await ref.read(blsFoodSearchProvider).byCodes({for (final r in open) links[r.label.trim().toLowerCase()]!})) f.code: f};
      for (final r in open) {
        final food = foods[links[r.label.trim().toLowerCase()]];
        if (food == null) continue;
        r
          ..per100 = food.per100
          ..per100Basis = 'g'
          ..blsCode = food.code
          ..matchName = food.nameDe
          ..microsPer100 = food.micros;
      }
    } catch (_) {
      // die Naehrwerte sind eine Zugabe
    }
  }

  Future<void> _pickRecipe() async {
    final picked = await showRecipePicker(context);
    if (picked != null && mounted) await _applyRecipe(picked);
  }

  /// Zeilen aus gespeicherten Zutaten einer Mahlzeit.
  List<_Row> _rowsFrom(List<MealIngredient> ingredients, Map<String, Product> products, {bool noDeduction = false}) {
    final rows = <_Row>[];
    for (final i in ingredients) {
      final (qty, unit) = switch (i.unit) {
        'kg' => (i.quantity * 1000, EntryUnit.g),
        'l' => (i.quantity * 1000, EntryUnit.ml),
        _ => (i.quantity, EntryUnit.piece),
      };
      final product = i.productId == null ? null : products[i.productId];
      NutrientsPer100? per100;
      NutrientAmounts? manual;
      // Ein Produkt speichert seinen BLS-Code nur, wenn die Zeile mit dem BLS-Eintrag gerechnet hat (siehe MealRepository)
      final fromSnapshot = product == null || i.blsCode != null;
      if (fromSnapshot) {
        // Ohne Produkt (Freitext, BLS oder geloeschtes Produkt) steht nur der Snapshot zur Verfuegung: daraus je 100 g
        // zurueckrechnen, damit die Menge noch aenderbar bleibt; ohne bekannte Menge bleiben die Werte absolut.
        final basis = i.amountG;
        double? per(double? v) => (v == null || basis == null || basis <= 0) ? null : v * 100 / basis;
        if (basis != null && basis > 0) {
          per100 = NutrientsPer100(
            kcal: per(i.kcal),
            proteinG: per(i.proteinG),
            fatG: per(i.fatG),
            carbsG: per(i.carbsG),
            sugarG: per(i.sugarG),
            fiberG: per(i.fiberG),
            saltG: per(i.saltG),
          );
        } else if (product == null && [i.kcal, i.proteinG, i.fatG, i.carbsG, i.sugarG, i.fiberG, i.saltG].any((v) => v != null)) {
          manual = NutrientAmounts(
            kcal: i.kcal, proteinG: i.proteinG, fatG: i.fatG, carbsG: i.carbsG, sugarG: i.sugarG, fiberG: i.fiberG, saltG: i.saltG,
          );
        }
      }
      rows.add(_Row(
        product: product,
        freeText: product == null ? (i.freeText ?? 'Gelöschtes Produkt') : null,
        quantity: qty,
        unit: unit,
        per100: per100,
        per100Basis: per100 == null ? null : 'g',
        manual: manual,
        deduct: !noDeduction && (i.source == 'inventory' || i.inventoryItemId != null),
        source: i.source,
        confidence: i.confidence,
        blsCode: i.blsCode,
        matchTrust: i.nutrientBasis == 'bls_matched' ? MatchTrust.auto : MatchTrust.sure,
        // Bei Stueckmengen steht das Gewicht einer Einheit im Snapshot (Menge in g durch Anzahl)
        unitWeightG: unit == EntryUnit.piece && i.amountG != null && i.quantity > 0 ? i.amountG! / i.quantity : null,
        unitKey: unit == EntryUnit.piece ? FoodUnitKey.fromDb(i.unitKey) : null,
        microsPer100: fromSnapshot ? undoRetention(micros100From(parseMicros(i.micros), i.amountG), retentionFromStorage(i.preparation)) : null,
        preparation: product == null && retentionFromStorage(i.preparation) != null ? i.preparation : null,
        lineProfileWins: product != null && per100 != null,
      ));
    }
    return rows;
  }

  /// Zeilen aus frueheren Mahlzeiten kennen nur den BLS-Code, nicht den Namen des Eintrags. Fuer die Garfaktoren braucht die Zeile ihn: aus
  /// der Datenbank holen. Ohne Netz oder bei einem Fehler bleibt es ohne Auswahl der Zubereitung, alles andere funktioniert.
  Future<void> _resolveBlsNames() async {
    final codes = {for (final r in _rows) if (r.product == null && r.blsCode != null && r.matchName == null && r.microsPer100 != null) r.blsCode!};
    if (codes.isEmpty) return;
    try {
      final foods = {for (final f in await ref.read(blsFoodSearchProvider).byCodes(codes)) f.code: f.nameDe};
      if (!mounted) return;
      setState(() {
        for (final r in _rows) {
          if (r.matchName == null && r.blsCode != null && foods.containsKey(r.blsCode)) r.matchName = foods[r.blsCode];
        }
      });
    } catch (_) {
      // die Zubereitung ist eine Zugabe
    }
  }

  bool get _hasPhoto => _newPhoto != null || (_isEdit && widget.existing!.photoPath != null && !_photoRemoved);

  Future<void> _pickPhoto({required bool camera}) async {
    try {
      final raw = await ref.read(mealPhotoPickerProvider)(camera: camera);
      if (raw == null || !mounted) return;
      // Gleich verkleinern: ein unlesbares Bild (z.B. HEIC aus der Galerie) soll jetzt auffallen, nicht erst nach dem
      // Speichern der Mahlzeit.
      final prepared = await ref.read(mealPhotoServiceProvider).prepare(raw);
      if (mounted) {
        setState(() {
          _newPhoto = prepared;
          _photoRemoved = false;
          _error = null;
        });
      }
    } on FormatException {
      if (mounted) setState(() => _error = 'Das Foto konnte nicht gelesen werden. Bitte ein JPEG oder PNG wählen.');
    } catch (e) {
      if (mounted) setState(() => _error = 'Foto nicht verfügbar: $e');
    }
  }

  /// Wendet die Foto-Entscheidung auf die gespeicherte Mahlzeit an. Ein Fehler hier macht die Mahlzeit nicht
  /// rueckgaengig (sie ist gespeichert), wird aber gemeldet.
  Future<String?> _applyPhoto(Meal saved) async {
    try {
      final service = ref.read(mealPhotoServiceProvider);
      if (_newPhoto != null) {
        await service.attach(saved, _newPhoto!, prepared: true);
      } else if (_photoRemoved && widget.existing?.photoPath != null) {
        await service.purge(widget.existing!, clearPath: true);
      }
      return null;
    } catch (e) {
      return 'Die Mahlzeit ist gespeichert, das Foto konnte nicht abgelegt werden: $e';
    }
  }

  static const _analysisNoticeKv = 'meal_analysis_notice_seen';

  /// Einmaliger Hinweis vor dem ersten Senden eines Fotos (Doku 15 §6: dieselbe Einwilligungslogik wie bei den Bons,
  /// aber ein Foto ist etwas anderes als Text, deshalb wird hier ausdruecklich bestaetigt).
  Future<bool> _confirmFirstUse() async {
    final db = ref.read(databaseProvider);
    if (await db.getKv(_analysisNoticeKv) == 'true') return true;
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Foto in der Cloud auswerten?'),
        content: const Text(
          'Das Foto und die Namen deiner Produkte werden zusammen mit Titel, Notiz, Portionen und schon eingetragenen Zutaten der '
          'Mahlzeit zur Auswertung an Claude (Anthropic) geschickt. Die App legt das Foto '
          'dafür nicht zusätzlich auf dem Server ab; wie lange Anthropic Eingaben aufbewahrt, regeln deren eigene Bedingungen. '
          'Die Einstellung „Cloud-Auswertung erlauben“ gilt auch hierfür. '
          'Der Vorschlag ist eine Schätzung, du prüfst und änderst ihn, bevor etwas gespeichert wird.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(key: const Key('meal-analyze-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Senden')),
        ],
      ),
    );
    if (ok != true) return false;
    await db.setKv(_analysisNoticeKv, 'true');
    return true;
  }

  String _analysisError(Object e) {
    if (e is CookingCloudNotAllowed || e is CookingCloudDailyLimit || e is AppUpdateRequiredException) return e.toString();
    if (e is CookingCloudUnavailable) return 'Die Foto-Analyse ist gerade nicht verfügbar (${e.message}).';
    return 'Die Foto-Analyse ist gerade nicht verfügbar.';
  }

  /// Foto-KI (Phase 7c): schlaegt Gericht, Mahlzeitentyp und Zutaten mit geschaetzten Mengen vor. Nichts davon wird
  /// ohne Pruefung uebernommen: die Zutaten erscheinen als normale Zeilen und lassen sich aendern oder entfernen.
  Future<void> _analyze() async {
    final photo = _newPhoto ?? (widget.existing == null ? null : await ref.read(mealPhotoServiceProvider).bytes(widget.existing!));
    if (photo == null) return setState(() => _error = 'Das Foto ist gerade nicht verfügbar.');
    if (!await _confirmFirstUse() || !mounted) return;

    final products = ref.read(productsStreamProvider).value ?? const <Product>[];
    final active = ref.read(activeInventoryStreamProvider).value ?? const <InventoryItem>[];
    final inStock = {for (final i in active) i.productId};
    // Produkte im Vorrat zuerst: sie sind die wahrscheinlichsten Treffer und bleiben bei der Obergrenze erhalten.
    final live = products.where((p) => p.deletedAt == null).toList()
      ..sort((a, b) => (inStock.contains(b.id) ? 1 : 0).compareTo(inStock.contains(a.id) ? 1 : 0));
    final offered = [for (final p in live.take(80)) (id: p.id, name: p.name)];

    // Die Portionen hat der Nutzer gesetzt, wenn er sie geaendert hat oder die Mahlzeit bearbeitet; die Vorbelegung 1 sagt nichts.
    final made = _parsePositive(_made.text);
    final servingsGiven = made != null && (_isEdit || made != 1);
    final title = _title.text.trim();
    final note = _note.text.trim();
    final context = MealAnalysisContext(
      title: title.isEmpty ? null : title,
      note: note.isEmpty ? null : note,
      mealType: _isEdit || _typeChosen ? _type : null,
      servingsMade: servingsGiven ? made : null,
      // Ein frueherer Vorschlag aus diesem Formular wird ersetzt, ist also keine Angabe des Nutzers
      knownIngredients: [for (final r in _rows) if (!(_analysisApplied && r.source == 'photo_ai')) r.label],
    );

    setState(() {
      _analyzing = true;
      _error = null;
    });
    try {
      final analysis = await ref.read(mealAnalysisCloudProvider).analyze(photo, offered, context: context);
      if (!mounted) return;
      _applyAnalysis(analysis, {for (final p in live) p.id: p}, inStock, keepServings: servingsGiven);
    } catch (e) {
      if (mounted) setState(() => _error = _analysisError(e));
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  void _applyAnalysis(MealAnalysis a, Map<String, Product> byId, Set<String> inStock, {required bool keepServings}) {
    if (a.isEmpty) {
      setState(() => _error = a.notes ?? 'Auf dem Foto ist keine Mahlzeit zu erkennen.');
      return;
    }
    setState(() {
      if (_title.text.trim().isEmpty && a.dishTitle.isNotEmpty) _title.text = a.dishTitle;
      if (!_isEdit && !_typeChosen && a.mealType != null) _type = a.mealType!;
      if (!keepServings && a.servingsVisible != null) _made.text = formatQuantity(a.servingsVisible!);
      // Ein zweiter Vorschlag ersetzt den ersten, statt ihn zu verdoppeln
      if (_analysisApplied) _rows.removeWhere((r) => r.source == 'photo_ai');
      final present = {for (final r in _rows) r.label.trim().toLowerCase()};
      for (final i in a.ingredients) {
        if (!present.add(i.name.trim().toLowerCase())) continue;
        final product = i.inventoryProductId == null ? null : byId[i.inventoryProductId];
        // Hat das Produkt eigene Naehrwerte, gelten sie. Sonst (die meisten Produkte vom Bon) springt der automatisch
        // zugeordnete BLS-Eintrag ein; ohne beides bleibt die Zeile "unbekannt" (Phase N1, ADR-031).
        final ownProfile = product != null && productNutrientProfile(product) != null;
        // Gekocht geschaetzte Mengen brauchen den gekochten Eintrag: Das Profil des Produkts gilt fuer die rohe Ware (Q-28)
        final asEaten = ownProfile && i.state == 'cooked' && i.match != null;
        final match = ownProfile && !asEaten ? null : i.match;
        // Hat der Server eine Stueckzahl samt Gewicht geliefert ("2 Eier a 50 g"), gilt sie statt der Gramm-Schaetzung (Phase N2)
        final counted = i.unit;
        _rows.add(_Row(
          product: product,
          freeText: product == null ? i.name : null,
          quantity: counted?.count ?? i.estimatedGrams ?? 0,
          unitKey: counted?.key,
          unitWeightG: counted?.weightG,
          // Getraenke fuehrt die App in ml; die Naehrwerte der BLS gelten je 100 g, bei Wasserdichte 1 ist das dasselbe
          unit: counted != null ? EntryUnit.piece : ((product != null && product.baseUnit == 'l') || i.isDrink ? EntryUnit.ml : EntryUnit.g),
          // Gekochtes wiegt mehr als das Rohgewicht im Bestand: kein Abzug vorbelegt (Q-28), der Nutzer kann ihn einschalten
          // Was man nur vermutet, wird auch nicht vom Bestand abgezogen
          deduct: product != null && inStock.contains(product.id) && i.state != 'cooked' && !i.inferred,
          source: 'photo_ai',
          confidence: i.confidence,
          inferred: i.inferred,
          per100: match?.per100,
          per100Basis: match == null ? null : 'g',
          blsCode: match?.code,
          matchName: match?.name,
          microsPer100: match?.micros,
          matchTrust: match?.trust ?? MatchTrust.sure,
          // Gedaechtnis und Synonym kennt der Server schon, alles andere merkt sich der Haushalt beim Speichern
          learn: match != null && !match.alreadyKnown,
          lineProfileWins: asEaten,
        ));
      }
      // FR-17: Mengen aus einem Foto sind Schaetzungen und muessen in allen Auswertungen erkennbar sein.
      _estimate = true;
      _source = 'photo_ai';
      _analysisApplied = true;
      _analysisNotes = a.notes;
    });
    _fillMissingAmounts();
    _suggestUsual();
  }

  /// Sucht in den letzten Mahlzeiten nach ueblichen Zutaten, die in dieser fehlen. Ein Fehler hier bleibt ohne Folgen: es gibt dann
  /// einfach keine Vorschlaege.
  Future<void> _suggestUsual() async {
    try {
      final history = await ref.read(mealRepositoryProvider).recentHistory(excludeMealId: widget.existing?.id);
      final products = {for (final p in await ref.read(productRepositoryProvider).allSnapshot()) p.id: p};
      final past = <PastMeal>[
        for (final (m, ings) in history)
          (
            id: m.id,
            ingredients: [
              for (final i in ings)
                if ((i.productId == null ? i.freeText : products[i.productId]?.name) case final label? when label.trim().isNotEmpty)
                  (
                    label: label,
                    productId: i.productId,
                    blsCode: i.blsCode,
                    grams: ingredientGrams(i),
                    kcal: i.kcal,
                    proteinG: i.proteinG,
                    fatG: i.fatG,
                    carbsG: i.carbsG,
                    sugarG: i.sugarG,
                    fiberG: i.fiberG,
                    saltG: i.saltG,
                    micros: undoRetention(parseMicros(i.micros), retentionFromStorage(i.preparation)),
                  ),
            ],
          ),
      ];
      final current = {for (final r in _rows) ingredientKey(productId: r.product?.id, blsCode: r.blsCode, name: r.label)};
      final names = {for (final r in _rows) ingredientKey(name: r.label)};
      final found = suggestMissingIngredients(current: current, currentNames: names, history: past);
      if (mounted) setState(() => _usual = found);
    } catch (_) {
      // Vorschlaege sind eine Zugabe
    }
  }

  Future<void> _addUsual(UsualIngredient u) async {
    final products = {for (final p in await ref.read(productRepositoryProvider).allSnapshot()) p.id: p};
    final active = ref.read(activeInventoryStreamProvider).value ?? const <InventoryItem>[];
    final product = u.productId == null ? null : products[u.productId];
    if (!mounted) return;
    setState(() {
      _rows.add(_Row(
        product: product,
        freeText: product == null ? u.label : null,
        quantity: u.medianGrams == null ? 0 : (u.medianGrams! * 10).round() / 10,
        unit: product != null && product.baseUnit == 'l' ? EntryUnit.ml : EntryUnit.g,
        per100: product == null ? NutrientsPer100.fromMap(u.per100) : null,
        per100Basis: product == null && u.per100 != null ? 'g' : null,
        blsCode: product == null ? u.blsCode : null,
        microsPer100: product == null ? u.micros100 : null,
        deduct: product != null && active.any((i) => i.productId == product.id),
        source: 'estimate',
      ));
      _usual = [for (final x in _usual) if (x.key != u.key) x];
    });
  }

  /// Das Gewicht einer Einheit nach der Kette Haushalt > Produkt > Tabelle (Phase N2, ADR-033), die bekannten Einheiten des
  /// Lebensmittels und woher das Gewicht stammt. Fehler (kein Netz) ergeben nur weniger Angaben, nie eine Ausnahme.
  Future<({List<FoodUnit> units, double? pieceWeight, String source})> _unitContext({Product? product, String? blsCode}) async {
    final code = blsCode ?? product?.blsCode;
    var units = const <FoodUnit>[];
    double? household;
    if (code != null) {
      try {
        units = await ref.read(foodUnitsSourceProvider).unitsFor(code);
      } catch (_) {
        // ohne Tabelle nur Gramm, Milliliter und das eigene Stueckgewicht
      }
      try {
        household = await ref.read(foodLinkRepositoryProvider).unitWeightForCode(code);
      } catch (_) {
        // kein gemerktes Gewicht
      }
    }
    if (household != null) return (units: units, pieceWeight: household, source: 'household');
    if (product?.unitWeightG != null) return (units: units, pieceWeight: product!.unitWeightG, source: 'product');
    return (units: units, pieceWeight: null, source: 'usda');
  }

  /// Zutaten ohne Menge ("Gewuerzgurke", von der KI nicht schaetzbar): statt einer leeren Menge 1 Einheit vorbelegen, wenn das
  /// Lebensmittel eine bekannte hat (Phase N2). Der Nutzer prueft ohnehin jede Zeile; bei unbekannten bleibt die Menge leer.
  Future<void> _fillMissingAmounts() async {
    for (final r in List.of(_rows)) {
      if (r.quantity > 0 || r.blsCode == null && r.product?.blsCode == null) continue;
      final ctx = await _unitContext(product: r.product, blsCode: r.blsCode);
      if (!mounted || r.quantity > 0) continue;
      final keys = unitKeysOf(ctx.units);
      if (keys.isEmpty) continue;
      final key = keys.first;
      final w = key == FoodUnitKey.piece ? (ctx.pieceWeight ?? defaultUnit(ctx.units, key)?.gramsEdible) : defaultUnit(ctx.units, key)?.gramsEdible;
      if (w == null) continue;
      setState(() {
        r
          ..quantity = 1
          ..unit = EntryUnit.piece
          ..unitKey = key
          ..unitWeightG = w;
      });
    }
  }

  /// Sucht zu einer Zutat ohne Naehrwerte (z.B. aus der Foto-Analyse) ein Produkt oder einen BLS-Treffer und
  /// uebernimmt dessen Naehrwerte; die erfasste Menge bleibt.
  Future<void> _lookupNutrients(int index) async {
    final row = _rows[index];
    final picked = await showIngredientPicker(context, initialQuery: row.label);
    if (picked == null || !mounted) return;
    setState(() {
      final product = picked.product;
      final bls = picked.bls;
      if (product != null) {
        final active = ref.read(activeInventoryStreamProvider).value ?? const <InventoryItem>[];
        row
          ..product = product
          ..freeText = null
          ..per100 = null
          ..per100Basis = null
          ..blsCode = null
          ..matchName = null
          ..microsPer100 = null
          ..preparation = null
          ..learn = false
          ..lineProfileWins = false
          ..deduct = active.any((i) => i.productId == product.id);
        if (product.baseUnit == 'l' && row.unit == EntryUnit.g) row.unit = EntryUnit.ml;
      } else if (bls != null) {
        // Der Nutzer hat selbst gewaehlt: sicher, und der Haushalt merkt sich "dieser Name = dieser Eintrag"
        final asked = row.label;
        row
          ..product = null
          ..freeText = asked
          ..per100 = bls.per100
          ..per100Basis = 'g'
          ..blsCode = bls.code
          ..matchName = bls.nameDe
          ..microsPer100 = bls.micros
          ..preparation = null
          ..matchTrust = MatchTrust.sure
          ..learn = true
          ..deduct = false;
      } else {
        row.freeText = picked.freeText;
      }
    });
  }

  Future<void> _pickDateTime() async {
    final local = utcToViennaLocal(_eatenAt);
    final date = await showDatePicker(
      context: context,
      initialDate: local,
      firstDate: DateTime(local.year - 2),
      lastDate: appClock.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay(hour: local.hour, minute: local.minute));
    if (time == null || !mounted) return;
    setState(() => _eatenAt = viennaLocalToUtc(date.year, date.month, date.day, time.hour, time.minute));
  }

  String? _stockHint(Product p) {
    final active = ref.read(activeInventoryStreamProvider).value ?? const <InventoryItem>[];
    final total = active.where((i) => i.productId == p.id).fold<double>(0, (s, i) => s + i.quantity);
    return total <= 0 ? 'Nicht im Bestand: der Eintrag zählt trotzdem für die Nährwerte.' : 'Im Bestand: ${describeStock(total, p.baseUnit, p)}';
  }

  Future<void> _addIngredient() async {
    final picked = await showIngredientPicker(context);
    if (picked == null || !mounted) return;
    final product = picked.product;
    final bls = picked.bls;
    final label = product?.name ?? bls?.nameDe ?? picked.freeText!;
    final ctx = await _unitContext(product: product, blsCode: bls?.code);
    if (!mounted) return;
    final q = await askIngredientQuantity(
      context,
      label: label,
      initialUnit: product != null ? EntryUnit.naturalFor(product.baseUnit) : EntryUnit.g,
      canDeduct: product != null,
      stockHint: product == null ? null : _stockHint(product),
      units: ctx.units,
      pieceWeightG: ctx.pieceWeight,
      pieceWeightSource: ctx.source,
      per100: bls?.per100 ?? (product == null ? null : productNutrientProfile(product)),
    );
    if (q == null || !mounted) return;
    setState(() => _rows.add(_Row(
          product: product,
          freeText: product == null ? label : null,
          quantity: q.quantity,
          unit: q.unit,
          per100: bls?.per100,
          per100Basis: bls == null ? null : 'g',
          blsCode: bls?.code,
          matchName: bls?.nameDe,
          microsPer100: bls?.micros,
          deduct: q.deduct,
          unitKey: q.unitKey,
          unitWeightG: q.unitWeightG,
          learnWeight: q.learnWeight,
        )));
  }

  /// Zeile ohne Produkt und ohne Naehrwertprofil, deren absolute Werte von Hand eingetragen sind.
  bool _isManual(_Row r) => r.manual != null && r.product == null && r.per100 == null;

  Future<void> _addManual() async {
    final entry = await askManualNutrients(context, initialName: _title.text.trim());
    if (entry == null || !mounted) return;
    setState(() {
      _rows.add(_Row(freeText: entry.name, quantity: 1, unit: EntryUnit.piece, manual: entry.nutrients, source: 'estimate'));
      // Von Hand eingetragene Werte (Speisekarte, Schaetzung) sind keine Messwerte: erkennbar halten (FR-17). Wer sie genau
      // kennt, schaltet "Nur geschaetzt" wieder aus.
      _estimate = true;
    });
  }

  Future<void> _editManual(int index) async {
    final row = _rows[index];
    final entry = await askManualNutrients(context, initialName: row.label, initial: row.manual);
    if (entry == null || !mounted) return;
    setState(() {
      row.freeText = entry.name;
      row.manual = entry.nutrients;
    });
  }

  /// Rechnet das Gericht auf eine andere Portionenzahl um (Doku 15 §3.2: "Portionen anpassen, Mengen werden
  /// skaliert"): alle Mengen werden mit neu/alt multipliziert und "Portionen gekocht" gesetzt. Von Hand eingetragene
  /// Naehrwerte (absolute Werte der ganzen Portion) werden mit skaliert, Zutaten ohne Menge bleiben ohne Menge.
  Future<void> _scalePortions() async {
    final current = _parsePositive(_made.text) ?? 1;
    final target = await showDialog<double>(context: context, builder: (_) => _ScaleDialog(current: current));
    if (target == null || !mounted || target == current) return;
    final factor = target / current;
    setState(() {
      for (final r in _rows) {
        if (_isManual(r)) {
          r.manual = r.manual!.scaled(factor);
        } else {
          r.quantity = (r.quantity * factor * 1000).round() / 1000;
        }
      }
      _made.text = formatQuantity(target);
    });
  }

  Future<void> _editIngredient(int index) async {
    if (_isManual(_rows[index])) return _editManual(index);
    final row = _rows[index];
    final ctx = await _unitContext(product: row.product, blsCode: row.blsCode);
    if (!mounted) return;
    final q = await askIngredientQuantity(
      context,
      label: row.label,
      initialUnit: row.unit,
      initialQuantity: row.quantity,
      canDeduct: row.product != null,
      initialDeduct: row.deduct,
      stockHint: row.product == null ? null : _stockHint(row.product!),
      units: ctx.units,
      pieceWeightG: ctx.pieceWeight,
      pieceWeightSource: ctx.source,
      per100: row.profile,
      initialUnitKey: row.unitKey,
      initialUnitWeightG: row.unitWeightG,
    );
    if (q == null || !mounted) return;
    setState(() {
      row.quantity = q.quantity;
      row.unit = q.unit;
      row.deduct = q.deduct;
      row.unitKey = q.unitKey;
      row.unitWeightG = q.unitWeightG;
      row.learnWeight = row.learnWeight || q.learnWeight;
    });
  }

  double? _parsePositive(String text) {
    final v = double.tryParse(text.replaceAll(',', '.').trim());
    return (v == null || v <= 0) ? null : v;
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final eaten = _parsePositive(_eaten.text);
    final made = _parsePositive(_made.text);
    if (title.isEmpty) return setState(() => _error = 'Bitte einen Titel eingeben.');
    if (eaten == null || made == null) return setState(() => _error = 'Portionen müssen größer als 0 sein.');
    final missing = _rows.where((r) => r.quantity <= 0).firstOrNull;
    if (missing != null) return setState(() => _error = 'Bei „${missing.label}“ fehlt die Menge. Tippe die Zutat an und trage sie ein.');
    setState(() {
      _saving = true;
      _error = null;
    });
    final draft = MealDraft(
      title: title,
      eatenAt: _eatenAt,
      mealType: _type,
      note: _note.text,
      servingsEaten: eaten,
      servingsMade: made,
      isEstimate: _estimate,
      source: _source,
      ingredients: [for (final r in _rows) r.toDraft()],
    );
    try {
      final repo = ref.read(mealRepositoryProvider);
      final saved = _isEdit ? await repo.update(widget.existing!.id, draft) : await repo.create(draft);
      final photoProblem = await _applyPhoto(saved);
      await _learnLinks();
      await _learnWeights();
      if (!mounted) return;
      if (photoProblem != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(photoProblem)));
      context.pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Speichern nicht möglich: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Merkt sich die Zuordnungen "Name -> BLS-Eintrag", die der Nutzer gewaehlt oder durch Speichern bestaetigt hat (Phase N1,
  /// ADR-031): beim naechsten Foto kennt der Server sie. Ein Fehler hier darf das Speichern der Mahlzeit nie kippen.
  Future<void> _learnLinks() async {
    try {
      final links = ref.read(foodLinkRepositoryProvider);
      for (final r in _rows) {
        if (r.learn && r.blsCode != null && r.product == null && r.per100 != null) await links.learn(r.label, r.blsCode!);
      }
    } catch (_) {
      // das Gedaechtnis ist eine Zugabe
    }
  }

  /// Merkt sich Stueckgewichte, die der Nutzer selbst eingetragen hat (Phase N2): am Produkt oder, ohne Produkt, im Gedaechtnis
  /// des Haushalts zum BLS-Eintrag. Ein Fehler hier darf das Speichern der Mahlzeit nie kippen.
  Future<void> _learnWeights() async {
    for (final r in _rows) {
      final w = r.unitWeightG;
      if (!r.learnWeight || w == null || r.unit != EntryUnit.piece) continue;
      try {
        if (r.product != null) {
          await ref.read(productRepositoryProvider).setUnitWeight(r.product!.id, w);
        } else if (r.blsCode != null) {
          await ref.read(foodLinkRepositoryProvider).setUnitWeight(r.label, r.blsCode!, w);
        }
      } catch (_) {
        // das Gewicht ist eine Zugabe
      }
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mahlzeit löschen?'),
        content: const Text('Der Eintrag verschwindet aus dem Tagebuch. Was vom Bestand abgezogen wurde, wird zurückgebucht.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(key: const Key('meal-delete-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(mealRepositoryProvider).delete(widget.existing!.id);
    if (widget.existing!.photoPath != null) {
      try {
        await ref.read(mealPhotoServiceProvider).purge(widget.existing!);
      } catch (_) {
        // das Foto ohne Mahlzeit ist nicht mehr abrufbar (kein Verweis), ein Aufraeumfehler soll das Loeschen nicht kippen
      }
    }
    if (mounted) context.pop(true);
  }

  /// Summe der Zutaten und der Anteil, der tatsaechlich gegessen wurde (FR-13).
  ({NutrientTotals all, NutrientTotals eaten, int unknown}) _totals() {
    var sum = const NutrientTotals();
    var unknown = 0;
    for (final r in _rows) {
      final n = r.nutrients;
      if (n == null) {
        unknown++;
        continue;
      }
      sum = sum +
          NutrientTotals(
            kcal: n.kcal ?? 0, proteinG: n.proteinG ?? 0, fatG: n.fatG ?? 0, carbsG: n.carbsG ?? 0,
            sugarG: n.sugarG ?? 0, fiberG: n.fiberG ?? 0, saltG: n.saltG ?? 0,
          );
    }
    final eaten = _parsePositive(_eaten.text) ?? 1;
    final made = _parsePositive(_made.text) ?? 1;
    return (all: sum, eaten: sum.scaled(eaten / made), unknown: unknown);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    // Abonnieren, damit beide Streams schon Werte haben, wenn spaeter ein Knopf sie per ref.read abfragt (Bestandshinweis,
    // Foto-Vorschlag): ein StreamProvider liefert beim ersten Lesen noch nichts (siehe ADR-021, Fund 2026-10-01).
    ref.watch(productsStreamProvider);
    ref.watch(activeInventoryStreamProvider);
    final totals = _totals();
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit
            ? 'Mahlzeit bearbeiten'
            : widget.leftover
                ? 'Rest erfassen'
                : widget.template != null
                    ? 'Nochmal erfassen'
                    : 'Neue Mahlzeit'),
        actions: [
          if (_isEdit) IconButton(key: const Key('meal-delete'), tooltip: 'Löschen', icon: const Icon(Icons.delete_outline), onPressed: _delete),
          // In der App-Leiste statt am Listenende: das Formular ist lang, Speichern soll immer erreichbar sein.
          TextButton(key: const Key('meal-save'), onPressed: _saving ? null : _save, child: Text(_saving ? 'Speichert…' : 'Speichern')),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // Ganz oben, damit eine Fehlermeldung beim Speichern nicht unterhalb des sichtbaren Bereichs verschwindet.
        if (_error != null)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, key: const Key('meal-error'), style: TextStyle(color: t.colorScheme.error))),
        _photoSection(t),
        TextField(
          key: const Key('meal-title'),
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Was gab es?', hintText: 'z.B. Gemüsepfanne mit Reis'),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final e in mealTypeLabels.entries)
            ChoiceChip(
              key: Key('meal-type-${e.key}'),
              avatar: Icon(mealTypeIcon(e.key), size: 18),
              label: Text(e.value),
              selected: _type == e.key,
              onSelected: (_) => setState(() {
                _type = e.key;
                _typeChosen = true;
              }),
            ),
        ]),
        ListTile(
          key: const Key('meal-datetime'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule),
          title: Text(formatViennaDateTime(_eatenAt)),
          trailing: const Icon(Icons.edit_outlined, size: 18),
          onTap: _pickDateTime,
        ),
        Row(children: [
          Expanded(
            child: TextField(
              key: const Key('meal-servings-eaten'),
              controller: _eaten,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Portionen gegessen'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              key: const Key('meal-servings-made'),
              controller: _made,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Portionen gekocht'),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        Text('Zutaten', style: t.textTheme.titleMedium),
        if (_rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Noch keine Zutat. Aus dem Inventar, der Lebensmitteldatenbank oder als Freitext.', style: t.textTheme.bodySmall),
          ),
        if (_recipeApplied) _recipeHint(t),
        if (_rows.isNotEmpty) _trustSummary(t),
        for (var i = 0; i < _rows.length; i++) _ingredientTile(i, t),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(spacing: 8, children: [
            TextButton.icon(key: const Key('meal-add-ingredient'), onPressed: _addIngredient, icon: const Icon(Icons.add), label: const Text('Zutat hinzufügen')),
            TextButton.icon(key: const Key('meal-from-recipe'), onPressed: _pickRecipe, icon: const Icon(Icons.bookmark_outline), label: const Text('Aus Rezept')),
            TextButton.icon(key: const Key('meal-add-manual'), onPressed: _addManual, icon: const Icon(Icons.edit_note), label: const Text('Nährwerte eintragen')),
            if (_rows.isNotEmpty)
              TextButton.icon(key: const Key('meal-scale'), onPressed: _scalePortions, icon: const Icon(Icons.scale_outlined), label: const Text('Portionen umrechnen')),
          ]),
        ),
        if (_rows.isNotEmpty) _totalsCard(t, totals),
        SwitchListTile(
          key: const Key('meal-estimate'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Nur geschätzt'),
          subtitle: const Text('z.B. Restaurant: wird in der Auswertung als Schätzung gekennzeichnet'),
          value: _estimate,
          onChanged: (v) => setState(() => _estimate = v),
        ),
        TextField(key: const Key('meal-note'), controller: _note, decoration: const InputDecoration(labelText: 'Notiz (optional)'), maxLines: 2),
      ]),
    );
  }

  /// Woher die Mengen kommen, und der kurze Weg, wenn man sie gar nicht eintragen will.
  Widget _recipeHint(ThemeData t) {
    final from = _recipeAmountsFrom;
    final missing = _rows.where((r) => r.quantity <= 0).length;
    if (from == null && missing == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (from != null) Text('Mengen vom letzten Mal (${formatViennaDateTime(from)}), bitte prüfen.', key: const Key('meal-recipe-amounts-from'), style: t.textTheme.bodySmall),
        if (missing > 0) ...[
          Text(
            missing == 1 ? 'Rezepte kennen keine Mengen: Bei einer Zutat fehlt sie noch. Beim nächsten Mal steht sie schon da.' : 'Rezepte kennen keine Mengen: Bei $missing Zutaten fehlt sie noch. Beim nächsten Mal stehen sie schon da.',
            key: const Key('meal-recipe-missing'),
            style: t.textTheme.bodySmall,
          ),
          TextButton(
            key: const Key('meal-recipe-drop-empty'),
            onPressed: () => setState(() => _rows.removeWhere((r) => r.quantity <= 0)),
            child: const Text('Zutaten ohne Menge weglassen'),
          ),
        ],
      ]),
    );
  }

  Widget _photoSection(ThemeData t) {
    if (!widget.photosAvailable) return const SizedBox.shrink();
    final Widget preview;
    if (_newPhoto != null) {
      preview = Image.memory(_newPhoto!, key: const Key('meal-photo-preview'), fit: BoxFit.cover, gaplessPlayback: true);
    } else if (_hasPhoto) {
      preview = MealPhoto(meal: widget.existing!, placeholder: const Icon(Icons.image_outlined, size: 40), fit: BoxFit.cover);
    } else {
      preview = const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_hasPhoto)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(width: double.infinity, height: 180, child: preview),
          ),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(
            key: const Key('meal-photo-camera'),
            onPressed: () => _pickPhoto(camera: true),
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text(_hasPhoto ? 'Neues Foto' : 'Foto aufnehmen'),
          ),
          TextButton.icon(
            key: const Key('meal-photo-gallery'),
            onPressed: () => _pickPhoto(camera: false),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Aus Galerie'),
          ),
          if (_hasPhoto)
            FilledButton.tonalIcon(
              key: const Key('meal-analyze'),
              onPressed: _analyzing ? null : _analyze,
              icon: const Icon(Icons.auto_awesome),
              label: Text(_analyzing ? 'Foto wird ausgewertet…' : 'Zutaten vom Foto vorschlagen'),
            ),
          if (_hasPhoto)
            TextButton.icon(
              key: const Key('meal-photo-remove'),
              onPressed: () => setState(() {
                _newPhoto = null;
                _photoRemoved = true;
              }),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Foto entfernen'),
            ),
        ]),
        if (_hasPhoto)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Titel, Notiz, Portionen und Zutaten gehen mit. Trag ein, was du weißt, dann wird der Vorschlag genauer.',
              key: const Key('meal-analyze-hint'),
              style: t.textTheme.bodySmall,
            ),
          ),
        if (_analyzing) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator(key: Key('meal-analyzing'))),
        if (_usual.isNotEmpty)
          Card(
            key: const Key('meal-usual'),
            margin: const EdgeInsets.only(top: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Fehlt etwas?', style: t.textTheme.titleSmall),
                const SizedBox(height: 4),
                const Text('In ähnlichen früheren Mahlzeiten war meist auch dabei:'),
                const SizedBox(height: 4),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  for (var i = 0; i < _usual.length; i++)
                    ActionChip(
                      key: Key('usual-chip-$i'),
                      avatar: const Icon(Icons.add, size: 18),
                      label: Text(_usual[i].medianGrams == null ? _usual[i].label : '${_usual[i].label} (ca. ${formatQuantity((_usual[i].medianGrams! * 10).round() / 10)} g)'),
                      onPressed: () => _addUsual(_usual[i]),
                    ),
                ]),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(key: const Key('usual-dismiss'), onPressed: () => setState(() => _usual = const []), child: const Text('Nein danke')),
                ),
              ]),
            ),
          ),
        if (_analysisApplied)
          Card(
            key: const Key('meal-analysis-info'),
            margin: const EdgeInsets.only(top: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Vorschlag aus dem Foto', style: t.textTheme.titleSmall),
                const SizedBox(height: 4),
                const Text(
                  'Die Mengen sind Schätzungen, bitte prüfen. Öl, Butter, Gewürze und die Basis von Soßen sieht man auf einem '
                  'Foto nicht: Was „vermutet“ ist, gehört meist dazu, stimmt aber nicht immer. Fehlt etwas?',
                ),
                if (_analysisNotes != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_analysisNotes!, key: const Key('meal-analysis-notes'), style: t.textTheme.bodySmall)),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _ingredientTile(int i, ThemeData t) {
    final r = _rows[i];
    final n = r.nutrients;
    final amount = _isManual(r)
        ? 'Handeingabe'
        : r.quantity <= 0
            ? 'Menge eintragen'
            : r.quantityText;
    final grams = r.unit == EntryUnit.piece && r.unitWeightG != null && r.quantity > 0 ? r.quantity * r.unitWeightG! : null;
    final parts = <String>[
      amount,
      // Bei Stueck, Scheibe, EL: was das in Gramm ist, damit nichts verborgen bleibt
      if (grams != null) '≈ ${formatQuantity(grams.roundToDouble() == grams ? grams : (grams * 10).round() / 10)} g',
      if (n?.kcal != null) formatKcal(n!.kcal!) else 'Nährwerte unbekannt',
      if (r.deductBlocked) 'kein Bestandsabzug: Stückgewicht fehlt' else if (r.deduct && r.product != null) 'vom Bestand',
      if (r.inferred) 'vermutet' else if (r.source == 'photo_ai') (r.confidence ?? 0) < 0.5 ? 'unsicher geschätzt' : 'geschätzt',
    ];
    // Woher die Naehrwerte stammen, wenn nicht aus dem Namen der Zeile selbst ersichtlich ("Paprika" -> "Gemüsepaprika rot, roh")
    final matched = r.matchName != null && r.matchName != r.label && r.per100 != null && r.product == null;
    return ListTile(
      key: Key('ingredient-row-$i'),
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(r.product != null ? Icons.kitchen_outlined : (_isManual(r) ? Icons.edit_note : Icons.eco_outlined), size: 20),
      title: Text(r.label),
      isThreeLine: matched,
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (matched) Text('Nährwerte: ${r.matchName}', key: Key('ingredient-match-$i')),
        Text(parts.join(' · ')),
        if (r.retentionCategoryOfRow case final category?) _preparationChips(i, r, category, t),
      ]),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        _trustMark(i, r, t),
        // Ohne bekannte Naehrwerte: direkt ein Produkt oder einen Datenbank-Treffer dazu suchen
        if (n == null)
          IconButton(key: Key('ingredient-lookup-$i'), tooltip: 'Nährwerte suchen', icon: const Icon(Icons.search), onPressed: () => _lookupNutrients(i)),
        IconButton(key: Key('ingredient-remove-$i'), tooltip: 'Entfernen', icon: const Icon(Icons.close), onPressed: () => setState(() => _rows.removeAt(i))),
      ]),
      onTap: () => _editIngredient(i),
    );
  }

  /// Zubereitung der Zutat (Garfaktoren, ADR-037): "roh" oder eine der Zubereitungen, fuer die es USDA-Faktoren gibt. Die Menge gilt dann als
  /// Rohgewicht, Vitamine und Mineralstoffe werden um die typischen Verluste gemindert (Energie und Makros bleiben).
  Widget _preparationChips(int i, _Row r, String category, ThemeData t) {
    final selected = retentionFromStorage(r.preparation);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 6, children: [
          ChoiceChip(
            key: Key('prep-$i-raw'),
            label: const Text('roh'),
            visualDensity: VisualDensity.compact,
            selected: selected == null,
            onSelected: (_) => setState(() => r.preparation = null),
          ),
          for (final m in cookMethodsFor(category))
            ChoiceChip(
              key: Key('prep-$i-${m.key}'),
              label: Text(m.label),
              visualDensity: VisualDensity.compact,
              selected: selected?.method == m,
              onSelected: (_) => setState(() => r.preparation = '$category:${m.key}'),
            ),
        ]),
        if (selected != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              [
                'Menge als Rohgewicht',
                () {
                  final loss = lossSummary(selected, present: r.microsPer100?.keys);
                  return loss.isEmpty ? 'für die bekannten Werte keine Verluste' : loss;
                }(),
                'USDA-Durchschnitt',
              ].join(' · '),
              key: Key('prep-info-$i'),
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
            ),
          ),
      ]),
    );
  }

  /// Marke je Zutat: ✓ sicher, ~ automatisch zugeordnet (antippen bestaetigt), ? unbekannt (Phase N1, ADR-031).
  Widget _trustMark(int i, _Row r, ThemeData t) {
    switch (r.trust) {
      case MatchTrust.sure:
        return Icon(Icons.check_circle_outline, key: Key('ingredient-trust-sure-$i'), size: 20, color: t.colorScheme.primary);
      case MatchTrust.auto:
        return IconButton(
          key: Key('ingredient-trust-auto-$i'),
          tooltip: 'Automatisch zugeordnet. Antippen bestätigt.',
          icon: Icon(Icons.change_circle_outlined, size: 20, color: t.colorScheme.tertiary),
          onPressed: () => setState(() => r.matchTrust = MatchTrust.sure),
        );
      case MatchTrust.unknown:
        return Icon(Icons.help_outline, key: Key('ingredient-trust-unknown-$i'), size: 20, color: t.colorScheme.outline);
    }
  }

  /// "7 von 8 Zutaten mit Nährwerten, 2 automatisch zugeordnet" und der Knopf, alle automatischen Zuordnungen zu bestaetigen.
  Widget _trustSummary(ThemeData t) {
    final auto = _rows.where((r) => r.trust == MatchTrust.auto).length;
    final unknown = _rows.where((r) => r.trust == MatchTrust.unknown).length;
    if (auto == 0 && unknown == 0) return const SizedBox.shrink();
    final known = _rows.length - unknown;
    final text = StringBuffer('$known von ${_rows.length} Zutaten mit Nährwerten');
    if (auto > 0) text.write(', $auto automatisch zugeordnet (~)');
    if (unknown > 0) text.write(', $unknown unbekannt (?)');
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(children: [
        Expanded(child: Text(text.toString(), key: const Key('ingredient-summary'), style: t.textTheme.bodySmall)),
        if (auto > 0)
          TextButton(
            key: const Key('ingredient-confirm-all'),
            onPressed: () => setState(() {
              for (final r in _rows) {
                if (r.trust == MatchTrust.auto) r.matchTrust = MatchTrust.sure;
              }
            }),
            child: const Text('Alle übernehmen'),
          ),
      ]),
    );
  }

  Widget _totalsCard(ThemeData t, ({NutrientTotals all, NutrientTotals eaten, int unknown}) totals) {
    final e = totals.eaten;
    final sharing = (_parsePositive(_made.text) ?? 1) != (_parsePositive(_eaten.text) ?? 1);
    return Card(
      key: const Key('meal-totals'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(sharing ? 'Dein Anteil' : 'Nährwerte', style: t.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            '${formatKcal(e.kcal)} · ${formatNutrientGrams(e.proteinG)} Eiweiß · ${formatNutrientGrams(e.fatG)} Fett · ${formatNutrientGrams(e.carbsG)} Kohlenhydrate',
            key: const Key('meal-totals-text'),
          ),
          if (sharing) Text('Ganzes Gericht: ${formatKcal(totals.all.kcal)}', style: t.textTheme.bodySmall),
          if (totals.unknown > 0)
            Text(
              totals.unknown == 1 ? 'Für 1 Zutat sind keine Nährwerte bekannt.' : 'Für ${totals.unknown} Zutaten sind keine Nährwerte bekannt.',
              key: const Key('meal-totals-unknown'),
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
            ),
        ]),
      ),
    );
  }
}

/// Fragt die neue Portionenzahl ab, auf die das Gericht umgerechnet werden soll.
class _ScaleDialog extends StatefulWidget {
  const _ScaleDialog({required this.current});
  final double current;

  @override
  State<_ScaleDialog> createState() => _ScaleDialogState();
}

class _ScaleDialogState extends State<_ScaleDialog> {
  late final _controller = TextEditingController(text: formatQuantity(widget.current));
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = double.tryParse(_controller.text.replaceAll(',', '.').trim());
    if (v == null || !v.isFinite || v <= 0 || v > 100) return setState(() => _error = 'Bitte eine Portionenzahl zwischen 0 und 100 eingeben.');
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Portionen umrechnen'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Das Gericht ist für ${formatQuantity(widget.current)} Portion(en) erfasst. Alle Mengen werden auf die neue Zahl umgerechnet.'),
        const SizedBox(height: 12),
        TextField(
          key: const Key('scale-servings'),
          controller: _controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Neue Portionenzahl', errorText: _error),
          onSubmitted: (_) => _submit(),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(key: const Key('scale-ok'), onPressed: _submit, child: const Text('Umrechnen')),
      ],
    );
  }
}
