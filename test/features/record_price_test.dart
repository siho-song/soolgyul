import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/core/sensory/revisit_intent.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/design/app_tokens.dart';
import 'package:soolgyul/src/features/preferences/data/preference_history_content.dart';
import 'package:soolgyul/src/features/preferences/presentation/history/preference_history_daily_records.dart';
import 'package:soolgyul/src/features/records/data/record_note_gateway.dart';
import 'package:soolgyul/src/features/records/data/record_price.dart';
import 'package:soolgyul/src/features/records/data/tasting_note_gateway.dart';
import 'package:soolgyul/src/features/records/presentation/widgets/record_memo_editor.dart';
import 'package:soolgyul/src/features/records/presentation/widgets/record_price_editor.dart';
import 'package:soolgyul/src/features/records/presentation/widgets/tasting_note_editor.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_wire_parser.dart';
import 'package:soolgyul/src/features/taste_card/presentation/taste_card_screen.dart';
import 'package:soolgyul/src/features/taste_card/presentation/widgets/taste_card_more_action.dart';
import 'package:soolgyul/src/features/taste_card/presentation/widgets/taste_card_note_opener.dart';
import 'package:soolgyul/src/widgets/app_text_field.dart';

import 'package:soolgyul/src/features/onboarding/adaptive/onboarding_aroma_menu.dart';
import 'package:soolgyul/src/features/onboarding/data/sensory_questionnaire_data.dart';
import 'package:soolgyul/src/features/onboarding/presentation/widgets/sensory_inputs.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_answers_gateway.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_result.dart';
import 'package:soolgyul/src/features/taste_card/presentation/widgets/taste_card_answers_editor.dart';

import '../support/sensory_fixtures.dart';
import '../support/taste_card_envelopes.dart';
import 'package:soolgyul/src/widgets/app_icon.dart';
import '../support/app_icon_finder.dart';

// The 테이스팅 노트 is read until the header's 수정 turns it into one form,
// which the header's 완료 keeps at once; and the price as lists show it.

class _Prices implements RecordPriceGateway {
  _Prices([this.stored]);

  RecordPrice? stored;
  final saves = <(int?, String?)>[];

  @override
  Future<RecordPrice?> loadPrice(String recordId) async => stored;

  @override
  Future<void> save({
    required String recordId,
    int? amount,
    String? place,
  }) async => saves.add((amount, place));
}

class _Notes implements TastingNoteGateway {
  _Notes([Map<String, String>? stored]) : stored = {...?stored};
  final Map<String, String> stored;
  final saves = <Map<String, Object?>>[];
  bool fail = false;

  @override
  Future<Map<String, String>> load(String recordId) async => {...stored};

  @override
  Future<void> save(String recordId, Map<String, Object?> patch) async {
    if (fail) throw const TastingNoteException('테이스팅 노트를 저장하지 못했어요.');
    saves.add(patch);
  }
}

class _Answers implements TasteCardAnswersGateway {
  _Answers({this.revisit});

  /// The stored answer to 재음용 의사, in place of the fixture's.
  final String? revisit;
  int revisions = 0;

  @override
  Future<TasteCardAnswers> loadAnswers(String resultId) async =>
      TasteCardAnswers(
        revisable: true,
        answers: {
          ...gaugeNoteAnswers,
          if (revisit case final revisit?) 'sensory_revisit': [revisit],
        },
      );

  @override
  Future<TasteCardResult> reviseAnswers(
    String resultId,
    Map<String, List<String>> answers,
  ) async {
    revisions++;
    throw UnimplementedError();
  }

  @override
  Future<TasteCardResult> fetchOwnedResult(String resultId) =>
      throw UnimplementedError();
}

TasteCardAnswersEditor _answersEditor(_Answers gateway) {
  return TasteCardAnswersEditor(
    resultId: 'result',
    gateway: gateway,
    loadQuestions: () async => SensoryQuestionnaireData(
      registry: sensoryRegistry(),
      aromaMenu: OnboardingAromaMenu.forDrink('wine', 'red_wine'),
      gauges: gaugesFor('wine', 'red_wine'),
    ),
  );
}

