import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/features/home/data/taste_letters.dart';
import 'package:soolgyul/src/features/home/presentation/home_screens.dart';
import 'package:soolgyul/src/features/home/presentation/soolgyul_letters_detail_sections.dart';
import '../support/provider_harness.dart';

class FakeTasteLettersGateway implements TasteLettersGateway {
  FakeTasteLettersGateway(this.snapshot);
  final TasteLettersSnapshot snapshot;
  final completer = Completer<TasteLettersSnapshot>();

  @override
  Future<TasteLettersSnapshot> load() => completer.future;

  void finish() => completer.complete(snapshot);
}

class FailingTasteLettersGateway implements TasteLettersGateway {
  @override
  Future<TasteLettersSnapshot> load() async => throw StateError('no network');
}

TasteLetterAxisState axis(String? letter, int left, int right, int votes) =>
    TasteLetterAxisState(
      letter: letter,
      leftShare: left,
      rightShare: right,
      voteCount: votes,
    );

final sampleState = TasteLettersState(
  axes: {
    TasteLetterAxis.aroma: axis('F', 75, 25, 4),
    TasteLetterAxis.sweetness: axis('D', 63, 37, 4),
    TasteLetterAxis.weight: axis(null, 0, 0, 0),
    TasteLetterAxis.finish: axis('C', 50, 50, 2),
  },
  recordCount: 4,
);

/// No row yet: every slot closed.
final emptyState = TasteLettersState.fromRow(const {'record_count': 0});

final sampleChanges = <TasteLetterChange>[
  TasteLetterChange(
    axis: TasteLetterAxis.sweetness,
    toLetter: 'D',
    productName: '글렌피딕 12년',
    changedAt: DateTime(2026, 10, 2),
  ),
  TasteLetterChange(
    axis: TasteLetterAxis.aroma,
    fromLetter: 'R',
    toLetter: 'F',
    leftShare: 75,
    rightShare: 25,
    productName: '모스카토 다스티',
    changedAt: DateTime(2026, 10, 20),
  ),
];

Future<void> pumpPage(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(411, 891);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: page),
    ),
  );
  await tester.pump();
}

Finder tile(String letter) => find.descendant(
  of: find.byType(SoolgyulLetterStrip),
  matching: find.text(letter),
);

