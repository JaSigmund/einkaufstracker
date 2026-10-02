import 'package:einkaufstracker/domain/recipes/recipe_search_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildRecipeSearchUrl', () {
    test('baut eine auf die Domain eingeschraenkte Google-Suche, nicht die interne Suche der Seite', () {
      final url = buildRecipeSearchUrl('Kürbissuppe');
      expect(url, startsWith('https://www.google.com/search?q='));
      expect(url, isNot(contains('gutekueche.at/suche')));
      expect(Uri.parse(url).queryParameters['q'], 'site:gutekueche.at Kürbissuppe rezept');
    });

    test('andere Seite per Parameter einstellbar', () {
      final url = buildRecipeSearchUrl('Erdäpfelgulasch', site: 'chefkoch.de');
      expect(Uri.parse(url).queryParameters['q'], contains('site:chefkoch.de'));
    });

    test('Leerzeichen am Rand werden entfernt', () {
      final url = buildRecipeSearchUrl('  Gemüsecurry  ');
      expect(Uri.parse(url).queryParameters['q'], 'site:gutekueche.at Gemüsecurry rezept');
    });
  });
}
