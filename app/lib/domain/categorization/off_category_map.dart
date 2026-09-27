import 'keyword_rules.dart';

/// Ordnet Open-Food-Facts-Kategorie-Tags (z.B. "en:milks", "en:fresh-vegetables") grob einer eigenen
/// Standardkategorie zu, fuer die Vorbelegung beim Anlegen eines Produkts aus einem Barcode-Scan
/// (Doku 06 §4). Der Nutzer kann die Kategorie danach jederzeit aendern.
String? categoryFromOffTags(List<String> tags) {
  final joined = tags.join(' ').toLowerCase();
  bool has(String s) => joined.contains(s);

  if (has('milks') || has('yogurt') || has('creams') || has('dairies') || has('butter')) return CategoryNames.milch;
  if (has('cheese')) return CategoryNames.kaese;
  if (has('eggs')) return CategoryNames.eier;
  if (has('meats') || has('sausages') || has('hams') || has('poultry')) return CategoryNames.fleisch;
  if (has('fish') || has('seafood')) return CategoryNames.fisch;
  if (has('breads') || has('bakery') || has('pastries')) return CategoryNames.brot;
  if (has('vegetables')) return CategoryNames.gemuese;
  if (has('fruits')) return CategoryNames.obst;
  if (has('frozen')) return CategoryNames.tiefkuehl;
  if (has('beverages') || has('waters') || has('juices') || has('sodas') || has('coffees') || has('teas')) return CategoryNames.getraenke;
  if (has('pastas') || has('rices') || has('cereals') || has('canned') || has('legumes') || has('flours')) return CategoryNames.konserven;
  if (has('oils') || has('condiments') || has('sauces') || has('spices')) return CategoryNames.oele;
  if (has('snacks') || has('chocolates') || has('candies') || has('biscuits') || has('desserts')) return CategoryNames.suess;
  if (has('meals') || has('pizzas') || has('soups')) return CategoryNames.fertig;
  if (has('household') || has('hygiene') || has('cleaning')) return CategoryNames.haushalt;
  return null;
}
