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
        return <Map<String, dynamic>>[
          <String, dynamic>{
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
        ];
      },
    );

    final results = await gateway.search(' 스파클링 ', limit: 100, offset: 40);

    expect(functionName, 'soolgyul_search_alcohol_catalog');
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

  test('lines read off a label go to the label search, and to the typed '
      'one on a server without it', () async {
    final calls = <String>[];
    Map<String, dynamic> row(String name) => <String, dynamic>{
      'query_index': 1,
      'id': 'id-$name',
      'name_ko': name,
      'category_key': 'wine',
      'media_path': null,
    };
    final current = SupabaseCatalogSearchGateway(
      client,
      rpcInvoker: (name, params) async {
        calls.add(name);
        return <Map<String, dynamic>>[row('샤또 몽페라 루즈')];
      },
    );
    final older = SupabaseCatalogSearchGateway(
      client,
      rpcInvoker: (name, params) async {
        calls.add(name);
        if (name == 'soolgyul_search_alcohol_catalog_by_label') {
          throw const PostgrestException(
            message: 'not found',
            code: 'PGRST202',
          );
        }
        return <Map<String, dynamic>>[row('샤또 몽페라 레드')];
      },
    );

    final found = await current.searchMany(<String>[
      '사또 몽페라 루즈',
    ], readOffLabel: true);
    final fallback = await older.searchMany(<String>[
      '사또 몽페라 루즈',
    ], readOffLabel: true);

    expect(found.single.single.displayName, '샤또 몽페라 루즈');
    expect(fallback.single.single.displayName, '샤또 몽페라 레드');
    expect(calls, <String>[
      'soolgyul_search_alcohol_catalog_by_label',
      'soolgyul_search_alcohol_catalog_by_label',
      'soolgyul_search_alcohol_catalog_batch',
    ]);
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
