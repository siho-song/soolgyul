import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/features/home/data/taste_letters.dart';
import 'package:soolgyul/src/features/home/presentation/first_record_invite_slide.dart';
import 'package:soolgyul/src/features/home/presentation/home_screens.dart';
import 'package:soolgyul/src/widgets/app_page_indicator.dart';

import '../support/provider_harness.dart';

/// Letters that arrive when the test says so.
class _Letters implements TasteLettersGateway {
  final _answer = Completer<TasteLettersSnapshot>();

  @override
  Future<TasteLettersSnapshot> load() => _answer.future;

  void arrive({required int records, bool row = true}) => _answer.complete(
    row
        ? TasteLettersSnapshot(
            state: TasteLettersState(axes: const {}, recordCount: records),
          )
        : const TasteLettersSnapshot(),
  );

  void fail() => _answer.completeError(StateError('no network'));
}

const _invite = ValueKey<String>('first-record-invite');
const _slides = ValueKey<String>('first-record-invite-slides');
const _start = ValueKey<String>('first-record-invite-start');

/// One frame of the test clock.
const _tick = Duration(milliseconds: 16);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size viewport = const Size(411, 891),
  bool reducedMotion = false,
  double textScale = 1,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, page) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reducedMotion,
          textScaler: TextScaler.linear(textScale),
        ),
        child: page!,
      ),
      home: Scaffold(body: child),
    ),
  );
}

/// The home of a member whose letters are still on their way.
Future<({_Letters letters, List<String> taps})> _pumpHome(
  WidgetTester tester,
) async {
  final letters = _Letters();
  final taps = <String>[];
  await _pump(
    tester,
    withProviders(
      letters: letters,
      child: HomeScreen(
        onOpenSoolgyulLetters: () => taps.add('letters'),
        onOpenTasteFit: () => taps.add('fit'),
        onStartRecord: () => taps.add('record'),
      ),
    ),
  );
  await tester.pump();
  return (letters: letters, taps: taps);
}

Future<List<String>> _pumpInvite(
  WidgetTester tester, {
  Size viewport = const Size(411, 891),
  bool reducedMotion = false,
  double textScale = 1,
}) async {
  final taps = <String>[];
  await _pump(
    tester,
    SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: FirstRecordInvite(onStart: () => taps.add('record')),
    ),
    viewport: viewport,
    reducedMotion: reducedMotion,
    textScale: textScale,
  );
  return taps;
}

int _shownSlide(WidgetTester tester) =>
    tester.widget<AppPageIndicator>(find.byType(AppPageIndicator)).activeIndex;

/// How far row [row] of slide [slide] has come in: 0 unseen, 1 landed.
double _row(WidgetTester tester, int slide, int row) => tester
    .widget<FadeTransition>(
      find.descendant(
        of: find.byKey(ValueKey<String>('first-record-invite-row-$slide-$row')),
        matching: find.byType(FadeTransition),
      ),
    )
    .opacity
    .value;

List<double> _rows(WidgetTester tester, int slide) => <double>[
  for (var row = 0; row < 3; row++) _row(tester, slide, row),
];

double _picture(WidgetTester tester, int slide) => tester
    .widget<FadeTransition>(
      find.byKey(ValueKey<String>('first-record-invite-picture-$slide')),
    )
    .opacity
    .value;

/// How far the check of row [row] of slide [slide] has popped in.
double _check(WidgetTester tester, int slide, int row) => tester
    .widget<ScaleTransition>(
      find.descendant(
        of: find.byKey(ValueKey<String>('first-record-invite-row-$slide-$row')),
        matching: find.byType(ScaleTransition),
      ),
    )
    .scale
    .value;

void _expectBoxes(Matcher matcher) {
  expect(find.text('고민 중인 술이 있나요?'), matcher);
  expect(find.byType(TasteFitSearchEntry), matcher);
  expect(find.byType(SoolgyulLettersCard), matcher);
}

