import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_drink.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_search_gateway.dart';
import 'package:soolgyul/src/features/taste_fit/data/label_catalog_search.dart';
import 'package:soolgyul/src/features/taste_fit/data/label_layout.dart';
import 'package:soolgyul/src/features/taste_fit/data/label_queries.dart';

import '../support/fake_search.dart';

CatalogDrink _drink(String name, [String? nameEn]) => CatalogDrink(
  id: name,
  displayName: name,
  nameEn: nameEn,
  category: DrinkCategory.whisky,
);

ReadLine _line(
  String text,
  double left,
  double top, {
  double width = 0.3,
  double height = 0.02,
}) => ReadLine(text: text, left: left, top: top, width: width, height: height);

class _Catalog with SearchManyByOne {
  _Catalog(this.resultsByQuery, {this.failing = const <String>{}});

  final Map<String, List<CatalogDrink>> resultsByQuery;
  final Set<String> failing;
  final List<String> queries = <String>[];
  int calls = 0;
  int labelCalls = 0;

  @override
  Future<List<List<CatalogDrink>>> searchMany(
    List<String> queries, {
    int limit = 10,
    bool readOffLabel = false,
  }) {
    calls += 1;
    labelCalls += readOffLabel ? 1 : 0;
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
      expect(catalog.labelCalls, 1, reason: 'asked as lines read off a label');
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

    test('a name in an import label\'s spelling or one stroke off still '
        'counts as shown', () async {
      final cabernet = _drink('몬테스 알파 까베르네 소비뇽');
      final blanc = _drink('몬테스 알파 소비뇽 블랑');
      final kakubin = _drink('산토리 가쿠빈');
      final stray = _drink('쿠반 비노 화이트 브뤼');
      final catalog = _Catalog(<String, List<CatalogDrink>>{
        '몬테스 알파 카버네 소비뇽': <CatalogDrink>[blanc, cabernet],
        '가쿠반': <CatalogDrink>[stray, kakubin],
      });

      final montes = await searchCatalogByLabel(catalog, const <String>[
        '제품명 몬테스 알파 카버네 소비뇽',
      ]);
      final suntory = await searchCatalogByLabel(catalog, const <String>[
        '제품명: 가쿠반',
      ]);

      expect(montes.matches.first, cabernet);
      expect(suntory.matches.first, kakubin);
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

    test('a word that happens to be in a name names no drink', () async {
      // A keyboard read as "option" and "command": Elderton Command Shiraz
      // has "command" in its name, and only a quarter of it.
      final command = _drink(
        '엘더튼 바로사 코멘드 쉬라즈',
        'Elderton Barossa Command Shiraz',
      );
      final catalog = _Catalog(<String, List<CatalogDrink>>{
        'command': <CatalogDrink>[command],
        'option command': <CatalogDrink>[command],
      });

      final found = await searchCatalogByLabel(catalog, const <String>[
        'option',
        'command',
      ]);

      expect(found.queries, isNotEmpty);
      expect(found.matches, isEmpty);
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

  group('searchCatalogByPhoto', () {
    final viuCabernet = _drink(
      '뷰 마넨 싱글 빈야드 까베르네 소비뇽',
      'Viu Manent Single Vineyard Cabernet Sauvignon',
    );
    final viuMalbec = _drink(
      '뷰 마넨 싱글 빈야드 말벡',
      'Viu Manent Single Vineyard Malbec',
    );
    final hahn = _drink('한 까베르네 소비뇽', 'Hahn Cabernet Sauvignon');

    test('a label is searched by its largest line, alone and with each '
        'other line', () async {
      final catalog = _Catalog(<String, List<CatalogDrink>>{
        'VIU MANENT': <CatalogDrink>[viuMalbec],
        'VIU MANENT CABERNET SAUVIGNON': <CatalogDrink>[viuCabernet],
        'CABERNET SAUVIGNON': <CatalogDrink>[hahn],
      });
      final found = await searchCatalogByPhoto(catalog, <ReadLine>[
        // A neck sticker above the label is read first.
        _line('JAMESSUCKLING.COM', 0.40, 0.05, width: 0.2, height: 0.012),
        _line('CABERNET SAUVIGNON', 0.34, 0.54, width: 0.32),
        _line('SINGLE VINEYARD', 0.36, 0.50, width: 0.28),
        _line('VIU MANENT', 0.30, 0.40, width: 0.4, height: 0.06),
      ]);

      expect(found.finds.map((find) => find.drink.displayName), <String>[
        viuCabernet.displayName,
      ]);
      expect(
        found.finds.single.search.matches.map((drink) => drink.displayName),
        <String>[viuCabernet.displayName, viuMalbec.displayName],
      );
      expect(catalog.queries, contains('VIU MANENT CABERNET SAUVIGNON'));
    });

    test('a grape alone names no drink', () async {
      final catalog = _Catalog(<String, List<CatalogDrink>>{
        'CABERNET SAUVIGNON': <CatalogDrink>[hahn],
      });
      final found = await searchCatalogByPhoto(catalog, <ReadLine>[
        _line('CABERNET SAUVIGNON', 0.3, 0.5),
      ]);

      expect(found.finds, isEmpty);
      expect(found.queries, <String>['CABERNET SAUVIGNON']);
    });

    test('small print cannot name the drink its label prints large', () async {
      final santaEma = _drink(
        '산타에마 까베르네 소비뇽 마이포밸리',
        'Santa Ema Cabernet Sauvignon Maipo Valley',
      );
      final selected = _drink(
        '1865 셀렉티드 빈야드 까베르네 소비뇽',
        '1865 Selected Vineyards Cabernet Sauvignon',
      );
      final catalog = _Catalog(<String, List<CatalogDrink>>{
        '1865': <CatalogDrink>[selected],
        'CABERNET SAUVIGNON': <CatalogDrink>[santaEma],
        'D.O. VALLE DEL MAIPO': <CatalogDrink>[santaEma],
      });
      final found = await searchCatalogByPhoto(catalog, <ReadLine>[
        _line('1865', 0.35, 0.10, height: 0.09),
        _line('CABERNET SAUVIGNON', 0.34, 0.24, width: 0.32, height: 0.016),
        _line('D.O. VALLE DEL MAIPO', 0.34, 0.27, width: 0.32, height: 0.016),
      ]);

      expect(found.finds.single.drink.displayName, selected.displayName);
      expect(found.finds.single.search.matches, hasLength(1));
      expect(catalog.queries, containsAll(<String>['1865']));
    });

    test('a menu is searched a line at a time, without its prices, and a '
        'name in two languages is one entry', () async {
      final duckhorn = _drink(
        '덕혼 디코이 까베르네 소비뇽',
        'Duckhorn Decoy Cabernet Sauvignon',
      );
      final oyster = _drink('오이스터 베이 소비뇽 블랑', 'Oyster Bay Sauvignon Blanc');
      final clicquot = _drink(
        '뵈브 클리코 옐로우 라벨 브뤼',
        'Veuve Clicquot Yellow Label Brut',
      );
      final catalog = _Catalog(<String, List<CatalogDrink>>{
        '덕혼 디코이 까베르네 소비뇽': <CatalogDrink>[duckhorn],
        'Duckhorn Decoy Cabernet Sauvignon 미국': <CatalogDrink>[duckhorn],
        '오이스터 베이 쇼비뇽 블랑': <CatalogDrink>[oyster],
        'Oyster Bay Sauvignon 뉴질랜드': <CatalogDrink>[oyster],
        '뵈브 클리코 옐로우 라벨': <CatalogDrink>[clicquot],
        'Veuve Clicquot Yellow Label 프랑스': <CatalogDrink>[clicquot],
      });
      final found = await searchCatalogByPhoto(catalog, <ReadLine>[
        _line('WINE LIST', 0.35, 0.10, height: 0.04),
        _line('- 덕혼 디코이 까베르네 소비뇽 B 89.0', 0.21, 0.20, width: 0.5),
        _line('Duckhorn Decoy Cabernet Sauvignon, 미국)', 0.23, 0.225),
        _line('- 오이스터 베이 쇼비뇽 블랑', 0.21, 0.28),
        _line('Oyster Bay Sauvignon Blanc, 뉴질랜드)', 0.23, 0.305),
        _line('- 뵈브 클리코 옐로우 라벨', 0.21, 0.36),
        _line('Veuve Clicquot Yellow Label, 프랑스)', 0.23, 0.385),
        _line('B 45.0 / G 10.0', 0.72, 0.28, width: 0.12),
      ]);

      expect(found.finds.map((find) => find.drink.displayName), <String>[
        duckhorn.displayName,
        oyster.displayName,
        clicquot.displayName,
      ]);
      expect(found.finds.every((find) => find.group.listEntry), isTrue);
      expect(found.finds.first.group.lines, hasLength(2));
      expect(catalog.queries, isNot(contains(contains('89'))));
    });

    test('a drink two groups find is listed once', () async {
      final makers = _drink('메이커스 마크', "Maker's Mark");
      final catalog = _Catalog(<String, List<CatalogDrink>>{
        "Maker's Mark": <CatalogDrink>[makers],
        '메이커스마크': <CatalogDrink>[makers],
      });
      final found = await searchCatalogByPhoto(catalog, <ReadLine>[
        _line("Maker's Mark", 0.05, 0.30, width: 0.3, height: 0.05),
        // Another bottle's shelf tag, away from the label.
        _line('메이커스마크', 0.60, 0.80, width: 0.2),
      ]);

      expect(found.finds, hasLength(1));
    });

    test('the price tag under a bottle orders its candidates and adds '
        'none', () async {
      final xr = _drink('윈저 XR', 'Windsor XR');
      final twelve = _drink('윈저 12년', 'Windsor 12yo');
      final catalog = _Catalog(<String, List<CatalogDrink>>{
        'WINDSOR': <CatalogDrink>[xr, twelve],
        // The tag's own line finds a drink the label does not name.
        '윈저12년500ML': <CatalogDrink>[_drink('골든블루 12년', 'Golden Blue 12')],
      });
      final found = await searchCatalogByPhoto(catalog, <ReadLine>[
        _line('WINDSOR', 0.40, 0.10, width: 0.3, height: 0.08),
        _line('39,000', 0.38, 0.85, width: 0.2, height: 0.04),
        _line('윈저12년500ML', 0.38, 0.90, width: 0.25, height: 0.03),
      ]);

      expect(
        found.finds.first.search.matches.map((drink) => drink.displayName),
        <String>[twelve.displayName, xr.displayName],
      );
    });

    test('a photo lists the bottle in its middle and the drinks it surely '
        'shows', () async {
      final montes = _drink(
        '몬테스 알파 까베르네 소비뇽',
        'Montes Alpha Cabernet Sauvignon',
      );
      final bonterra = _drink('본테라 메를로', 'Bonterra Merlot');
      final roman = _drink('로만로드', 'Roman Road');
      final catalog = _Catalog(<String, List<CatalogDrink>>{
        'MONTES ALPHA': <CatalogDrink>[montes],
        'BONTERRA': <CatalogDrink>[bonterra],
        'ROAD': <CatalogDrink>[roman],
      });
      final found = await searchCatalogByPhoto(catalog, <ReadLine>[
        // The bottle the photo is of: its grape was not read.
        _line('MONTES ALPHA', 0.35, 0.30, width: 0.3, height: 0.08),
        // A neighbour read whole, and a scrap of another.
        _line('BONTERRA', 0.02, 0.32, width: 0.2, height: 0.05),
        _line('MERLOT', 0.04, 0.39, width: 0.16),
        _line('ROAD', 0.80, 0.35, width: 0.15, height: 0.04),
      ]);

      expect(found.finds, hasLength(3));
      expect(found.finds.map((find) => find.search.sure), <bool>[
        false,
        true,
        false,
      ]);
      expect(found.listed.map((find) => find.drink.displayName), <String>[
        montes.displayName,
        bonterra.displayName,
      ]);
    });

    test('a name in the next largest letters is found when the largest '
        'name nothing', () async {
      final mio = _drink('미오 스파클링', 'MIO');
      final catalog = _Catalog(<String, List<CatalogDrink>>{
        'MIO': <CatalogDrink>[mio],
      });
      final found = await searchCatalogByPhoto(catalog, <ReadLine>[
        _line('澪', 0.45, 0.50, width: 0.1, height: 0.13),
        _line('MIO', 0.46, 0.65, width: 0.08, height: 0.034),
        _line('SPARKLING SAKE', 0.43, 0.70, width: 0.14, height: 0.018),
      ]);

      expect(found.listed.single.drink.displayName, mio.displayName);
    });

    test('an age alone names no drink', () async {
      final catalog = _Catalog(<String, List<CatalogDrink>>{
        '25 AL C': <CatalogDrink>[_drink('글렌알라키 25년', 'Glenallachie 25')],
      });
      final found = await searchCatalogByPhoto(catalog, <ReadLine>[
        _line('25/ AL C', 0.55, 0.88, width: 0.1),
      ]);

      expect(found.finds, isEmpty);
    });

    test('one label whose search failed leaves the others to show', () async {
      final makers = _drink('메이커스 마크', "Maker's Mark");
      final catalog = _Catalog(
        <String, List<CatalogDrink>>{
          "Maker's Mark": <CatalogDrink>[makers],
        },
        failing: <String>{'TEACHERS'},
      );
      final lines = <ReadLine>[
        _line("Maker's Mark", 0.05, 0.30, width: 0.3, height: 0.05),
        _line('TEACHERS', 0.60, 0.30, width: 0.3, height: 0.05),
      ];

      final found = await searchCatalogByPhoto(catalog, lines);
      expect(found.finds.single.drink.displayName, makers.displayName);

      await expectLater(
        searchCatalogByPhoto(catalog, lines.sublist(1)),
        throwsA(isA<CatalogSearchException>()),
      );
    });

    group('a brand with several bottles', () {
      final m = _drink('몬테스 알파 M 2021', 'Montes Alpha M');
      final syrah = _drink('몬테스 알파 시라', 'Montes Alpha Syrah');
      final cabernet = _drink(
        '몬테스 알파 까베르네 소비뇽 2016',
        'Montes Alpha Cabernet Sauvignon 2016',
      );
      final catalog = _Catalog(<String, List<CatalogDrink>>{
        'MONTES ALPHA': <CatalogDrink>[m, syrah, cabernet],
      });

      test('read without the bottle is tied, and the catalog\'s year does '
          'not count against a drink', () async {
        final found = await searchCatalogByPhoto(catalog, <ReadLine>[
          _line('MONTES ALPHA', 0.30, 0.50, width: 0.4, height: 0.06),
          // The grape is behind a shelf bar; the shop's bottle is a 2022.
          _line('2022', 0.45, 0.62, width: 0.08),
          _line('D.O. VALLE DE COLCHAGUA', 0.30, 0.68, width: 0.4),
        ]);

        final search = found.finds.single.search;
        expect(search.tied, isTrue);
        expect(search.sure, isFalse);
        expect(
          search.matches.map((drink) => drink.displayName),
          containsAll(<String>[
            m.displayName,
            syrah.displayName,
            cabernet.displayName,
          ]),
        );
      });

      test('read without the bottle beside a drink read whole lists '
          'both', () async {
        final bonterra = _drink('본테라 메를로', 'Bonterra Merlot');
        final found = await searchCatalogByPhoto(
          _Catalog(<String, List<CatalogDrink>>{
            'MONTES ALPHA': <CatalogDrink>[m, syrah, cabernet],
            'BONTERRA': <CatalogDrink>[bonterra],
          }),
          <ReadLine>[
            _line('MONTES ALPHA', 0.35, 0.50, width: 0.3, height: 0.06),
            _line('BONTERRA', 0.02, 0.50, width: 0.2, height: 0.05),
            _line('MERLOT', 0.04, 0.57, width: 0.16),
          ],
        );

        expect(found.main?.search.tied, isTrue);
        expect(found.listed, hasLength(2));
        expect(
          found.listed.map((find) => find.search.sure),
          unorderedEquals(<bool>[false, true]),
        );
      });

      test('read with the bottle is that bottle', () async {
        final found = await searchCatalogByPhoto(catalog, <ReadLine>[
          _line('MONTES ALPHA', 0.30, 0.50, width: 0.4, height: 0.06),
          _line('CABERNET SAUVIGNON', 0.32, 0.58, width: 0.36),
          _line('2022', 0.45, 0.62, width: 0.08),
        ]);

        final search = found.finds.single.search;
        expect(search.matches.first.displayName, cabernet.displayName);
        expect(search.tied, isFalse);
        expect(search.sure, isTrue);
      });
    });

    test('a photo with nothing to search finds nothing', () async {
      final catalog = _Catalog(const <String, List<CatalogDrink>>{});
      final found = await searchCatalogByPhoto(catalog, <ReadLine>[
        _line('750ml', 0.3, 0.5),
        _line('ALC. 13.5% VOL.', 0.3, 0.53),
      ]);

      expect(found.finds, isEmpty);
      expect(found.queries, isEmpty);
      expect(catalog.calls, 0);
    });
  });

  // What the phone's reader made of 94 label photos, front and back of
  // fifty bottles, with what the catalog answered each search then.
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
  });
}
