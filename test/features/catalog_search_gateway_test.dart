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
