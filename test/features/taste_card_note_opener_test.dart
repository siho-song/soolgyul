import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/features/records/data/record_note_gateway.dart';
import 'package:soolgyul/src/features/records/presentation/widgets/record_memo_editor.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_wire_parser.dart';
import 'package:soolgyul/src/features/taste_card/presentation/taste_card_screen.dart';
import 'package:soolgyul/src/features/taste_card/presentation/widgets/taste_card_note_opener.dart';

import '../support/taste_card_envelopes.dart';

class _Notes implements RecordNoteGateway {
  @override
  Future<String> loadNote(String recordId) async => '향이 오래 남았어요';

  @override
  Future<void> saveNote({
    required String recordId,
    required String note,
  }) async {}
}

void main() {
  testWidgets('the ⋮ menu\'s 총평 turns the card to its 테이스팅 노트 and '
      'opens the sheet there', (tester) async {
    tester.view.physicalSize = const Size(402, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final memo = RecordMemoEditor(recordId: 'record', gateway: _Notes());
    final opener = TasteCardNoteOpener();
    addTearDown(memo.dispose);
    addTearDown(opener.dispose);
    final envelope = validEnvelope();
    viewOf(envelope)['note'] = gaugeNoteJson();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: TasteCardScreen(
            viewData: TasteCardWireParser.parseResult(envelope).viewData,
            recordMemo: memo,
            noteOpener: opener,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final noteHead = find
        .byKey(const ValueKey<String>('taste-card-note-head'))
        .hitTestable();
    expect(noteHead, findsNothing);

    opener.open(TasteCardNoteSlot.overall);
    await tester.pumpAndSettle();
    expect(find.text('총평'), findsOneWidget);
    final field = tester.widget<TextFormField>(
      find.descendant(
        of: find.byKey(const ValueKey('taste-card-note-field')),
        matching: find.byType(TextFormField),
      ),
    );
    expect(field.controller!.text, '향이 오래 남았어요');

    // Closed, the sheet leaves the 테이스팅 노트 on screen.
    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('taste-card-note-field')), findsNothing);
    expect(noteHead, findsOneWidget);
  });
}
