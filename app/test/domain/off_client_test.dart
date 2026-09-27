import 'dart:convert';

import 'package:einkaufstracker/data/products/off_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Client _mock(int status, Object body) => MockClient((req) async => http.Response(jsonEncode(body), status));

void main() {
  group('HttpOffClient.lookup', () {
    test('vollstaendiges Produkt mit Naehrwerten', () async {
      final client = HttpOffClient(client: _mock(200, {
        'status': 1,
        'product': {
          'product_name': 'Vollmilch 3,5%',
          'brands': 'Clever,Billa',
          'categories_tags': ['en:dairies', 'en:milks'],
          'quantity': '1 l',
          'nutriments': {'energy-kcal_100g': 64, 'proteins_100g': 3.3, 'fat_100g': 3.5, 'carbohydrates_100g': 4.8},
        },
      }));
      final p = await client.lookup('9008700000000');
      expect(p, isNotNull);
      expect(p!.name, 'Vollmilch 3,5%');
      expect(p.brand, 'Clever'); // erste Marke vor dem Komma
      expect(p.categoryTags, ['en:dairies', 'en:milks']);
      expect(p.quantityText, '1 l');
      expect(p.nutrientsBasis, 'g');
      expect(p.nutrientsPer100, {'kcal': 64.0, 'protein_g': 3.3, 'fat_g': 3.5, 'carbs_g': 4.8});
    });

    test('status 0 (nicht gefunden): null', () async {
      final client = HttpOffClient(client: _mock(200, {'status': 0}));
      expect(await client.lookup('0000000000000'), isNull);
    });

    test('HTTP-Fehler: null statt Exception', () async {
      final client = HttpOffClient(client: _mock(500, {}));
      expect(await client.lookup('123'), isNull);
    });

    test('Produkt ohne Namen: null', () async {
      final client = HttpOffClient(client: _mock(200, {'status': 1, 'product': {}}));
      expect(await client.lookup('123'), isNull);
    });

    test('Produkt ohne Naehrwerte: nutrientsPer100 bleibt null', () async {
      final client = HttpOffClient(client: _mock(200, {
        'status': 1,
        'product': {'product_name': 'Testartikel'},
      }));
      final p = await client.lookup('123');
      expect(p!.nutrientsPer100, isNull);
      expect(p.brand, isNull);
    });

    test('kaputte Antwort (kein JSON): null statt Absturz', () async {
      final client = HttpOffClient(client: MockClient((req) async => http.Response('nicht json', 200)));
      expect(await client.lookup('123'), isNull);
    });
  });
}
