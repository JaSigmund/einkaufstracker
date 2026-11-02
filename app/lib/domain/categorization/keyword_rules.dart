/// Namen der Standardkategorien (siehe supabase/migrations/0002_default_categories.sql).
/// Die Regeln verweisen auf diese Namen. Hat der Nutzer eine Kategorie umbenannt oder geloescht, greift die
/// Regel nicht und der Artikel bleibt unzugeordnet (dann lernt die App aus der Korrektur).
class CategoryNames {
  static const obst = 'Obst';
  static const gemuese = 'Gemüse';
  static const fleisch = 'Fleisch & Wurst';
  static const fisch = 'Fisch';
  static const milch = 'Milch & Milchprodukte';
  static const eier = 'Eier';
  static const brot = 'Brot & Backwaren';
  static const kaese = 'Käse';
  static const getraenke = 'Getränke';
  static const tiefkuehl = 'Tiefkühl';
  static const konserven = 'Konserven & Trockenware';
  static const oele = 'Öle, Gewürze & Saucen';
  static const suess = 'Süßes & Snacks';
  static const fertig = 'Fertiggerichte';
  static const haushalt = 'Haushalt & Drogerie';
  static const pfand = 'Pfand';
  static const sonstiges = 'Sonstiges';

  // Selbst angelegt, nicht in der Vorlage fuer neue Haushalte. Fehlt eine davon, greift die naechste passende Regel (alte Kategorie).
  static const nudeln = 'Nudeln, Reis & Getreide';
  static const saucen = 'Saucen & Pesto';
  static const aufstriche = 'Aufstriche & Dips';
  static const chipsNuesse = 'Chips & Nüsse';
  static const toGo = 'Snacks to go';
}

/// Eine Stichwortregel. Die Stichwoerter stehen in normalisierter Form (siehe normalizeItemName: klein,
/// Umlaute als ae/oe/ue, ss statt ß).
///
/// Schreibweise eines Stichworts:
///   `abc`   Wort **enthaelt** abc (deckt Zusammensetzungen wie "Karottenbrot" und abgeschnittene Namen ab)
///   `^abc`  Wort **beginnt** mit abc
///   `=abc`  Wort ist **genau** abc (fuer kurze, mehrdeutige Woerter wie "ei", "tea", "bag")
///   `a b`   mit Leerzeichen: der ganze normalisierte Name enthaelt diese Wortfolge
class KeywordRule {
  const KeywordRule(this.category, this.keywords);
  final String category;
  final List<String> keywords;

  bool matches(String normalized, List<String> tokens) {
    for (final k in keywords) {
      if (k.contains(' ')) {
        if (normalized.contains(k)) return true;
      } else if (k.startsWith('=')) {
        if (tokens.contains(k.substring(1))) return true;
      } else if (k.startsWith('^')) {
        final p = k.substring(1);
        if (tokens.any((t) => t.startsWith(p))) return true;
      } else {
        if (tokens.any((t) => t.contains(k))) return true;
      }
    }
    return false;
  }
}

