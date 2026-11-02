import 'frequent_meals.dart';
import 'ingredient_nutrition.dart';
import 'micros.dart';
import 'nutrient_scaling.dart';

/// Getraenke als Mischung (ADR-048, Doku 26 §2.2): Eine Zeile unter "Schnell eintragen" ist kein Produkt mit Menge, sondern eine Mischung aus Teilen.
/// "Pur" ist die Mischung mit einem Teil, "Orangensaft gespritzt" die mit Saft und Wasser. Gespeichert wird eine normale Mahlzeit vom Typ `drink`,
/// deshalb gibt es keine eigene Tabelle: Der juengste Eintrag eines Namens ist die Vorlage fuer den naechsten.

/// Glasgroesse wie beim Wasser (`SupplementRepository.defaultGlassMl`).
const drinkGlassMl = 250.0;

/// Basis zu Wasser, 1:n. 0 ist pur; 6 und 8 sind die Stufen fuer Sirup.
const drinkRatios = [0, 1, 2, 3, 6, 8];

/// Trinkwasser in der BLS (Doku 22). Fest hinterlegt, damit ein gespritzter Saft auch ohne Netz mit einem Tipp geht; die Mineralstoffe sind weggelassen, sie
/// haengen ohnehin vom Wasser ab.
const waterBlsCode = 'N110000';

/// Ein Teil einer Mischung. [amount] in [unit]: ml, bei gezaehlten Teilen (Teebeutel) Stueck.
class DrinkPart {
  const DrinkPart({
    required this.name,
    required this.amount,
    this.unit = EntryUnit.ml,
    this.productId,
    this.blsCode,
    this.per100,
    this.microsPer100,
    this.manual,
    this.nutrientBasis,
    this.unitWeightG,
  });

  /// Der Wasseranteil: keine Kalorien, kein Bestand.
  factory DrinkPart.water(double ml) => DrinkPart(
        name: 'Wasser',
        amount: ml,
        blsCode: waterBlsCode,
        per100: const NutrientsPer100(kcal: 0, proteinG: 0, fatG: 0, carbsG: 0, sugarG: 0, fiberG: 0, saltG: 0.006),
        microsPer100: const {'water_g': 100.0},
        nutrientBasis: 'bls_exact',
      );

  final String name;
  final double amount;
  final EntryUnit unit;
  final String? productId;
  final String? blsCode;
  final NutrientsPer100? per100;
  final Micros? microsPer100;

  /// Absolute Werte aus einer Handeingabe, wenn es kein Profil je 100 g gibt.
  final NutrientAmounts? manual;
  final String? nutrientBasis;
  final double? unitWeightG;

  bool get isWater => blsCode == waterBlsCode && productId == null;

  /// Menge in ml, `null` bei Stueck ohne bekanntes Volumen.
  double? get ml => switch (unit) {
        EntryUnit.ml || EntryUnit.g => amount,
        EntryUnit.l || EntryUnit.kg => amount * 1000,
        EntryUnit.piece => unitWeightG == null ? null : amount * unitWeightG!,
      };

  DrinkPart withAmount(double value) => DrinkPart(
        name: name,
        amount: value,
        unit: unit,
        productId: productId,
        blsCode: blsCode,
        per100: per100,
        microsPer100: microsPer100,
        manual: manual,
        nutrientBasis: nutrientBasis,
        unitWeightG: unitWeightG,
      );
}

/// Eine Mischung, wie sie eingetragen wird.
class DrinkDraft {
  const DrinkDraft({required this.title, required this.parts});
  final String title;
  final List<DrinkPart> parts;

  double get totalMl => parts.fold(0, (sum, p) => sum + (p.ml ?? 0));

  /// Das, was nicht Wasser ist: der Hauptteil, nach dem sich Name und Verhaeltnis richten.
  DrinkPart? get base => parts.where((p) => !p.isWater).firstOrNull;

  /// Das Verhaeltnis laesst sich nur anbieten, wenn es genau eine Basis in ml und hoechstens Wasser dazu gibt.
  bool get canMix => parts.where((p) => !p.isWater).length == 1 && base!.unit == EntryUnit.ml;

