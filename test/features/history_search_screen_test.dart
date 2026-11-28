import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/preferences/data/preference_history_content.dart';
import 'package:soolgyul/src/features/preferences/presentation/history/history_search_screen.dart';
import 'package:soolgyul/src/widgets/app_state_view.dart';

import '../support/app_test_harness.dart';
import '../support/provider_harness.dart';

HistoryRecord _record(
  String id,
  String title,
  DateTime at, {
  String label = '와인',
}) => HistoryRecord(
  resultId: id,
  title: title,
  categoryKey: null,
  categoryLabel: label,
  recordedAt: at,
);

/// Answers every record only when the test lets it, or fails.
class _History implements PreferenceHistoryGateway {
  _History(this.records);

  /// Newest first, as the gateway gives them.
  List<HistoryRecord> records;
  bool fail = false;
  Completer<void>? wait;
  int loads = 0;

  @override
  Future<List<HistoryRecord>> loadAll() async {
    loads++;
    await wait?.future;
    if (fail) throw StateError('offline');
    return records;
  }

  @override
  Future<DateTime?> latestRecordedAt() => throw UnimplementedError();

  @override
  Future<List<HistoryRecord>> loadMonth(DateTime month) =>
      throw UnimplementedError();
}

final _records = <HistoryRecord>[
  _record('c', 'Glenfiddich 12', DateTime(2026, 11, 3, 21), label: '위스키'),
  _record('b', '샤토 마고', DateTime(2026, 6, 18, 20)),
  _record('a', '샤토 마고', DateTime(2025, 12, 24, 19)),
];

final _field = find.byKey(const ValueKey<String>('history-search-field'));

/// The names on the rows, top to bottom.
List<String> _names(WidgetTester tester) {
  final list = find.byKey(const ValueKey<String>('history-search-list'));
  final names = <(double, String)>[
    for (final title in const ['Glenfiddich 12', '샤토 마고'])
      for (final element
          in find.descendant(of: list, matching: find.text(title)).evaluate())
        (tester.getTopLeft(find.byWidget(element.widget)).dy, title),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final (_, name) in names) name];
}

Future<List<String>> _pump(
  WidgetTester tester,
  _History history, {
  Size viewport = defaultAppTestViewport,
}) async {
  final opened = <String>[];
  await pumpTestScreen(
    tester,
    withProviders(
      history: history,
      child: HistorySearchScreen(onOpenCard: opened.add),
    ),
    viewport: viewport,
  );
  await tester.pumpAndSettle();
  return opened;
}

void main() {
  testWidgets('every record is listed newest first, each with its kind and '
      'day, and the cursor is in the field', (tester) async {
    final history = _History(_records)..wait = Completer<void>();
    await pumpTestScreen(
      tester,
      withProviders(
        history: history,
        child: HistorySearchScreen(onOpenCard: (_) {}),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('history-search-loading')),
      findsOneWidget,
    );
    expect(find.text('술 이름으로 검색'), findsOneWidget);
    expect(
      tester.testTextInput.hasAnyClients,
      isTrue,
      reason: 'the keyboard is up as the page opens',
    );

    history.wait!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AppLoadingView), findsNothing);
    expect(_names(tester), ['Glenfiddich 12', '샤토 마고', '샤토 마고']);
    expect(find.text('위스키 · 2026.11.03'), findsOneWidget);
    expect(find.text('와인 · 2026.06.18'), findsOneWidget);
    expect(find.text('와인 · 2025.12.24'), findsOneWidget);
    expect(history.loads, 1);
  });

  testWidgets('typing keeps the records whose name holds it, whatever the '
      'letter case and the spaces; ✕ brings them all back', (tester) async {
    final history = _History(_records);
    await _pump(tester, history);

    await tester.enterText(_field, 'glen FID');
    await tester.pumpAndSettle();
    expect(_names(tester), ['Glenfiddich 12']);

    await tester.enterText(_field, '샤토마 고');
    await tester.pumpAndSettle();
    expect(_names(tester), ['샤토 마고', '샤토 마고']);

    await tester.enterText(_field, '사케');
    await tester.pumpAndSettle();
    expect(find.text('검색 결과가 없어요.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('history-search-list')),
      findsNothing,
    );

    await tester.tap(find.byTooltip('입력 내용 삭제'));
    await tester.pumpAndSettle();
    expect(_names(tester), hasLength(3));
    expect(find.byTooltip('입력 내용 삭제'), findsNothing);
    expect(history.loads, 1, reason: 'the records are narrowed on the phone');
  });

  testWidgets('a row opens that record\'s card', (tester) async {
    final opened = await _pump(tester, _History(_records));
    await tester.tap(find.text('와인 · 2025.12.24'));
    await tester.pumpAndSettle();
    expect(opened, ['a']);
  });

  testWidgets('an account without a record is told so', (tester) async {
    await _pump(tester, _History(const <HistoryRecord>[]));
    expect(find.text('아직 남긴 기록이 없어요.'), findsOneWidget);
    await tester.enterText(_field, '와인');
    await tester.pumpAndSettle();
    expect(find.text('아직 남긴 기록이 없어요.'), findsOneWidget);
    expect(find.text('검색 결과가 없어요.'), findsNothing);
  });

  testWidgets('records that could not be read offer a retry', (tester) async {
    final history = _History(_records)..fail = true;
    await _pump(tester, history);
    expect(find.text('기록을 불러오지 못했어요'), findsOneWidget);

    history.fail = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(_names(tester), hasLength(3));
    expect(history.loads, 2);
  });

  testWidgets('a narrow phone with large text and a long name does not '
      'overflow', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(
      tester,
      _History(<HistoryRecord>[
        _record(
          'long',
          '샤토 라피트 로칠드 포이약 그랑 크뤼 클라세 2015 매그넘',
          DateTime(2026, 11, 3),
          label: '레드 와인',
        ),
      ]),
      viewport: const Size(360, 640),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('레드 와인 · 2026.11.03'), findsOneWidget);
  });
}
