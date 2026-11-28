import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/core/errors/connection_failure.dart';
import 'package:soolgyul/src/core/errors/error_report.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/features/records/data/record_note_gateway.dart';
import 'package:soolgyul/src/features/records/presentation/widgets/record_memo_editor.dart';
import 'package:soolgyul/src/features/taste_card/presentation/widgets/record_delete_dialog.dart';
import 'package:soolgyul/src/features/taste_card/presentation/widgets/taste_card_more_action.dart';

const _recordId = '30000000-0000-4000-8000-000000000001';

class _NoteGateway implements RecordNoteGateway {
  _NoteGateway({
    this.stored = '',
    this.failNote = false,
    this.failLoad = false,
  });
  String stored;
  bool failLoad;

  /// What a failed read fails with.
  Object loadFailure = const RecordNoteException('메모를 불러오지 못했어요.');
  bool failNote;
  final notes = <String>[];
  int loads = 0;

  @override
  Future<String> loadNote(String recordId) async {
    expect(recordId, _recordId);
    loads++;
    if (failLoad) throw loadFailure;
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

/// Opens 더보기 and returns once its menu shows.
Future<void> _openMore(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('taste-card-more')));
  await tester.pumpAndSettle();
}

Future<void> _pumpMore(
  WidgetTester tester, {
  VoidCallback? onEdit,
  VoidCallback? onDelete,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          actions: <Widget>[
            TasteCardMoreAction(onEdit: onEdit, onDelete: onDelete),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// A button that opens the 총평 sheet, as the 테이스팅 노트's 총평 line does.
Future<void> _pumpMemo(
  WidgetTester tester, {
  required _NoteGateway notes,
  VoidCallback? onSaved,
}) async {
  final memo = RecordMemoEditor(
    recordId: _recordId,
    gateway: notes,
    onSaved: onSaved,
  );
  addTearDown(memo.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            key: const ValueKey('open-overall'),
            onPressed: () => memo.edit(context, title: '총평'),
            child: const Text('열기'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens the 총평 sheet.
Future<void> _chooseNote(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open-overall')));
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

  group('TasteCardMoreAction', () {
    List<String> labels(WidgetTester tester) => <String>[
      for (final item in tester.widgetList<PopupMenuItem<Object?>>(
        find.byWidgetPredicate((widget) => widget is PopupMenuItem),
      ))
        (tester.widget<Text>(
          find.descendant(
            of: find.byKey(item.key!),
            matching: find.byType(Text),
          ),
        )).data!,
    ];

    testWidgets('the menu holds 수정 and 삭제 in that order, and nothing else', (
      tester,
    ) async {
      var edits = 0;
      var deletes = 0;
      await _pumpMore(tester, onEdit: () => edits++, onDelete: () => deletes++);
      await _openMore(tester);
      expect(labels(tester), ['수정', '삭제']);
      expect(find.textContaining('저장'), findsNothing);
      await tester.tap(find.text('수정'));
      await tester.pumpAndSettle();
      expect(edits, 1);
      await _openMore(tester);
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      expect(deletes, 1);
    });

    testWidgets('a card that cannot be deleted here offers 수정 alone', (
      tester,
    ) async {
      await _pumpMore(tester, onEdit: () {});
      await _openMore(tester);
      expect(labels(tester), ['수정']);
    });
  });

  group('총평 sheet', () {
    testWidgets('without a 총평 the menu offers to write one, which saves it', (
      tester,
    ) async {
      final notes = _NoteGateway();
      var saved = 0;
      await _pumpMemo(tester, notes: notes, onSaved: () => saved++);

      await _chooseNote(tester);
      expect(find.text('총평'), findsOneWidget);
      expect(find.textContaining('취향 분석에 활용'), findsNothing);
      await _saveNote(tester, '  뒤에 달큰함이 남아서 좋았어요  ');

      expect(notes.notes, ['  뒤에 달큰함이 남아서 좋았어요  ']);
      expect(saved, 1);
      // The sheet closes only now, and the reader is told it was saved.
      expect(find.text('총평'), findsNothing);
      expect(find.text('총평을 저장했어요.'), findsOneWidget);
    });

    testWidgets('the keyboard comes up once the note sheet has slid up', (
      tester,
    ) async {
      await _pumpMemo(tester, notes: _NoteGateway());
      await tester.tap(find.byKey(const ValueKey('open-overall')));
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
      await _pumpMemo(tester, notes: notes, onSaved: () => saved++);

      // An unchanged 총평 is not sent again.
      await _chooseNote(tester);
      expect(_noteFieldText(tester), '향이 오래 남았어요');
      await tester.tap(find.byKey(const ValueKey('taste-card-note-save')));
      await tester.pumpAndSettle();
      expect(notes.notes, isEmpty);
      expect(saved, 0);

      // Clearing saves a blank one.
      await _chooseNote(tester);
      await _saveNote(tester, '');
      expect(notes.notes, ['']);
      expect(saved, 1);
      expect(find.text('총평을 지웠어요.'), findsOneWidget);
    });

    testWidgets('a note that failed to load is read again when chosen', (
      tester,
    ) async {
      final notes = _NoteGateway(stored: '다시 읽은 총평', failLoad: true);
      await _pumpMemo(tester, notes: notes);
      await _chooseNote(tester);
      expect(find.text('총평을 불러오지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
      expect(find.byKey(const ValueKey('taste-card-note-field')), findsNothing);

      notes.failLoad = false;
      await _chooseNote(tester);
      expect(notes.loads, 3);
      expect(_noteFieldText(tester), '다시 읽은 총평');
    });

    testWidgets('a note the connection kept from loading says the '
        'connection', (tester) async {
      final notes = _NoteGateway(failLoad: true)
        ..loadFailure = ConnectionFailure('no route');
      await _pumpMemo(tester, notes: notes);
      await _chooseNote(tester);
      expect(
        find.text('네트워크 연결이 불안정해요. 연결을 확인한 뒤 다시 시도해 주세요.'),
        findsOneWidget,
      );
      expect(find.textContaining('총평을 불러오지'), findsNothing);
    });

    testWidgets('a failed note save keeps the sheet open with what was '
        'written, to send again', (tester) async {
      final notes = _NoteGateway(failNote: true);
      await _pumpMemo(tester, notes: notes);
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
    });
  });
}
