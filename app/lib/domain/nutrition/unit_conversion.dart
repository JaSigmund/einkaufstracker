/// Einheiten-Umrechnung fuers Essenstagebuch (Doku 15 Essenstagebuch und Naehrwerte, §5.3).
///
/// Das Inventar fuehrt Mengen in `kg`, `l` oder `piece` (siehe `base_unit`-Enum), Naehrwerte stehen je Produkt
/// aber "je 100 g" ODER "je 100 ml" (`products.nutrients_basis`). Diese Funktion bringt eine erfasste Menge
/// auf die Einheit, die zur Naehrwert-Basis des jeweiligen Produkts passt.
library;

/// Standardwerte fuer Loeffel-Schnelleingaben (Doku 15 §5.3), grob geschaetzt.
const double tablespoonGrams = 10; // 1 EL, z.B. Oel
const double teaspoonGrams = 5; // 1 TL, z.B. Zucker

/// Rechnet [quantity] in [quantityUnit] ('kg', 'l' oder 'piece') auf die Einheit von [basis]
/// ('g' oder 'ml') um.
///
/// [unitWeightG] ist noetig, wenn [quantityUnit] 'piece' ist (Gewicht eines Stuecks, z.B. Paprika
/// ~150 g) -- fehlt es, gibt es `null` zurueck: die Oberflaeche muss dann nachfragen (Doku 15 §5.3).
/// [densityGPerMl] wird nur gebraucht, wenn zwischen Masse und Volumen gewechselt werden muss
/// (z.B. Menge in `l` bei einem Produkt mit Naehrwerten "je 100 g"), Standard 1,0 (wie Wasser).
double? convertToNutrientBasis({
  required double quantity,
  required String quantityUnit,
  required String basis,
  double? unitWeightG,
  double densityGPerMl = 1.0,
}) {
  assert(basis == 'g' || basis == 'ml', 'basis muss "g" oder "ml" sein');

  double? grams;
  double? milliliters;
  switch (quantityUnit) {
    case 'kg':
      grams = quantity * 1000;
    case 'l':
      milliliters = quantity * 1000;
    case 'piece':
      if (unitWeightG == null) return null;
      grams = quantity * unitWeightG;
    default:
      return null;
  }

  if (basis == 'g') return grams ?? milliliters! * densityGPerMl;
  return milliliters ?? grams! / densityGPerMl;
}
