import 'dart:convert';
import 'package:soolgyul/src/core/ids.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:soolgyul/src/app/state/taste_card_flow_state.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_snapshot_view_data.dart';
import 'package:soolgyul/src/features/taste_card/data/supabase_taste_card_gateway.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_gateway.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_wire_parser.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_wire_requests.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_result.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/taste_card_envelopes.dart';
import '../support/design_taste_card.dart';

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

    test('fails closed for trace fields and bad timestamps', () {
      final traceLeak = _copy(_anonymousEnvelope())
        ..['claim_trace'] = <Object?>[];
      expect(
        () => TasteCardWireParser.parseResult(traceLeak),
        throwsA(isA<TasteCardWireException>()),
      );

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
        questionnaireVersion: 'sensory-questionnaire-v1',
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
      expect(result.viewData.bite.tags.first.term, isNotNull);
      expect(result.viewData.positive.single.terms, isNotEmpty);
      expect(result.viewData.bite.guide?.directions, isNotEmpty);

      final handWritten = _anonymousEnvelope();
      for (final section in ['positive', 'burden']) {
        for (final paragraph in viewOf(handWritten)[section]! as List) {
          (paragraph as Map<String, Object?>)['terms'] = [termJson('산미')];
        }
      }
      for (final tag in objectAt(viewOf(handWritten), 'bite')['tags'] as List) {
        (tag as Map<String, Object?>)['term'] = termJson('산미');
      }
      _expectSameKeys(fixture, handWritten, 'envelope');
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

    test('fails closed on the old wire, unknown keys and empty text', () {
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
      rejects(
        (e) => viewOf(e)['next_drink'] = <String, Object?>{},
        'unexpected_fields',
      );
      rejects((e) => viewOf(e).remove('balanced'), 'unexpected_fields');
      rejects(
        (e) => viewOf(e)['core_summary'] = <String, Object?>{},
        'unexpected_fields',
      );
      rejects(
        (e) => objectAt(viewOf(e), 'bite')['facts'] = <String, Object?>{},
        'unexpected_fields',
      );
      rejects(
        (e) => objectAt(viewOf(e), 'bite')['summary'] = '',
        'non_empty_string_required',
      );
      rejects(
        (e) =>
            ((viewOf(e)['positive']! as List<Object?>).single!
                as Map<String, Object?>)['terms'] = <Object?>[
              <String, Object?>{'word': '산미', 'label': '산미', 'kind': '맛'},
            ],
        'unexpected_fields',
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
          <String, Object?>{'label': '산미', 'kind': 'nope'},
        ],
        'tag_kind_invalid',
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
          <String, Object?>{
            'answer': '답',
            'text': '설명',
            'claim_refs': <String>[],
          },
        ],
        'unexpected_fields',
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

    test('the design fixture is a complete three-part card', () {
      const fixture = designTasteCard;
      expect(fixture.bite.tags, isNotEmpty);
      expect(fixture.bite.summary, isNot(contains('\n')));
      expect(fixture.positive, isNotEmpty);
      expect(fixture.burden, isNotEmpty);
      expect(fixture.bite.guide, isNotNull);
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
      status = 404;
      reply = <String, Object?>{'error_code': 'result_not_found'};

      await expectLater(
        gateway.deleteOwnedResult('20000000-0000-4000-8000-000000000002'),
        throwsA(
          isA<TasteCardGatewayException>()
              .having(
                (error) => error.operation,
                'operation',
                TasteCardGatewayOperation.delete,
              )
              .having((error) => error.code, 'code', 'result_not_found'),
        ),
      );
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