  /// 0 bei pur, sonst n in 1:n, wenn es genau eines der [drinkRatios] ist; `null` bei einem anderen Verhaeltnis.
  int? get ratio {
    if (!canMix) return null;
    final water = parts.where((p) => p.isWater).fold<double>(0, (s, p) => s + p.amount);
    if (water == 0) return 0;
    final n = water / base!.amount;
    for (final r in drinkRatios) {
      if (r > 0 && (n - r).abs() < 0.05 * r) return r;
    }
    return null;
  }

  /// Dieselbe Gesamtmenge im Verhaeltnis 1:[n]. Der Titel folgt, solange er automatisch ist. Nur mit [canMix].
  DrinkDraft mixedAt(int n) {
    final total = totalMl;
    final b = base!;
    final baseMl = (total / (1 + n)).roundToDouble();
    return DrinkDraft(
      title: title == autoDrinkTitle(b.name, ratio ?? 0) ? autoDrinkTitle(b.name, n) : title,
      parts: [b.withAmount(baseMl), if (n > 0) DrinkPart.water(total - baseMl)],
    );
  }

  /// Rechnet die Teile in ml auf eine neue Gesamtmenge um, gezaehlte Teile bleiben.
  DrinkDraft scaledTo(double ml) {
    final scalable = parts.where((p) => p.unit == EntryUnit.ml).fold<double>(0, (s, p) => s + p.amount);
    if (scalable <= 0) return this;
    final fixed = totalMl - scalable;
    final factor = (ml - fixed) / scalable;
    if (factor <= 0) return this;
    return DrinkDraft(title: title, parts: [for (final p in parts) p.unit == EntryUnit.ml ? p.withAmount((p.amount * factor).roundToDouble()) : p]);
  }

  /// Erkennt ein Getraenk ohne Mengen, das sich so nicht eintragen laesst.
  bool get isBookable => title.trim().isNotEmpty && parts.isNotEmpty && parts.every((p) => p.amount > 0);
}

/// Sirup trinkt niemand pur, der heisst auch verduennt nur Sirup; alles andere wird "gespritzt".
String autoDrinkTitle(String baseName, int ratio) {
  final name = baseName.trim();
  return ratio == 0 || name.toLowerCase().contains('sirup') ? name : '$name gespritzt';
}

/// Eine Zeile der Getraenke-Liste: aus einem frueheren Eintrag ([templateMealId]) oder ein trinkbares Produkt aus dem Bestand ([productId]).
typedef DrinkRow = ({String title, String? templateMealId, String? productId});

/// Ein Produkt, das fuer die Liste infrage kommt.
typedef DrinkProduct = ({String id, String name});

/// Die haeufigsten Mischungen der letzten 60 Tage, aufgefuellt mit trinkbaren Produkten aus dem Bestand, die noch nicht pur in der Liste stehen.
/// [pureProductOf] sagt, welches Produkt ein frueherer Eintrag pur enthaelt.
List<DrinkRow> rankDrinkRows({
  required Iterable<FrequentCandidate> drinkMeals,
  required Iterable<DrinkProduct> inStock,
  required String? Function(String mealId) pureProductOf,
  required DateTime now,
  int limit = 8,
}) {
  final frequent = frequentMeals(drinkMeals, limit: limit, since: now.subtract(const Duration(days: 60)));
  final rows = <DrinkRow>[for (final m in frequent) (title: m.title, templateMealId: m.latestId, productId: null)];
  final used = {for (final m in frequent) ?pureProductOf(m.latestId)};
  final titles = {for (final m in frequent) m.title.toLowerCase()};
  final rest = [for (final p in inStock) if (!used.contains(p.id) && !titles.contains(p.name.trim().toLowerCase())) p]
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  for (final p in rest) {
    if (rows.length >= limit) break;
    rows.add((title: p.name, templateMealId: null, productId: p.id));
  }
  return rows;
}
