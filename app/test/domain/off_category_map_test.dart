import 'package:einkaufstracker/domain/categorization/keyword_rules.dart';
import 'package:einkaufstracker/domain/categorization/off_category_map.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('categoryFromOffTags', () {
    final cases = <List<String>, String?>{
      ['en:dairies', 'en:milks']: CategoryNames.milch,
      ['en:cheeses']: CategoryNames.kaese,
      ['en:eggs']: CategoryNames.eier,
      ['en:meats', 'en:sausages']: CategoryNames.fleisch,
      ['en:fishes', 'en:seafood']: CategoryNames.fisch,
      ['en:breads']: CategoryNames.brot,
      ['en:fresh-vegetables']: CategoryNames.gemuese,
      ['en:fresh-fruits']: CategoryNames.obst,
      ['en:frozen-foods']: CategoryNames.tiefkuehl,
      ['en:beverages', 'en:waters']: CategoryNames.getraenke,
      ['en:pastas']: CategoryNames.konserven,
      ['en:condiments', 'en:sauces']: CategoryNames.oele,
      ['en:chocolates']: CategoryNames.suess,
      ['en:meals', 'en:pizzas']: CategoryNames.fertig,
      ['en:household']: CategoryNames.haushalt,
      []: null,
      ['en:unknown-tag']: null,
    };
    cases.forEach((tags, expected) {
      test('$tags -> ${expected ?? 'unbekannt'}', () => expect(categoryFromOffTags(tags), expected));
    });
  });
}
