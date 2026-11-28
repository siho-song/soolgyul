import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/app_header_policy.dart';
import 'package:soolgyul/src/features/onboarding/presentation/auth/app_loading_screen.dart';
import 'package:soolgyul/src/navigation/app_route.dart';
import 'package:soolgyul/src/widgets/app_brand_logo.dart';
import 'package:soolgyul/src/widgets/app_top_bar.dart';

// The app's mark is the 술결 wordmark everywhere; the brush lettering is
// gone from the bundle.

double _heightOf(WidgetTester tester) =>
    tester.getSize(find.byType(AppBrandLogo)).height;

void main() {
  test('the wordmark is bundled and the old marks are not', () {
    expect(AppBrandLogo.assetPath, 'assets/brand/soolgyul_wordmark.webp');
    expect(File(AppBrandLogo.assetPath).existsSync(), isTrue);
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains(AppBrandLogo.assetPath));
    for (final old in ['soolgyeol_logo.svg', 'soolgyeol_app_icon.svg']) {
      expect(File('assets/brand/$old').existsSync(), isFalse, reason: old);
      expect(pubspec, isNot(contains(old)), reason: old);
    }
  });

  testWidgets('it is drawn 24 tall in a header and 40 tall on the loading '
      'screen, and read as 술결', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppHeaderPolicy.build(
            route: AppRoute.recordSearch,
            onBack: () {},
          ),
        ),
      ),
    );
    final image = tester.widget<Image>(
      find.descendant(
        of: find.byType(AppBrandLogo),
        matching: find.byType(Image),
      ),
    );
    expect((image.image as AssetImage).assetName, AppBrandLogo.assetPath);
    expect(image.semanticLabel, '술결');
    expect(_heightOf(tester), 24);
    // In the middle of the header, beside the way back.
    expect(
      tester.getCenter(find.byType(AppBrandLogo)).dx,
      tester.getCenter(find.byType(AppTopBar)).dx,
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppLoadingScreen())),
    );
    expect(_heightOf(tester), 40);
    await tester.pumpAndSettle();
  });
}
