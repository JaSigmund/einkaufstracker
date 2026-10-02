import 'package:einkaufstracker/domain/app_update/app_update_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isAppUpdateRequired', () {
    test('eigene Build-Nummer unter der Mindestversion: Update erforderlich', () {
      expect(isAppUpdateRequired(currentBuildNumber: 17, minSupportedBuildNumber: 18), isTrue);
    });

    test('eigene Build-Nummer gleich der Mindestversion: kein Update noetig', () {
      expect(isAppUpdateRequired(currentBuildNumber: 18, minSupportedBuildNumber: 18), isFalse);
    });

    test('eigene Build-Nummer ueber der Mindestversion: kein Update noetig', () {
      expect(isAppUpdateRequired(currentBuildNumber: 19, minSupportedBuildNumber: 18), isFalse);
    });

    test('Standard-Mindestversion 1: praktisch nie ein Update noetig', () {
      expect(isAppUpdateRequired(currentBuildNumber: 1, minSupportedBuildNumber: 1), isFalse);
    });
  });

  group('AppUpdateRequiredException', () {
    test('verstaendlicher Text statt technischer Fehlermeldung', () {
      expect(const AppUpdateRequiredException().toString(), contains('Update'));
    });
  });
}
