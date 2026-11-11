import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_search_gateway.dart';
import 'package:soolgyul/src/features/catalog/data/supabase_catalog_search_gateway.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_drink.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late SupabaseClient client;

  setUp(() {
    client = SupabaseClient('https://example.supabase.co', 'test-anon-key');
  });

  tearDown(() async {
    await client.dispose();
  });

  test('search maps the bounded catalog RPC response', () async {
    String? functionName;
    Map<String, dynamic>? parameters;
    final gateway = SupabaseCatalogSearchGateway(
      client,
      rpcInvoker: (name, params) async {
        functionName = name;
        parameters = params;
        return <String, dynamic>{
          'not_carried': null,
          'results': <Map<String, dynamic>>[
            <String, dynamic>{
              'match_kind': 'exact',
              'id': '10000000-0000-4000-8000-000000000001',
              'name_ko': '테스트 스파클링 와인',
              'name_en': 'Test Sparkling Wine',
              'category_key': 'wine',
              'style_key': 'sparkling_wine',
              'style_label': '스파클링 와인',
              'abv_percent': 11.5,
              'media_path': 'wine/10000000-0000-4000-8000-000000000001.webp',
              'country_code': 'FR',
              'region': '몽타뉴 드 랭스',
            },
          ],
        };
      },
    );

    final results = await gateway.search(' 스파클링 ', limit: 100, offset: 40);

    expect(functionName, 'soolgyul_search_catalog');
    expect(results, isA<CatalogMatches>());
    expect((results as CatalogMatches).guesses, isFalse);
    expect(results.notCarried, isNull);
    expect(parameters, <String, dynamic>{
      'target_query': '스파클링',
      'target_limit': 20,
      'target_offset': 40,
    });
    expect(results, hasLength(1));
    expect(results.single.category, DrinkCategory.sparklingWine);
    expect(results.single.abvPercent, 11.5);
    expect(results.single.nameEn, 'Test Sparkling Wine');
    expect(results.single.styleLabel, '스파클링 와인');
    expect(results.single.countryCode, 'FR');
    expect(results.single.region, contains('몽타뉴 드 랭스'));
    expect(
      results.single.photoUrl,
      'https://example.supabase.co/storage/v1/object/public/'
      'alcohol-product-images/wine/10000000-0000-4000-8000-000000000001.webp',
    );
  });

  test(
    'search says when the drinks are guesses or the drink is not carried',
    () async {
      Map<String, dynamic> row(String kind) => <String, dynamic>{
        'match_kind': kind,
        'id': 'id-$kind',
        'name_ko': '발렌타인 12년',
        'category_key': 'whisky',
        'media_path': null,
      };
      Object? answer;
      final gateway = SupabaseCatalogSearchGateway(
        client,
        rpcInvoker: (name, params) async => answer,
      );

      answer = <String, dynamic>{
        'not_carried': null,
        'results': <Object?>[row('near')],
      };
      final near = await gateway.search('발렌타임') as CatalogMatches;
      expect(near.guesses, isTrue);
      expect(
        catalogSearchNote(notCarried: near.notCarried, guesses: near.guesses),
        '입력하신 이름과 비슷한 술이에요.',
      );

      answer = <String, dynamic>{
        'not_carried': null,
        'results': <Object?>[row('sound')],
      };
      expect((await gateway.search('샤토') as CatalogMatches).guesses, isTrue);

      answer = <String, dynamic>{'not_carried': 'beer', 'results': <Object?>[]};
      final beer = await gateway.search('카스') as CatalogMatches;
      expect(beer, isEmpty);
      expect(
        catalogSearchNote(notCarried: beer.notCarried, guesses: beer.guesses),
        '술결은 와인, 위스키, 사케, 전통주를 다뤄요. 맥주는 다루지 않아요.',
      );

      answer = <Object?>[row('exact')];
      await expectLater(
        gateway.search('발렌타인'),
        throwsA(isA<CatalogSearchException>()),
      );
    },
  );

  test('searchMany answers every query from one call', () async {
    final calls = <String>[];
    Map<String, dynamic>? parameters;
    Map<String, dynamic> row(int queryIndex, String name) => <String, dynamic>{
      'query_index': queryIndex,
      'id': 'id-$name',
      'name_ko': name,
      'category_key': 'whisky',
      'media_path': null,
    };
    final gateway = SupabaseCatalogSearchGateway(
      client,
      rpcInvoker: (name, params) async {
        calls.add(name);
        parameters = params;
        return <Map<String, dynamic>>[
          row(1, '발베니 12년'),
          row(1, '발베니 14년'),
          row(3, '화요 25'),
        ];
      },
    );

    final answers = await gateway.searchMany(<String>[
      '발베니',
      '없는 술',
      '화요 25',
    ], limit: 5);

    expect(calls, <String>['soolgyul_search_alcohol_catalog_batch']);
    expect(parameters, <String, dynamic>{
      'target_queries': <String>['발베니', '없는 술', '화요 25'],
      'target_limit': 5,
    });
    expect(
      answers.map((drinks) => drinks.map((d) => d.displayName).toList()),
      <List<String>>[
        <String>['발베니 12년', '발베니 14년'],
        <String>[],
        <String>['화요 25'],
      ],
    );
  });

  test('blank and malformed searches fail closed', () async {
    final blankGateway = SupabaseCatalogSearchGateway(
      client,
      rpcInvoker: (_, _) async => throw StateError('must not run'),
    );
    expect(await blankGateway.search('   '), isEmpty);

    final malformedGateway = SupabaseCatalogSearchGateway(
      client,
      rpcInvoker: (_, _) async => <Object?>[
        <String, Object?>{'id': 1},
      ],
    );
    await expectLater(
      malformedGateway.search('술'),
      throwsA(isA<CatalogSearchException>()),
    );
  });
}
