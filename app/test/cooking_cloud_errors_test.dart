import 'package:einkaufstracker/data/cloud/cooking_cloud.dart';
import 'package:einkaufstracker/data/cloud/supabase_cooking_cloud.dart';
import 'package:flutter_test/flutter_test.dart';

/// Zuordnung der Edge-Function-Antworten (ADR-021) zu Ausnahmen, ohne Netzwerk.
void main() {
  test('403 cloud_ocr_not_allowed: vom Nutzer ausgeschaltet', () {
    expect(cookingCloudExceptionFor(403, {'error': 'cloud_ocr_not_allowed'}), isA<CookingCloudNotAllowed>());
  });

  test('429 daily_limit_reached: Tageslimit erreicht (Doku 09 §2)', () {
    expect(cookingCloudExceptionFor(429, {'error': 'daily_limit_reached'}), isA<CookingCloudDailyLimit>());
  });

  test('403 mit anderem Grund (z.B. kein Mitglied) ist NICHT "ausgeschaltet"', () {
    final e = cookingCloudExceptionFor(403, {'error': 'forbidden'});
    expect(e, isA<CookingCloudUnavailable>());
    expect(e.toString(), 'Fehler 403');
  });

  test('429 ohne bekanntes Detail bleibt ein allgemeiner Fehler', () {
    expect(cookingCloudExceptionFor(429, null), isA<CookingCloudUnavailable>());
  });

  test('sonstige Fehler und unerwartete Detailformen: allgemeiner Fehler mit Status', () {
    expect(cookingCloudExceptionFor(502, {'error': 'llm_failed'}).toString(), 'Fehler 502');
    expect(cookingCloudExceptionFor(500, 'kein JSON-Objekt').toString(), 'Fehler 500');
  });

  test('Meldungstext des Tageslimits ist fuer Nutzer verstaendlich', () {
    expect(const CookingCloudDailyLimit().toString(), contains('Tageslimit'));
  });
}