void main() {
  group('the home of a member', () {
    testWidgets('without a record shows the invite in place of its boxes', (
      tester,
    ) async {
      final home = await _pumpHome(tester);

      // Still loading: the home as it is, and no invite.
      expect(find.byKey(_invite), findsNothing);
      _expectBoxes(findsOneWidget);

      home.letters.arrive(records: 0);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<String>('home-logo')), findsOneWidget);
      expect(find.text('홈'), findsNothing);
      expect(find.byKey(_invite), findsOneWidget);
      _expectBoxes(findsNothing);
      expect(find.text('나의 취향 조각'), findsNothing);
      expect(find.text('한 잔이면 내 취향이 보여요'), findsOneWidget);
      expect(find.text('라벨만 찍으면 나와 맞는지 알려드려요'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('who has no letters row yet is shown the invite too', (
      tester,
    ) async {
      final home = await _pumpHome(tester);
      home.letters.arrive(records: 0, row: false);
      await tester.pumpAndSettle();

      expect(find.byKey(_invite), findsOneWidget);
      _expectBoxes(findsNothing);
    });

    testWidgets('with a record keeps its boxes', (tester) async {
      final home = await _pumpHome(tester);
      home.letters.arrive(records: 1);
      await tester.pumpAndSettle();

      expect(find.byKey(_invite), findsNothing);
      _expectBoxes(findsOneWidget);
    });

    testWidgets('whose letters failed to load keeps its boxes', (tester) async {
      final home = await _pumpHome(tester);
      home.letters.fail();
      await tester.pumpAndSettle();

      expect(find.byKey(_invite), findsNothing);
      _expectBoxes(findsOneWidget);
      expect(find.text('취향 조각을 불러오지 못했어요.'), findsOneWidget);
    });

    testWidgets('starts a record from the invite\'s button', (tester) async {
      final home = await _pumpHome(tester);
      home.letters.arrive(records: 0);
      await tester.pumpAndSettle();

      expect(find.text('첫 한 잔 기록하기'), findsOneWidget);
      await tester.ensureVisible(find.byKey(_start));
      await tester.tap(find.byKey(_start));
      await tester.pumpAndSettle();

      expect(home.taps, <String>['record']);
    });
  });

  group('the invite', () {
    testWidgets('brings the picture, then the rows one after another, each '
        'with its check', (tester) async {
      const fade = FirstRecordInviteTimeline.pictureFade;
      const lands = FirstRecordInviteTimeline.rowLands;
      const every = FirstRecordInviteTimeline.rowEvery;
      await _pumpInvite(tester);
      expect(_picture(tester, 0), 0);
      expect(_rows(tester, 0), <double>[0, 0, 0]);

      // The picture is coming in: no row yet.
      await tester.pump(fade * 0.5);
      expect(_picture(tester, 0), inExclusiveRange(0, 1));
      expect(_rows(tester, 0), <double>[0, 0, 0]);

      // The first row has landed and its check is on its way.
      await tester.pump(fade * 0.5 + lands + _tick);
      expect(_picture(tester, 0), 1);
      expect(_rows(tester, 0), <double>[1, 0, 0]);
      expect(_check(tester, 0, 0), lessThan(0.5));

      await tester.pump(every);
      expect(_rows(tester, 0), <double>[1, 1, 0]);
      expect(_check(tester, 0, 0), 1);
      expect(_check(tester, 0, 1), lessThan(0.5));

      await tester.pump(every);
      expect(_rows(tester, 0), <double>[1, 1, 1]);
      expect(_check(tester, 0, 2), lessThan(0.5));

      await tester.pump(FirstRecordInviteTimeline.checkPops);
      expect(_check(tester, 0, 2), 1);
      // Nothing more to draw: the slide rests on a timer.
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('rests, moves on to the label slide by itself, scans it '
        'before its rows, and comes back', (tester) async {
      await _pumpInvite(tester);
      await tester.pumpAndSettle();
      expect(_shownSlide(tester), 0);

      // Just short of the rest it has not moved.
      await tester.pump(FirstRecordInvite.rest - _tick);
      expect(_shownSlide(tester), 0);
      await tester.pump(_tick);
      expect(_shownSlide(tester), 1);
      expect(_rows(tester, 1), <double>[0, 0, 0]);

      // The picture is in and the scan line is on its way: no row yet.
      await tester.pump(
        FirstRecordInviteTimeline.pictureFade +
            FirstRecordInviteTimeline.scan * 0.5,
      );
      expect(_picture(tester, 1), 1);
      expect(_rows(tester, 1), <double>[0, 0, 0]);

      await tester.pump(
        FirstRecordInviteTimeline.scan * 0.5 +
            FirstRecordInviteTimeline.rowLands +
            _tick,
      );
      expect(_rows(tester, 1), <double>[1, 0, 0]);

      await tester.pumpAndSettle();
      expect(_rows(tester, 1), <double>[1, 1, 1]);
      // The slide it left stays whole.
      expect(_rows(tester, 0), <double>[1, 1, 1]);

      await tester.pump(FirstRecordInvite.rest);
      expect(_shownSlide(tester), 0);
      expect(_rows(tester, 0), <double>[0, 0, 0]);
      await tester.pumpAndSettle();
      expect(_rows(tester, 0), <double>[1, 1, 1]);
    });

    testWidgets('a swipe brings the other slide and plays it from its start', (
      tester,
    ) async {
      await _pumpInvite(tester);
      await tester.pumpAndSettle();

      await tester.drag(find.byKey(_slides), const Offset(-300, 0));
      await tester.pump();
      expect(_shownSlide(tester), 1);
      expect(_rows(tester, 1), <double>[0, 0, 0]);
      await tester.pumpAndSettle();
      expect(_rows(tester, 1), <double>[1, 1, 1]);

      await tester.drag(find.byKey(_slides), const Offset(300, 0));
      await tester.pump();
      expect(_shownSlide(tester), 0);
      expect(_rows(tester, 0), <double>[0, 0, 0]);
      await tester.pumpAndSettle();
      expect(_rows(tester, 0), <double>[1, 1, 1]);

      // A swipe too short to turn it plays the same slide again.
      await tester.drag(find.byKey(_slides), const Offset(-60, 0));
      await tester.pump();
      expect(_shownSlide(tester), 0);
      expect(_rows(tester, 0), <double>[0, 0, 0]);
      await tester.pumpAndSettle();
      expect(_shownSlide(tester), 0);
    });

    testWidgets('with reduced motion shows every slide whole and stays', (
      tester,
    ) async {
      await _pumpInvite(tester, reducedMotion: true);

      expect(_picture(tester, 0), 1);
      expect(_rows(tester, 0), <double>[1, 1, 1]);
      expect(_check(tester, 0, 2), 1);
      expect(_rows(tester, 1), <double>[1, 1, 1]);
      // Nothing moves: no frame is asked for after the first.
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);

      await tester.pump(FirstRecordInvite.rest * 4);
      expect(_shownSlide(tester), 0);

      // It still turns under the finger, and stays there.
      await tester.drag(find.byKey(_slides), const Offset(-300, 0));
      await tester.pump();
      expect(_shownSlide(tester), 1);
      expect(_rows(tester, 1), <double>[1, 1, 1]);
      await tester.pump(FirstRecordInvite.rest * 4);
      expect(_shownSlide(tester), 1);
    });

    testWidgets('the button starts the record', (tester) async {
      final taps = await _pumpInvite(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_start));
      await tester.pump();

      expect(taps, <String>['record']);
    });

    testWidgets('fits a narrow phone and large letters', (tester) async {
      for (final (viewport, textScale) in const <(Size, double)>[
        (Size(360, 640), 1.0),
        (Size(360, 640), 1.6),
        (Size(320, 568), 2.0),
      ]) {
        await _pumpInvite(tester, viewport: viewport, textScale: textScale);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$viewport $textScale');
        // Seen through the second slide too.
        await tester.pump(FirstRecordInvite.rest);
        await tester.pumpAndSettle();
        expect(_shownSlide(tester), 1);
        expect(tester.takeException(), isNull, reason: '$viewport $textScale');
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('leaves no timer behind when it goes', (tester) async {
      await _pumpInvite(tester);
      await tester.pumpAndSettle();

      // Gone while it rests: the test fails if its timer were still pending.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(FirstRecordInvite.rest * 2);
      expect(tester.takeException(), isNull);
    });
  });
}
