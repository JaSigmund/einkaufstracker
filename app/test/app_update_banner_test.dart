import 'package:einkaufstracker/app/providers.dart';
import 'package:einkaufstracker/features/common/app_update_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app({required bool updateRequired}) => ProviderScope(
        overrides: [appUpdateRequiredProvider.overrideWithValue(updateRequired)],
        child: const MaterialApp(home: Scaffold(body: AppUpdateBanner())),
      );

  testWidgets('kein Update noetig: nichts zu sehen', (tester) async {
    await tester.pumpWidget(app(updateRequired: false));
    expect(find.byKey(const Key('app-update-banner')), findsNothing);
  });

  testWidgets('Update noetig: Standardtext', (tester) async {
    await tester.pumpWidget(app(updateRequired: true));
    expect(find.byKey(const Key('app-update-banner')), findsOneWidget);
    expect(find.textContaining('Update ist erforderlich'), findsOneWidget);
  });
}
