import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/design/app_tokens.dart';
import 'package:soolgyul/src/features/onboarding/presentation/taste_card_snapshot_view_data.dart'
    show TasteCardTagKind;
import 'package:soolgyul/src/features/preferences/data/preference_history_content.dart';
import 'package:soolgyul/src/features/preferences/presentation/history/preference_history_screen.dart';
import '../support/app_test_harness.dart';

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

HistoryRecord _record(
  String id,
  DateTime at, {
  String title = '샤토 테스트',
  String? category = 'wine',
  String label = '와인',
  String? note,
  String? summary,
  List<HistoryTag> tags = const <HistoryTag>[
    HistoryTag('산뜻함', TasteCardTagKind.liked),
  ],
}) => HistoryRecord(
  resultId: id,
  title: title,
  categoryKey: category,
  categoryLabel: label,
  recordedAt: at,
  tags: tags,
  summary: summary,
  note: note,
);

class _History implements PreferenceHistoryGateway {
  _History(this.records, {this.fail = false, this.latest});
  final List<HistoryRecord> records;
  bool fail;

  /// What the newest-record lookup answers; `null` keeps the tab on today.
  final DateTime? latest;
  final months = <DateTime>[];

  @override
  Future<DateTime?> latestRecordedAt() async => latest;

  @override
  Future<List<HistoryRecord>> loadMonth(DateTime month) async {
    months.add(month);
    if (fail) throw StateError('offline');
    return [
      for (final record in records)
        if (record.recordedAt.year == month.year &&
            record.recordedAt.month == month.month)
          record,
    ];
  }
}

