import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/taste_fit/data/supabase_taste_fit_gateway.dart';
import 'package:soolgyul/src/features/taste_fit/data/taste_fit_gateway.dart';
import 'package:soolgyul/src/features/taste_fit/data/taste_fit_verdict.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Map<String, Object?> contractExample = <String, Object?>{
  'schema_version': 'taste-fit-v1',
  'has_cards': true,
  'products': <Object?>[
    <String, Object?>{
      'product_id': '10000000-0000-4000-8000-000000000001',
      'badge': 'star',
      'headline': '딱 맞는 PICK',
      'tags': <String>['#상큼한_과일향', '#침고이는_산미', '#부드러운_목넘김'],
      'sentence':
          '평소 민지님께서 좋아하신 상큼한 과일 향, 산뜻한 산미, 부드러운 목넘김을 갖고 있는 술이라 시도해 보셔도 괜찮아요.',
      'levels': <String, Object?>{
        'sweetness': 1,
        'acidity': 5,
        'astringency': 1,
        'body': 2,
      },
      'facts': <Object?>[
        <String, Object?>{
          'kind': 'producer',
          'label': '클라우디 베이',
          'description': '뉴질랜드 말버러의 와이너리예요.',
        },
        <String, Object?>{
          'kind': 'region',
          'label': '말버러',
          'description': null,
        },
      ],
    },
  ],
};

void main() {
  late SupabaseClient client;

  setUp(() {
    client = SupabaseClient('https://example.supabase.co', 'test-anon-key');
  });

  tearDown(() async {
    await client.dispose();
  });

  test(
    'judge posts the ids to taste-fit and parses the contract example',
    () async {
      String? functionName;
      Map<String, dynamic>? body;
      final gateway = SupabaseTasteFitGateway(
        client,
        functionInvoker: (name, requestBody) async {
          functionName = name;
          body = requestBody;
          return contractExample;
        },
      );

      final response = await gateway.judge(<String>['a', 'b']);

      expect(functionName, 'taste-fit');
      expect(body, <String, dynamic>{
        'product_ids': <String>['a', 'b'],
      });
      expect(response.hasCards, isTrue);
      final verdict = response.verdictFor(
        '10000000-0000-4000-8000-000000000001',
      )!;
      expect(verdict.badge, TasteFitBadge.star);
      expect(verdict.headline, '딱 맞는 PICK');
      expect(verdict.tags, hasLength(3));
      expect(verdict.sentence, startsWith('평소 민지님께서 좋아하신'));
      expect(verdict.facts.map((f) => f.label), <String>['클라우디 베이', '말버러']);
      expect(verdict.facts.first.description, '뉴질랜드 말버러의 와이너리예요.');
      expect(verdict.facts.last.description, isNull);
      expect(verdict.levels, <String, int>{
        'sweetness': 1,
        'acidity': 5,
        'astringency': 1,
        'body': 2,
      });
    },
  );

  test('a function error becomes a gateway exception with its code', () async {
    final gateway = SupabaseTasteFitGateway(
      client,
      functionInvoker: (_, _) async => throw FunctionException(
        status: 401,
        details: <String, Object?>{'error_code': 'authorization_required'},
      ),
    );

    await expectLater(
      gateway.judge(<String>['a']),
      throwsA(
        isA<TasteFitGatewayException>().having(
          (error) => error.code,
          'code',
          'authorization_required',
        ),
      ),
    );
  });

  test('a malformed body becomes a gateway exception', () async {
    final gateway = SupabaseTasteFitGateway(
      client,
      functionInvoker: (_, _) async => 'not json',
    );

    await expectLater(
      gateway.judge(<String>['a']),
      throwsA(isA<TasteFitGatewayException>()),
    );
  });

  group('TasteFitResponse.fromJson', () {
    test('tolerates missing levels and tags and unknown badges', () {
      final response = TasteFitResponse.fromJson(<String, Object?>{
        'has_cards': false,
        'products': <Object?>[
          <String, Object?>{
            'product_id': 'p1',
            'badge': 'something_new',
            'headline': '아직 이 술의 정보가 없어요',
          },
          <String, Object?>{'badge': 'star'},
          'garbage',
        ],
      });

      expect(response.hasCards, isFalse);
      expect(response.verdicts.keys, <String>['p1']);
      final verdict = response.verdictFor('p1')!;
      expect(verdict.badge, TasteFitBadge.noInfo);
      expect(verdict.tags, isEmpty);
      expect(verdict.levels, isEmpty);
      expect(verdict.sentence, isEmpty);
    });

    test('an empty object means no cards and no verdicts', () {
      final response = TasteFitResponse.fromJson(<String, Object?>{});
      expect(response.hasCards, isFalse);
      expect(response.verdicts, isEmpty);
    });
  });
}
