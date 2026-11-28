import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/widgets/app_icon.dart';

void main() {
  test('every icon has its file', () {
    for (final icon in AppIconAsset.values) {
      expect(
        File('assets/icons/line/${icon.fileName}.svg').existsSync(),
        isTrue,
        reason: icon.name,
      );
    }
  });

  testWidgets('an icon is its file, at the size and colour asked for', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppIcon(AppIconAsset.close, size: 18, color: Colors.black),
      ),
    );

    final drawn = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(drawn.width, 18);
    expect(drawn.height, 18);
    expect(
      drawn.colorFilter,
      const ColorFilter.mode(Colors.black, BlendMode.srcIn),
    );
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('the half star is filled on its left half only', (tester) async {
    const size = 96.0;
    final boundary = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: boundary,
            child: const ColoredBox(
              color: Colors.white,
              child: AppIcon(
                AppIconAsset.starHalf,
                size: size,
                color: Colors.black,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    final pixels = await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage();
      final data = await image.toByteData();
      return data!;
    });
    int red(double x, double y) =>
        pixels!.getUint8(((y.round() * size.round()) + x.round()) * 4);

    // Inside the star, a little left and right of its middle line.
    final left = red(size * 0.40, size * 0.55);
    final right = red(size * 0.60, size * 0.55);
    expect(left, lessThan(64), reason: 'left half is filled');
    expect(right, greaterThan(192), reason: 'right half is empty');
  });
}
