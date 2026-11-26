import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/core/async_shown.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/features/glossary/data/saved_terms.dart';
import 'package:soolgyul/src/features/glossary/data/saved_terms_provider.dart';
import 'package:soolgyul/src/features/glossary/data/supabase_saved_terms_gateway.dart';
import 'package:soolgyul/src/features/glossary/presentation/saved_terms_screen.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_wire_parser.dart';
import 'package:soolgyul/src/features/taste_fit/data/taste_fit_verdict.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/widgets/taste_fit_fact_chips.dart';

const _cherry = SavedTerm(
  key: 'aroma:cherry',
  label: '체리',
  kind: '향',
  drinks: <TermDrink>{TermDrink.common},
  description: '잘 익은 붉은 체리를 베어 물 때 나는 달콤하고 새콤한 과일 향이에요.',
);
const _pinot = SavedTerm(
  key: 'grape:pinot_noir',
  label: '피노 누아',
  kind: '품종',
  drinks: <TermDrink>{TermDrink.wine},
  description: '서늘한 기후에서 잘 자라는 껍질 얇은 검은 포도 품종이에요.',
);
const _sherry = SavedTerm(
  key: 'maturation:ex_sherry_cask',
  label: '셰리 캐스크',
  kind: '제조·숙성',
  drinks: <TermDrink>{TermDrink.whisky, TermDrink.wine},
  description: '스페인 셰리 와인을 담았던 오크통이에요.',
);

/// The dictionary the fake server explains keys by.
const _dictionary = <SavedTerm>[_cherry, _pinot, _sherry];

/// One member's saved terms, newest first, and what was asked.
class _Terms implements SavedTermsGateway {
  _Terms([List<SavedTerm> saved = const <SavedTerm>[]])
    : saved = <SavedTerm>[...saved];

  final List<SavedTerm> saved;
  final List<(String, bool)> asked = <(String, bool)>[];
  bool failWrite = false;
  int loads = 0;

  @override
  String? accountId = 'member';

  @override
  Future<List<SavedTerm>> load() async {
    loads++;
    return <SavedTerm>[...saved];
  }

  @override
  Future<List<SavedTerm>> setSaved(String key, {required bool saved}) async {
    asked.add((key, saved));
    if (failWrite) throw StateError('offline');
    this.saved.removeWhere((term) => term.key == key);
    if (saved) {
      this.saved.insert(0, _dictionary.firstWhere((term) => term.key == key));
    }
    return <SavedTerm>[...this.saved];
  }
}

Widget _app(Widget body, {SavedTermsGateway? gateway, bool scoped = true}) {
  final app = MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: Center(child: body)),
  );
  if (!scoped) return app;
  return ProviderScope(
    retry: (_, _) => null,
    overrides: [savedTermsGatewayProvider.overrideWithValue(gateway)],
    child: app,
  );
}

/// A fit page's chips for one grape the dictionary explains.
Widget _grapeChip({String? key = 'grape:pinot_noir'}) => TasteFitFactChips(
  facts: <TasteFitFact>[
    TasteFitFact(
      kind: 'grape',
      label: '피노 누아',
      description: _pinot.description,
      key: key,
    ),
  ],
);

final _save = find.byKey(const ValueKey<String>('term-tooltip-save'));

Future<void> _openHelp(WidgetTester tester) async {
  await tester.tap(find.text('피노 누아'));
  await tester.pumpAndSettle();
  expect(find.text(_pinot.description), findsOneWidget);
}