void main() {
  group('HomeScreen with taste letters', () {
    testWidgets('shows loading, then the four tiles and the summary', (
      tester,
    ) async {
      final gateway = FakeTasteLettersGateway(
        TasteLettersSnapshot(state: sampleState),
      );
      await pumpPage(
        tester,
        withProviders(
          letters: gateway,
          child: HomeScreen(
            onOpenSoolgyulLetters: () {},
            onOpenCard: (_) {},
            onOpenTasteFit: () {},
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(tile('?'), findsNWidgets(4));

      gateway.finish();
      await tester.pumpAndSettle();

      expect(tile('산'), findsOneWidget);
      expect(tile('드'), findsOneWidget);
      expect(tile('?'), findsOneWidget);
      expect(tile('깔'), findsOneWidget);
      expect(tile('F'), findsNothing);
      for (final caption in ['향', '단맛', '무게', '여운']) {
        expect(tile(caption), findsOneWidget);
      }
      // The wording itself is pinned in taste_letters_test.
      expect(find.text(sampleState.overviewStatement), findsOneWidget);
      expect(find.text('부드럽게 넘어가고 은은한 여운이 남는 술이 잘 맞아요.'), findsNothing);
    });

    testWidgets('shows the empty line when the user has no row', (
      tester,
    ) async {
      final gateway = FakeTasteLettersGateway(const TasteLettersSnapshot());
      await pumpPage(
        tester,
        withProviders(
          letters: gateway,
          child: SoolgyulLettersCard(onOpen: () {}),
        ),
      );
      gateway.finish();
      await tester.pumpAndSettle();

      expect(tile('?'), findsNWidgets(4));
      expect(find.text(emptyState.overviewStatement), findsOneWidget);
    });

    testWidgets('shows the error line when loading fails', (tester) async {
      await pumpPage(
        tester,
        withProviders(
          letters: FailingTasteLettersGateway(),
          child: SoolgyulLettersCard(onOpen: () {}),
        ),
      );
      await tester.pumpAndSettle();

      expect(tile('?'), findsNWidgets(4));
      expect(find.text('취향 조각을 불러오지 못했어요.'), findsOneWidget);
    });
  });

  group('SoolgyulLettersDetailScreen with taste letters', () {
    testWidgets('renders overview, pieces, hidden axes and changes', (
      tester,
    ) async {
      final gateway = FakeTasteLettersGateway(
        TasteLettersSnapshot(state: sampleState, changes: sampleChanges),
      );
      await pumpPage(
        tester,
        withProviders(letters: gateway, child: SoolgyulLettersDetailScreen()),
      );
      gateway.finish();
      await tester.pumpAndSettle();

      expect(find.text('나의 취향 조각'), findsOneWidget);
      expect(find.textContaining('기록 4건', findRichText: true), findsNothing);
      expect(
        find.textContaining('산뜻한 향이 감돌고', findRichText: true),
        findsOneWidget,
      );

      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('취향의 변화'),
        200,
        scrollable: scrollable,
      );
      expect(find.text('산뜻한 향'), findsOneWidget);
      expect(find.text('드라이'), findsOneWidget);
      expect(find.text('깔끔한 여운'), findsOneWidget);
      expect(find.text('기록이 쌓이며 선명해진 나만의 입맛 기준이에요.'), findsOneWidget);
      expect(find.text('산뜻함 (Fresh) 75%'), findsOneWidget);
      expect(find.text('풍부함 (Rich) 25%'), findsOneWidget);
      expect(find.text('드라이 (Dry) 63%'), findsOneWidget);
      expect(find.text('달콤함 (Sweet) 37%'), findsOneWidget);
      expect(find.text('깔끔함 (Clean) 50%'), findsOneWidget);
      expect(find.text('긴 여운 (Persistent) 50%'), findsOneWidget);
      expect(find.byType(TasteLetterShareGauge), findsNWidgets(3));
      expect(find.text('묵직한 바디감'), findsNothing);
      expect(find.text('마지막 한 조각만 채우면 취향 조각이 완성돼요.'), findsOneWidget);
      expect(find.text('바디감 (무게)'), findsOneWidget);
      expect(
        find.text('좋아하는 바디감을 아직 알 수 없어요.\n다음 한 잔의 목넘김을 기록하면\n이 조각이 채워져요.'),
        findsOneWidget,
      );
      expect(find.text('1번 더 기록하면 오픈'), findsNothing);
      expect(find.text('과일'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('unknown-letter-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('unknown-letter-1')),
        findsNothing,
      );

      expect(find.text('모스카토 다스티'), findsOneWidget);
      expect(find.text('향 변화'), findsOneWidget);
      expect(find.text('“산뜻한 향 취향으로 바뀌었어요”'), findsOneWidget);
      expect(find.text('2026.10.20'), findsOneWidget);
      // Only the newest moment shows; the older one waits in the journey.
      expect(find.text('글렌피딕 12년'), findsNothing);
      expect(find.text('취향 여정 전체보기'), findsOneWidget);

      expect(find.text('지금까지의 해석, 잘 맞나요?'), findsNothing);
    });

    testWidgets('shows only the newest change and opens the whole journey', (
      tester,
    ) async {
      final many = <TasteLetterChange>[
        for (var day = 1; day <= 5; day++)
          TasteLetterChange(
            axis: TasteLetterAxis.aroma,
            fromLetter: day.isEven ? 'F' : 'R',
            toLetter: day.isEven ? 'R' : 'F',
            productName: '술 $day',
            changedAt: DateTime(2026, 10, day),
          ),
      ];
      final gateway = FakeTasteLettersGateway(
        TasteLettersSnapshot(state: sampleState, changes: many),
      );
      await pumpPage(
        tester,
        withProviders(letters: gateway, child: SoolgyulLettersDetailScreen()),
      );
      gateway.finish();
      await tester.pumpAndSettle();
      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('취향 여정 전체보기'),
        200,
        scrollable: scrollable,
      );
      expect(find.text('술 5'), findsOneWidget);
      expect(find.text('술 4'), findsNothing);

      await tester.tap(find.text('취향 여정 전체보기'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('letter-journey-list')),
        findsOneWidget,
      );
      expect(find.text('술 1'), findsOneWidget);
      expect(find.text('술 2'), findsOneWidget);

      // No title or close button; the list pulled down from its top closes.
      expect(find.text('내 취향 여정'), findsNothing);
      await tester.fling(
        find.byKey(const ValueKey<String>('letter-journey-list')),
        const Offset(0, 600),
        2000,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('letter-journey-list')),
        findsNothing,
      );
    });

    testWidgets('a moment opens the card of its record, a deleted one not', (
      tester,
    ) async {
      final changes = <TasteLetterChange>[
        TasteLetterChange(
          axis: TasteLetterAxis.sweetness,
          toLetter: 'D',
          productName: '지운 술',
          changedAt: DateTime(2026, 10, 2),
        ),
        TasteLetterChange(
          axis: TasteLetterAxis.aroma,
          fromLetter: 'R',
          toLetter: 'F',
          productName: '노구치 나오히코 연구소 카나가소',
          changedAt: DateTime(2026, 10, 20),
          resultId: 'card-20',
        ),
      ];
      final opened = <String>[];
      final gateway = FakeTasteLettersGateway(
        TasteLettersSnapshot(state: sampleState, changes: changes),
      );
      await pumpPage(
        tester,
        withProviders(
          letters: gateway,
          child: SoolgyulLettersDetailScreen(onOpenCard: opened.add),
        ),
      );
      gateway.finish();
      await tester.pumpAndSettle();
      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('취향 여정 전체보기'),
        200,
        scrollable: scrollable,
      );

      final name = tester.widget<Text>(find.text('노구치 나오히코 연구소 카나가소'));
      expect(name.style?.decoration, TextDecoration.underline);
      await tester.tap(find.text('노구치 나오히코 연구소 카나가소'));
      await tester.pumpAndSettle();
      expect(opened, <String>['card-20']);

      await tester.tap(find.text('취향 여정 전체보기'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.text('지운 술')).style?.decoration,
        isNot(TextDecoration.underline),
      );
      await tester.tap(find.text('지운 술'));
      await tester.pumpAndSettle();
      expect(opened, <String>['card-20']);
      expect(
        find.byKey(const ValueKey<String>('letter-journey-list')),
        findsOneWidget,
      );

      await tester.tap(find.text('노구치 나오히코 연구소 카나가소').last);
      await tester.pumpAndSettle();
      expect(opened, <String>['card-20', 'card-20']);
      expect(
        find.byKey(const ValueKey<String>('letter-journey-list')),
        findsNothing,
      );
    });

    testWidgets('skips the hidden section when all four are revealed', (
      tester,
    ) async {
      final full = TasteLettersState(
        axes: {
          for (final axis in TasteLetterAxis.values)
            axis: TasteLetterAxisState(
              letter: axis.leftLetter,
              leftShare: 100,
              voteCount: 1,
            ),
        },
        recordCount: 1,
      );
      final gateway = FakeTasteLettersGateway(
        TasteLettersSnapshot(state: full),
      );
      await pumpPage(
        tester,
        withProviders(letters: gateway, child: SoolgyulLettersDetailScreen()),
      );
      gateway.finish();
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('취향의 변화'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('채워질 취향 조각'), findsNothing);
      expect(
        find.text('아직 변경된 조각이 없어요.\n기록이 쌓이면 취향 변화를 보여드릴게요.'),
        findsOneWidget,
      );
    });

    testWidgets('shows the empty overview when the user has no row', (
      tester,
    ) async {
      final gateway = FakeTasteLettersGateway(const TasteLettersSnapshot());
      await pumpPage(
        tester,
        withProviders(letters: gateway, child: SoolgyulLettersDetailScreen()),
      );
      gateway.finish();
      await tester.pumpAndSettle();

      expect(find.text(emptyState.overviewStatement), findsOneWidget);
      expect(find.text('발견한 취향 조각'), findsNothing);
    });
  });
}
