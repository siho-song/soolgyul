import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/design/app_tokens.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/widgets/label_reading_screen.dart';
import 'package:soolgyul/src/widgets/app_paper.dart';
import 'package:soolgyul/src/widgets/app_screen.dart';
import 'package:soolgyul/src/widgets/app_top_bar.dart';

// Every page lies on the same 한지: the shared screen lays it, a page's own
// scaffold and its header let it show, and what is painted in one colour
// takes the paper's average.

DecorationImage _paperOf(WidgetTester tester, Finder paper) {
  final box = tester.widget<DecoratedBox>(
    find.descendant(of: paper, matching: find.byType(DecoratedBox)).first,
  );
  return (box.decoration as BoxDecoration).image!;
}

void main() {
  test('the paper is bundled', () {
    expect(File(AppPaper.asset).existsSync(), isTrue);
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('- assets/images/paper/'),
    );
  });

  testWidgets('the shared screen lays the paper under a scaffold and a '
      'header that let it show', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AppScreen(
          appBar: AppTopBar.back(onPressed: () {}, title: '제목'),
          child: const Text('내용'),
        ),
      ),
    );
    final paper = find.byType(AppPaper);
    expect(paper, findsOneWidget);
    expect(tester.getSize(paper), tester.getSize(find.byType(MaterialApp)));

    final image = _paperOf(tester, paper);
    expect((image.image as AssetImage).assetName, AppPaper.asset);
    // Repeated from the top left at the size its grain was made for, never
    // stretched to the screen.
    expect(image.repeat, ImageRepeat.repeat);
    expect(image.alignment, Alignment.topLeft);
    expect(image.fit, isNull);
    expect(image.scale, closeTo(759 / 346, 1e-9));

    final scaffold = tester.widget<Scaffold>(
      find.descendant(of: paper, matching: find.byType(Scaffold)),
    );
    expect(scaffold.backgroundColor, Colors.transparent);
    // The header paints no colour over the paper.
    final header = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(AppTopBar),
            matching: find.byType(Container),
          )
          .first,
    );
    expect((header.decoration! as BoxDecoration).color, isNull);
    expect(header.color, isNull);
  });

  testWidgets('a page outside the shared screen lies on the same paper', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: LabelReadingScreen(
          shots: const [],
          bottles: 2,
          read: 1,
          onBack: () {},
        ),
      ),
    );
    final paper = find.byType(AppPaper);
    expect(paper, findsOneWidget);
    expect(
      tester
          .widget<Scaffold>(
            find.descendant(of: paper, matching: find.byType(Scaffold)),
          )
          .backgroundColor,
      Colors.transparent,
    );
  });

  testWidgets('the page colour is the paper\'s average, so a part painted '
      'in one colour matches it', (tester) async {
    final mean = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(
        File(AppPaper.asset).readAsBytesSync(),
      );
      final image = (await codec.getNextFrame()).image;
      // The tile as it is repeated: 759 px across.
      expect(image.width, 759);
      final bytes = (await image.toByteData())!.buffer.asUint8List();
      final sums = <int>[0, 0, 0];
      for (var i = 0; i < bytes.length; i += 4) {
        for (var c = 0; c < 3; c++) {
          sums[c] += bytes[i + c];
        }
      }
      return [for (final sum in sums) sum / (bytes.length / 4)];
    });
    const colour = AppColors.surfaceCanvas;
    final token = [colour.r * 255, colour.g * 255, colour.b * 255];
    for (var c = 0; c < 3; c++) {
      expect(mean![c], closeTo(token[c], 1), reason: 'channel $c');
    }
    expect(AppTheme.light.scaffoldBackgroundColor, AppColors.surfaceCanvas);
  });
}
