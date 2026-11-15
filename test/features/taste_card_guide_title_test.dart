import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_snapshot_view_data.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_wire_parser.dart';
import 'package:soolgyul/src/features/taste_card/presentation/widgets/taste_card_guide_body.dart';
import 'package:soolgyul/src/widgets/level_gauge.dart';
import 'package:soolgyul/src/widgets/text_underline.dart';

TasteCardTermViewData _termOf(String label) => TasteCardTermViewData(
  word: label,
  label: label,
  kind: '라벨',
  description: '$label의 설명이에요.',
);

Future<void> _pumpBody(
  WidgetTester tester,
  TasteCardGuideViewData guide, {
  String category = '와인',
}) => tester.pumpWidget(
  MaterialApp(
    home: Material(
      child: SingleChildScrollView(
        child: TasteCardGuideBody(categoryLabel: category, guide: guide),
      ),
    ),
  ),
);

void main() {
  test('a wine guide of label words is titled 추천 라벨 표기', () {
    const grape = TasteCardGuidePickViewData(
      keyword: '바르베라',
      country: 'IT',
      place: '이탈리아 피에몬테',
    );
    const label = TasteCardGuidePickViewData(keyword: "'Saignée' 표기");
    expect(TasteCardGuideBody.picksTitle('와인', [grape]), '추천 품종 및 산지');
    expect(TasteCardGuideBody.picksTitle('와인', [label]), '라벨 추천 표기');
    expect(TasteCardGuideBody.picksTitle('와인', [grape, label]), '추천 품종 및 산지');
    expect(TasteCardGuideBody.picksTitle('위스키', [label]), '추천 캐스크 및 숙성 방식');
    expect(TasteCardGuideBody.picksTitle('사케', [label]), '라벨 추천 표기');
    expect(
      TasteCardGuideBody.picksTitle('사케', [
        const TasteCardGuidePickViewData(keyword: '준마이 긴조 · 준마이 다이긴조'),
      ]),
      '추천 등급',
    );
  });

  test('the chips get a line that says what to find on the label', () {
    const grape = TasteCardGuidePickViewData(
      keyword: '바르베라',
      country: 'IT',
      place: '이탈리아 피에몬테',
    );
    const label = TasteCardGuidePickViewData(keyword: "'Triple distilled' 표기");
    const cask = TasteCardGuidePickViewData(keyword: '셰리 캐스크(Sherry Cask)');
    const line = '병 라벨에서 이런 표기를 찾아보세요';
    expect(TasteCardGuideBody.picksDescription('위스키', [label]), line);
    expect(TasteCardGuideBody.picksDescription('위스키', [cask]), line);
    expect(TasteCardGuideBody.picksDescription('한국 전통주', [label]), line);
    expect(TasteCardGuideBody.picksDescription('와인', [label]), line);
    expect(
      TasteCardGuideBody.picksDescription('와인', [grape]),
      '병 라벨에서 이런 품종과 산지를 찾아보세요',
    );
    expect(
      TasteCardGuideBody.picksDescription('사케', [
        const TasteCardGuidePickViewData(keyword: '준마이 긴조 · 준마이 다이긴조'),
      ]),
      '병 라벨에서 이런 등급을 찾아보세요',
    );
  });

  testWidgets('a label word drops 표기 under the line that already says it', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: TasteCardGuideBody(
            categoryLabel: '위스키',
            guide: TasteCardGuideViewData(
              head: '머리 문장',
              picks: [
                TasteCardGuidePickViewData(
                  keyword: "'Corn Whiskey' 표기",
                  note: '옥수수의 단맛이 또렷해요.',
                ),
                TasteCardGuidePickViewData(keyword: '셰리 캐스크(Sherry Cask)'),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('병 라벨에서 이런 표기를 찾아보세요'), findsOneWidget);
    expect(find.text("'Corn Whiskey'"), findsOneWidget);
    expect(find.text("'Corn Whiskey' 표기"), findsNothing);
    expect(find.text('셰리 캐스크(Sherry Cask)'), findsOneWidget);
  });

  testWidgets(
    'a cask chip underlines its name and opens its explanation; the home does not',
    (tester) async {
      const term = TasteCardTermViewData(
        word: '셰리 캐스크(Sherry Cask)',
        label: '셰리 캐스크',
        kind: '제조·숙성',
        description: '셰리 와인을 담아 두었던 오크통에서 숙성하는 방식이에요.',
      );
      const guide = TasteCardGuideViewData(
        head: '머리 문장',
        picks: [
          TasteCardGuidePickViewData(
            keyword: '셰리 캐스크(Sherry Cask)',
            note: '셰리 와인이 깊게 밴 통에서 숙성돼요. 진한 말린 과일 향이 나요.',
            term: term,
          ),
        ],
      );
      Future<void> pump({required bool explain}) => tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: TasteCardGuideBody(
              categoryLabel: '위스키',
              guide: guide,
              explainPicks: explain,
            ),
          ),
        ),
      );
      const name = ValueKey<String>('taste-card-pick-term-셰리 캐스크(Sherry Cask)');

      await pump(explain: true);
      expect(
        find.descendant(
          of: find.byKey(name),
          matching: find.byType(TextUnderline),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(name));
      await tester.pumpAndSettle();
      expect(find.text(term.description), findsOneWidget);

      await pump(explain: false);
      await tester.pumpAndSettle();
      expect(find.byKey(name), findsNothing);
      expect(find.byType(TextUnderline), findsNothing);
    },
  );

  test('chips that carry their words are titled without a trailing 표기', () {
    const grape = TasteCardGuidePickViewData(
      keyword: 'Barbera(바르베라)',
      words: [TasteCardGuideWordViewData(text: 'Barbera(바르베라)')],
      country: 'it',
      place: '이탈리아 피에몬테',
    );
    const label = TasteCardGuidePickViewData(
      keyword: 'dry(드라이) · trocken(트로켄)',
      words: [
        TasteCardGuideWordViewData(text: 'dry(드라이)'),
        TasteCardGuideWordViewData(text: 'trocken(트로켄)'),
      ],
    );
    expect(TasteCardGuideBody.picksTitle('와인', [grape]), '추천 품종 및 산지');
    expect(TasteCardGuideBody.picksTitle('와인', [grape, label]), '추천 품종 및 산지');
    expect(TasteCardGuideBody.picksTitle('와인', [label]), '라벨 추천 표기');
    expect(
      TasteCardGuideBody.picksDescription('와인', [label]),
      TasteCardGuideBody.labelWordsDescription,
    );
  });

  test('a chip that says what it is decides the title, flag or no flag', () {
    const grade = TasteCardGuidePickViewData(
      keyword: '純米吟醸(준마이 긴조)',
      words: [TasteCardGuideWordViewData(text: '純米吟醸(준마이 긴조)')],
      labelWord: false,
    );
    const method = TasteCardGuidePickViewData(
      keyword: '山廃(야마하이)',
      words: [TasteCardGuideWordViewData(text: '山廃(야마하이)')],
      labelWord: true,
    );
    const grape = TasteCardGuidePickViewData(
      keyword: 'Merlot(메를로)',
      words: [TasteCardGuideWordViewData(text: 'Merlot(메를로)')],
      labelWord: false,
    );
    expect(TasteCardGuideBody.picksTitle('사케', [grade]), '추천 등급');
    expect(TasteCardGuideBody.picksTitle('사케', [grade, method]), '추천 등급');
    expect(TasteCardGuideBody.picksTitle('사케', [method]), '라벨 추천 표기');
    // A grape named without its region is still a grape.
    expect(TasteCardGuideBody.picksTitle('와인', [grape]), '추천 품종 및 산지');
  });

  testWidgets('each word of a chip is underlined and opens its own balloon', (
    tester,
  ) async {
    await _pumpBody(
      tester,
      TasteCardGuideViewData(
        head: '머리 문장',
        picks: [
          TasteCardGuidePickViewData(
            keyword: 'dry(드라이) · trocken(트로켄) · sec(세크)',
            words: [
              TasteCardGuideWordViewData(
                text: 'dry(드라이)',
                term: _termOf('드라이'),
              ),
              TasteCardGuideWordViewData(
                text: 'trocken(트로켄)',
                term: _termOf('트로켄'),
              ),
              const TasteCardGuideWordViewData(text: 'sec(세크)'),
            ],
            note: '좋아하신 깔끔한 맛이 담겨요.',
          ),
          TasteCardGuidePickViewData(
            country: 'us',
            place: '미국 워싱턴',
            keyword: 'Merlot(메를로)',
            words: [
              TasteCardGuideWordViewData(
                text: 'Merlot(메를로)',
                term: _termOf('메를로'),
              ),
            ],
          ),
        ],
      ),
    );

    // Two of the three words and the grape on its ticket are explained.
    expect(find.byType(TextUnderline), findsNWidgets(3));
    expect(find.text('sec(세크)'), findsOneWidget);
    for (final (word, label) in [
      ('dry(드라이)', '드라이'),
      ('trocken(트로켄)', '트로켄'),
      ('Merlot(메를로)', '메를로'),
    ]) {
      await tester.tap(
        find.byKey(ValueKey<String>('taste-card-pick-term-$word')),
      );
      await tester.pumpAndSettle();
      expect(find.text('$label의 설명이에요.'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('term-tooltip-close')),
      );
      await tester.pumpAndSettle();
    }
  });

  testWidgets('a mark is said in a word, and its name opens its explanation', (
    tester,
  ) async {
    await _pumpBody(
      tester,
      TasteCardGuideViewData(
        head: '머리 문장',
        levels: [
          TasteCardGuideLevelViewData(
            label: '당도',
            mark: 1,
            range: '1~2',
            word: '드라이',
            term: _termOf('당도'),
          ),
          const TasteCardGuideLevelViewData(
            label: '바디',
            mark: 3,
            range: '3',
            word: '미디엄 바디',
          ),
          const TasteCardGuideLevelViewData(
            label: '도수',
            mark: 3,
            range: '13% 안팎',
          ),
        ],
      ),
    );

    expect(find.text('취향 맛 밸런스'), findsOneWidget);
    expect(find.byType(LevelGauge), findsNWidgets(3));
    // The word stands where the steps were; a range that says more stays.
    expect(find.textContaining('드라이', findRichText: true), findsOneWidget);
    expect(find.textContaining('미디엄 바디', findRichText: true), findsOneWidget);
    expect(find.textContaining('1~2', findRichText: true), findsNothing);
    expect(find.textContaining('13% 안팎', findRichText: true), findsOneWidget);
    expect(find.text('낮음'), findsNothing);

    const name = ValueKey<String>('level-gauge-explain-당도');
    expect(
      find.descendant(
        of: find.byKey(name),
        matching: find.byType(TextUnderline),
      ),
      findsOneWidget,
    );
    expect(find.byType(TextUnderline), findsOneWidget);
    await tester.tap(find.byKey(name));
    await tester.pumpAndSettle();
    expect(find.text('당도의 설명이에요.'), findsOneWidget);
  });

  testWidgets('a whisky is said in words over its one 도수 mark', (tester) async {
    await _pumpBody(
      tester,
      const TasteCardGuideViewData(
        head: '머리 문장',
        levels: [
          TasteCardGuideLevelViewData(label: '도수', mark: 2, range: '40~43%'),
        ],
        profile: [
          TasteCardGuideProfileLineViewData(
            label: 'AROMA',
            words: ['바닐라', '꿀'],
          ),
          TasteCardGuideProfileLineViewData(label: 'FLAVOR', words: ['토피']),
          TasteCardGuideProfileLineViewData(label: 'FINISH', words: ['긴 여운']),
        ],
      ),
      category: '위스키',
    );

    expect(find.text(TasteCardGuideBody.profileTitle), findsOneWidget);
    expect(find.text('바닐라 · 꿀'), findsOneWidget);
    expect(find.text('추천 도수'), findsOneWidget);
    expect(find.text('40~43%'), findsOneWidget);
    final lines = [
      for (final label in ['AROMA', 'FLAVOR', 'FINISH', '추천 도수'])
        tester.getTopLeft(find.text(label)).dy,
    ];
    expect(lines, orderedEquals([...lines]..sort()));
  });

  testWidgets('what follows a chip\'s words is drawn after them, plain', (
    tester,
  ) async {
    TasteCardGuidePickViewData without(String word, {String? note}) =>
        TasteCardGuidePickViewData(
          keyword: '$word 없는 것',
          words: [TasteCardGuideWordViewData(text: word, term: _termOf(word))],
          labelWord: true,
          note: note,
        );
    final noted = without('Peated(피트 처리 맥아)', note: '이유 문장이에요.');
    final ticket = without('Port Cask(포트 캐스크)');
    expect(noted.trail, ' 없는 것');
    // A card stored before the words has nothing after them.
    expect(
      const TasteCardGuidePickViewData(keyword: "'Peated' 표기가 없는 것").trail,
      isNull,
    );

    await _pumpBody(
      tester,
      TasteCardGuideViewData(head: '머리 문장', picks: [noted, ticket]),
      category: '위스키',
    );
    // Only the word is underlined; 없는 것 stands beside it on both chips.
    expect(find.byType(TextUnderline), findsNWidgets(2));
    expect(find.text(' 없는 것'), findsNWidgets(2));
    for (final word in ['Peated(피트 처리 맥아)', 'Port Cask(포트 캐스크)']) {
      final wordBox = tester.getRect(find.text(word));
      final trail = find
          .text(' 없는 것')
          .evaluate()
          .map((element) => tester.getRect(find.byWidget(element.widget)));
      expect(
        trail.any(
          (rect) =>
              rect.left >= wordBox.right - 1 &&
              (rect.center.dy - wordBox.center.dy).abs() < 2,
        ),
        isTrue,
        reason: word,
      );
    }
  });

  testWidgets('marks whose ranges are all words draw as worded rows', (
    tester,
  ) async {
    await _pumpBody(
      tester,
      const TasteCardGuideViewData(
        head: '머리 문장',
        levels: [
          TasteCardGuideLevelViewData(
            label: '당도(주도)',
            mark: 4,
            range: '살짝 단 아마구치 (-1.5~-3.4)',
          ),
          TasteCardGuideLevelViewData(
            label: '산미(산도)',
            mark: 3,
            range: '1.4~1.6',
          ),
        ],
      ),
      category: '사케',
    );
    // No word was sent, yet neither range is bare steps: the row shows the
    // range in full and the old 낮음·높음 ends are not drawn.
    expect(
      find.textContaining('살짝 단 아마구치 (-1.5~-3.4)', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('1.4~1.6', findRichText: true), findsOneWidget);
    expect(find.text('낮음'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a card stored before draws as it did, without its directions', (
    tester,
  ) async {
    final stored = TasteCardWireParser.parseGuide({
      'head': '머리 문장',
      'picks': [
        {
          'country': 'it',
          'place': '이탈리아 피에몬테',
          'keyword': '바르베라',
          'note': null,
        },
      ],
      'tip': '와인 라벨에서 이 특징을 찾아보세요!',
      'levels': [
        {'label': '당도', 'mark': 1, 'range': '1~2'},
      ],
      'directions': [
        {'word': '체리 향', 'change': 'keep'},
        {'word': '떫은맛', 'change': 'lower'},
      ],
    }, 'guide');
    await _pumpBody(tester, stored);

    expect(find.text('체리 향'), findsNothing);
    expect(find.text('떫은맛'), findsNothing);
    expect(find.text('바르베라'), findsOneWidget);
    expect(find.text('낮음'), findsOneWidget);
    expect(find.text('1~2'), findsOneWidget);
    expect(find.text('와인 라벨에서 이 특징을 찾아보세요!'), findsOneWidget);
  });

  test('the words, the mark\'s word and the profile are read when sent', () {
    Map<String, Object?> term(String label) => {
      'key': 'label:$label',
      'word': label,
      'label': label,
      'kind': '라벨',
      'description': '$label의 설명이에요.',
    };
    final guide = TasteCardWireParser.parseGuide({
      'head': '머리 문장',
      'picks': [
        {
          'country': null,
          'place': null,
          'keyword': 'dry(드라이) · trocken(트로켄)',
          'words': [
            {'text': 'dry(드라이)', 'term': term('드라이')},
            {'text': 'trocken(트로켄)', 'term': null},
            {'text': 'sec(세크)'},
          ],
          'labelWord': true,
          'note': '좋아하신 깔끔한 맛이 담겨요.',
          'term': term('드라이'),
        },
      ],
      'tip': '매장에서 이 화면을 보여주세요.',
      'levels': [
        {
          'label': '당도',
          'mark': 1,
          'range': '1~2',
          'word': '드라이',
          'term': term('당도'),
        },
        {'label': '도수', 'mark': 3, 'range': '13% 안팎', 'word': null},
      ],
      'directions': <Object?>[],
      'profile': [
        {
          'label': 'AROMA',
          'words': ['바닐라', '꿀'],
        },
        {'label': 'FLAVOR', 'words': <Object?>[]},
      ],
    }, 'guide');

    final pick = guide.picks.single;
    expect(pick.shownWords.map((word) => word.text), [
      'dry(드라이)',
      'trocken(트로켄)',
      'sec(세크)',
    ]);
    expect(pick.words.map((word) => word.term?.key), ['label:드라이', null, null]);
    expect(pick.labelWord, isTrue);
    expect(guide.levels.map((level) => level.word), ['드라이', null]);
    expect(guide.levels.first.term?.label, '당도');
    // A line with no word is left out.
    expect(guide.profile.single.label, 'AROMA');
    expect(guide.profile.single.words, ['바닐라', '꿀']);

    // A card stored before any of them, and one without 'directions'.
    final stored = TasteCardWireParser.parseGuide({
      'head': '머리 문장',
      'picks': [
        {'country': null, 'place': null, 'keyword': '바르베라', 'note': null},
      ],
      'tip': null,
      'levels': [
        {'label': '당도', 'mark': 1, 'range': '1~2'},
      ],
      'profile': null,
    }, 'guide');
    expect(stored.picks.single.words, isEmpty);
    expect(stored.picks.single.labelWord, isNull);
    expect(stored.picks.single.shownWords.single.text, '바르베라');
    expect(stored.levels.single.word, isNull);
    expect(stored.profile, isEmpty);
  });

  test('a served chip carries its explanation; a stored one has none', () {
    Map<String, Object?> guideWith(Map<String, Object?> pick) => {
      'head': '머리 문장',
      'picks': [pick],
      'tip': null,
      'levels': <Object?>[],
      'directions': <Object?>[],
    };
    const base = <String, Object?>{
      'country': null,
      'place': null,
      'keyword': '셰리 캐스크(Sherry Cask)',
      'note': '진한 말린 과일 향이 나요',
    };
    final served = TasteCardWireParser.parseGuide(
      guideWith({
        ...base,
        'term': {
          'word': '셰리 캐스크(Sherry Cask)',
          'label': '셰리 캐스크',
          'kind': '제조·숙성',
          'description': '셰리 와인을 담아 두었던 오크통이에요.',
        },
      }),
      'guide',
    );
    expect(served.picks.single.term?.label, '셰리 캐스크');
    final grape = TasteCardWireParser.parseGuide(
      guideWith({...base, 'term': null}),
      'guide',
    );
    expect(grape.picks.single.term, isNull);
    final stored = TasteCardWireParser.parseGuide(guideWith(base), 'guide');
    expect(stored.picks.single.term, isNull);
  });
}
