import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/core/errors/error_report.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/features/profile/data/liked_cards_gateway.dart';
import 'package:soolgyul/src/features/records/data/record_note_gateway.dart';
import 'package:soolgyul/src/features/records/presentation/widgets/record_memo_editor.dart';
import 'package:soolgyul/src/features/taste_card/presentation/widgets/record_delete_dialog.dart';
import 'package:soolgyul/src/features/taste_card/presentation/widgets/taste_card_like_button.dart';
import 'package:soolgyul/src/features/taste_card/presentation/widgets/taste_card_more_action.dart';
import 'package:soolgyul/src/features/taste_card/presentation/widgets/taste_card_note_opener.dart';

const _recordId = '30000000-0000-4000-8000-000000000001';

class _Likes implements LikedCardsGateway {
  bool liked = false;
  bool failLoad = false;
  bool failWrite = false;
  int writes = 0;
  Completer<void>? pending;
  @override
  Future<bool> isLiked(String id) async {
    if (failLoad) throw StateError('offline');
    return liked;
  }

  @override
  Future<void> like(String id, {DateTime? likedAt}) async {
    writes++;
    if (pending != null) await pending!.future;
    if (failWrite) throw StateError('offline');
    liked = true;
  }

  @override
  Future<void> unlike(String id) async {
    liked = false;
  }

  @override
  Future<LikedCardsPage> fetch({
    String? category,
    bool latestFirst = true,
    int offset = 0,
  }) => throw UnimplementedError();
}

class _NoteGateway implements RecordNoteGateway {
  _NoteGateway({
    this.stored = '',
    this.failNote = false,
    this.failLoad = false,
  });
  String stored;
  bool failLoad;
  bool failNote;
  final notes = <String>[];
  int loads = 0;

  @override
  Future<String> loadNote(String recordId) async {
    expect(recordId, _recordId);
    loads++;
    if (failLoad) throw const RecordNoteException('메모를 불러오지 못했어요.');
    return stored;
  }

  @override
  Future<void> saveNote({
    required String recordId,
    required String note,
  }) async {
    expect(recordId, _recordId);
    if (failNote) throw const RecordNoteException('메모를 저장하지 못했어요.');
    notes.add(note);
    stored = note;
  }
}

final _likeButton = find.byKey(const ValueKey('taste-card-like-button'));

