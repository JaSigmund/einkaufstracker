import 'package:einkaufstracker/data/cloud/cloud_receipt.dart';
import 'package:einkaufstracker/data/cloud/supabase_cloud_receipt_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cloudReceiptExceptionFor (Antworten von parse-receipt)', () {
    test('403 cloud_ocr_not_allowed = in den Einstellungen ausgeschaltet', () {
      expect(cloudReceiptExceptionFor(403, {'error': 'cloud_ocr_not_allowed'}), isA<CloudNotAllowed>());
    });

    test('429 daily_limit_reached = Tageslimit, mit verstaendlicher Meldung statt "Fehler 429"', () {
      final e = cloudReceiptExceptionFor(429, {'error': 'daily_limit_reached'});
      expect(e, isA<CloudUnavailable>());
      expect((e as CloudUnavailable).message, contains('Tageslimit'));
    });

    test('alles andere = vorerst nicht verfuegbar, mit Statuscode', () {
      for (final (status, details) in [(403, {'error': 'forbidden'}), (429, null), (500, 'kaputt'), (502, {'error': 'llm_failed'})]) {
        final e = cloudReceiptExceptionFor(status, details);
        expect(e, isA<CloudUnavailable>(), reason: '$status');
        expect((e as CloudUnavailable).message, 'Fehler $status');
      }
    });
  });
}
