import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/widgets/app_term_tooltip.dart';

/// A home page that opens a second page whose middle word opens a balloon
/// with [text] and a "메모 수정" action.
Future<void> _pumpPageWithWord(
  WidgetTester tester, {
  required String text,
  VoidCallback? onAction,
}) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  body: Center(
                    child: Builder(
                      builder: (word) => TextButton(
                        onPressed: () => showTermTooltip(
                          word,
                          title: '남긴 메모',
                          text: text,
                          actionLabel: '메모 수정',
                          onAction: onAction ?? () {},
                        ),
                        child: const Text('단어'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            child: const Text('열기'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('단어'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a long text scrolls inside the balloon and its action stays '
      'on screen', (tester) async {
    var edits = 0;
    await _pumpPageWithWord(
      tester,
      text: '긴 메모 ' * 400,
      onAction: () => edits += 1,
    );

    expect(tester.takeException(), isNull);
    final action = find.byKey(const ValueKey<String>('term-tooltip-action'));
    final close = find.byKey(const ValueKey<String>('term-tooltip-close'));
    const screen = Rect.fromLTWH(0, 0, 360, 640);
    for (final part in <Finder>[action, close]) {
      final rect = tester.getRect(part);
      expect(screen.contains(rect.topLeft), isTrue);
      expect(screen.contains(rect.bottomRight - const Offset(1, 1)), isTrue);
    }
    expect(find.byType(Scrollable), findsWidgets);

    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(edits, 1);
    expect(find.byType(TermTooltipLayer), findsNothing);
  });

  testWidgets('back closes the balloon before the page under it', (
    tester,
  ) async {
    await _pumpPageWithWord(tester, text: '짧은 메모');
    expect(find.byType(TermTooltipLayer), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TermTooltipLayer), findsNothing);
    expect(find.text('단어'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('단어'), findsNothing);
    expect(find.text('열기'), findsOneWidget);
  });

  testWidgets('a balloon closed by its ✕ leaves back to the page', (
    tester,
  ) async {
    await _pumpPageWithWord(tester, text: '짧은 메모');

    await tester.tap(find.byKey(const ValueKey<String>('term-tooltip-close')));
    await tester.pumpAndSettle();
    expect(find.byType(TermTooltipLayer), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('열기'), findsOneWidget);
  });
}
