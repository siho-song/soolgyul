import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/core/errors/error_report.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/features/profile/data/liked_cards_gateway.dart';
import 'package:soolgyul/src/features/records/data/record_note_gateway.dart';
import 'package:soolgyul/src/features/taste_card/presentation/widgets/record_delete_dialog.dart';
import 'package:soolgyul/src/features/taste_card/presentation/widgets/taste_card_like_button.dart';
import 'package:soolgyul/src/features/taste_card/presentation/widgets/taste_card_more_action.dart';

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
  final bool failNote;
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
  VoidCallback? onDelete,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        appBar: AppBar(
          actions: <Widget>[
            TasteCardMoreAction(
              recordId: _recordId,
              noteGateway: notes,
              onNoteSaved: onSaved,
              onDelete: onDelete,
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _menuNote = find.byKey(const ValueKey('taste-card-menu-note'));
final _menuDelete = find.byKey(const ValueKey('taste-card-menu-delete'));

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('taste-card-more')));
  await tester.pumpAndSettle();
}

/// Opens 더보기 and chooses the note item.
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
        await tester.tap(find.byTooltip('보관 취소'));
        await tester.pumpAndSettle();
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
    testWidgets('without a note the menu offers 메모 작성, which saves one', (
      tester,
    ) async {
      final notes = _NoteGateway();
      var saved = 0;
      await _pumpMore(tester, notes: notes, onSaved: () => saved++);

      await _openMenu(tester);
      expect(find.text('메모 남기기'), findsOneWidget);
      expect(_menuDelete, findsNothing);
      await tester.tap(_menuNote);
      await tester.pumpAndSettle();
      expect(find.text('한 줄 메모'), findsOneWidget);
      expect(find.textContaining('취향 분석에 활용'), findsNothing);
      await _saveNote(tester, '  뒤에 달큰함이 남아서 좋았어요  ');

      expect(notes.notes, ['  뒤에 달큰함이 남아서 좋았어요  ']);
      expect(saved, 1);
      await _openMenu(tester);
      expect(find.text('메모 보기'), findsOneWidget);
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

    testWidgets('메모 보기 opens the balloon and 수정 edits the note', (
      tester,
    ) async {
      final notes = _NoteGateway(stored: '향이 오래 남았어요');
      var saved = 0;
      await _pumpMore(tester, notes: notes, onSaved: () => saved++);

      await _openMenu(tester);
      expect(find.text('메모 보기'), findsOneWidget);
      await tester.tap(_menuNote);
      await tester.pumpAndSettle();
      expect(find.text('남긴 메모'), findsOneWidget);
      expect(find.text('향이 오래 남았어요'), findsOneWidget);

      // 수정 closes the balloon and opens the sheet with the note in it; an
      // unchanged note is not sent again.
      await tester.tap(find.byKey(const ValueKey('term-tooltip-action')));
      await tester.pumpAndSettle();
      expect(find.text('남긴 메모'), findsNothing);
      expect(_noteFieldText(tester), '향이 오래 남았어요');
      await tester.tap(find.byKey(const ValueKey('taste-card-note-save')));
      await tester.pumpAndSettle();
      expect(notes.notes, isEmpty);
      expect(saved, 0);

      // Clearing saves a blank note, and the menu offers a new one.
      await _chooseNote(tester);
      await tester.tap(find.byKey(const ValueKey('term-tooltip-action')));
      await tester.pumpAndSettle();
      await _saveNote(tester, '');
      expect(notes.notes, ['']);
      expect(saved, 1);
      await _openMenu(tester);
      expect(find.text('메모 남기기'), findsOneWidget);
    });

    testWidgets('a note that failed to load is read again when chosen', (
      tester,
    ) async {
      final notes = _NoteGateway(stored: '다시 읽은 메모', failLoad: true);
      await _pumpMore(tester, notes: notes);
      await _chooseNote(tester);
      expect(find.text('메모를 불러오지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
      expect(find.byKey(const ValueKey('taste-card-note-field')), findsNothing);

      notes.failLoad = false;
      await _chooseNote(tester);
      expect(notes.loads, 3);
      expect(find.text('다시 읽은 메모'), findsOneWidget);
    });

    testWidgets('a failed note save keeps the previous note and reports it', (
      tester,
    ) async {
      await _pumpMore(tester, notes: _NoteGateway(failNote: true));
      await _chooseNote(tester);
      await _saveNote(tester, '저장되지 않는 메모');
      expect(find.text('메모를 저장하지 못했어요.'), findsOneWidget);
      await _openMenu(tester);
      expect(find.text('메모 남기기'), findsOneWidget);
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