/// Opens the form with the answers read, which takes real time.
Future<void> _editWithAnswers(
  WidgetTester tester,
  TasteCardNoteOpener opener,
) async {
  opener.open(TasteCardNoteSlot.edit);
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
}

class _Memo implements RecordNoteGateway {
  final saves = <String>[];

  @override
  Future<String> loadNote(String recordId) async => '진한 시라';

  @override
  Future<void> saveNote({
    required String recordId,
    required String note,
  }) async => saves.add(note);
}

const _filled = <String, String>{
  'pairing': '양갈비 스테이크',
  'companion_place': '친구와 집에서',
  'purchased_on': '2026-09-01',
};

Future<TasteCardNoteOpener> _open(
  WidgetTester tester, {
  required _Notes notes,
  _Prices? prices,
  _Memo? memo,
  bool header = false,
  bool justMade = false,
  bool openNote = true,
  TasteCardAnswersEditor? answers,
  double width = 402,
  List<String>? nose,
  String? revisit,
}) async {
  tester.view.physicalSize = Size(width, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final envelope = validEnvelope();
  final note = viewOf(envelope)['note'] = gaugeNoteJson()
    ..['serving'] = <String, Object?>{
      'label': '음용 방식',
      'prompt': '마신 방식을 모두 골라주세요',
      'options': <Object?>[
        <String, Object?>{'key': 'open_now', 'label': '바로 오픈'},
        <String, Object?>{
          'key': 'decanting',
          'label': '디캔터 사용(디캔팅)',
          'short': '디캔팅',
        },
      ],
    };
  // A record whose 재음용 의사 was skipped, written in [revisit].
  if (revisit != null) {
    note['revisit'] = revisit;
    ((note['words']! as Map)['revisit']! as Map)['revisit:unsure'] = revisit;
  }
  if (nose != null) {
    note['nose'] = <Object?>[
      <String, Object?>{
        'label': '마음에 들었어요',
        'marks': <Object?>[
          for (final name in nose)
            <String, Object?>{'label': name, 'felt': 'liked'},
        ],
      },
    ];
  }
  final entries = TastingNoteEditor(recordId: 'record', gateway: notes);
  final price = RecordPriceEditor(
    recordId: 'record',
    gateway: prices ?? _Prices(),
  );
  final memoEditor = RecordMemoEditor(
    recordId: 'record',
    gateway: memo ?? _Memo(),
  );
  final opener = TasteCardNoteOpener();
  addTearDown(entries.dispose);
  addTearDown(price.dispose);
  addTearDown(memoEditor.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        appBar: header
            ? AppBar(
                actions: <Widget>[
                  TasteCardMoreAction(
                    onEdit: () => opener.open(TasteCardNoteSlot.edit),
                  ),
                ],
              )
            : null,
        body: TasteCardScreen(
          viewData: TasteCardWireParser.parseResult(envelope).viewData,
          noteEntries: entries,
          recordPrice: price,
          recordMemo: memoEditor,
          noteOpener: opener,
          offerNoteForm: justMade,
          answers: answers,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (openNote) await _toTab(tester, 'note');
  return opener;
}

Future<void> _toTab(WidgetTester tester, String tab) async {
  await tester.tap(find.byKey(ValueKey<String>('taste-card-tab-$tab')));
  await tester.pumpAndSettle();
}

Future<void> _edit(WidgetTester tester, TasteCardNoteOpener opener) async {
  opener.open(TasteCardNoteSlot.edit);
  await tester.pumpAndSettle();
}

/// The bar of the two tabs.
final _tabBar = find
    .ancestor(
      of: find.byKey(const ValueKey('taste-card-tab-card')),
      matching: find.byType(Row),
    )
    .first;

Finder _box(String key) => find.descendant(
  of: find.byKey(ValueKey<String>('taste-card-note-$key')),
  matching: find.byType(EditableText),
);

bool _red(WidgetTester tester, String key) => tester
    .widget<AppTextField>(find.byKey(ValueKey<String>('taste-card-note-$key')))
    .hasError;

String _text(WidgetTester tester, String key) =>
    tester.widget<EditableText>(_box(key)).controller.text;

HistoryRecord _record(String id, {RecordPrice? price}) => HistoryRecord(
  resultId: id,
  title: '테스트 리슬링',
  categoryKey: 'wine',
  categoryLabel: '와인',
  recordedAt: DateTime(2026, 11, 8, 20, 10),
  price: price,
);

void main() {
  test('a price reads with thousands separators and the place in words', () {
    expect(formatWon(1), '1');
    expect(formatWon(38000), '38,000');
    expect(formatWon(10000000), '10,000,000');
    expect(
      const RecordPrice(amount: 38000, place: '와인샵').line,
      '구매 정보 : 38,000원 · 와인샵',
    );
    // A place stored as one of the old choices reads in words.
    expect(RecordPrice.fromStored(38000, 'bar')!.place, '바');
    expect(RecordPrice.fromStored(null, '와인샵')!.infoLine, '와인샵');
    expect(RecordPrice.fromStored(null, null), isNull);
  });

  testWidgets('read, the note shows what is written as cells and offers '
      'nothing to change', (tester) async {
    await _open(
      tester,
      notes: _Notes(_filled),
      prices: _Prices(const RecordPrice(amount: 89000, place: '와인샵')),
    );
    for (final text in [
      '2026.09.01',
      '친구와 집에서',
      '양갈비 스테이크',
      '89,000원',
      '와인샵',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.textContaining('진한 시라'), findsOneWidget);
    expect(find.byKey(const ValueKey('taste-card-note-form')), findsNothing);
    expect(find.text('다시 고르기'), findsNothing);
    expect(find.text('수정'), findsNothing);
    expect(find.text('+ 입력'), findsNothing);
    expect(find.byType(EditableText), findsNothing);
  });

  testWidgets('더보기 → 수정 opens the note in edit mode', (tester) async {
    final opener = await _open(tester, notes: _Notes(_filled), header: true);
    await tester.tap(find.byKey(const ValueKey('taste-card-tab-card')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('taste-card-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('taste-card-menu-edit')));
    await tester.pumpAndSettle();
    expect(opener.editing, isTrue);
    expect(find.byKey(const ValueKey('taste-card-note-form')), findsOneWidget);
  });

  testWidgets('while the note is written the tabs are closed and dimmed; '
      'they come back when it ends by 완료, by back or by 그만두기', (tester) async {
    final opener = await _open(tester, notes: _Notes(_filled));
    final cardTab = find.byKey(const ValueKey('taste-card-tab-card'));
    final form = find.byKey(const ValueKey('taste-card-note-form'));
    Color? tabColor(String label) => tester
        .widget<Text>(find.descendant(of: _tabBar, matching: find.text(label)))
        .style
        ?.color;
    final open = (card: tabColor('술결 카드'), note: tabColor('테이스팅 노트'));
    expect(open.card, isNot(open.note));

    Future<void> expectClosed() async {
      expect(opener.editing, isTrue);
      expect(tabColor('술결 카드'), AppColors.controlInactive);
      expect(tabColor('테이스팅 노트'), AppColors.controlInactive);
      await tester.tap(cardTab);
      await tester.pumpAndSettle();
      // Still the note's form: the card did not come up under it.
      expect(form.hitTestable(), findsOneWidget);
      expect(opener.editing, isTrue);
    }

    Future<void> expectOpen() async {
      expect(opener.editing, isFalse);
      expect(tabColor('술결 카드'), open.card);
      expect(tabColor('테이스팅 노트'), open.note);
      await _toTab(tester, 'card');
      expect(tabColor('술결 카드'), open.note);
      await _toTab(tester, 'note');
    }

    // Left by 완료 with nothing changed.
    await _edit(tester, opener);
    await expectClosed();
    expect(await opener.done(), isTrue);
    await tester.pumpAndSettle();
    await expectOpen();

    // Left by back with nothing changed.
    await _edit(tester, opener);
    await expectClosed();
    await opener.back();
    await tester.pumpAndSettle();
    await expectOpen();

    // Left by back over a change: the tabs stay closed while the question
    // is up and under 계속 수정, and come back with 그만두기.
    await _edit(tester, opener);
    await tester.enterText(_box('pairing'), '치즈');
    await tester.pump();
    unawaited(opener.back());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('taste-card-note-stay')));
    await tester.pumpAndSettle();
    await expectClosed();
    unawaited(opener.back());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('taste-card-note-leave')));
    await tester.pumpAndSettle();
    await expectOpen();
  });

  testWidgets('a card just made offers its form once, on the first visit '
      'to the note; 나중에 leaves it read', (tester) async {
    final opener = await _open(tester, notes: _Notes(), justMade: true);
    expect(find.text('테이스팅 노트를 채웠어요.'), findsOneWidget);
    // Only what the form asks for today: no 마신 날짜.
    expect(find.text('평점과 페어링, 가격도 이어서 적어둘까요?'), findsOneWidget);
    expect(find.textContaining('마신 날짜'), findsNothing);
    await tester.tap(find.text('나중에'));
    await tester.pumpAndSettle();
    expect(opener.editing, isFalse);
    expect(find.byKey(const ValueKey('taste-card-note-form')), findsNothing);
    await _toTab(tester, 'card');
    await _toTab(tester, 'note');
    expect(find.text('테이스팅 노트를 채웠어요.'), findsNothing);
  });

  testWidgets('지금 적기 opens the note in edit mode', (tester) async {
    final opener = await _open(tester, notes: _Notes(), justMade: true);
    await tester.tap(find.text('지금 적기'));
    await tester.pumpAndSettle();
    expect(opener.editing, isTrue);
    expect(find.byKey(const ValueKey('taste-card-note-form')), findsOneWidget);
  });

  testWidgets('a saved card opened again offers nothing', (tester) async {
    await _open(tester, notes: _Notes());
    expect(find.text('테이스팅 노트를 채웠어요.'), findsNothing);
  });

  testWidgets('back in edit mode, with changes, asks first: 계속 수정 '
      'stays, 그만두기 returns to the note read, the change dropped', (
    tester,
  ) async {
    final opener = await _open(tester, notes: _Notes(_filled));
    await _edit(tester, opener);
    await tester.enterText(_box('pairing'), '치즈');
    await tester.pump();
    PopScope<Object?> pop() =>
        tester.widget<PopScope<Object?>>(find.byType(PopScope<Object?>).last);
    expect(pop().canPop, isFalse);
    // The Android back, and the header's arrow, which goes the same way.
    pop().onPopInvokedWithResult?.call(false, null);
    await tester.pumpAndSettle();
    expect(find.text('수정을 그만둘까요?'), findsOneWidget);
    expect(find.text('수정 중인 내용은 저장되지 않고 사라져요.'), findsOneWidget);
    await tester.tap(find.text('계속 수정'));
    await tester.pumpAndSettle();
    expect(opener.editing, isTrue);
    expect(_text(tester, 'pairing'), '치즈');
    unawaited(opener.back());
    await tester.pumpAndSettle();
    await tester.tap(find.text('그만두기'));
    await tester.pumpAndSettle();
    expect(opener.editing, isFalse);
    // Still on the card, read, with the stored words.
    expect(find.byType(TasteCardScreen), findsOneWidget);
    expect(find.text('양갈비 스테이크'), findsOneWidget);
    expect(find.text('치즈'), findsNothing);
  });

  testWidgets('back in edit mode with nothing changed returns to the note '
      'read at once', (tester) async {
    final opener = await _open(tester, notes: _Notes(_filled));
    await _edit(tester, opener);
    tester
        .widget<PopScope<Object?>>(find.byType(PopScope<Object?>).last)
        .onPopInvokedWithResult
        ?.call(false, null);
    await tester.pumpAndSettle();
    expect(find.text('수정을 그만둘까요?'), findsNothing);
    expect(opener.editing, isFalse);
    expect(find.byKey(const ValueKey('taste-card-note-form')), findsNothing);
  });

  testWidgets('음용 방식 is chosen, not typed: it opens its options and shows '
      'what was chosen', (tester) async {
    final opener = await _open(tester, notes: _Notes());
    await _edit(tester, opener);
    final serving = find.byKey(const ValueKey('taste-card-note-serving'));
    expect(
      find.descendant(of: serving, matching: find.byType(EditableText)),
      findsNothing,
    );
    expect(
      find.descendant(of: serving, matching: find.text('선택해 주세요')),
      findsOneWidget,
    );
    await tester.ensureVisible(serving);
    await tester.tap(serving);
    await tester.pumpAndSettle();
    expect(find.text('마신 방식을 모두 골라주세요'), findsOneWidget);
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.tap(find.text('디캔터 사용(디캔팅)'));
    await tester.pump();
    await tester.tap(find.text('완료').last);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: serving, matching: find.text('디캔팅')),
      findsOneWidget,
    );
    expect(opener.dirty, isTrue);
  });

  testWidgets('in edit mode 향, 맛 and 여운 are the questionnaire\'s own '
      'picker and gauges, set to the answers; 완료 keeps a change once', (
    tester,
  ) async {
    final gateway = _Answers();
    final answers = _answersEditor(gateway);
    addTearDown(answers.dispose);
    final opener = await _open(tester, notes: _Notes(), answers: answers);
    await _editWithAnswers(tester, opener);
    expect(find.byType(AromaPicker), findsOneWidget);
    // Every chip of the tab, with no 더보기.
    expect(
      tester.widget<AromaPicker>(find.byType(AromaPicker)).showAll,
      isTrue,
    );
    expect(find.byKey(const ValueKey('aroma-more:0')), findsNothing);
    // 당도 2, 산미 4, 바디 4, 탄닌 5, then the finish's two.
    expect(find.byType(SensoryGaugeRow), findsNWidgets(6));
    final sweetness = tester.widget<SensoryGaugeRow>(
      find.byType(SensoryGaugeRow).first,
    );
    expect(sweetness.level, 2);
    expect(opener.dirty, isFalse);
    final step = find.byKey(const ValueKey('gauge:sweetness:4'));
    await tester.ensureVisible(step);
    await tester.tap(step);
    await tester.pump();
    expect(opener.dirty, isTrue);
    expect(answers.hasPending, isFalse);
    final done = opener.done();
    await tester.pumpAndSettle();
    expect(await done, isTrue);
    expect(answers.hasPending, isTrue);
    expect(
      answers.answersOf('sensory_palate_level'),
      contains('level:sweetness:4:liked'),
    );
    // Sent when the card is shown or left, not by 완료 itself.
    expect(gateway.revisions, 0);
  });

  testWidgets('leaving the form drops what was changed in it', (tester) async {
    final answers = _answersEditor(_Answers());
    addTearDown(answers.dispose);
    final opener = await _open(tester, notes: _Notes(), answers: answers);
    await _editWithAnswers(tester, opener);
    final step = find.byKey(const ValueKey('gauge:sweetness:4'));
    await tester.ensureVisible(step);
    await tester.tap(step);
    await tester.pump();
    opener.endEditing();
    await tester.pumpAndSettle();
    expect(answers.hasPending, isFalse);
    expect(find.byType(AromaPicker), findsNothing);
  });

  testWidgets('수정 turns the whole note into one form', (tester) async {
    final opener = await _open(
      tester,
      notes: _Notes(_filled),
      prices: _Prices(const RecordPrice(amount: 89000, place: '와인샵')),
    );
    await _edit(tester, opener);
    expect(opener.editing, isTrue);
    expect(find.byKey(const ValueKey('taste-card-note-form')), findsOneWidget);
    expect(_text(tester, 'purchased_on'), '2026.09.01');
    expect(_text(tester, 'price'), '89,000');
    expect(_text(tester, 'overall'), '진한 시라');
    expect(opener.dirty, isFalse);
    await tester.enterText(_box('pairing'), '치즈');
    await tester.pump();
    expect(opener.dirty, isTrue);
  });

  testWidgets('a wrong box stops 완료: one notice, edged in red and '
      'focused; writing in it clears its red', (tester) async {
    final notes = _Notes();
    final opener = await _open(tester, notes: notes);
    await _edit(tester, opener);
    await tester.enterText(_box('purchased_on'), '어제');
    // Leaving the box says nothing.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(_red(tester, 'purchased_on'), isFalse);
    final done = opener.done();
    await tester.pumpAndSettle();
    expect(await done, isFalse);
    expect(opener.editing, isTrue);
    expect(notes.saves, isEmpty);
    expect(find.text('정보를 올바르게 입력해 주세요.'), findsOneWidget);
    expect(_red(tester, 'purchased_on'), isTrue);
    expect(
      tester.widget<EditableText>(_box('purchased_on')).focusNode.hasFocus,
      isTrue,
    );
    await tester.enterText(_box('purchased_on'), '200115');
    await tester.pump();
    expect(_red(tester, 'purchased_on'), isFalse);
  });

  testWidgets('read, the stars show under the drink\'s line, a half for a '
      'half, with no number', (tester) async {
    await _open(tester, notes: _Notes({'rating': '4.5'}));
    final stars = find.byKey(const ValueKey('taste-card-note-rating'));
    expect(stars, findsOneWidget);
    Finder icon(AppIconAsset star) =>
        find.descendant(of: stars, matching: findAppIcon(star));
    expect(icon(AppIconAsset.starFill), findsNWidgets(4));
    expect(icon(AppIconAsset.starHalf), findsOneWidget);
    expect(find.text('4.5'), findsNothing);
  });

  testWidgets('재음용 의사 reads in the questionnaire\'s words, and its sheet '
      'offers the questionnaire\'s answers in its order', (tester) async {
    // The card says 무난 for "would accept again", which the questionnaire
    // calls 애매해요.
    final opener = await _open(tester, notes: _Notes());
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('taste-card-note-revisit')),
        matching: find.text('애매해요'),
      ),
      findsOneWidget,
    );
    expect(find.text('무난'), findsNothing);
    final answers = _answersEditor(_Answers());
    addTearDown(answers.dispose);
    final withAnswers = await _open(tester, notes: _Notes(), answers: answers);
    await _editWithAnswers(tester, withAnswers);
    final box = find.byKey(const ValueKey('taste-card-note-revisit'));
    await tester.ensureVisible(box);
    await tester.tap(box);
    await tester.pumpAndSettle();
    final labels = [
      for (final (_, label) in RevisitQuestion.recordOptions) label,
    ];
    expect(labels, ['있음', '애매해요', '없음']);
    final tops = [
      for (final label in labels) tester.getTopLeft(find.text(label).last).dx,
    ];
    expect(tops, orderedEquals([...tops]..sort()));
    expect(opener.editing, isFalse);
  });

  testWidgets('a skipped 재음용 의사 reads 애매해요, and its sheet opens with '
      '애매해요 chosen', (tester) async {
    Finder inRevisit(String text) => find.descendant(
      of: find.byKey(const ValueKey('taste-card-note-revisit')),
      matching: find.text(text),
    );
    // The word the server writes for a skipped question, and the word a
    // phone kept from before it was changed.
    for (final word in ['애매해요', '모르겠음']) {
      await _open(tester, notes: _Notes(), revisit: word);
      expect(inRevisit('애매해요'), findsOneWidget, reason: word);
      expect(find.text('모르겠음'), findsNothing, reason: word);
    }

    final answers = _answersEditor(_Answers(revisit: 'revisit:unsure'));
    addTearDown(answers.dispose);
    final opener = await _open(
      tester,
      notes: _Notes(),
      answers: answers,
      revisit: '애매해요',
    );
    await _editWithAnswers(tester, opener);
    final box = find.byKey(const ValueKey('taste-card-note-revisit'));
    expect(
      find.descendant(of: box, matching: find.text('애매해요')),
      findsOneWidget,
    );
    await tester.ensureVisible(box);
    await tester.tap(box);
    await tester.pumpAndSettle();
    FontWeight? weight(RevisitIntent intent) => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(
              ValueKey('taste-card-note-option-revisit-${intent.name}'),
            ),
            matching: find.byType(Text),
          ),
        )
        .style
        ?.fontWeight;
    expect(weight(RevisitIntent.wouldAcceptAgain), FontWeight.w700);
    expect(weight(RevisitIntent.wantAgain), isNot(FontWeight.w700));
    // 완료 on the answer shown answers nothing again: the skipped question
    // stays as it is stored.
    final done = find.byKey(const ValueKey('taste-card-note-revisit-done'));
    await tester.tap(done);
    await tester.pumpAndSettle();
    expect(opener.dirty, isFalse);
    // Another answer is one.
    await tester.tap(box);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('taste-card-note-option-revisit-wantAgain')),
    );
    await tester.pump();
    await tester.tap(done);
    await tester.pumpAndSettle();
    expect(opener.dirty, isTrue);
    expect(find.descendant(of: box, matching: find.text('있음')), findsOneWidget);
  });

  // The app draws every screen at appTextScale, whatever the phone says.
  for (final scale in [1.0, appTextScale]) {
    testWidgets('read at text scale $scale: long aroma names stay whole on '
        'one line, and a gauge\'s end words stay inside the bar', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final notes = _Notes();
      // Narrow, as the smallest phones are, so long names are tested.
      const names = ['블랙베리', '오크', '라즈베리', '바닐라', '장미'];
      await _open(tester, notes: notes, width: 360, nose: names);
      expect(tester.takeException(), isNull);
      // At their own widths, left to right: a line holds what fits, four at
      // most, and nothing reaches past the line.
      Rect rect(String name) =>
          tester.getRect(find.textContaining(name, findRichText: true).first);
      final lines = <double, List<Rect>>{};
      for (final name in names) {
        lines.putIfAbsent(rect(name).top, () => <Rect>[]).add(rect(name));
      }
      final right = tester
          .getRect(find.byKey(const ValueKey('taste-card-note-nose')))
          .right;
      for (final line in lines.values) {
        expect(line.length, lessThanOrEqualTo(4));
        for (final item in line) {
          expect(item.right, lessThanOrEqualTo(right));
        }
      }
      expect(lines.values.first.length, greaterThan(1));
      // Every aroma name is drawn on one line.
      for (final name in names) {
        final found = find.textContaining(name, findRichText: true);
        if (found.evaluate().isEmpty) continue;
        final painted = tester.renderObject<RenderParagraph>(found.first);
        expect(painted.size.height, lessThan(30 * scale), reason: name);
        expect(painted.didExceedMaxLines, isFalse, reason: name);
      }
      // The end words of the long finish gauge stay within its bar.
      final bar = find.byKey(const ValueKey('taste-card-note-step-끝맛의 인상'));
      final barRect = tester.getRect(bar);
      for (final word in ['드라이·\u200B미네랄', '과실·\u200B오크 풍미']) {
        final rect = tester.getRect(find.text(word));
        expect(
          rect.left,
          greaterThanOrEqualTo(barRect.left - .5),
          reason: word,
        );
        expect(rect.right, lessThanOrEqualTo(barRect.right + .5), reason: word);
      }
    });
  }

  testWidgets('aroma names that fit share a line, four at most', (
    tester,
  ) async {
    const names = ['블랙베리', '오크', '라즈베리', '바닐라', '장미'];
    await _open(tester, notes: _Notes(), width: 800, nose: names);
    double top(String name) => tester
        .getTopLeft(find.textContaining(name, findRichText: true).first)
        .dy;
    for (final name in names.take(4)) {
      expect(top(name), top(names.first), reason: name);
    }
    expect(top(names.last), greaterThan(top(names.first)));
  });

  testWidgets('no rating, no stars when read', (tester) async {
    await _open(tester, notes: _Notes());
    expect(find.byKey(const ValueKey('taste-card-note-rating')), findsNothing);
  });

  testWidgets('in edit mode the rating is a number box: 3.50 is kept as '
      '3.5, emptied it clears', (tester) async {
    final notes = _Notes({'rating': '2'});
    final opener = await _open(tester, notes: notes);
    await _edit(tester, opener);
    expect(findAppIcon(AppIconAsset.starFill), findsNothing);
    expect(_text(tester, 'rating'), '2.0');
    await tester.enterText(_box('rating'), '3.50');
    final saved = opener.done();
    await tester.pumpAndSettle();
    expect(await saved, isTrue);
    expect(notes.saves.single, {'rating': '3.5'});
    // Read again: the stars, a half for the half.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('taste-card-note-rating')),
        matching: findAppIcon(AppIconAsset.starHalf),
      ),
      findsOneWidget,
    );
    await _edit(tester, opener);
    await tester.enterText(_box('rating'), '');
    final cleared = opener.done();
    await tester.pumpAndSettle();
    expect(await cleared, isTrue);
    expect(notes.saves.last, {'rating': null});
  });

  testWidgets('a rating off the half steps is wrong at 완료, and the topmost '
      'wrong box is focused', (tester) async {
    final notes = _Notes();
    final opener = await _open(tester, notes: notes);
    await _edit(tester, opener);
    await tester.enterText(_box('rating'), '3.3');
    await tester.enterText(_box('purchased_on'), '어제');
    final done = opener.done();
    await tester.pumpAndSettle();
    expect(await done, isFalse);
    expect(notes.saves, isEmpty);
    expect(find.text('정보를 올바르게 입력해 주세요.'), findsOneWidget);
    expect(_red(tester, 'rating'), isTrue);
    expect(_red(tester, 'purchased_on'), isTrue);
    expect(
      tester.widget<EditableText>(_box('rating')).focusNode.hasFocus,
      isTrue,
    );
  });

  testWidgets('the form has no 마신 날짜 and hints at what each box takes', (
    tester,
  ) async {
    final opener = await _open(tester, notes: _Notes());
    await _edit(tester, opener);
    expect(find.text('마신 날짜'), findsNothing);
    for (final hint in [
      '예) 2026.09.01',
      '예) 3.5',
      '예) 50,000',
      '예) 와인샵',
      '예) 친구와 집에서',
      '예) 스테이크, 치즈',
      '선택해 주세요',
    ]) {
      expect(find.text(hint), findsWidgets, reason: hint);
    }
  });

  testWidgets('완료 keeps everything at once and the note is read again', (
    tester,
  ) async {
    final notes = _Notes();
    final prices = _Prices();
    final memo = _Memo();
    final opener = await _open(
      tester,
      notes: notes,
      prices: prices,
      memo: memo,
    );
    await _edit(tester, opener);
    await tester.enterText(_box('purchased_on'), '200115');
    await tester.enterText(_box('pairing'), ' 양갈비 ');
    await tester.enterText(_box('price'), '80000');
    expect(_text(tester, 'price'), '80,000');
    await tester.enterText(_box('purchase-place'), '와인샵');
    await tester.enterText(_box('overall'), '또 마실래요');
    late bool saved;
    await tester.runAsync(() async => saved = await opener.done());
    await tester.pumpAndSettle();
    expect(saved, isTrue);
    expect(notes.saves.single, {
      'purchased_on': '2020-01-15',
      'pairing': '양갈비',
    });
    expect(prices.saves.single, (80000, '와인샵'));
    expect(memo.saves.single, '또 마실래요');
    expect(opener.editing, isFalse);
    expect(find.byKey(const ValueKey('taste-card-note-form')), findsNothing);
    expect(find.text('2020.01.15'), findsOneWidget);
    expect(find.text('수정한 내용을 저장했어요.'), findsOneWidget);
  });

  testWidgets('a save that fails keeps the form and says so', (tester) async {
    final notes = _Notes()..fail = true;
    final opener = await _open(tester, notes: notes);
    await _edit(tester, opener);
    await tester.enterText(_box('pairing'), '치즈');
    late bool saved;
    await tester.runAsync(() async => saved = await opener.done());
    await tester.pumpAndSettle();
    expect(saved, isFalse);
    expect(opener.editing, isTrue);
    expect(find.text('테이스팅 노트를 저장하지 못했어요.'), findsOneWidget);
    expect(find.byKey(const ValueKey('taste-card-note-form')), findsOneWidget);
  });

  testWidgets('the 취향 tab shows a price line only on a priced record', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: HistoryDayCard(
              title: '11월 8일',
              records: <HistoryRecord>[
                _record(
                  'a',
                  price: const RecordPrice(amount: 38000, place: '와인샵'),
                ),
                _record('b'),
              ],
              onOpenCard: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('history-record-price-a')),
      findsOneWidget,
    );
    expect(find.text('구매 정보 : 38,000원 · 와인샵'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('history-record-price-b')),
      findsNothing,
    );
    expect(find.textContaining('+ 입력'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