void main() {
  testWidgets('the tab opens on the month of the newest record', (
    tester,
  ) async {
    final history = _History([
      _record('r-june', DateTime(2026, 6, 3, 20), title: '라 크라사드'),
    ], latest: DateTime(2026, 6, 3, 20));
    await pumpTestScreen(
      tester,
      PreferenceHistoryScreen(
        gateway: history,
        onOpenCard: (_) {},
        today: DateTime(2026, 11, 8, 9),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2026년 6월'), findsOneWidget);
    expect(find.text('6월의 술결'), findsOneWidget);
    expect(find.text('라 크라사드'), findsOneWidget);
    expect(history.months, [DateTime(2026, 6)]);
  });

  group('calendar cells', () {
    test('mark each recorded day with its kinds and pad whole weeks', () {
      final days = historyMonthDays(DateTime(2026, 6), [
        _record('a', DateTime(2026, 6, 3, 20)),
        _record(
          'b',
          DateTime(2026, 6, 3, 22),
          category: 'whisky',
          label: '위스키',
        ),
        _record('c', DateTime(2026, 7, 1)),
      ]);
      // June 2026 starts on a Monday: one leading Sunday, five weeks.
      expect(days, hasLength(35));
      expect(days.first.text, '31');
      expect(days.first.muted, isTrue);
      final third = days[3];
      expect(third.text, '3');
      expect(third.rings, [AppDataColors.wine, AppDataColors.whisky]);
      expect(days.where((day) => day.rings.isNotEmpty), hasLength(1));
    });

    test('meta reads kind, date and 12-hour time', () {
      expect(
        _record('a', DateTime(2026, 6, 18, 20, 5)).meta,
        '와인 · 2026.06.18 8:05 PM',
      );
      expect(
        _record('a', DateTime(2026, 6, 18, 0, 30)).meta,
        '와인 · 2026.06.18 12:30 AM',
      );
    });
  });

  testWidgets(
    'lists the month, a tapped day narrows it, a second tap widens it',
    (tester) async {
      final opened = <String>[];
      final history = _History([
        _record('r-june', DateTime(2026, 6, 18, 20), note: '부드러웠어요'),
        _record('r-june-b', DateTime(2026, 6, 18, 22), title: '샤토 둘째'),
        _record(
          'r-june-2',
          DateTime(2026, 6, 20, 21),
          title: '라프로익 10',
          category: 'whisky',
          label: '위스키',
        ),
        _record('r-july', DateTime(2026, 7, 2, 19), title: '닷사이 45'),
      ]);
      await pumpTestScreen(
        tester,
        PreferenceHistoryScreen(
          gateway: history,
          onOpenCard: opened.add,
          today: DateTime(2026, 6, 18, 9),
        ),
      );
      await tester.pumpAndSettle();

      final selected = find.byKey(
        const ValueKey<String>('history-selected-day'),
      );
      expect(find.text('2026년 6월'), findsOneWidget);
      expect(find.text('6월의 술결'), findsOneWidget);
      expect(find.text('총 3개'), findsOneWidget);
      expect(selected, findsNothing);
      expect(
        find.text('6월엔 세 잔, 와인을 가장 많이 마셨고 산뜻함을 특히 좋아했어요.'),
        findsOneWidget,
      );

      await _tapVisible(
        tester,
        find.byKey(const ValueKey<String>('history-record-r-june')),
      );
      expect(opened, ['r-june']);

      final day20 = find.byKey(const ValueKey<String>('history-day-20'));
      await _tapVisible(tester, day20);
      expect(find.text('6월 20일의 술결'), findsOneWidget);
      expect(find.text('총 1개'), findsOneWidget);
      expect(find.text('라프로익 10'), findsOneWidget);
      expect(selected, findsOneWidget);

      final day5 = find.byKey(const ValueKey<String>('history-day-5'));
      await _tapVisible(tester, day5);
      expect(find.text('6월 5일에는 기록된 술결이 없어요.'), findsOneWidget);

      await _tapVisible(tester, day5);
      expect(find.text('6월의 술결'), findsOneWidget);
      expect(find.text('총 3개'), findsOneWidget);
      expect(selected, findsNothing);

      // Another month opens on the whole month.
      await _tapVisible(tester, day20);
      await _tapVisible(tester, find.byTooltip('다음 달'));
      expect(find.text('2026년 7월'), findsOneWidget);
      expect(find.text('7월의 술결'), findsOneWidget);
      expect(find.text('닷사이 45'), findsOneWidget);

      await _tapVisible(tester, find.byTooltip('다음 달'));
      expect(find.text('8월에는 기록된 술결이 없어요.'), findsOneWidget);
      expect(history.months, [
        DateTime(2026, 6),
        DateTime(2026, 7),
        DateTime(2026, 8),
      ]);
    },
  );

  testWidgets('on Android the month control opens the Material date picker', (
    tester,
  ) async {
    await pumpTestScreen(
      tester,
      PreferenceHistoryScreen(
        gateway: _History([
          _record('r', DateTime(2026, 6, 20, 21), title: '라프로익 10'),
        ]),
        onOpenCard: (_) {},
        today: DateTime(2026, 6, 18),
      ),
    );
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.byKey(const ValueKey<String>('history-month-selector')),
    );
    expect(find.byType(DatePickerDialog), findsOneWidget);
    // The picker cannot go past today.
    final dialog = find.byType(DatePickerDialog);
    await tester.tap(find.descendant(of: dialog, matching: find.text('17')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: dialog, matching: find.byType(TextButton)).last,
    );
    await tester.pumpAndSettle();
    expect(find.text('6월 17일에는 기록된 술결이 없어요.'), findsOneWidget);
  });

  testWidgets('a failed month offers a retry', (tester) async {
    final history = _History([
      _record('r', DateTime(2026, 6, 18, 20)),
    ], fail: true);
    await pumpTestScreen(
      tester,
      PreferenceHistoryScreen(
        gateway: history,
        onOpenCard: (_) {},
        today: DateTime(2026, 6, 18),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('기록을 불러오지 못했어요.'), findsOneWidget);

    history.fail = false;
    await _tapVisible(tester, find.text('다시 시도'));
    expect(find.text('6월의 술결'), findsOneWidget);
  });

  testWidgets(
    'the month line names the kind drunk most and the liked sensation',
    (tester) async {
      await pumpTestScreen(
        tester,
        PreferenceHistoryScreen(
          gateway: _History([
            _record('a', DateTime(2026, 6, 1, 20)),
            _record('b', DateTime(2026, 6, 2, 20)),
            _record(
              'c',
              DateTime(2026, 6, 3, 20),
              category: 'whisky',
              label: '위스키',
            ),
          ]),
          onOpenCard: (_) {},
          today: DateTime(2026, 6, 18),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('6월엔 세 잔, 와인을 가장 많이 마셨고 산뜻함을 특히 좋아했어요.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('a tied month drank its kinds evenly', (tester) async {
    await pumpTestScreen(
      tester,
      PreferenceHistoryScreen(
        gateway: _History([
          _record('a', DateTime(2026, 6, 1, 20)),
          _record(
            'b',
            DateTime(2026, 6, 2, 20),
            category: 'whisky',
            label: '위스키',
          ),
        ]),
        onOpenCard: (_) {},
        today: DateTime(2026, 6, 18),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('6월엔 두 잔, 와인과 위스키를 고루 마셨고 산뜻함을 특히 좋아했어요.'),
      findsOneWidget,
    );
  });

  testWidgets('a record shows its card\'s line, its note opens from a mark', (
    tester,
  ) async {
    await pumpTestScreen(
      tester,
      PreferenceHistoryScreen(
        gateway: _History([
          _record(
            'a',
            DateTime(2026, 6, 1, 20),
            summary: '향긋한 바닐라 향과 깔끔한 마무리까지 마음에 쏙 들었어요.',
            note: '다음에 또.',
          ),
          _record('b', DateTime(2026, 6, 2, 20), summary: '산미가 반가웠어요.'),
        ]),
        onOpenCard: (_) {},
        today: DateTime(2026, 6, 18),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('향긋한 바닐라 향과 깔끔한 마무리까지 마음에 쏙 들었어요.'), findsOneWidget);
    expect(find.text('6월엔 두 잔, 와인만 마셨고 산뜻함을 특히 좋아했어요.'), findsOneWidget);

    // The note is off the card; only the record that has one gets the mark.
    expect(find.text('다음에 또.'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('history-record-note-b')),
      findsNothing,
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey<String>('history-record-note-a')),
    );
    expect(find.text('나의 메모'), findsOneWidget);
    expect(find.text('다음에 또.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('term-tooltip-close')));
    await tester.pumpAndSettle();
    expect(find.text('다음에 또.'), findsNothing);
  });

  testWidgets('a line past three lines folds behind 더보기 and unfolds in place', (
    tester,
  ) async {
    const long =
        '싱그러운 체리 향과 침샘을 자극하는 깔끔한 산미는 반갑지만, 입안을 꽉 조이는 떫은맛과 '
        '입안을 꽉 채우는 묵직함, 확 올라오는 알코올 열감은 아직 조금 버거워요. 다음엔 떫은맛이 '
        '한 톤 부드러운 술로 가볼까요? 마무리는 깔끔하게 떨어져서 좋았어요.';
    final opened = <String>[];
    await pumpTestScreen(
      tester,
      PreferenceHistoryScreen(
        gateway: _History([
          _record('a', DateTime(2026, 6, 1, 20), summary: long),
        ]),
        onOpenCard: opened.add,
        today: DateTime(2026, 6, 18),
      ),
    );
    await tester.pumpAndSettle();
    final summary = find.byKey(
      const ValueKey<String>('history-record-summary'),
    );
    final carousel = find.byKey(const ValueKey<String>('history-day-carousel'));
    final folded = tester.getSize(carousel).height;
    expect(find.textContaining('… 더보기', findRichText: true), findsOneWidget);
    expect(find.text(long, findRichText: true), findsNothing);
    expect(
      tester.getSize(summary).height,
      lessThan(4 * 12 * 1.55), // three lines, not four
    );

    await _tapVisible(
      tester,
      find.byKey(const ValueKey<String>('history-record-summary-toggle')),
    );
    expect(opened, isEmpty, reason: 'unfolding is not opening the card');
    expect(
      find.textContaining('조금 버거워요. 다음엔', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('접기', findRichText: true), findsOneWidget);
    expect(tester.getSize(carousel).height, greaterThan(folded));

    await _tapVisible(
      tester,
      find.byKey(const ValueKey<String>('history-record-summary-toggle')),
    );
    expect(find.textContaining('… 더보기', findRichText: true), findsOneWidget);
    expect(tester.getSize(carousel).height, folded);
  });

  testWidgets('chips that wrap to a second row leave the line whole', (
    tester,
  ) async {
    const line = '싱그러운 체리 향과 침샘을 자극하는 깔끔한 산미는 반갑지만 떫은맛은 아직 조금 버거워요.';
    const tags = <HistoryTag>[
      HistoryTag('탄산감', TasteCardTagKind.liked),
      HistoryTag('바디감', TasteCardTagKind.liked),
      HistoryTag('여운', TasteCardTagKind.liked),
      HistoryTag('곡물향', TasteCardTagKind.liked),
      HistoryTag('산뜻함', TasteCardTagKind.liked),
      HistoryTag('떫은맛', TasteCardTagKind.burden),
    ];
    await pumpTestScreen(
      tester,
      PreferenceHistoryScreen(
        gateway: _History([
          _record('a', DateTime(2026, 6, 1, 20), summary: line, tags: tags),
        ]),
        onOpenCard: (_) {},
        today: DateTime(2026, 6, 18),
      ),
    );
    await tester.pumpAndSettle();
    final first = tester.getTopLeft(
      find.byKey(const ValueKey<String>('history-record-tag-탄산감')),
    );
    final last = tester.getTopLeft(
      find.byKey(const ValueKey<String>('history-record-tag-떫은맛')),
    );
    expect(last.dy, greaterThan(first.dy), reason: 'the chips wrap');
    final summary = tester.getRect(
      find.byKey(const ValueKey<String>('history-record-summary')),
    );
    // The slide clips its content to the card; the line must end inside.
    final clip = tester.getRect(
      find
          .descendant(
            of: find.byKey(const ValueKey<String>('history-record-a')),
            matching: find.byType(ClipRect),
          )
          .first,
    );
    expect(summary.bottom, lessThanOrEqualTo(clip.bottom));
  });

  testWidgets('without a gateway every month is empty', (tester) async {
    await pumpTestScreen(
      tester,
      PreferenceHistoryScreen(
        gateway: null,
        onOpenCard: (_) {},
        today: DateTime(2026, 6, 18),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('6월에는 기록된 술결이 없어요.'), findsOneWidget);
  });
}
