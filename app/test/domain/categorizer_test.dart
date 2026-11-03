import 'package:einkaufstracker/domain/categorization/categorizer.dart';
import 'package:einkaufstracker/domain/categorization/keyword_rules.dart';
import 'package:einkaufstracker/domain/categorization/normalize_name.dart';
import 'package:flutter_test/flutter_test.dart';

/// Kategorie-IDs sind hier einfach die Namen, das macht Fehlermeldungen lesbar.
final _allNames = [
  CategoryNames.obst, CategoryNames.gemuese, CategoryNames.fleisch, CategoryNames.fisch, CategoryNames.milch,
  CategoryNames.eier, CategoryNames.brot, CategoryNames.kaese, CategoryNames.getraenke, CategoryNames.tiefkuehl,
  CategoryNames.konserven, CategoryNames.oele, CategoryNames.suess, CategoryNames.fertig, CategoryNames.haushalt,
  CategoryNames.pfand, CategoryNames.sonstiges,
];

Categorizer _categorizer({Map<String, String> aliases = const {}, List<String>? without}) => Categorizer(
      categoryIdByName: {for (final n in _allNames.where((n) => !(without ?? const []).contains(n))) n: n},
      aliasCategoryIdByKey: aliases,
    );

void main() {
  group('normalizeItemName', () {
    final cases = <String, String>{
      'IC DKIH Erdäpfel vofe 2kg': 'dkih erdaepfel vofe',
      'IC DKIH Paprika Tricolore': 'dkih paprika tricolore',
      'DKIH Paprika Tricolore': 'dkih paprika tricolore', // gleicher Schluessel mit und ohne "IC"
      '1C DKIH Paprika Tricolore': 'dkih paprika tricolore', // OCR-Variante
      'IO Billa getr. Kichererbs': 'billa getr kichererbs',
      'SG RUCOLA SALAT 125G': 'sg rucola salat',
      'Nestlé Pirulo Kaktus Box': 'nestle pirulo kaktus box',
      'Vöslauer Balance': 'voeslauer balance',
      'Clever Champignon weiß': 'clever champignon weiss',
      'Onigiri Wakame 100g': 'onigiri wakame',
      'IC Clever Knobl.Bag.': 'clever knobl bag',
      'Ofen- und Grillerdäpfel': 'ofen und grillerdaepfel',
      '  Clever   Hirtenkäse  ': 'clever hirtenkaese',
      'CV FASCHIERTES GEM.500G': 'cv faschiertes gem',
      'Zwetschken 1kg': 'zwetschken',
      'Billa Immer Gut Erdnüsse': 'billa immer gut erdnuesse',
      'Clever Bl�tenhonig': 'clever bl tenhonig', // kaputte Kodierung (Ersatzzeichen) bleibt stabil
      '': '',
    };
    cases.forEach((input, expected) {
      test('"$input" -> "$expected"', () => expect(normalizeItemName(input), expected));
    });

    test('Der Punkt aus dem tuerkischen Grossbuchstaben I wird entfernt (OCR: "İC")', () {
      expect(normalizeItemName('İC DKIH Papr ika Tricolore'), 'dkih papr ika tricolore');
    });
  });

  group('Stichwortregeln auf allen 58 echten Artikelnamen aus den Testbons', () {
    // Soll-Zuordnung von Hand festgelegt. null = bewusst unbekannt (der Nutzer lernt der App das bei).
    final expected = <String, String?>{
      'Airwaves Cherry Menthol S': CategoryNames.suess,
      'BARILLA PESTO RUSTICO BAS': CategoryNames.oele,
      'BILLA IMMER GUT JASMINREIS': CategoryNames.konserven,
      'Billa Bio Bulgur': CategoryNames.konserven,
      'Billa Himb-Straccia Torte': CategoryNames.suess,
      'Billa Immer Gut Erdnüsse': CategoryNames.suess,
      'Billa Spaghetti Bronze': CategoryNames.konserven,
      'Bio Mohnstriezerl': CategoryNames.brot,
      'CLEVER PESTO GENOVESE': CategoryNames.oele,
      'CV FASCHIERTES GEM.500G': CategoryNames.fleisch,
      'Clever Blütenhonig': CategoryNames.suess,
      'Clever Champignon weiß': CategoryNames.gemuese,
      'Clever Hirtenkäse': CategoryNames.kaese,
      'Clever Laugenbreze': CategoryNames.brot,
      'Clever Pesto Rosso Vegan': CategoryNames.oele,
      'Clever Ung. Salami': CategoryNames.fleisch,
      'Coca-Cola Flasche': CategoryNames.getraenke,
      'Currywurst Zimbo': CategoryNames.fleisch,
      'DKIH Cherrytomaten Sophie': CategoryNames.gemuese,
      'DKIH Paprika Tricolore': CategoryNames.gemuese,
      'DKIH Zwiebel gelb 1kg': CategoryNames.gemuese,
      'EWP RED BULL ORG. MINT. B': CategoryNames.getraenke,
      'Eskimo Cornetto Classico': CategoryNames.tiefkuehl,
      'Farmer Soft Sandwich': CategoryNames.brot,
      'Grillselektion': CategoryNames.fleisch,
      'Hitschies brizzl UFO Pops': CategoryNames.suess,
      'IC Billa getr. Kichererbs': CategoryNames.konserven,
      'IC CV Joghurt griech. Art': CategoryNames.milch,
      'IC CV Pesto Alla Calabres': CategoryNames.oele,
      'IC CV Pesto Rosso vegan': CategoryNames.oele,
      'IC CV Sonnenblumenmarg.': CategoryNames.oele,
      'IC CV gehackte Tomaten': CategoryNames.konserven,
      'IC Clever Champignon weiß': CategoryNames.gemuese,
      'IC Clever Edamer Sch.': CategoryNames.kaese,
      'IC Clever Knobl.Bag.': CategoryNames.brot,
      'IC Clever Kräuter Bag.': CategoryNames.brot,
      'IC Clever Tomatenmark': CategoryNames.konserven,
      'IC DKIH Erdäpfel vofe 2kg': CategoryNames.gemuese,
      'IC DKIH Jungzwiebel Bund': CategoryNames.gemuese,
      'IC DKIH Kohlrabi Stk.': CategoryNames.gemuese,
      'IC DKIH Paprika Tricolore': CategoryNames.gemuese,
      'Karottenbrot': CategoryNames.brot,
      'Knoppers Nussriegel': CategoryNames.suess,
      'Mini Babybel Mix': CategoryNames.kaese,
      'Nestlé Pirulo Kaktus Box': CategoryNames.suess,
      'Ofen- und Grillerdäpfel': CategoryNames.gemuese,
      'Olivenbrot': CategoryNames.brot,
      'Onigiri Wakame 100g': CategoryNames.fertig,
      'Pfanner Pure Tea': CategoryNames.getraenke,
      'Protein Sandwich Thunfisc': CategoryNames.brot,
      'SG RUCOLA SALAT 125G': CategoryNames.gemuese,
      'SL Trauben rot kernl. kg': CategoryNames.obst,
      'Snickers Creamy Single': CategoryNames.suess,
      'Srd Berghof Vollmilch': CategoryNames.milch,
      'TAFELESSIG': CategoryNames.oele,
      'Vöslauer Balance': CategoryNames.getraenke,
      'Zwetschken 1kg': CategoryNames.obst,
      'scharfer Aufstrich': null,
    };

    expected.forEach((name, category) {
      test('"$name" -> ${category ?? 'unbekannt'}', () {
        final s = _categorizer().categorize(name);
        expect(s.categoryId, category);
        expect(s.source, category == null ? CategorySource.none : CategorySource.rule);
      });
    });

    test('Trefferquote der Regeln: 57 von 58 Namen (der eine unbekannte ist Absicht)', () {
      final assigned = expected.keys.where((n) => _categorizer().categorize(n).isAssigned).length;
      expect(assigned, 57);
    });
  });

  group('Reihenfolge der Regeln loest Streitfaelle', () {
    String? c(String name) => _categorizer().categorize(name).categoryId;

    test('Brot vor Gemuese, Schinken vor Saft, Keks vor Butter, Tomatenmark vor Tomate', () {
      expect(c('Karottenbrot'), CategoryNames.brot);
      expect(c('Saftschinken'), CategoryNames.fleisch);
      expect(c('Butterkeks'), CategoryNames.suess);
      expect(c('Erdnussbutter'), CategoryNames.suess);
      expect(c('Tomatenmark'), CategoryNames.konserven);
      expect(c('Tomaten Rispen'), CategoryNames.gemuese);
    });

    test('Eisbergsalat ist Gemuese, Eis am Stiel ist Tiefkuehl, Reis ist kein Eis', () {
      expect(c('Eisbergsalat'), CategoryNames.gemuese);
      expect(c('Eis Vanille'), CategoryNames.tiefkuehl);
      expect(c('Basmati Reis'), CategoryNames.konserven);
    });

    test('Kurze Woerter nur als ganzes Wort: "Ei" ist Eier, "Reis" nicht', () {
      expect(c('Ei'), CategoryNames.eier);
      expect(c('Freilandeier 10er'), CategoryNames.eier);
      expect(c('Bio Reis'), CategoryNames.konserven);
    });
  });

  group('Eigene Kategorien des Haushalts', () {
    Categorizer withOwn() => Categorizer(categoryIdByName: {
          for (final n in [
            ..._allNames, CategoryNames.nudeln, CategoryNames.saucen, CategoryNames.aufstriche, CategoryNames.chipsNuesse, CategoryNames.toGo,
          ])
            n: n,
        });

    // Echte Bon-Texte, dazu Streitfaelle, die nicht in die neue Kategorie gehoeren
    final expected = <String, String>{
      'IC Billa gew. Bandnudeln': CategoryNames.nudeln,
      'Billa Bio Bulgur': CategoryNames.nudeln,
      'BILLA IMMER GUT JASMINREI': CategoryNames.nudeln,
      'IC Clever Penne': CategoryNames.nudeln,
      'Billa Spaghetti Bronze': CategoryNames.nudeln,
      'IC CV Weizenmehl univers.': CategoryNames.nudeln,
      'Lasagneblätter': CategoryNames.nudeln,
      'Lasagne Bolognese': CategoryNames.saucen, // "bolognese" vor "lasagne": gelernte Zuordnung korrigiert das
      'BARILLA PESTO RUSTICO BAS': CategoryNames.saucen,
      'IC Barilla Sugo Arrab.': CategoryNames.saucen,
      'IC Chunky Salsa Med': CategoryNames.saucen,
      'BILLA IMMER GUT SATE ERDN': CategoryNames.saucen,
      'Sojasauce': CategoryNames.saucen,
      'BM GUACAMOLE 150 G': CategoryNames.aufstriche,
      'scharfer Aufstrich': CategoryNames.aufstriche,
      'Scharfer Brotaufstrich': CategoryNames.aufstriche,
      'IC CV Sonnenblumenmarg.': CategoryNames.aufstriche,
      'Clever Blütenhonig': CategoryNames.aufstriche,
      'Chips Papr i ka 250g': CategoryNames.chipsNuesse,
      "IC Kelly's Chips Ketch.": CategoryNames.chipsNuesse,
      'IC Kellys Riffels SC': CategoryNames.chipsNuesse,
      'Billa Immer Gut Erdnüsse': CategoryNames.chipsNuesse,
      'Baguette Thunfisch': CategoryNames.toGo,
      'BILLA SANDWICH LACHS/EI': CategoryNames.toGo,
      'Protein Sandwich Thunfisc': CategoryNames.toGo,
      'Onigiri Wakame 100g': CategoryNames.toGo,
      // Bleiben, wo sie sind
      'Farmer Soft Sandwich': CategoryNames.brot,
      'IC Clever Knobl.Bag.': CategoryNames.brot,
      'IC Knoppers Erdnussr. 3er': CategoryNames.suess,
      'Knoppers Nussriegel': CategoryNames.suess,
      'Schokolade Haselnüsse': CategoryNames.suess,
      'Erdnussbutter': CategoryNames.suess,
      'Thunfisch in Tomatensauce': CategoryNames.fisch,
      'IC CV gehackte Tomaten': CategoryNames.konserven,
      'IC Billa getr. Kichererbs': CategoryNames.konserven,
      'Sonnenblumenöl': CategoryNames.oele,
      'TAFELESSIG': CategoryNames.oele,
      'BILLA Instant Nudeln Huhn': CategoryNames.fertig,
      'Shin Ramen Toomba 137g': CategoryNames.fertig,
    };
    expected.forEach((name, category) {
      test('"$name" -> $category', () => expect(withOwn().categorize(name).categoryId, category));
    });

    test('Ohne die eigenen Kategorien greift die alte Regel', () {
      final c = _categorizer();
      expect(c.categorize('IC Clever Penne').categoryId, CategoryNames.konserven);
      expect(c.categorize('CLEVER PESTO GENOVESE').categoryId, CategoryNames.oele);
      expect(c.categorize('Billa Immer Gut Erdnüsse').categoryId, CategoryNames.suess);
      expect(c.categorize('Baguette Thunfisch').categoryId, CategoryNames.brot);
      expect(c.categorize('Onigiri Wakame 100g').categoryId, CategoryNames.fertig);
    });
  });

  group('Alias, Pfand und Sonderfaelle', () {
    test('Gelernte Zuordnung schlaegt die Regel', () {
      final c = _categorizer(aliases: {'dkih paprika tricolore': CategoryNames.sonstiges});
      final s = c.categorize('IC DKIH Paprika Tricolore'); // andere Schreibweise, gleicher Schluessel
      expect(s.categoryId, CategoryNames.sonstiges);
      expect(s.source, CategorySource.alias);
    });

    test('Alias fuer einen unbekannten Artikel: aus "unbekannt" wird zugeordnet', () {
      final c = _categorizer(aliases: {'scharfer aufstrich': CategoryNames.oele});
      expect(c.categorize('scharfer Aufstrich').categoryId, CategoryNames.oele);
    });

    test('Pfandposition bekommt die Kategorie Pfand, egal wie sie heisst', () {
      final s = _categorizer().categorize('EINWEGPFAND', isDeposit: true);
      expect(s.categoryId, CategoryNames.pfand);
      expect(s.source, CategorySource.kind);
    });

    test('Fehlt die Kategorie beim Nutzer (umbenannt/geloescht), greift die naechste Regel oder keine', () {
      final c = _categorizer(without: [CategoryNames.gemuese]);
      // "Champignon" -> Gemuese existiert nicht, keine weitere Regel passt: unzugeordnet
      expect(c.categorize('Clever Champignon weiß').categoryId, isNull);
      // Pfand ohne Pfand-Kategorie: kein Absturz
      final noPfand = _categorizer(without: [CategoryNames.pfand]);
      expect(noPfand.categorize('PFANDARTIKEL', isDeposit: true).categoryId, isNull);
    });

    test('Leerer Name bleibt unzugeordnet', () {
      expect(_categorizer().categorize('').categoryId, isNull);
    });
  });
}
