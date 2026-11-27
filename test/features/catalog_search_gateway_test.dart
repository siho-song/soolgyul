import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/core/errors/error_report.dart';
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
      expect(
        catalogSearchNote(notCarried: 'mass_market', guesses: false),
        '술결은 와인, 위스키, 사케, 전통주를 다뤄요. 마트에서 흔히 파는 막걸리·청주·매실주는 다루지 않아요.',
      );
      expect(
        catalogSearchNote(notCarried: 'not_listed', guesses: false),
        '찾으시는 술은 아직 술결에 등록되지 않았어요.',
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
        return <Map<String, dynamic>>[
          <String, dynamic>{
            ...row('샤또 몽페라 루즈'),
            'label_facts': <String, dynamic>{
              'vintage': 2019,
              'grapes': <String>['merlot'],
              'regions': <List<String>>[
                <String>['보르도', 'Bordeaux'],
                <String>['프랑스', 'France'],
              ],
              'producer': <String>['샤또 몽페라'],
              'staple': true,
            },
          },
        ];
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
    final facts = found.single.single.labelFacts!;
    expect(facts.vintageYear, 2019);
    expect(facts.ageYears, isNull);
    expect(facts.grapes, <String>['merlot']);
    expect(facts.regions.first, <String>['보르도', 'Bordeaux']);
    expect(facts.producer, <String>['샤또 몽페라']);
    expect((facts.known, facts.staple), (false, true));
    expect(fallback.single.single.displayName, '샤또 몽페라 레드');
    expect(fallback.single.single.labelFacts, isNull);
    expect(calls, <String>[
      'soolgyul_search_alcohol_catalog_by_label',
      'soolgyul_search_alcohol_catalog_by_label',
      'soolgyul_search_alcohol_catalog_batch',
    ]);
  });

  test(
    'a row without an id, name or category is left out of the page',
    () async {
      Map<String, dynamic> row(String name, {int queryIndex = 1}) =>
          <String, dynamic>{
            'match_kind': 'exact',
            'query_index': queryIndex,
            'id': 'id-$name',
            'name_ko': name,
            'category_key': 'whisky',
            'style_key': 7,
            'media_path': null,
          };
      final rows = <Object?>[
        row('발베니 12년'),
        <String, dynamic>{...row('이름 없는 술'), 'name_ko': null},
        'not a row',
        <String, dynamic>{...row('번호 없는 술'), 'query_index': null},
        row('화요 25'),
      ];
      final gateway = SupabaseCatalogSearchGateway(
        client,
        rpcInvoker: (name, _) async => name == 'soolgyul_search_catalog'
            ? <String, dynamic>{'not_carried': null, 'results': rows}
            : rows,
      );

      final page = await gateway.search('술');
      final many = await gateway.searchMany(<String>['술']);

      expect(page.map((drink) => drink.displayName), [
        '발베니 12년',
        '번호 없는 술',
        '화요 25',
      ]);
      expect(many.single.map((drink) => drink.displayName), [
        '발베니 12년',
        '화요 25',
      ]);
    },
  );

  test('a fault is reported before it becomes a failed search; a server '
      'refusal is not', () async {
    final reported = <Object>[];
    addTearDown(captureErrorReports((error, _, _) => reported.add(error)));
    Object failure = StateError('a bug');
    final gateway = SupabaseCatalogSearchGateway(
      client,
      rpcInvoker: (_, _) async => throw failure,
    );

    await expectLater(
      gateway.search('술'),
      throwsA(isA<CatalogSearchException>()),
    );
    await expectLater(
      gateway.searchMany(<String>['술']),
      throwsA(isA<CatalogSearchException>()),
    );
    expect(reported, [same(failure), same(failure)]);

    failure = const PostgrestException(message: 'refused', code: 'P0001');
    await expectLater(
      gateway.search('술'),
      throwsA(isA<CatalogSearchException>()),
    );
    expect(reported, hasLength(2));
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

  test('the label word search answers candidates with their words\' rarity, '
      'and nothing from a server without it', () async {
    Map<String, dynamic>? parameters;
    final current = SupabaseCatalogSearchGateway(
      client,
      rpcInvoker: (name, params) async {
        expect(name, 'soolgyul_search_alcohol_catalog_by_label_words');
        parameters = params;
        return <Map<String, dynamic>>[
          <String, dynamic>{
            'id': '10000000-0000-4000-8000-000000000001',
            'name_ko': '케이머스 까베르네 소비뇽',
            'name_en': 'Caymus Cabernet Sauvignon',
            'category_key': 'wine',
            'style_key': 'red_wine',
            'media_path': null,
            'label_facts': <String, dynamic>{'known': true},
            'name_rarity': <String, dynamic>{'caymus': 9.2, 'cabernet': 2.8},
            'found': 7.4,
          },
          <String, dynamic>{'id': 'no name'},
        ];
      },
    );
    final older = SupabaseCatalogSearchGateway(
      client,
      rpcInvoker: (name, params) async => throw const PostgrestException(
        message: 'not found',
        code: 'PGRST202',
      ),
    );

    final found = await current.searchByLabelWords(
      <String>['caymu5', 'napa'],
      alsoIds: <String>['20000000-0000-4000-8000-000000000002'],
    );

    expect(parameters, <String, dynamic>{
      'target_words': <String>['caymu5', 'napa'],
      'also_ids': <String>['20000000-0000-4000-8000-000000000002'],
      'target_limit': 300,
    });
    expect(found.single.drink.displayName, '케이머스 까베르네 소비뇽');
    expect(found.single.drink.labelFacts!.known, isTrue);
    expect(found.single.kind, 'wine');
    expect(found.single.nameRarity, <String, double>{
      'caymus': 9.2,
      'cabernet': 2.8,
    });
    expect(found.single.found, 7.4);
    expect(await older.searchByLabelWords(<String>['caymus']), isEmpty);
  });

  group('the label judge', () {
    final photo = Uint8List.fromList(const <int>[0xFF, 0xD8, 0xFF]);

    test('is sent the photo, at most ten candidates and the app\'s own '
        'sureness, and answers the drink it names', () async {
      Map<String, dynamic>? sent;
      final gateway = SupabaseCatalogSearchGateway(
        client,
        labelPickInvoker: () => (body) async {
          sent = body;
          return <String, dynamic>{'drink_id': 'drink-2'};
        },
      );

      final drinkId = await gateway.pickByPhoto(photo, <String>[
        for (var index = 1; index <= 12; index++) 'drink-$index',
      ], appSure: true);

      expect(drinkId, 'drink-2');
      expect(sent, <String, dynamic>{
        'photo': '/9j/',
        'candidate_ids': <String>[
          for (var index = 1; index <= 10; index++) 'drink-$index',
        ],
        'app_sure': true,
      });
    });

    test('answers no drink when the server is sure of none', () async {
      final gateway = SupabaseCatalogSearchGateway(
        client,
        labelPickInvoker: () =>
            (_) async => <String, dynamic>{'drink_id': null},
      );

      expect(
        await gateway.pickByPhoto(photo, <String>['drink-1'], appSure: false),
        isNull,
      );
    });

    test('gives no answer when nobody is signed in or the server refuses, '
        'and reports only an answer that is not one', () async {
      final reported = <Object>[];
      addTearDown(captureErrorReports((error, _, _) => reported.add(error)));
      final refusals = <LabelPickInvoker? Function()>[
        () => null,
        () =>
            (_) async => throw const FunctionException(status: 503),
        () =>
            (_) async => <String, dynamic>{'error_code': 'internal_error'},
      ];
      for (final invoker in refusals) {
        final gateway = SupabaseCatalogSearchGateway(
          client,
          labelPickInvoker: invoker,
        );
        await expectLater(
          gateway.pickByPhoto(photo, <String>['drink-1'], appSure: false),
          throwsA(isA<LabelPhotoJudgeException>()),
        );
      }
      expect(reported.single, isA<FormatException>());
    });
  });
}
