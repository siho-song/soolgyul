import 'dart:convert';
import 'package:soolgyul/src/core/errors/error_report.dart';
import 'package:soolgyul/src/core/errors/connection_failure.dart';
import 'package:soolgyul/src/core/ids.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:soolgyul/src/app/state/taste_card_flow_state.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/onboarding_aroma_menu.dart';
import 'package:soolgyul/src/features/onboarding/data/sensory_questionnaire_data.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_answers_gateway.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_note_redraw.dart';
import 'package:soolgyul/src/features/taste_card/presentation/widgets/taste_card_answers_editor.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_snapshot_view_data.dart';
import 'package:soolgyul/src/features/taste_card/data/supabase_taste_card_gateway.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_gateway.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_wire_parser.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_wire_requests.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_result.dart';
import 'package:soolgyul/src/features/taste_card/presentation/taste_card_screen.dart';
import 'package:soolgyul/src/widgets/level_gauge.dart';
import 'package:soolgyul/src/widgets/step_scale.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/memory_saved_views.dart';
import '../support/sensory_fixtures.dart';
import '../support/taste_card_envelopes.dart';

void main() {
  group('TasteCard wire', () {
    test(
      'parses the exact final envelope without interpreting opaque refs',
      () {
        final outcome = TasteCardWireParser.parseCreateResponse(
          <String, Object?>{'state': 'final', 'result': _anonymousEnvelope()},
        );

        expect(outcome, isA<TasteCardFinalOutcome>());
        final result = (outcome as TasteCardFinalOutcome).result;
        expect(result.resultId, '20000000-0000-4000-8000-000000000002');
        expect(result.snapshotRef, 'snapshot-v3');
        expect(result.ownership, TasteCardOwnership.anonymous);
        expect(result.pendingConversion?.conversionToken, 'opaque-token');
      },
    );

    test(
      'parses retryable response and preserves the server retry interval',
      () {
        final outcome =
            TasteCardWireParser.parseCreateResponse(<String, Object?>{
              'state': 'retryable',
              'idempotency_key': '20000000-0000-4000-8000-000000000001',
              'attempt_ref': 'attempt-one',
              'error_code': 'catalog_unavailable',
              'retry_after_ms': 1500,
            });

        final retryable = outcome as TasteCardRetryableOutcome;
        expect(retryable.error, TasteCardRetryError.catalogUnavailable);
        expect(retryable.retryAfter, const Duration(milliseconds: 1500));
      },
    );

    test('fails closed for bad timestamps', () {
      final badTimestamp = _copy(_anonymousEnvelope())
        ..['created_at'] = 'today';
      expect(
        () => TasteCardWireParser.parseResult(badTimestamp),
        throwsA(isA<TasteCardWireException>()),
      );
    });

    test(
      'a drink entered by name is refused: the old key and mode fail closed',
      () {
        final oldKey = _copy(_anonymousEnvelope());
        (oldKey['alcohol_identification']
                as Map<String, Object?>)['entered_alcohol_name'] =
            null;
        expect(
          () => TasteCardWireParser.parseResult(oldKey),
          throwsA(
            isA<TasteCardWireException>().having(
              (error) => error.code,
              'code',
              'entered_alcohol_name_removed',
            ),
          ),
        );

        final oldMode = _copy(_anonymousEnvelope());
        oldMode['alcohol_identification'] = <String, Object?>{
          'mode': 'direct_input',
          'alcohol_item_id': null,
          'alcohol_name_snapshot': '테스트 술',
          'category': null,
        };
        expect(
          () => TasteCardWireParser.parseResult(oldMode),
          throwsA(
            isA<TasteCardWireException>().having(
              (error) => error.code,
              'code',
              'direct_input_removed',
            ),
          ),
        );
      },
    );

    test('request serialization keeps every nullable field explicit', () {
      final request = CreateTasteCardResultRequest(
        idempotencyKey: '20000000-0000-4000-8000-000000000001',
        anonymousSessionId: 'session-one',
        questionnaireVersion: 'sensory-questionnaire-v2',
        alcoholIdentification: const AlcoholIdentificationInput.catalogMatch(
          alcoholItemId: '30000000-0000-4000-8000-000000000001',
          alcoholNameSnapshot: '테스트 술',
          category: 'sake',
        ),
        answers: const <QuestionnaireAnswerInput>[
          QuestionnaireAnswerInput(
            questionKey: 'q1',
            selectedOptionKeys: <String>['want_again'],
          ),
        ],
      ).toJson();

      expect(request.keys, <String>{
        'idempotency_key',
        'anonymous_session_id',
        'questionnaire_version',
        'alcohol_identification',
        'answers',
        'q7_free_text',
        'photo_asset_id',
      });
      expect(request['q7_free_text'], isNull);
      expect(request['photo_asset_id'], isNull);
    });

    test('generated request identifiers are RFC 4122 UUID v4 values', () {
      final value = createUuidV4();
      expect(
        value,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    });

    test('the shared generator envelope parses and matches the hand-written '
        'one key for key', () {
      // The Deno tests read the same file; a server-side key change lands
      // here before it reaches a phone.
      final fixture = Map<String, Object?>.from(
        jsonDecode(
              File(
                'supabase/functions/_tests/fixtures/taste_card_envelope_v3.json',
              ).readAsStringSync(),
            )
            as Map,
      );

      final result = TasteCardWireParser.parseResult(fixture);
      expect(result.ownership, TasteCardOwnership.anonymous);
      expect(result.pendingConversion?.resultId, result.resultId);
      expect(result.viewData.product.styleLabel, '레드 와인');
      expect(result.viewData.product.abvPercent, 13.5);
      expect(result.viewData.recordedAt, isNotNull);
      expect(result.viewData.bite.tags, hasLength(3));
      // An aroma everyone knows (체리 향) opens nothing; a taste does.
      expect(result.viewData.bite.tags.first.term, isNull);
      expect(result.viewData.bite.tags.last.term, isNotNull);
      expect(result.viewData.bite.guide, isNull);
      expect(result.viewData.bite.next!.lines.single.terms, isNotEmpty);
      expect(result.viewData.positive.single.terms, isNotEmpty);
      expect(result.viewData.note?.originalName, 'Château Margaux');
      // The look the record's note holds, marked on the note's groups.
      expect(
        result.viewData.note!.appearance!.groups.map(
          (group) => (group.field, group.chosenKey),
        ),
        [('appearance', 'ruby'), ('appearance_texture', 'heavy')],
      );

      final handWritten = _anonymousEnvelope();
      // The hand-written card is one stored before the 테이스팅 노트; a card
      // written now carries one, so the generator's own is put on it.
      viewOf(handWritten)['note'] = viewOf(fixture)['note'];
      for (final section in ['positive', 'burden']) {
        for (final paragraph in viewOf(handWritten)[section]! as List) {
          (paragraph as Map<String, Object?>)['terms'] = [termJson('산미')];
        }
      }
      for (final tag in objectAt(viewOf(handWritten), 'bite')['tags'] as List) {
        (tag as Map<String, Object?>)['term'] = termJson('산미');
      }
      // The hand-written card is one stored with a guide; a card written
      // now carries 다음 방향 in its place, and only an explained tag has a
      // term.
      final bite = objectAt(viewOf(handWritten), 'bite');
      bite['guide'] = null;
      bite['next'] = objectAt(viewOf(fixture), 'bite')['next'];
      (bite['tags']! as List).first['term'] = null;
      _expectSameKeys(fixture, handWritten, 'envelope');
    });
  });

  group('a note read without its record (a visitor\'s card, a card just '
      'claimed)', () {
    Map<String, Object?> sentCard() => Map<String, Object?>.from(
      jsonDecode(
            File(
              'supabase/functions/_tests/fixtures/taste_card_envelope_v3.json',
            ).readAsStringSync(),
          )
          as Map,
    );
    List<Map<String, Object?>> lookGroups(Map<String, Object?> envelope) => [
      for (final group
          in objectAt(
                objectAt(viewOf(envelope), 'note'),
                'appearance',
              )['groups']!
              as List)
        group as Map<String, Object?>,
    ];
    Future<void> openNote(
      WidgetTester tester,
      Map<String, Object?> envelope,
    ) async {
      tester.view.physicalSize = const Size(402, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: TasteCardScreen(
              key: UniqueKey(),
              viewData: TasteCardWireParser.parseResult(envelope).viewData,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('taste-card-tab-note')),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows the 색 and 점성 the server marked as chosen, only '
        'read', (tester) async {
      await openNote(tester, sentCard());
      expect(find.text('색'), findsOneWidget);
      expect(find.text('자줏빛'), findsOneWidget);
      expect(find.text('점성'), findsOneWidget);
      expect(find.text('진득하고 오일리함'), findsOneWidget);
      // Only the one chosen of each, and nothing to write in.
      expect(find.text('보랏빛'), findsNothing);
      expect(find.text('가볍고 산뜻함'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('taste-card-note-form')),
        findsNothing,
      );
      expect(find.byType(EditableText), findsNothing);
    });

    testWidgets('shows only what was chosen: one of the two, or neither; a '
        'key that is no option chooses nothing', (tester) async {
      final textureOnly = sentCard();
      lookGroups(textureOnly).first.remove('chosen');
      await openNote(tester, textureOnly);
      expect(find.text('색'), findsNothing);
      expect(find.text('점성'), findsOneWidget);

      final neither = sentCard();
      lookGroups(neither).first['chosen'] = 'mahogany';
      lookGroups(neither).last.remove('chosen');
      await openNote(tester, neither);
      expect(find.text('색'), findsNothing);
      expect(find.text('점성'), findsNothing);
      // The rest of the note is there as before.
      expect(find.text('향'), findsOneWidget);
    });
  });

  group('TasteCardSnapshotViewData', () {
    test('parses the three-part card exactly as the server sends it', () {
      final result = TasteCardWireParser.parseResult(validEnvelope());
      final view = result.viewData;

      expect(view.snapshotRef, 'snapshot-v3');
      expect(view.header.drinkNameSnapshot, '테스트 리슬링');
      expect(view.product.userName, '민지');
      expect(view.product.categoryLabel, '와인');
      expect(view.product.styleLabel, '화이트 와인');
      expect(view.product.abvPercent, 12);

      // A card made before the style and ABV were kept still opens.
      final older = validEnvelope();
      objectAt(viewOf(older), 'product')
        ..remove('style_label')
        ..remove('abv_percent');
      final olderProduct = TasteCardWireParser.parseResult(
        older,
      ).viewData.product;
      expect(olderProduct.styleLabel, isNull);
      expect(olderProduct.abvPercent, isNull);
      expect(view.product.imageReference, isNull);
      expect(view.bite.nickname, '선명한 프루티 러버');
      expect(view.bite.tags, hasLength(3));
      expect(view.bite.tags.first.label, '복숭아향');
      expect(view.bite.tags.last.kind, TasteCardTagKind.less);
      expect(view.bite.summary, isNot(contains('\n')));
      expect(view.bite.brief, '복숭아 향과 산미는 반갑지만, 떫은맛은 아직 조금 버거워요.');
      expect(view.bite.guide!.head, startsWith('떫은맛만 줄인'));
      expect(view.bite.guide!.picks.first.keyword, '바르베라');
      expect(view.bite.guide!.picks.first.country, 'it');
      expect(view.bite.guide!.levels.last.mark, 2);
      expect(view.positive, hasLength(1));
      expect(view.positive.single.answer, '또렷한 과일 향과 깔끔하게 떨어지는 산미');
      expect(view.burden.single.text, contains('매끄러운 촉감'));
      expect(view.balanced, isEmpty);
    });

    test('a stored view has no terms; a served one carries them per word', () {
      final stored = TasteCardWireParser.parseResult(validEnvelope()).viewData;
      expect(stored.positive.single.terms, isEmpty);
      expect(stored.bite.tags.first.term, isNull);

      final envelope = validEnvelope();
      final positive = viewOf(envelope)['positive']! as List<Object?>;
      (positive.single! as Map<String, Object?>)['terms'] = <Object?>[
        termJson('복숭아 향', label: '복숭아', kind: '향', description: '복숭아 향이에요'),
        termJson('산미'),
      ];
      final tags = objectAt(viewOf(envelope), 'bite')['tags'] as List<Object?>;
      (tags[0]! as Map<String, Object?>)['term'] = termJson(
        '복숭아향',
        label: '복숭아',
        kind: '향',
        description: '복숭아 향이에요',
      );
      (tags[1]! as Map<String, Object?>)['term'] = null;
      final served = TasteCardWireParser.parseResult(envelope).viewData;
      expect(
        served.positive.single.terms.map((t) => (t.word, t.label, t.kind)),
        [('복숭아 향', '복숭아', '향'), ('산미', '산미', '맛')],
      );
      expect(served.bite.tags[0].term?.description, '복숭아 향이에요');
      expect(served.bite.tags[1].term, isNull);
      expect(served.bite.tags[2].term, isNull);
    });

    test('the balanced card carries 왜 편안했을까요 paragraphs', () {
      final view = TasteCardWireParser.parseResult(
        validEnvelope(
          withPositive: false,
          withBurden: false,
          withBalanced: true,
        ),
      ).viewData;
      expect(view.positive, isEmpty);
      expect(view.burden, isEmpty);
      expect(view.balanced.single.answer, '산미가 튀지 않고 적당했어요');
    });

    test(
      'a section with nothing to say is empty, and the guide may be null',
      () {
        final view = TasteCardWireParser.parseResult(
          validEnvelope(withPositive: false, guide: null),
        ).viewData;
        expect(view.positive, isEmpty);
        expect(view.burden, hasLength(1));
        expect(view.bite.guide, isNull);
      },
    );

    test('fails closed on the old wire, missing keys and empty text', () {
      void rejects(
        void Function(Map<String, Object?> envelope) mutate,
        String code,
      ) {
        final envelope = validEnvelope();
        mutate(envelope);
        expect(
          () => TasteCardWireParser.parseResult(envelope),
          throwsA(
            isA<TasteCardWireException>().having(
              (error) => error.code,
              'code',
              code,
            ),
          ),
          reason: code,
        );
      }

      rejects(
        (e) => e['wire_schema_version'] = 'taste-card-result-wire-v2',
        'unknown_wire_schema_version',
      );
      rejects((e) => viewOf(e).remove('balanced'), 'missing_fields');
      rejects(
        (e) => objectAt(viewOf(e), 'bite').remove('tags'),
        'missing_fields',
      );
      rejects(
        (e) => objectAt(viewOf(e), 'bite')['summary'] = '',
        'non_empty_string_required',
      );
      rejects(
        (e) => objectAt(viewOf(e), 'bite')['tags'] = '산미',
        'array_required',
      );
      rejects(
        (e) => objectAt(viewOf(e), 'bite')['tags'] = <Object?>[
          <String, Object?>{'label': '', 'kind': 'liked'},
        ],
        'non_empty_string_required',
      );
      rejects(
        (e) => objectAt(viewOf(e), 'bite')['tags'] = <Object?>[
          <String, Object?>{'label': '산미', 'kind': 1},
        ],
        'string_required',
      );
      rejects(
        (e) => e['ownership_state'] = 'shared',
        'unknown_ownership_state',
      );
      rejects(
        (e) => objectAt(viewOf(e), 'bite')['nickname'] = null,
        'string_required',
      );
      rejects(
        (e) => objectAt(viewOf(e), 'metadata')['schema_version'] = 2,
        'schema_version_required',
      );
      rejects(
        (e) => objectAt(viewOf(e), 'metadata')['snapshot_ref'] = 'other',
        'snapshot_ref_mismatch',
      );
      rejects(
        (e) => viewOf(e)['positive'] = <Object?>[
          <String, Object?>{'answer': '답', 'claim_refs': <String>[]},
        ],
        'missing_fields',
      );
      rejects(
        (e) => viewOf(e)['burden'] = <Object?>[
          for (var index = 0; index <= tasteCardMaxParagraphs; index++)
            paragraphJson(answer: '답 $index', text: '설명 $index'),
        ],
        'paragraph_count_invalid',
      );
      rejects(
        (e) => e['ownership_state'] = 'anonymous',
        'conversion_ownership_mismatch',
      );
    });

    test('a display value the app does not know yet is dropped or plainer', () {
      // A server that adds a tag kind, an image source, a drink category
      // or a retry code must not stop an older app's card.
      final envelope = validEnvelope();
      (objectAt(viewOf(envelope), 'bite')['tags']! as List<Object?>).add(
        <String, Object?>{'label': '새 표시', 'kind': 'surprising'},
      );
      objectAt(viewOf(envelope), 'product')['image_reference'] =
          <String, Object?>{'source': 'partner_shop', 'reference': 'photo-1'};
      objectAt(envelope, 'alcohol_identification')['category'] = 'beer';

      final view = TasteCardWireParser.parseResult(envelope).viewData;
      expect(view.bite.tags.map((tag) => tag.label), ['복숭아향', '산미', '떫은맛']);
      expect(view.product.imageReference, isNull);

      final retry = TasteCardWireParser.parseCreateResponse(<String, Object?>{
        'state': 'retryable',
        'idempotency_key': '20000000-0000-4000-8000-000000000001',
        'attempt_ref': 'attempt-one',
        'error_code': 'queue_full',
        'retry_after_ms': null,
      });
      expect(retry, isA<TasteCardRetryableOutcome>());
    });

    test('a field the app does not know yet is left alone', () {
      // A server that adds to the card must not stop an older app's cards
      // from opening.
      final envelope = validEnvelope();
      envelope['added_later'] = 1;
      viewOf(envelope)['next_drink'] = <String, Object?>{};
      objectAt(viewOf(envelope), 'bite')['facts'] = <String, Object?>{};
      ((viewOf(envelope)['positive']! as List<Object?>).single!
              as Map<String, Object?>)['added_later'] =
          '새 항목';
      final view = TasteCardWireParser.parseResult(envelope).viewData;
      expect(view.positive, hasLength(1));
      expect(
        view.bite.summary,
        TasteCardWireParser.parseResult(validEnvelope()).viewData.bite.summary,
      );
    });
  });

  group('테이스팅 노트', () {
    TasteCardNoteViewData parseNote(Map<String, Object?> note) {
      final envelope = validEnvelope();
      viewOf(envelope)['note'] = note;
      return TasteCardWireParser.parseResult(envelope).viewData.note!;
    }

    Map<String, List<String>> groups(List<TasteCardNoteGroupViewData> groups) =>
        <String, List<String>>{
          for (final group in groups)
            group.label: <String>[
              for (final mark in group.marks) '${mark.label}/${mark.felt.name}',
            ],
        };

    /// A row as (the bottle's level, how it was taken, the reader's word,
    /// the step chosen), by its axis.
    Map<String?, (int?, String?, String?, int?)> rows(
      List<TasteCardNoteBalanceViewData> rows,
    ) => <String?, (int?, String?, String?, int?)>{
      for (final row in rows)
        row.key: (row.mark, row.felt?.name, row.said, row.level),
    };

    test('a note written from the gauges reads its flavours, the step of '
        'each row, the finish\'s own rows and the ends of its character', () {
      final note = parseNote(gaugeNoteJson());
      expect(groups(note.flavor!), {
        '마음에 들었어요': ['후추/liked', '바닐라/liked'],
      });
      expect(note.texture, isEmpty);
      expect(rows(note.balance), {
        'sweetness': (1, 'liked', '드라이', 2),
        'acidity': (3, 'liked', '미디엄 하이', 4),
        'body': (4, 'liked', '미디엄 풀', 4),
        'tannin': (4, 'less', '풀 타닌', 5),
      });
      expect(rows(note.finishBalance!), {
        'finish_length': (4, 'liked', '미디엄 롱', 4),
        'finish_character': (null, 'liked', '풍미 중심', 4),
      });
      expect(note.finishBalance!.first.ends, isNull);
      expect(note.finishBalance!.last.ends, ('드라이·미네랄', '과실·오크 풍미'));
      // The finish holds the aromas left, no longer the gauges as marks.
      expect(groups(note.finish), {
        '부담됐어요': ['스모키/burden'],
      });
      expect(note.words!.groups.map((group) => group.label), [
        '마음에 들었어요',
        '부담됐어요',
      ]);
      expect(note.words!.revisit['revisit:wouldAcceptAgain'], '무난');

      // A step or ends this app cannot read are left out; the row stays.
      final odd = gaugeNoteJson();
      final character =
          (odd['finish_balance']! as List).last as Map<String, Object?>;
      character['level'] = 9;
      character['ends'] = <String>['드라이·미네랄'];
      final row = parseNote(odd).finishBalance!.last;
      expect((row.said, row.level, row.ends), ('풍미 중심', null, null));
    });

    test('a note stored before the gauges still reads, with 질감 and no '
        'steps, and is redrawn by nothing', () {
      final note = parseNote(storedNoteJson());
      expect(note.originalName, 'Château Margaux');
      expect(note.flavor, isNull);
      expect(note.finishBalance, isNull);
      expect(groups(note.texture), {
        '부담됐어요': ['떫음/less'],
      });
      expect(groups(note.finish), {
        '부담됐어요': ['텁텁하고 무겁게 남는 느낌/less'],
      });
      expect(rows(note.balance), {
        'sweetness': (1, null, null, null),
        'acidity': (4, 'liked', '또렷해서 좋았어요', null),
        'bitterness': (2, null, null, null),
        'astringency': (4, null, null, null),
      });
      expect(note.revisit, '있음');
      expect(note.words, isNull);
      expect(
        redrawNote(
          note,
          const {
            'sensory_nose_aroma': ['aroma:nose:oak:liked'],
          },
          gauges: gaugesFor('wine', 'red_wine'),
          aromaLabel: sensoryRegistry().aromaLabel,
        ),
        same(note),
      );
    });

    test('a part answered again is redrawn as the server will write it', () {
      final registry = sensoryRegistry();
      final note = parseNote(gaugeNoteJson());
      TasteCardNoteViewData redraw(Map<String, List<String>> pending) =>
          redrawNote(
            note,
            pending,
            gauges: gaugesFor('wine', 'red_wine'),
            aromaLabel: registry.aromaLabel,
          );
      expect(redraw(const {}), same(note));

      // One aroma out and one a burden; 당도 emptied, 산미 too weak, 타닌
      // liked after all; the length too long, the character a burden; the
      // finish's aroma out.
      final redrawn = redraw(const {
        'sensory_revisit': ['revisit:doNotWantAgain'],
        'sensory_nose_aroma': [
          'aroma:nose:black_cherry:liked',
          'aroma:nose:oak:disliked',
        ],
        'sensory_palate_level': [
          'level:acidity:1:disliked',
          'level:body:4:liked',
          'level:tannin:5:liked',
        ],
        'sensory_palate_aroma': [
          'aroma:palate:vanilla:liked',
          'aroma:palate:pepper:disliked',
        ],
        'sensory_finish_level': [
          'level:finish_length:4:disliked',
          'level:finish_character:5:disliked',
        ],
        'sensory_finish_aroma': <String>[],
      });
      expect(groups(redrawn.nose), {
        '마음에 들었어요': ['블랙체리/liked'],
        '부담됐어요': ['오크/burden'],
      });
      // A row keeps the bottle's level and word; one no longer answered
      // says nothing.
      expect(rows(redrawn.balance), {
        'sweetness': (1, null, null, null),
        'acidity': (3, 'more', '로우', 1),
        'body': (4, 'liked', '미디엄 풀', 4),
        'tannin': (4, 'liked', '풀탄닌', 5),
      });
      expect(redrawn.balance.first.word, '드라이');
      expect(groups(redrawn.flavor!), {
        '마음에 들었어요': ['바닐라/liked'],
        '부담됐어요': ['후추/burden'],
      });
      // A burden at a high step is less wanted; between two characters it
      // is only a burden.
      expect(rows(redrawn.finishBalance!), {
        'finish_length': (4, 'less', '미디엄 롱', 4),
        'finish_character': (null, 'burden', '농밀·달콤', 5),
      });
      expect(redrawn.finishBalance!.last.ends, ('드라이·미네랄', '과실·오크 풍미'));
      expect(groups(redrawn.finish), {
        '마음에 들었어요': <String>[],
        '부담됐어요': <String>[],
      });
      expect(redrawn.revisit, '없음');

      // Every part emptied: the rows the bottle has a level for stay,
      // unanswered; the character, which it has none for, goes. The parts
      // not answered again stay as they were.
      final emptied = redraw(const {
        'sensory_nose_aroma': ['nose:unsure'],
        'sensory_palate_level': <String>[],
        'sensory_finish_level': <String>[],
      });
      expect(groups(emptied.nose).values, everyElement(isEmpty));
      expect(rows(emptied.balance), {
        'sweetness': (1, null, null, null),
        'acidity': (3, null, null, null),
        'body': (4, null, null, null),
        'tannin': (4, null, null, null),
      });
      expect(rows(emptied.finishBalance!), {
        'finish_length': (4, null, null, null),
      });
      expect(emptied.flavor, same(note.flavor));
      expect(emptied.finish, same(note.finish));
      expect(emptied.revisit, '무난');
    });

    testWidgets('a card answered on the gauges draws each answered gauge '
        'as its name and the questionnaire bar with the step chosen; an older '
        'card keeps the bottle bars', (tester) async {
      tester.view.physicalSize = const Size(402, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Future<void> open(Map<String, Object?> note) async {
        final envelope = validEnvelope();
        viewOf(envelope)['note'] = note;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: TasteCardScreen(
                key: UniqueKey(),
                viewData: TasteCardWireParser.parseResult(envelope).viewData,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('taste-card-tab-note')),
        );
        await tester.pumpAndSettle();
      }

      Finder within(String section, Finder matching) => find.descendant(
        of: find.byKey(ValueKey<String>('taste-card-note-$section')),
        matching: matching,
      );
      Map<String, Object?> unanswered(String key, String label) =>
          <String, Object?>{
            'key': key,
            'label': label,
            'mark': 2,
            'word': '약한 탄산',
            'felt': null,
            'said': null,
          };

      // The catalog knows the bottle's 탄산감, which the reader left
      // unanswered: it is not listed.
      final gauged = gaugeNoteJson();
      (gauged['balance']! as List).add(unanswered('sparkling', '탄산감'));
      await open(gauged);
      expect(find.byType(LevelGauge), findsNothing);
      // 향, 맛 and 여운 are rows of one section.
      expect(
        find.byKey(const ValueKey<String>('taste-card-note-senses')),
        findsOneWidget,
      );
      for (final (section, label, level) in const [
        ('palate', '당도', 2),
        ('palate', '산미', 4),
        ('palate', '바디감', 4),
        ('palate', '타닌', 5),
        ('finish', '여운의 길이', 4),
        ('finish', '끝맛의 인상', 4),
      ]) {
        // The name, then the questionnaire's bar with the step filled.
        expect(within(section, find.text(label)), findsOneWidget);
        final bar = tester.widget<StepScale>(
          find.byKey(ValueKey<String>('taste-card-note-step-$label')),
        );
        expect(bar.level, level, reason: label);
      }
      // Under a bar served with its ends, those and 보통.
      expect(within('finish', find.text('드라이·\u200B미네랄')), findsOneWidget);
      expect(within('finish', find.text('과실·\u200B오크 풍미')), findsOneWidget);
      expect(within('finish', find.text('보통')), findsOneWidget);
      // Nothing of the bottle's own level, no step count.
      expect(find.text('탄산감'), findsNothing);
      for (final word in const ['중간 산도', '탄탄한 타닌', '약한 탄산']) {
        expect(find.text(word), findsNothing);
      }
      expect(find.textContaining('/5'), findsNothing);
      expect(find.textContaining('↔'), findsNothing);

      // With no gauge answered the part says so, whatever the catalog has.
      final bare = gaugeNoteJson()
        ..['balance'] = <Object?>[unanswered('sparkling', '탄산감')]
        ..['finish_balance'] = <Object?>[];
      await open(bare);
      expect(find.byType(LevelGauge), findsNothing);
      expect(find.text('탄산감'), findsNothing);
      expect(find.text('남긴 기록이 없어요'), findsNWidgets(2));

      // A card answered before the gauges draws the bottle's bars as ever.
      await open(storedNoteJson());
      expect(find.byType(LevelGauge), findsNWidgets(4));
      expect(find.text('탄탄한 타닌'), findsOneWidget);
      expect(
        find.textContaining('또렷해서 좋았어요', findRichText: true),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    test('the answers of a record made under the older questionnaire are '
        'served as not revisable', () {
      final old = TasteCardWireParser.parseAnswers(<String, Object?>{
        'revisable': false,
        'answers': <Object?>[],
      });
      expect(old.revisable, isFalse);
      expect(old.answers, isEmpty);
      final current = TasteCardWireParser.parseAnswers(<String, Object?>{
        'revisable': true,
        'answers': <Object?>[
          <String, Object?>{
            'question_key': 'sensory_nose_aroma',
            'selected_option_keys': <Object?>['nose:unsure'],
          },
        ],
      });
      expect(current.revisable, isTrue);
      expect(current.answers, {
        'sensory_nose_aroma': ['nose:unsure'],
      });
    });

    testWidgets('an old card, whose note has no words, cannot be corrected: '
        'its answers are not read and no flow starts', (tester) async {
      final answers = _StoredAnswers();
      final editor = TasteCardAnswersEditor(
        resultId: 'result',
        gateway: answers,
        loadQuestions: () async => SensoryQuestionnaireData(
          registry: sensoryRegistry(),
          aromaMenu: OnboardingAromaMenu.forDrink('wine', 'red_wine'),
          gauges: gaugesFor('wine', 'red_wine'),
        ),
      );
      addTearDown(editor.dispose);
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (inner) {
                context = inner;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      const refusal = '이 기록은 답을 고칠 수 없어요.';

      final none = await editor.startFlow(context, parseNote(storedNoteJson()));
      await tester.pump();
      expect(none, isNull);
      expect(find.text(refusal), findsOneWidget);
      expect(answers.loads, 0);

      // A card written from the gauges starts a flow with its answers.
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      await tester.pump();
      final flow = await tester.runAsync(
        () => editor.startFlow(context, parseNote(gaugeNoteJson())),
      );
      await tester.pump();
      expect(find.text(refusal), findsNothing);
      expect(answers.loads, 1);
      expect(editor.questions!.registry.readAnswers(flow!), gaugeNoteAnswers);
    });
  });

  group('answers that cannot be read or sent', () {
    TasteCardNoteViewData parseNote(Map<String, Object?> note) {
      final envelope = validEnvelope();
      viewOf(envelope)['note'] = note;
      return TasteCardWireParser.parseResult(envelope).viewData.note!;
    }

    Future<BuildContext> page(WidgetTester tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (inner) {
                context = inner;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      return context;
    }

    TasteCardAnswersEditor editorOver(_StoredAnswers answers) =>
        TasteCardAnswersEditor(
          resultId: 'result',
          gateway: answers,
          loadQuestions: () async => SensoryQuestionnaireData(
            registry: sensoryRegistry(),
            aromaMenu: OnboardingAromaMenu.forDrink('wine', 'red_wine'),
            gauges: gaugesFor('wine', 'red_wine'),
          ),
        );

    testWidgets('a read the connection failed says the connection; any '
        'other failed read the editor\'s own line', (tester) async {
      addTearDown(captureErrorReports((_, _, _) {}));
      for (final (failure, line) in <(Object, String)>[
        (
          ConnectionFailure('no route'),
          '네트워크 연결이 불안정해요. 연결을 확인한 뒤 다시 시도해 주세요.',
        ),
        (StateError('bad row'), '답을 불러오지 못했어요. 다시 시도해 주세요.'),
      ]) {
        final editor = editorOver(_StoredAnswers()..loadFailure = failure);
        addTearDown(editor.dispose);
        final context = await page(tester);
        final flow = await tester.runAsync(
          () => editor.startFlow(context, parseNote(gaugeNoteJson())),
        );
        await tester.pump();
        expect(flow, isNull);
        expect(find.text(line), findsOneWidget, reason: '$failure');
      }
    });

    testWidgets('a card that could not be written again says what it failed '
        'with', (tester) async {
      addTearDown(captureErrorReports((_, _, _) {}));
      final offline = ConnectionFailure('no route');
      final answers = _StoredAnswers()..reviseFailure = offline;
      final editor = editorOver(answers);
      addTearDown(editor.dispose);
      final context = await page(tester);
      await tester.runAsync(
        () => editor.startFlow(context, parseNote(gaugeNoteJson())),
      );
      editor.keep({
        'sensory_revisit': ['revisit:wantAgain'],
      });
      final rewrite = await tester.runAsync(editor.flush);
      expect(rewrite!.status, TasteCardRewriteStatus.failed);
      expect(rewrite.error, same(offline));
      expect(
        TasteCardAnswersEditor.rewriteFailure(rewrite.error),
        '네트워크 연결이 불안정해요. 연결을 확인한 뒤 다시 시도해 주세요.',
      );
      expect(
        TasteCardAnswersEditor.rewriteFailure(StateError('refused')),
        '고친 답을 반영하지 못했어요. 다시 시도해 주세요.',
      );
      // The corrections wait for another try.
      expect(editor.hasPending, isTrue);
    });
  });

  group('SupabaseTasteCardGateway', () {
    late SupabaseClient client;
    late List<http.Request> requests;
    var status = 200;
    Object? reply;

    setUp(() {
      requests = [];
      status = 200;
      reply = validEnvelope();
      client = SupabaseClient(
        'https://example.supabase.co',
        'test-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            reply is String ? reply! as String : jsonEncode(reply),
            status,
            request: request,
            headers: {
              'content-type': reply is String
                  ? 'text/plain'
                  : 'application/json',
            },
          );
        }),
      );
    });
    tearDown(() => client.dispose());

    test('a saved card is fetched by result id and parsed', () async {
      final gateway = SupabaseTasteCardGateway(client);

      final result = await gateway.fetchOwnedResult(
        '20000000-0000-4000-8000-000000000002',
      );

      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/functions/v1/taste-card-results');
      expect(
        requests.single.url.queryParameters['result_id'],
        '20000000-0000-4000-8000-000000000002',
      );
      expect(result.isSaved, isTrue);
      expect(result.snapshotRef, 'snapshot-v3');
    });

    test('an opened card stays on the phone until it is deleted', () async {
      const id = '20000000-0000-4000-8000-000000000002';
      final phone = MemorySavedViews();
      final gateway = SupabaseTasteCardGateway(client, saved: phone);
      expect(await gateway.keptResult(id), isNull);

      final loaded = await gateway.fetchOwnedResult(id);
      await Future<void>.delayed(Duration.zero);
      final kept = await SupabaseTasteCardGateway(
        client,
        saved: phone,
      ).keptResult(id);

      expect(requests, hasLength(1), reason: 'the copy needs no server');
      expect(kept?.resultId, loaded.resultId);
      expect(kept?.snapshotRef, loaded.snapshotRef);

      reply = <String, Object?>{'deleted': true};
      await gateway.deleteOwnedResult(id);
      await Future<void>.delayed(Duration.zero);
      expect(await gateway.keptResult(id), isNull);
    });

    test('a card the server no longer has leaves the phone', () async {
      const id = '20000000-0000-4000-8000-000000000002';
      final phone = MemorySavedViews();
      final gateway = SupabaseTasteCardGateway(client, saved: phone);
      await gateway.fetchOwnedResult(id);
      await Future<void>.delayed(Duration.zero);
      expect(await gateway.keptResult(id), isNotNull);

      status = 404;
      reply = <String, Object?>{'error_code': 'result_not_found'};
      await expectLater(
        gateway.fetchOwnedResult(id),
        throwsA(isA<TasteCardGatewayException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(await gateway.keptResult(id), isNull);
    });

    test('a saved card is deleted by result id', () async {
      final gateway = SupabaseTasteCardGateway(client);
      reply = <String, Object?>{'deleted': true};

      await gateway.deleteOwnedResult('20000000-0000-4000-8000-000000000002');

      expect(requests.single.method, 'DELETE');
      expect(requests.single.url.path, '/functions/v1/taste-card-results');
      expect(
        requests.single.url.queryParameters['result_id'],
        '20000000-0000-4000-8000-000000000002',
      );
    });

    test('a refused delete carries the public code', () async {
      final gateway = SupabaseTasteCardGateway(client);
      status = 403;
      reply = <String, Object?>{'error_code': 'active_account_required'};

      await expectLater(
        gateway.deleteOwnedResult('20000000-0000-4000-8000-000000000002'),
        throwsA(
          isA<TasteCardGatewayException>()
              .having(
                (error) => error.operation,
                'operation',
                TasteCardGatewayOperation.delete,
              )
              .having((error) => error.code, 'code', 'active_account_required'),
        ),
      );
    });

    test('deleting a card that is already gone is a delete', () async {
      // The second of two quick taps, or a retry after a lost answer.
      final gateway = SupabaseTasteCardGateway(client);
      status = 404;
      reply = <String, Object?>{'error_code': 'result_not_found'};

      await gateway.deleteOwnedResult('20000000-0000-4000-8000-000000000002');

      expect(requests.single.method, 'DELETE');
    });

    test(
      '401 becomes a gateway exception that carries the public code',
      () async {
        // The coordinator treats any gateway exception as a failed attempt
        // (retry state); the code is what distinguishes "log in again".
        final gateway = SupabaseTasteCardGateway(client);
        status = 401;
        reply = <String, Object?>{'error_code': 'authorization_required'};

        await expectLater(
          gateway.fetchOwnedResult('20000000-0000-4000-8000-000000000002'),
          throwsA(
            isA<TasteCardGatewayException>()
                .having(
                  (error) => error.operation,
                  'operation',
                  TasteCardGatewayOperation.detail,
                )
                .having(
                  (error) => error.code,
                  'code',
                  'authorization_required',
                ),
          ),
        );
        expect(gateway.isAuthenticated, isFalse);
      },
    );

    test(
      'a body the wire parser refuses surfaces as a wire exception',
      () async {
        final gateway = SupabaseTasteCardGateway(client);
        reply = 'not json';

        await expectLater(
          gateway.convert(
            const AnonymousTasteCardConversionRequest(
              anonymousSessionId: 'anonymous-1',
              resultId: '20000000-0000-4000-8000-000000000002',
              conversionToken: 'opaque-token',
              idempotencyKey: '20000000-0000-4000-8000-000000000003',
            ),
          ),
          throwsA(isA<TasteCardWireException>()),
        );
        expect(
          requests.single.url.path,
          '/functions/v1/taste-card-conversions',
        );
      },
    );
  });

  test(
    'flow rejects double submit and reuses one idempotency key on retry',
    () {
      final state = TasteCardFlowState();
      var next = 0;
      String createId() => 'id-${next++}';

      expect(
        state.beginSubmission(createId: createId, isAuthenticated: false),
        isTrue,
      );
      final firstKey = state.idempotencyKey;
      final firstSession = state.anonymousSessionId;
      expect(
        state.beginSubmission(createId: createId, isAuthenticated: false),
        isFalse,
      );
      state.markRetryable();

      expect(
        state.beginSubmission(createId: createId, isAuthenticated: false),
        isTrue,
      );
      expect(state.idempotencyKey, firstKey);
      expect(state.anonymousSessionId, firstSession);
    },
  );
}

/// The answers the record of [gaugeNoteJson] holds, counting the reads.
class _StoredAnswers implements TasteCardAnswersGateway {
  int loads = 0;

  /// What reading the answers fails with; null reads them.
  Object? loadFailure;

  /// What sending corrections fails with.
  Object reviseFailure = UnimplementedError();

  @override
  Future<TasteCardAnswers> loadAnswers(String resultId) async {
    loads += 1;
    if (loadFailure case final failure?) throw failure;
    return const TasteCardAnswers(revisable: true, answers: gaugeNoteAnswers);
  }

  @override
  Future<TasteCardResult> reviseAnswers(
    String resultId,
    Map<String, List<String>> answers,
  ) => throw reviseFailure;

  @override
  Future<TasteCardResult> fetchOwnedResult(String resultId) =>
      throw UnimplementedError();
}

Map<String, Object?> _anonymousEnvelope() => validEnvelope()
  ..['record_id'] = null
  ..['ownership_state'] = 'anonymous'
  ..['conversion'] = <String, Object?>{
    'anonymous_session_id': 'anonymous-1',
    'conversion_token': 'opaque-token',
  };

Map<String, Object?> _copy(Map<String, Object?> value) {
  return Map<String, Object?>.from(
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>,
  );
}

/// Every object both sides carry has the same keys; lists are compared by
/// their first element, and a value that is an object on one side only
/// (image_reference, a nullable guide) is left to the parser.
void _expectSameKeys(
  Map<Object?, Object?> a,
  Map<Object?, Object?> b,
  String path,
) {
  expect(a.keys.toSet(), b.keys.toSet(), reason: path);
  for (final key in a.keys) {
    final left = a[key];
    final right = b[key];
    if (left is Map && right is Map) {
      _expectSameKeys(left, right, '$path.$key');
    } else if (left is List && right is List) {
      if (left.isNotEmpty && right.isNotEmpty) {
        final first = left.first;
        final second = right.first;
        if (first is Map && second is Map) {
          _expectSameKeys(first, second, '$path.$key[0]');
        }
      }
    }
  }
}
