import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/nutrition/off_micros.dart';

/// Ergebnis eines Open-Food-Facts-Lookups: das Noetigste fuer die Produktanlage (Doku 06 §4).
class OffProduct {
  const OffProduct({
    required this.name,
    this.brand,
    this.categoryTags = const [],
    this.nutrientsPer100,
    this.nutrientsBasis,
    this.quantityText,
  });

  final String name;
  final String? brand;

  /// OFF-Kategorie-Tags (z.B. "en:milks"), fuer eine grobe Zuordnung zu eigenen Kategorien.
  final List<String> categoryTags;

  /// {kcal, protein_g, fat_g, sat_fat_g, carbs_g, sugar_g, fiber_g, salt_g}, soweit von OFF bekannt, dazu die Mikronaehrstoffe mit den
  /// Schluesseln des Registers (`vit_c_mg`, `iron_mg`, ...; Phase N4), soweit OFF sie kennt und sie plausibel sind.
  final Map<String, double>? nutrientsPer100;

  /// 'g' oder 'ml'.
  final String? nutrientsBasis;

  /// Packungsgroesse wie von OFF angegeben, z.B. "1 l", "500 g" (zur Anzeige, nicht geparst).
  final String? quantityText;
}

/// Liest Produktdaten von Open Food Facts. Wirft nichts: Netzfehler und "nicht gefunden" ergeben beide null,
/// der Aufrufer bietet dann die manuelle Anlage an.
abstract class OffClient {
  Future<OffProduct?> lookup(String ean);
}

class HttpOffClient implements OffClient {
  HttpOffClient({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const _fields = 'product_name,brands,categories_tags,nutriments,quantity';

  @override
  Future<OffProduct?> lookup(String ean) async {
    try {
      final uri = Uri.parse('https://world.openfoodfacts.org/api/v2/product/$ean.json?fields=$_fields');
      final resp = await _client.get(uri, headers: {'User-Agent': 'Einkaufstracker - Android - Version 1.0'}).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      if (body['status'] != 1) return null;
      return _parse(body['product'] as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  OffProduct? _parse(Map<String, dynamic> p) {
    final name = (p['product_name'] as String?)?.trim();
    if (name == null || name.isEmpty) return null;
    final brand = (p['brands'] as String?)?.split(',').first.trim();

    final nutriments = p['nutriments'] as Map<String, dynamic>?;
    Map<String, double>? nutrients;
    String? basis;
    if (nutriments != null) {
      double? get(String key) => (nutriments[key] as num?)?.toDouble();
      final map = <String, double>{};
      void set(String out, String key) {
        final v = get(key);
        if (v != null) map[out] = v;
      }
      set('kcal', 'energy-kcal_100g');
      set('protein_g', 'proteins_100g');
      set('fat_g', 'fat_100g');
      set('sat_fat_g', 'saturated-fat_100g');
      set('carbs_g', 'carbohydrates_100g');
      set('sugar_g', 'sugars_100g');
      set('fiber_g', 'fiber_100g');
      set('salt_g', 'salt_100g');
      map.addAll(microsFromOffNutriments(nutriments) ?? const {});
      if (map.isNotEmpty) {
        nutrients = map;
        basis = 'g'; // OFF liefert je 100 g, auch fuer Fluessigkeiten (dort faktisch ml)
      }
    }

    return OffProduct(
      name: name,
      brand: brand == null || brand.isEmpty ? null : brand,
      categoryTags: (p['categories_tags'] as List?)?.cast<String>() ?? const [],
      nutrientsPer100: nutrients,
      nutrientsBasis: basis,
      quantityText: (p['quantity'] as String?)?.trim(),
    );
  }
}
