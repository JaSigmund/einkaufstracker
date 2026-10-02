import 'package:einkaufstracker/data/app_config/app_config_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppConfig.fromJson', () {
    test('liest min_supported_build_number und message', () {
      final config = AppConfig.fromJson({'min_supported_build_number': 18, 'message': 'Bitte aktualisieren'});
      expect(config.minSupportedBuildNumber, 18);
      expect(config.message, 'Bitte aktualisieren');
    });

    test('message fehlt: null statt Absturz', () {
      final config = AppConfig.fromJson({'min_supported_build_number': 1});
      expect(config.message, isNull);
    });
  });
}