Future<void> _pumpLike(WidgetTester tester, _Likes likes) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          actions: <Widget>[
            TasteCardLikeButton(cardId: 'card', gateway: likes),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpMore(
  WidgetTester tester, {
  _NoteGateway? notes,
  VoidCallback? onSaved,
  TasteCardNoteOpener? opener,
  VoidCallback? onDelete,
}) async {
  final memo = notes == null
      ? null
      : RecordMemoEditor(recordId: _recordId, gateway: notes, onSaved: onSaved);
  addTearDown(() => memo?.dispose());
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        appBar: AppBar(
          actions: <Widget>[
            TasteCardMoreAction(
              recordId: _recordId,
              recordMemo: memo,
              noteOpener: opener,
              onDelete: onDelete,
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _menuNote = find.byKey(const ValueKey('taste-card-menu-overall'));
final _menuDelete = find.byKey(const ValueKey('taste-card-menu-delete'));

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('taste-card-more')));
  await tester.pumpAndSettle();
}

/// Opens 더보기 and chooses 총평.
Future<void> _chooseNote(WidgetTester tester) async {
  await _openMenu(tester);
  await tester.tap(_menuNote);
  await tester.pumpAndSettle();
}

String _noteFieldText(WidgetTester tester) => tester
    .widget<TextFormField>(
      find.descendant(
        of: find.byKey(const ValueKey('taste-card-note-field')),
        matching: find.byType(TextFormField),
      ),
    )
    .controller!
    .text;

Future<void> _saveNote(WidgetTester tester, String note) async {
  await tester.enterText(
    find.byKey(const ValueKey('taste-card-note-field')),
    note,
  );
  await tester.tap(find.byKey(const ValueKey('taste-card-note-save')));
  await tester.pumpAndSettle();
}

void main() {
  group('RecordDeleteDialog', () {
    testWidgets('a delete that throws leaves the popup to try again', (
      tester,
    ) async {
      final reported = <String>[];
      addTearDown(captureErrorReports((_, _, where) => reported.add(where)));
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => RecordDeleteDialog(
                  onDelete: () async {
                    calls += 1;
                    if (calls == 1) throw StateError('gone');
                  },
                ),
              ),
              child: const Text('열기'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      const confirm = ValueKey<String>('record-delete-confirm');

      await tester.tap(find.byKey(confirm));
      await tester.pumpAndSettle();
      expect(reported, <String>['card delete']);
      expect(find.byType(RecordDeleteDialog), findsOneWidget);

      await tester.tap(find.byKey(confirm));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.byType(RecordDeleteDialog), findsNothing);
    });
  });

  group('TasteCardLikeButton', () {
    testWidgets(
      'adds and cancels after server confirmation; blocks duplicate taps',
      (tester) async {
        final likes = _Likes()..pending = Completer<void>();
        await _pumpLike(tester, likes);
        await tester.tap(find.byTooltip('보관하기'));
        await tester.pump();
        await tester.tap(_likeButton, warnIfMissed: false);
        expect(likes.writes, 1);
        expect(find.byTooltip('보관 취소'), findsNothing);
        likes.pending!.complete();
        await tester.pumpAndSettle();
        expect(find.byTooltip('보관 취소'), findsOneWidget);
        expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
        // The reader is told where the card went; cancelling says nothing
        // and takes that notice down.
        const kept = '보관한 술결 카드에 담았어요. 마이페이지에서 다시 볼 수 있어요.';
        expect(find.text(kept), findsOneWidget);
        await tester.tap(find.byTooltip('보관 취소'));
        await tester.pumpAndSettle();
        expect(find.text(kept), findsNothing);
        expect(likes.liked, isFalse);
        expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      },
    );

    testWidgets('load can retry and failed mutation preserves state', (
      tester,
    ) async {
      final likes = _Likes()..failLoad = true;
      await _pumpLike(tester, likes);
      expect(find.byTooltip('보관 상태 다시 확인'), findsOneWidget);
      likes.failLoad = false;
      await tester.tap(find.byTooltip('보관 상태 다시 확인'));
      await tester.pumpAndSettle();
      likes.failWrite = true;
      await tester.tap(find.byTooltip('보관하기'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('보관하기'), findsOneWidget);
      expect(find.text('좋아요를 변경하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
    });
  });

  group('TasteCardMoreAction', () {
    testWidgets('without a 총평 the menu offers to write one, which saves it', (
      tester,
    ) async {
      final notes = _NoteGateway();
      var saved = 0;
      await _pumpMore(tester, notes: notes, onSaved: () => saved++);

      await _openMenu(tester);
      expect(find.text('총평 남기기'), findsOneWidget);
      expect(_menuDelete, findsNothing);
      await tester.tap(_menuNote);
      await tester.pumpAndSettle();
      expect(find.text('총평'), findsOneWidget);
      expect(find.textContaining('취향 분석에 활용'), findsNothing);
      await _saveNote(tester, '  뒤에 달큰함이 남아서 좋았어요  ');

      expect(notes.notes, ['  뒤에 달큰함이 남아서 좋았어요  ']);
      expect(saved, 1);
      // The sheet closes only now, and the reader is told it was saved.
      expect(find.text('총평'), findsNothing);
      expect(find.text('총평을 저장했어요.'), findsOneWidget);
      await _openMenu(tester);
      expect(find.text('총평 수정'), findsOneWidget);
    });

    testWidgets('the keyboard comes up once the note sheet has slid up', (
      tester,
    ) async {
      await _pumpMore(tester, notes: _NoteGateway());
      await _openMenu(tester);
      await tester.tap(_menuNote);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      EditableTextState field() => tester.state<EditableTextState>(
        find.descendant(
          of: find.byKey(const ValueKey('taste-card-note-field')),
          matching: find.byType(EditableText),
        ),
      );
      // Still sliding up: no focus, so no keyboard yet.
      expect(field().widget.focusNode.hasFocus, isFalse);

      await tester.pumpAndSettle();
      expect(field().widget.focusNode.hasFocus, isTrue);
    });

    testWidgets('총평 수정 opens the sheet with the 총평 in it', (tester) async {
      final notes = _NoteGateway(stored: '향이 오래 남았어요');
      var saved = 0;
      await _pumpMore(tester, notes: notes, onSaved: () => saved++);

      // An unchanged 총평 is not sent again.
      await _openMenu(tester);
      expect(find.text('총평 수정'), findsOneWidget);
      await tester.tap(_menuNote);
      await tester.pumpAndSettle();
      expect(_noteFieldText(tester), '향이 오래 남았어요');
      await tester.tap(find.byKey(const ValueKey('taste-card-note-save')));
      await tester.pumpAndSettle();
      expect(notes.notes, isEmpty);
      expect(saved, 0);

      // Clearing saves a blank one, and the menu offers a new one.
      await _chooseNote(tester);
      await _saveNote(tester, '');
      expect(notes.notes, ['']);
      expect(saved, 1);
      expect(find.text('총평을 지웠어요.'), findsOneWidget);
      await _openMenu(tester);
      expect(find.text('총평 남기기'), findsOneWidget);
    });

    testWidgets('with the card\'s note to go to, 총평 and 구매 정보 open '
        'nothing here', (tester) async {
      final opener = TasteCardNoteOpener();
      addTearDown(opener.dispose);
      final asked = <TasteCardNoteSlot?>[];
      opener.addListener(() => asked.add(opener.take()));
      await _pumpMore(tester, notes: _NoteGateway(), opener: opener);

      await _chooseNote(tester);
      expect(asked, [TasteCardNoteSlot.overall]);
      expect(find.byKey(const ValueKey('taste-card-note-field')), findsNothing);
    });

    testWidgets('a note that failed to load is read again when chosen', (
      tester,
    ) async {
      final notes = _NoteGateway(stored: '다시 읽은 총평', failLoad: true);
      await _pumpMore(tester, notes: notes);
      await _chooseNote(tester);
      expect(find.text('총평을 불러오지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
      expect(find.byKey(const ValueKey('taste-card-note-field')), findsNothing);

      notes.failLoad = false;
      await _chooseNote(tester);
      expect(notes.loads, 3);
      expect(_noteFieldText(tester), '다시 읽은 총평');
    });

    testWidgets('a failed note save keeps the sheet open with what was '
        'written, to send again', (tester) async {
      final notes = _NoteGateway(failNote: true);
      await _pumpMore(tester, notes: notes);
      await _chooseNote(tester);
      await _saveNote(tester, '저장되지 않는 메모');
      // The sheet stays, the text in its field and the reason under it.
      expect(find.text('총평'), findsOneWidget);
      expect(_noteFieldText(tester), '저장되지 않는 메모');
      expect(find.text('메모를 저장하지 못했어요.'), findsOneWidget);
      expect(find.text('총평을 저장했어요.'), findsNothing);

      // 완료 again sends the same text once the save goes through.
      notes.failNote = false;
      await tester.tap(find.byKey(const ValueKey('taste-card-note-save')));
      await tester.pumpAndSettle();
      expect(notes.notes, ['저장되지 않는 메모']);
      expect(find.text('총평'), findsNothing);
      expect(find.text('총평을 저장했어요.'), findsOneWidget);
      await _openMenu(tester);
      expect(find.text('총평 수정'), findsOneWidget);
    });

    testWidgets('삭제 is offered only with a delete action', (tester) async {
      var deletes = 0;
      await _pumpMore(tester, onDelete: () => deletes++);
      await _openMenu(tester);
      expect(_menuNote, findsNothing);
      await tester.tap(_menuDelete);
      await tester.pumpAndSettle();
      expect(deletes, 1);
    });
  });
}