void main() {
  testWidgets('a help balloon saves its term and says where it is kept', (
    tester,
  ) async {
    final terms = _Terms();
    await tester.pumpWidget(_app(_grapeChip(), gateway: terms));
    await _openHelp(tester);

    expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(terms.asked, <(String, bool)>[('grape:pinot_noir', true)]);
    expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
    expect(find.textContaining('나의 용어 사전에 저장했어요.'), findsOneWidget);
    expect(find.textContaining('마이페이지에서 다시 볼 수 있어요.'), findsOneWidget);
    // The balloon stays open: the reader was reading it.
    expect(find.text(_pinot.description), findsOneWidget);

    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(terms.asked.last, ('grape:pinot_noir', false));
    expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
    expect(find.text('나의 용어 사전에서 뺐어요.'), findsOneWidget);
  });

  testWidgets('a term saved before opens with its save mark filled', (
    tester,
  ) async {
    final terms = _Terms(<SavedTerm>[_pinot]);
    await tester.pumpWidget(_app(_grapeChip(), gateway: terms));
    await _openHelp(tester);
    expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
    expect(terms.loads, 1);

    // The list is kept for the session: a second balloon asks nothing.
    await tester.tap(find.byKey(const ValueKey<String>('term-tooltip-close')));
    await tester.pumpAndSettle();
    await _openHelp(tester);
    expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
    expect(terms.loads, 1);
  });

  testWidgets(
    'a save the server refuses leaves the save mark empty and says so',
    (tester) async {
      final terms = _Terms()..failWrite = true;
      await tester.pumpWidget(_app(_grapeChip(), gateway: terms));
      await _openHelp(tester);
      await tester.tap(_save);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
      expect(find.textContaining('저장을 변경하지 못했어요.'), findsOneWidget);
    },
  );

  testWidgets('only a member is offered the save, and only for a term', (
    tester,
  ) async {
    // A visitor.
    await tester.pumpWidget(
      _app(_grapeChip(), gateway: _Terms()..accountId = null),
    );
    await _openHelp(tester);
    expect(_save, findsNothing);

    // An explanation that is not a dictionary term.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(_grapeChip(key: null), gateway: _Terms()));
    await _openHelp(tester);
    expect(_save, findsNothing);

    // A build without a server, and a screen shown outside the app.
    for (final scoped in <bool>[true, false]) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(_grapeChip(), scoped: scoped));
      await _openHelp(tester);
      expect(_save, findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('나의 용어 사전 lists the saved terms and filters them by drink', (
    tester,
  ) async {
    final terms = _Terms(<SavedTerm>[_sherry, _pinot, _cherry]);
    await tester.pumpWidget(_app(const SavedTermsScreen(), gateway: terms));
    await tester.pumpAndSettle();

    Future<void> filter(String wire) async {
      await tester.tap(
        find.byKey(ValueKey<String>('saved-terms-filter-$wire')),
      );
      await tester.pumpAndSettle();
    }

    List<String> shown() => <String>[
      for (final term in _dictionary)
        if (find
            .byKey(ValueKey<String>('saved-term-${term.key}'))
            .evaluate()
            .isNotEmpty)
          term.label,
    ];

    for (final label in <String>['전체', '공통', '와인', '위스키', '사케', '전통주']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('총 3개'), findsOneWidget);
    expect(shown(), <String>['체리', '피노 누아', '셰리 캐스크']);
    // Newest first, each with what it is filed under and its explanation.
    expect(
      tester.getTopLeft(find.text('셰리 캐스크')).dy,
      lessThan(tester.getTopLeft(find.text('피노 누아')).dy),
    );
    // Its drinks read in the filter's order, however they were listed.
    expect(find.text('제조·숙성 · 와인 · 위스키'), findsOneWidget);
    expect(find.text('향 · 공통'), findsOneWidget);
    expect(find.text(_cherry.description), findsOneWidget);

    await filter('common');
    expect(shown(), <String>['체리']);
    expect(find.text('총 1개'), findsOneWidget);
    await filter('wine');
    expect(shown(), <String>['피노 누아', '셰리 캐스크']);
    await filter('whisky');
    expect(shown(), <String>['셰리 캐스크']);
    await filter('sake');
    expect(shown(), isEmpty);
    expect(find.text('사케에 저장한 용어가 없어요.'), findsOneWidget);
    await filter('all');
    expect(shown().length, 3);
  });

  testWidgets('a term is taken out by its save mark and comes back on undo', (
    tester,
  ) async {
    final terms = _Terms(<SavedTerm>[_pinot, _cherry]);
    await tester.pumpWidget(_app(const SavedTermsScreen(), gateway: terms));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('saved-term-grape:pinot_noir')),
        matching: find.byIcon(Icons.bookmark_rounded),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('피노 누아'), findsNothing);
    expect(find.text('총 1개'), findsOneWidget);
    expect(find.text('나의 용어 사전에서 뺐어요.'), findsOneWidget);

    await tester.tap(find.text('실행 취소'));
    await tester.pumpAndSettle();
    expect(find.text('피노 누아'), findsOneWidget);
    expect(terms.asked, <(String, bool)>[
      ('grape:pinot_noir', false),
      ('grape:pinot_noir', true),
    ]);
  });

  testWidgets('an empty 용어 사전 says how to fill it, a failed one retries', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const SavedTermsScreen(), gateway: _Terms()));
    await tester.pumpAndSettle();
    expect(find.textContaining('저장한 용어가 아직 없어요.'), findsOneWidget);
    expect(find.text('총 0개'), findsOneWidget);

    final offline = _Offline();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(const SavedTermsScreen(), gateway: offline));
    await tester.pumpAndSettle();
    expect(find.text('나의 용어 사전을 불러오지 못했어요'), findsOneWidget);
    offline.down = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('체리'), findsOneWidget);
  });

  test('what another account saved is never shown to the next one', () async {
    final terms = _Terms(<SavedTerm>[_cherry]);
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [savedTermsGatewayProvider.overrideWithValue(terms)],
    );
    addTearDown(container.dispose);
    expect(
      (await container.read(savedTermsProvider.future)).single.key,
      'aroma:cherry',
    );

    // Signed out, then another member in: nothing of the first while loading.
    terms
      ..accountId = 'other'
      ..saved.clear();
    container.invalidate(savedTermsProvider, asReload: true);
    expect(shownValue(container.read(savedTermsProvider)), isNull);
    expect(await container.read(savedTermsProvider.future), isEmpty);
  });

  test('the saved-terms answer and the served keys are read', () {
    final terms = savedTermsFromResponse(<String, Object?>{
      'terms': <Object?>[
        <String, Object?>{
          'key': 'region:fr',
          'label': '프랑스',
          'kind': '산지',
          'categories': <String>['wine', 'whisky'],
          'description': '와인의 기준이 된 나라예요.',
          'saved_at': '2026-11-14T00:00:00Z',
        },
        <String, Object?>{
          'key': 'aroma:cherry',
          'label': '체리',
          'kind': '향',
          'categories': <String>['common', 'a drink this app does not know'],
          'description': '체리 향이에요.',
        },
        <String, Object?>{'key': 'aroma:broken'},
      ],
    });
    expect(terms.map((term) => term.key), <String>[
      'region:fr',
      'aroma:cherry',
    ]);
    expect(terms.first.drinks, <TermDrink>{TermDrink.wine, TermDrink.whisky});
    expect(terms.last.drinks, <TermDrink>{TermDrink.common});
    expect(
      () => savedTermsFromResponse(<String, Object?>{}),
      throwsFormatException,
    );

    Map<String, Object?> fact([String? key]) => <String, Object?>{
      'kind': 'grape',
      'label': '피노 누아',
      'description': '포도 품종이에요.',
      'key': ?key,
    };
    expect(
      TasteFitFact.fromJson(fact('grape:pinot_noir'))?.key,
      'grape:pinot_noir',
    );
    // A server from before the key: the fact is explained but not saved.
    expect(TasteFitFact.fromJson(fact())?.key, isNull);

    Map<String, Object?> pick([String? key]) => <String, Object?>{
      'country': null,
      'place': null,
      'keyword': '셰리 캐스크',
      'note': '진한 말린 과일 향이 나요',
      'term': <String, Object?>{
        'word': '셰리 캐스크',
        'label': '셰리 캐스크',
        'kind': '제조·숙성',
        'description': '셰리 와인을 담아 두었던 오크통이에요.',
        'key': ?key,
      },
    };
    String? servedKey(Map<String, Object?> pick) =>
        TasteCardWireParser.parseGuide(<String, Object?>{
          'head': '머리 문장',
          'picks': <Object?>[pick],
          'tip': null,
          'levels': <Object?>[],
          'directions': <Object?>[],
        }, 'guide').picks.single.term?.key;
    expect(
      servedKey(pick('maturation:ex_sherry_cask')),
      'maturation:ex_sherry_cask',
    );
    expect(servedKey(pick()), isNull);
  });

  test('a place is one term that holds each style saved under it', () {
    final place = savedTermsFromResponse(<String, Object?>{
      'terms': <Object?>[
        <String, Object?>{
          'key': 'region:ar_san_juan',
          'label': '산 후안',
          'kind': '산지',
          'categories': <String>['wine'],
          'description': '산지 소개예요.\n\n레드: 레드 설명이에요.',
          'intro': '산지 소개예요.',
          'own': false,
          'parts': <Object?>[
            <String, Object?>{
              'key': _red,
              'label': '레드',
              'description': '레드 설명이에요.',
            },
            <String, Object?>{'key': 'regional_style:broken'},
          ],
        },
      ],
    }).single;
    expect(place.intro, '산지 소개예요.');
    expect(place.parts.map((part) => part.label), <String>['레드']);
    // The red's balloon finds its save; the place's own and the white's do not.
    expect(place.holds(_red), isTrue);
    expect(place.holds(_white), isFalse);
    expect(place.holds('region:ar_san_juan'), isFalse);
    // A term that is no place is its own save.
    expect(_pinot.holds('grape:pinot_noir'), isTrue);
  });

  testWidgets(
    'a place shows its explanation and each saved style, taken out one by one or all at once',
    (tester) async {
      final terms = _Place();
      await tester.pumpWidget(_app(const SavedTermsScreen(), gateway: terms));
      await tester.pumpAndSettle();

      expect(find.text('총 1개'), findsOneWidget);
      expect(find.text('산 후안'), findsOneWidget);
      expect(find.text('산지 · 와인'), findsOneWidget);
      expect(find.text(_Place.intro), findsOneWidget);
      for (final text in <String>['화이트', '레드', '화이트 설명이에요.', '레드 설명이에요.']) {
        expect(find.text(text), findsOneWidget);
      }

      // One style goes; the place and its other style stay.
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<String>('saved-term-part-$_red')),
          matching: find.byIcon(Icons.bookmark_rounded),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('레드 설명이에요.'), findsNothing);
      expect(find.text('화이트 설명이에요.'), findsOneWidget);
      await tester.tap(find.text('실행 취소'));
      await tester.pumpAndSettle();
      expect(find.text('레드 설명이에요.'), findsOneWidget);
      expect(terms.asked, <(String, bool)>[(_red, false), (_red, true)]);

      // The place's own mark takes everything under it, and undo brings
      // each style back.
      terms.asked.clear();
      await tester.tap(
        find
            .descendant(
              of: find.byKey(
                const ValueKey<String>('saved-term-region:ar_san_juan'),
              ),
              matching: find.byIcon(Icons.bookmark_rounded),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('산 후안'), findsNothing);
      expect(terms.asked, <(String, bool)>[('region:ar_san_juan', false)]);
      await tester.tap(find.text('실행 취소'));
      await tester.pumpAndSettle();
      expect(find.text('산 후안'), findsOneWidget);
      expect(terms.keys, <String>{_red, _white});
    },
  );
}

