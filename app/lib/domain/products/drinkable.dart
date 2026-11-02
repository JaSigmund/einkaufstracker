/// Ob ein Produkt trinkbar ist (ADR-048, Doku 26 §2.1). Weder die Einheit noch die Kategorie reichen allein: Kuerbiskernoel und Cornetto stehen in
/// Litern, der CO2-Zylinder unter "Getraenke", Vollmilch nicht. Deshalb eine Regel, die der Nutzer je Produkt ueberstimmen kann. Die Regel laeuft
/// beim Lesen, nicht einmalig: So gilt sie auch fuer Produkte, die spaeter vom Bon kommen oder erst dann eine Kategorie bekommen.
library;

const _drinkCategory = 'Getränke';

/// Trinkbares, das nicht in der Kategorie "Getraenke" steht (Milch, Hafermilch, Yakult).
const _drinkWords = ['saft', 'milch', 'drink', 'limo', 'eistee', 'sirup', 'smoothie', 'kefir', 'oatly', 'barista', 'cola', 'bier', 'wein', 'kakao'];

/// Was den Namen nach trinkbar klingt, es aber nicht ist.
const _notDrinkWords = ['essig', 'kondens', 'co2', 'zylinder', 'kapsel', 'pfand', 'kasten', 'bratensaft'];

/// [flag] ist die Entscheidung des Nutzers und gewinnt immer; `null` heisst, die Regel entscheidet.
bool isDrinkable({bool? flag, required String name, required String baseUnit, double? packSize, String? categoryName}) {
  if (flag != null) return flag;
  final n = name.toLowerCase();
  if (_notDrinkWords.any(n.contains)) return false;
  if (categoryName == _drinkCategory) {
    // Stueck mit Packungsgroesse ist eine Zaehlpackung: 20 Teebeutel trinkt man nicht als "1 Stueck"
    return baseUnit == 'l' || (baseUnit == 'piece' && packSize == null);
  }
  return baseUnit == 'l' && _drinkWords.any(n.contains);
}
