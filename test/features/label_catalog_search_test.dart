import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_drink.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_search_gateway.dart';
import 'package:soolgyul/src/features/taste_fit/data/label_catalog_search.dart';

import '../support/fake_search.dart';

CatalogDrink _drink(String name, [String? nameEn]) => CatalogDrink(
  id: name,
  displayName: name,
  nameEn: nameEn,
  category: DrinkCategory.whisky,
);

class _Catalog with SearchManyByOne {
  _Catalog(this.resultsByQuery, {this.failing = const <String>{}});

  final Map<String, List<CatalogDrink>> resultsByQuery;
  final Set<String> failing;
  final List<String> queries = <String>[];
  int calls = 0;

  @override
  Future<List<List<CatalogDrink>>> searchMany(
    List<String> queries, {
    int limit = 10,
  }) {
    calls += 1;
    return super.searchMany(queries, limit: limit);
  }

  @override
  Future<List<CatalogDrink>> search(
    String query, {
    int limit = 20,
    int offset = 0,
  }) async {
    queries.add(query);
    if (failing.contains(query)) throw const CatalogSearchException();
    return resultsByQuery[query] ?? const <CatalogDrink>[];
  }
}

void main() {
  group('labelSearchQueries', () {
    test('keeps the naming lines in label order and drops the rest', () {
      expect(
        labelSearchQueries(const <String>[
          'THE BALVENIE',
          '  12  ',
          'DoubleWood',
          'ALC. 40% VOL.',
          '700ml',
          '알코올 17도',
          '40%',
          '',
          'the balvenie',
          'Matured in two distinct casks and bottled by hand at the distillery.',
        ]),
        <String>['BALVENIE', 'DoubleWood'],
      );
    });

    test('drops kind words and the lines made only of them', () {
      expect(
        labelSearchQueries(const <String>[
          'Glenfiddich',
          'SINGLE MALT',
          'SCOTCH WHISKY',
          'AGED 12 YEARS',
          'Glen Grant Single Malt Scotch Whisky',
          '風の森',
          '純米大吟醸',
          '風の森 純米大吟醸',
          '日高見純米',
          '식품유형: 청주',
          '제품명: 닷사이 45',
        ]),
        <String>['Glenfiddich', 'Glen Grant', '風の森', '日高見', '닷사이 45'],
      );
    });

    test('drops company lines and searches a bracketed part by itself', () {
      expect(
        labelSearchQueries(const <String>[
          'BY APPOINTMENT TO HER MAJESTY THE QUEEN',
          'JOHN WALKER & SONS LIMITED, LONDON',
          'JOHNNIE WALKER',
          '수입원 (주)니혼슈코리아',
          '간바레 오또상(GANBARE TOUCHAN PACK)',
        ]),
        <String>['JOHNNIE WALKER', '간바레 오또상', 'GANBARE TOUCHAN PACK'],
      );
    });

    test('collapses inner whitespace and respects the limit', () {
      expect(
        labelSearchQueries(const <String>['참이슬   후레쉬', '진로', '처음처럼'], limit: 2),
        <String>['참이슬 후레쉬', '진로'],
      );
    });
  });

  group('labelProductName', () {
    test('reads the name up to the next field of a back label', () {
      String? name(String line) => labelProductName(<String>['경고', line]);
      expect(name('1.제품명:그란츠 트리플우드 2.,식품유형:위스키 •반품 및 교환'), '그란츠 트리플우드');
      expect(name('제품명조니워커 블랙 레이블™에탄올 함량 40%'), '조니워커 블랙 레이블');
      expect(name('1 제품명:발베니12년 2, 식품유형:위스키 3업소명 및 소재지'), '발베니12년');
      expect(name('*제품명 :닷사이 준마이다이긴죠 45'), '닷사이 준마이다이긴죠 45');
      expect(name('제품 명》 화요 25'), '화요 25');
      expect(
        name('제품명: 옐로우 테일 쉬라즈 YELLOW TAIL SHIRAZ / 식품의 유형 : 과실주'),
        '옐로우 테일 쉬라즈 YELLOW TAIL SHIRAZ',
      );
    });

    test('is null when the field has no value on its line, or is absent', () {
      expect(labelProductName(const <String>['제품명', '용기 상단 표기일까지']), isNull);
      expect(labelProductName(const <String>['품명', '제품 유형 청주']), isNull);
      expect(labelProductName(const <String>['Grants', 'TRIPLE WOOD']), isNull);
      expect(labelProductName(const <String>['제품문의 02-123-4567']), isNull);
    });
  });

  test('productNameQueries tries the name, its Korean words, and each '
      'without the last word', () {
    expect(productNameQueries('칸티 모스카토 다스티 디오씨지'), <String>[
      '칸티 모스카토 다스티 디오씨지',
      '칸티 모스카토 다스티',
    ]);
    expect(productNameQueries('옐로우 테일 쉬라즈 YELLOW TAIL SHIRAZ'), <String>[
      '옐로우 테일 쉬라즈 YELLOW TAIL SHIRAZ',
      '옐로우 테일 쉬라즈',
      '옐로우 테일 쉬라즈 YELLOW TAIL',
      '옐로우 테일',
    ]);
    expect(productNameQueries('화요2'), <String>['화요2']);
  });

  test('labelPairQueries joins each line with the next two', () {
    expect(labelPairQueries(const <String>['A1', 'B2', 'C3', 'D4']), <String>[
      'A1 B2',
      'B2 C3',
      'C3 D4',
      'A1 C3',
      'B2 D4',
    ]);
  });

  group('searchCatalogByLabel', () {
    test('finds the drink two lines name together', () async {
      final malbec = _drink('몬테스 알파 말벡', 'Montes Alpha Malbec');
      final other = _drink('맥켄지 까베르네 소비뇽', 'Mackenzie Cabernet Sauvignon');
      final cabernet = _drink(
        '몬테스 알파 까베르네 소비뇽',
        'Montes Alpha Cabernet Sauvignon',
      );
      final catalog = _Catalog(<String, List<CatalogDrink>>{
        'MONTES ALPHA': <CatalogDrink>[malbec],
        'CABERNET SAUVIGNON': <CatalogDrink>[other],
        'MONTES ALPHA CABERNET SAUVIGNON': <CatalogDrink>[cabernet],
      });

      final found = await searchCatalogByLabel(catalog, const <String>[
        'MONTES ALPHA',
        'CABERNET SAUVIGNON',
      ]);

      expect(catalog.calls, 1, reason: 'eight queries or fewer go in one call');
      expect(found.queries, <String>['MONTES ALPHA', 'CABERNET SAUVIGNON']);
      expect(found.matches.first, cabernet);
    });

    test('a line read wrong cannot outvote the name', () async {
      final tripleWood = _drink('그란츠 트리플 우드', "Grant's Triple Wood");
      final eighteen = _drink('그란츠 18년', "Grant's 18yo");
      final stray = _drink('탄다라다이 리슬링', 'Tandaradei Riesling');
      final catalog = _Catalog(<String, List<CatalogDrink>>{
        'Grants': <CatalogDrink>[eighteen, tripleWood],
        'TAND': <CatalogDrink>[stray],
      });

      final found = await searchCatalogByLabel(catalog, const <String>[
        'Grants',
        'TAND',
        'T IPLE W000',
        'BLENDED SCOTCH WHISEY',
      ]);

      expect(found.matches, <CatalogDrink>[tripleWood, eighteen]);
    });

    test('a back label is searched by its product name alone', () async {
      final black = _drink('조니워커 블랙 라벨', 'Johnnie Walker Black');
      final catalog = _Catalog(<String, List<CatalogDrink>>{
        '조니워커 블랙': <CatalogDrink>[black],
        '서울특별시 강남구 테헤란로': <CatalogDrink>[_drink('강남 소주')],
      });

      final found = await searchCatalogByLabel(catalog, const <String>[
        '제품명조니워커 블랙 레이블™에탄올 함량 40%',
        '원재료명위스키원액 99.95%,카라멜색소',
        '서울특별시 강남구 테헤란로',
      ]);

      expect(catalog.queries, <String>['조니워커 블랙 레이블', '조니워커 블랙']);
      expect(found.queries, <String>['조니워커 블랙 레이블']);
      expect(found.matches, <CatalogDrink>[black]);
    });

    test('a back label without a readable name shows no stray drink', () async {
      final catalog = _Catalog(<String, List<CatalogDrink>>{
        '소수': <CatalogDrink>[_drink('바칼호아 호쇼 슈페리어')],
      });

      final found = await searchCatalogByLabel(catalog, const <String>[
        '원재료명: 정제수, 쌀',
        '반품 및 교환: 구입처',
        '소수',
      ]);

      expect(found.queries, isNotEmpty);
      expect(found.matches, isEmpty);
    });

    test('a label with nothing to search with has no queries', () async {
      final found = await searchCatalogByLabel(
        _Catalog(const <String, List<CatalogDrink>>{}),
        const <String>['ALC. 40% VOL', '700ml'],
      );
      expect(found.queries, isEmpty);
      expect(found.matches, isEmpty);
    });

    test('a failed search throws', () async {
      final broken = _Catalog(
        const <String, List<CatalogDrink>>{},
        failing: <String>{'BALVENIE'},
      );
      expect(
        () => searchCatalogByLabel(broken, <String>['BALVENIE']),
        throwsA(isA<CatalogSearchException>()),
      );
    });
  });

  // What the phone's reader made of twenty label photos, front and back of
  // ten bottles, with what the catalog answered each search then.
  group('label photos read on a phone', () {
    final fixture =
        jsonDecode(File('test/fixtures/label_scans.json').readAsStringSync())
            as Map<String, dynamic>;
    final catalog = _Catalog(<String, List<CatalogDrink>>{
      for (final MapEntry(:key, :value)
          in (fixture['catalog'] as Map<String, dynamic>).entries)
        key: <CatalogDrink>[
          for (final row in value as List)
            _drink((row as List)[0] as String, row[1] as String?),
        ],
    });
    final scans = (fixture['scans'] as List).cast<Map<String, dynamic>>();

    for (final scan in scans) {
      test('${scan['label']} answers ${scan['first']}', () async {
        final found = await searchCatalogByLabel(
          catalog,
          (scan['lines'] as List).cast<String>(),
        );
        expect(found.matches.firstOrNull?.displayName, scan['first']);
      });
    }

    test('sixteen of the twenty put the bottle first', () {
      final right = scans.where(
        (scan) =>
            (scan['first'] as String?)?.startsWith(scan['drink'] as String) ??
            false,
      );
      expect(right.length, 16);
    });
  });
}