const _red = 'regional_style:san_juan_red';
const _white = 'regional_style:ar_san_juan_white';

/// A member who saved a place's red and white, as the server lists them:
/// one term for the place, newest style first.
class _Place implements SavedTermsGateway {
  static const intro = '멘도사 북쪽의 덥고 건조한 산지예요.';

  final List<String> keys = <String>[_white, _red];
  final List<(String, bool)> asked = <(String, bool)>[];

  @override
  String? accountId = 'member';

  List<SavedTerm> _listed() => <SavedTerm>[
    if (keys.isNotEmpty)
      SavedTerm(
        key: 'region:ar_san_juan',
        label: '산 후안',
        kind: '산지',
        drinks: const <TermDrink>{TermDrink.wine},
        description: '',
        intro: intro,
        own: false,
        parts: <SavedStyle>[
          for (final key in keys)
            SavedStyle(
              key: key,
              label: key == _red ? '레드' : '화이트',
              description: key == _red ? '레드 설명이에요.' : '화이트 설명이에요.',
            ),
        ],
      ),
  ];

  @override
  Future<List<SavedTerm>> load() async => _listed();

  @override
  Future<List<SavedTerm>> setSaved(String key, {required bool saved}) async {
    asked.add((key, saved));
    if (key.startsWith('region:')) {
      keys.clear();
    } else {
      keys.remove(key);
      if (saved) keys.insert(0, key);
    }
    return _listed();
  }
}

/// Fails every read until it is brought back.
class _Offline extends _Terms {
  _Offline() : super(<SavedTerm>[_cherry]);
  bool down = true;

  @override
  Future<List<SavedTerm>> load() async {
    if (down) throw StateError('offline');
    return super.load();
  }
}
