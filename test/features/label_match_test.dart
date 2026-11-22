import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_drink.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_search_gateway.dart';
import 'package:soolgyul/src/features/taste_fit/data/label_catalog_search.dart';
import 'package:soolgyul/src/features/taste_fit/data/label_layout.dart';
import 'package:soolgyul/src/features/taste_fit/data/label_match.dart';

// The fold, the ranker and the sure decision must give what the models
// were trained with: the fixture holds the training side's answers.
final Map<String, dynamic> _fixture =
    jsonDecode(File('test/fixtures/label_match.json').readAsStringSync())
        as Map<String, dynamic>;

ReadLine _line(String text, {double top = 0.4, double height = 0.05}) =>
    ReadLine(text: text, left: 0.2, top: top, width: 0.6, height: height);

LabelCandidate _candidate(
  String id,
  String nameKo,
  String nameEn, {
  List<String> producer = const <String>[],
  double found = 10,
  double? age,
}) {
  final words = <String>[
    ...labelMatchWords(nameEn),
    ...labelMatchWords(nameKo),
  ];
  return LabelCandidate(
    drink: CatalogDrink(
      id: id,
      displayName: nameKo,
      nameEn: nameEn,
      category: DrinkCategory.whisky,
      labelFacts: DrinkLabelFacts(producer: producer, ageYears: age),
    ),
    kind: 'whisky',
    nameRarity: <String, double>{for (final word in words) word: 7},
    found: found,
  );
}

class _WordCatalog implements LabelWordSearch {
  _WordCatalog(this.answer);

  final List<LabelCandidate> answer;
  List<String> words = const <String>[];
  List<String> alsoIds = const <String>[];

  @override
  Future<List<LabelCandidate>> searchByLabelWords(
    List<String> words, {
    List<String> alsoIds = const <String>[],
  }) async {
    this.words = words;
    this.alsoIds = alsoIds;
    return answer;
  }
}

void main() {
  test('folds text as the catalog and the training did', () {
    final folds = (_fixture['folds'] as Map).cast<String, String>();
    for (final MapEntry(key: text, value: folded) in folds.entries) {
      expect(labelMatchFold(text), folded, reason: text);
    }
  });

  test('the ranker scores as the trained trees do', () {
    for (final probe in (_fixture['ranker'] as List).cast<Map>()) {
      final input = <double>[
        for (final value in probe['input'] as List) (value as num).toDouble(),
      ];
      expect(labelRankerScore(input), closeTo(probe['score'] as num, 1e-9));
    }
  });

  test('the sure decision scores as the trained regression does', () {
    for (final probe in (_fixture['sure'] as List).cast<Map>()) {
      final input = <double>[
        for (final value in probe['input'] as List) (value as num).toDouble(),
      ];
      expect(labelSureScore(input), closeTo(probe['p'] as num, 1e-9));
    }
  });

  test('asks with the words read, each two neighbours joined, once each', () {
    expect(
      labelMatchQueryWords(<ReadLine>[
        _line('GLEN GRANT'),
        _line('12 YEARS OLD'),
        _line('Glen Grant'),
      ]),
      <String>[
        'glen',
        'glengrant',
        'grant',
        '12years',
        'years',
        'yearsold',
        'old',
      ],
    );
  });

  group('rankLabelMatch', () {
    test('puts first the drink whose rare words were read', () {
      final match = rankLabelMatch(
        <ReadLine>[_line('GLENGRANT', height: 0.1), _line('12 YEARS')],
        <LabelCandidate>[
          _candidate('a', '글렌피딕 12년', 'Glenfiddich 12 Year Old'),
          _candidate('b', '글렌그란트 12년', 'Glengrant 12 Year Old'),
        ],
      );
      expect(match.drinks.first.id, 'b');
      expect(match.state, isNot(LabelMatchState.none));
    });

    test('keeps one row a drink: its years are the same drink', () {
      final match = rankLabelMatch(
        <ReadLine>[_line('CAYMUS')],
        <LabelCandidate>[
          _candidate(
            'a',
            '케이머스 까베르네 소비뇽 2019',
            'Caymus Cabernet Sauvignon 2019',
          ),
          _candidate(
            'b',
            '케이머스 까베르네 소비뇽 2020',
            'Caymus Cabernet Sauvignon 2020',
          ),
        ],
      );
      expect(match.drinks, hasLength(1));
    });

    test('says nothing without candidates or words', () {
      expect(
        rankLabelMatch(<ReadLine>[
          _line('CAYMUS'),
        ], const <LabelCandidate>[]).state,
        LabelMatchState.none,
      );
      expect(
        rankLabelMatch(const <ReadLine>[], <LabelCandidate>[
          _candidate('a', '케이머스', 'Caymus'),
        ]).state,
        LabelMatchState.none,
      );
    });

    test(
      'names the brand alone when its bottles lead and the label names it',
      () {
        final producer = <String>['Glenfarclas', '글렌파클라스'];
        final match = rankLabelMatch(
          <ReadLine>[_line('GLENFARCLAS', height: 0.1), _line('HIGHLAND')],
          <LabelCandidate>[
            for (final (id, age) in <(String, double)>[
              ('a', 10),
              ('b', 12),
              ('c', 15),
            ])
              _candidate(
                id,
                '글렌파클라스 ${age.toInt()}년',
                'Glenfarclas ${age.toInt()} Year Old',
                producer: producer,
                age: age,
              ),
          ],
        );
        expect(match.state, LabelMatchState.brand);
      },
    );
  });

  test(
    'matchLabelPhoto asks with the words read and the line search finds',
    () async {
      final drink = _candidate('b', '글렌그란트 12년', 'Glengrant 12 Year Old');
      final catalog = _WordCatalog(<LabelCandidate>[drink]);
      final lines = <ReadLine>[_line('GLENGRANT')];
      final lineSearch = PhotoSearch(
        finds: <LabelFind>[
          LabelFind(
            group: LabelGroup(lines: lines),
            search: LabelSearch(
              queries: const <String>['GLENGRANT'],
              matches: <CatalogDrink>[drink.drink],
            ),
          ),
        ],
        queries: const <String>['GLENGRANT'],
      );
      final match = await matchLabelPhoto(catalog, lines, lineSearch);
      expect(catalog.words, <String>['glengrant']);
      expect(catalog.alsoIds, <String>['b']);
      expect(match.drinks.single.id, 'b');
    },
  );

  test('lineFindsOf reads a whole photo as the models learned it', () {
    final lines = <ReadLine>[_line('A')];
    LabelFind find(String name, {bool sure = false}) => LabelFind(
      group: LabelGroup(lines: lines),
      search: LabelSearch(
        queries: const <String>[],
        matches: <CatalogDrink>[
          CatalogDrink(
            id: name,
            displayName: '$name 2019',
            category: DrinkCategory.other,
          ),
        ],
        sure: sure,
      ),
    );
    final finds = lineFindsOf(
      PhotoSearch(
        finds: <LabelFind>[find('가', sure: true), find('나')],
        queries: const <String>[],
      ),
    );
    expect(finds.first.names, <String>['가']);
    expect(finds.first.first, isTrue);
    expect(finds.first.sure, isTrue);
  });
}
