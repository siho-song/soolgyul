import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/core/format/korean_wrap.dart';

const _j = wordJoiner;

void main() {
  test('letters of a word are joined; spaces and line ends stay', () {
    expect(keepWords('깔끔한 산미'), '깔$_j끔$_j한 산$_j미');
    expect(keepWords('찾아\n보세요'), '찾$_j아\n보$_j세$_j요');
    expect(keepWords('a  b'), 'a  b');
    expect(keepWords(''), '');
    // Taken out again, the joined text is the text as written.
    const sentence = '마음에 드는 와인을 찾아보세요.\n다음 잔도 기대돼요!';
    expect(keepWords(sentence).replaceAll(_j, ''), sentence);
  });

  test('a letter drawn from several code points stays one letter', () {
    // ㅎ + ㅏ + ㄴ as combining jamo, and a family emoji, each one grapheme.
    const jamo = '한';
    const family = '👨‍👩‍👧';
    expect(keepWords('$jamo$family'), '$jamo$_j$family');
  });

  test('a word that runs across styled pieces stays whole', () {
    final kept = keepSpanWords(
      const TextSpan(
        children: <InlineSpan>[
          TextSpan(text: '은은한 '),
          TextSpan(
            text: '산미',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: '가 남아요'),
        ],
      ),
    );
    final pieces = (kept as TextSpan).children!.cast<TextSpan>();
    expect(pieces.map((piece) => piece.text), <String>[
      '은$_j은$_j한 ',
      '산$_j미',
      '$_j가 남$_j아$_j요',
    ]);
    // Each changed piece reads aloud as written; the style is kept.
    expect(pieces.map((piece) => piece.semanticsLabel), <String>[
      '은은한 ',
      '산미',
      '가 남아요',
    ]);
    expect(pieces[1].style!.fontWeight, FontWeight.w700);
  });

  test('a word drawn as a widget is joined to the letters around it', () {
    final kept = keepSpanWords(
      const TextSpan(
        children: <InlineSpan>[
          TextSpan(text: '깊은'),
          WidgetSpan(child: SizedBox.shrink()),
          TextSpan(text: '이 좋아요'),
        ],
      ),
    );
    final pieces = (kept as TextSpan).children!;
    expect((pieces[0] as TextSpan).text, '깊$_j은$_j');
    expect(pieces[1], isA<WidgetSpan>());
    expect((pieces[2] as TextSpan).text, '$_j이 좋$_j아$_j요');
  });
}
