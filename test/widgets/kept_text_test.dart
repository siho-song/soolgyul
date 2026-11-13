import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/core/format/korean_wrap.dart';
import 'package:soolgyul/src/widgets/kept_text.dart';

const _sentence = '깔끔한 산미가 오래 남는 와인을 마음에 드는 곳에서 찾아보세요';
const _key = ValueKey<String>('kept');

Future<void> _pump(WidgetTester tester, Widget text, {double width = 100}) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: text),
          ),
        ),
      ),
    );

/// The drawn text, cut into its lines as laid out.
List<String> _lines(WidgetTester tester) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: find.byKey(_key), matching: find.byType(RichText)),
  );
  final drawn = paragraph.text.toPlainText();
  final lines = <StringBuffer>[];
  double? top;
  for (var i = 0; i < drawn.length; i++) {
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: i, extentOffset: i + 1),
    );
    if (boxes.isNotEmpty && boxes.first.top != top) {
      top = boxes.first.top;
      lines.add(StringBuffer());
    }
    lines.last.write(drawn[i]);
  }
  return <String>[
    for (final line in lines) line.toString().replaceAll(wordJoiner, ''),
  ];
}

void main() {
  testWidgets('a long sentence in a narrow box breaks only at spaces', (
    tester,
  ) async {
    await _pump(tester, const KeptText(_sentence, key: _key));
    final lines = _lines(tester);
    expect(lines.length, greaterThan(2));
    final words = _sentence.split(' ').toSet();
    for (final line in lines) {
      for (final word in line.trim().split(' ')) {
        expect(words, contains(word), reason: 'line "$line" cut a word');
      }
    }
    expect(lines.join(), _sentence);
    expect(tester.takeException(), isNull);

    // A plain Text in the same box ends a line inside a word.
    await _pump(tester, const Text(_sentence, key: _key));
    final plain = _lines(tester);
    expect(
      plain.any(
        (line) => line.trim().split(' ').any((word) => !words.contains(word)),
      ),
      isTrue,
    );
  });

  testWidgets('a word wider than the box still wraps inside the box', (
    tester,
  ) async {
    const word = '가나다라마바사아자차카타파하가나다라마바사아자차카타파하';
    await _pump(tester, const KeptText(word, key: _key), width: 100);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: find.byKey(_key), matching: find.byType(RichText)),
    );
    expect(_lines(tester).length, greaterThan(1));
    expect(paragraph.size.width, lessThanOrEqualTo(100));
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('finders and screen readers get the sentence as written', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, const KeptText(_sentence, key: _key));
    expect(find.text(_sentence), findsOneWidget);
    expect(find.textContaining('산미가'), findsOneWidget);
    expect(tester.getSemantics(find.byKey(_key)).label, _sentence);

    await _pump(
      tester,
      const KeptText.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(text: '은은한 '),
            TextSpan(
              text: '산미',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: '가 남아요'),
          ],
        ),
        key: _key,
      ),
    );
    expect(find.text('은은한 산미가 남아요'), findsOneWidget);
    expect(tester.getSemantics(find.byKey(_key)).label, '은은한 산미가 남아요');
    expect(
      tester.getSemantics(find.byKey(_key)).label.contains(wordJoiner),
      isFalse,
    );
    semantics.dispose();
  });
}
