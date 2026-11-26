import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/widgets/app_icon.dart';

void main() {
  testWidgets('the close icon is Flutter\'s own ×, at the size and colour '
      'asked for', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppIcon(AppIconAsset.close, size: 18, color: Colors.black),
      ),
    );

    final drawn = tester.widget<Icon>(find.byIcon(Icons.close_rounded));
    expect(drawn.size, 18);
    expect(drawn.color, Colors.black);
    expect(find.byType(SvgPicture), findsNothing);
  });

  testWidgets('every other icon is its file', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AppIcon(AppIconAsset.search)),
    );

    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
  });
}