/// Regeln in **Prioritaetsreihenfolge**: die erste passende gewinnt. Die Reihenfolge loest Streitfaelle:
/// "Karottenbrot" ist Brot (Backwaren vor Gemuese), "Tomatenmark" und "gehackte Tomaten" sind Konserven
/// (vor Gemuese), "Saftschinken" ist Wurst (vor Getraenken), "Butterkeks" ist ein Keks (Suesses vor Milch).
/// "Brotaufstrich" ist ein Aufstrich (vor Brot), "Farmer Soft Sandwich" bleibt Brot, nur belegte Namen sind Snacks to go.
/// "Thunfisch in Tomatensauce" bleibt Fisch: nur "pesto", "sugo" und "salsa" stehen weit vorn, "sauce" erst hinter den Konserven.
const keywordRules = <KeywordRule>[
  KeywordRule(CategoryNames.pfand, ['pfand', 'leergut', 'flaschenkasten', 'einweg']),
  KeywordRule(CategoryNames.toGo, [
    'billa sandwich', 'protein sandwich', 'sandwich lachs', 'sandwich thun', 'sandwich schinken', 'sandwich kaese', 'sandwich ei',
    'baguette thun', 'baguette lachs', 'baguette schinken', 'baguette salami', 'baguette kaese', 'onigiri', 'sushi',
  ]),
  KeywordRule(CategoryNames.aufstriche, [
    'aufstrich', 'guacamole', 'hummus', '=dip', '=dips', '=honig', 'bluetenhonig', 'waldhonig', 'akazienhonig', 'marmelade', 'konfituere',
    'nutella', 'margarine', 'sonnenblumenmarg', '=marg',
  ]),
  KeywordRule(CategoryNames.brot, [
    'brot', 'semmel', 'breze', 'brezel', 'striez', 'gebaeck', 'croissant', 'kipferl', 'toast', 'baguette', '=bag',
    'sandwich', 'weckerl', 'zopf', 'buchtel', 'krapfen', 'kornspitz', 'stangerl', 'fladen', 'brioche', 'laugen',
    'schrippe', 'ciabatta', 'foccacia', 'focaccia',
  ]),
  // Streitfaelle mit Gemuese/Milch
  KeywordRule(CategoryNames.konserven, ['tomatenmark', 'gehackte tomaten', 'passata', 'kokosmilch', 'pizzasauce']),
  KeywordRule(CategoryNames.saucen, ['pesto', 'sugo', 'salsa', '=sate']),
  // Instant-Nudeln vor Fleisch ("Instant Nudeln Huhn") und vor den Nudeln
  KeywordRule(CategoryNames.fertig, ['instant nudel', 'nudelsuppe', 'nudel cup', 'cup nudel', '=ramen', '=ramyun']),
  // Schokolade mit Nuessen bleibt Suesses, "Erdnussriegel" trifft "erdnuesse" nicht
  KeywordRule(CategoryNames.suess, ['schoko', 'riegel']),
  KeywordRule(CategoryNames.chipsNuesse, ['chips', 'riffels', 'erdnuesse', 'nuesse', 'cashew', 'pistazie', '=mandeln', 'popcorn', 'salzstangen', 'cracker']),
  KeywordRule(CategoryNames.suess, [
    'schoko', 'riegel', 'keks', 'gummi', 'bonbon', 'chips', 'erdnuss', 'erdnuesse', 'nuss', 'nuesse', 'honig', 'marmelade', 'konfituere',
    'nutella', 'waffel', 'lakritz', 'snickers', '=mars', 'twix', 'kitkat', 'knoppers', 'airwaves', 'hitschies',
    'pops', 'pirulo', 'nestle', 'haribo', 'popcorn', 'salzstangen', 'cracker', 'torte', 'kuchen', 'muffin', 'donut',
    'zuckerl', 'kaugummi', 'ferrero', 'milka', 'manner', 'oreo', 'praline', 'dessert', 'pudding', 'zuckerwatte',
  ]),
  KeywordRule(CategoryNames.fleisch, [
    'fleisch', 'faschiert', '^hack', 'schinken', 'wurst', 'salami', 'speck', 'grillselektion', 'grillfleisch',
    'kotelett', 'schnitzel', 'steak', 'huhn', 'huehn', 'haehnchen', 'hendl', 'pute', 'truthahn', 'rind', 'schwein', 'lamm',
    'leberkaese', 'extrawurst', 'frankfurter', 'zimbo', 'bacon', 'gyros', 'kebab', 'cabanossi', 'knacker',
    'pastete', 'burger', 'nuggets',
  ]),
  KeywordRule(CategoryNames.fisch, [
    'fisch', 'lachs', 'thunfisc', 'forelle', 'garnele', 'shrimp', 'surimi', 'hering', 'makrele', 'kabeljau',
    'sardine', 'scampi',
  ]),
  KeywordRule(CategoryNames.kaese, [
    'kaese', 'mozzarella', 'gouda', 'edamer', 'emmentaler', 'parmesan', 'feta', 'camembert', 'brie', 'gorgonzola',
    'babybel', 'halloumi', 'grana', 'pecorino', 'mascarpone', 'raclette',
  ]),
  KeywordRule(CategoryNames.getraenke, [
    'coca', '^cola', 'pepsi', 'fanta', 'sprite', 'limo', 'saft', 'wasser', 'voeslauer', 'bier', 'wein', 'sekt', '=bull', 'energy',
    '=tee', '=tea', 'eistee', 'kaffee', 'mineral', 'soda', 'spezi', 'almdudler', 'gasteiner', 'pfanner', 'rauch',
    'smoothie', 'prosecco', 'radler', 'shandy', 'kakao',
  ]),
  KeywordRule(CategoryNames.milch, [
    'milch', 'joghurt', 'jogurt', 'topfen', 'sauerrahm', 'schlagobers', 'obers', 'rahm', 'butter', 'kefir', 'skyr',
    'quark', 'sahne',
  ]),
  KeywordRule(CategoryNames.eier, ['=ei', '=eier', 'freilandei', 'bodenhaltung']),
  KeywordRule(CategoryNames.tiefkuehl, ['tiefkuehl', 'cornetto', 'eskimo', 'magnum', 'speiseeis', 'eiscreme', '=eis', 'eisstiel']),
  KeywordRule(CategoryNames.gemuese, [
    'erdaepfel', 'kartoffel', 'paprika', 'tomate', 'gurke', 'zucchini', 'karotte', 'moehre', 'zwiebel', 'lauch',
    'knoblauch', 'salat', 'rucola', 'spinat', 'kohl', 'brokkoli', 'karfiol', 'blumenkohl', 'sellerie', 'fenchel',
    'kuerbis', 'melanzani', 'aubergine', 'champignon', 'pilz', 'schwammerl', 'radieschen', 'rettich', 'rueben',
    'spargel', 'ingwer', 'kraut', 'gemuese', 'kren', 'mangold', 'petersil', 'schnittlauch', 'basilikum',
  ]),
  KeywordRule(CategoryNames.obst, [
    'apfel', 'aepfel', 'birne', 'banane', 'orange', 'zitrone', 'mandarine', 'clementine', 'trauben', 'erdbeer',
    'himbeer', 'heidelbeer', 'kirsche', 'zwetschk', 'pflaume', 'marille', 'pfirsich', 'nektarine', 'melone',
    'ananas', 'mango', 'kiwi', 'avocado', 'beere', 'obst', 'grapefruit', 'limette', 'feige',
  ]),
  KeywordRule(CategoryNames.nudeln, [
    'nudel', 'spaghetti', 'penne', 'fusilli', 'tagliatelle', 'fleckerl', 'lasagneblaett', 'lasagneplatt', 'reis', 'jasmin', 'basmati', 'bulgur',
    'couscous', 'mehl', 'haferflock', 'muesli', 'cornflakes', 'gries', 'polenta',
  ]),
  KeywordRule(CategoryNames.konserven, [
    'nudel', 'spaghetti', 'penne', 'fusilli', 'tagliatelle', 'fleckerl', 'reis', 'jasmin', 'basmati', 'bulgur',
    'couscous', 'linsen', 'kichererb', 'bohnen', 'erbsen', 'mais', 'mehl', 'zucker', 'haferflock', 'muesli',
    'cornflakes', 'konserve', 'rosinen', 'trockenfruecht', 'sonnenblumenkerne', 'gries', 'polenta',
  ]),
  KeywordRule(CategoryNames.saucen, ['sauce', 'sosse', 'bolognese']),
  KeywordRule(CategoryNames.oele, [
    'oel', 'essig', 'senf', 'ketchup', 'mayo', 'sauce', 'sosse', 'pesto', 'dressing', 'gewuerz', 'salz', 'pfeffer',
    'curry', 'marg', 'sojasauce', 'worcester', 'sriracha', 'tabasco', 'bruehe', 'suppenwuerfel', 'gemueseboullion',
    'oregano', 'paprikapulver', 'zimt', 'vanille', 'backpulver',
  ]),
  KeywordRule(CategoryNames.fertig, [
    'onigiri', 'sushi', 'pizza', 'lasagne', 'fertig', 'suppe', 'wrap', 'burrito', 'gulasch', 'eintopf', 'tortellini',
    'ravioli', 'gnocchi', 'pommes',
  ]),
  KeywordRule(CategoryNames.haushalt, [
    'papier', 'kuechenrolle', 'spuel', 'waschmittel', 'reiniger', 'seife', 'shampoo', 'duschgel', 'zahnpasta',
    'zahnbuerste', 'windel', 'tuecher', 'taschentuch', 'muellsack', 'alufolie', 'batterie', 'kerze', 'schwamm',
    'deo', 'tampon', 'rasier', 'sagrotan', 'fairy', 'somat', 'ariel',
  ]),
];
