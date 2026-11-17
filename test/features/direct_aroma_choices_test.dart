import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/core/catalog/catalog_assignment.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/aroma_catalog_input.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/direct_aroma_choices.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/onboarding_aroma_menu.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/onboarding_compact_aromas.dart';

import '../support/sensory_fixtures.dart';

void main() {
  final vocabulary = serviceVocabulary();
  final source = sensoryCatalog();
  final reference = aromaChoiceReference();
  final build = aromaEngine;
  final engine = build();
  List<String> keys(DirectAromaResolution result) =>
      result.ruled.map((option) => option.key).toList();
  DirectAromaResolution run({
    String category = 'wine',
    List<String> styles = const ['red_wine'],
    List<String> aromas = const [],
    List<String> processes = const [],
    AssignmentTarget target = AssignmentTarget.product,
  }) => engine.resolve(
    AromaProductContext(
      categoryKey: category,
      assignmentTarget: target,
      styleKeys: styles,
      aromaKeys: aromas,
      processKeys: processes,
    ),
  );

  test('uses exactly the approved visible aroma representatives', () {
    final expected = (vocabulary['groups'] as List)
        .where(
          (g) =>
              g['domain'] == 'descriptor' &&
              (g['phases'] as List).contains('aroma'),
        )
        .map((g) => g['key'] as String)
        .toSet();
    expect(engine.selectableKeys, expected);
    expect(engine.searchableCount, greaterThanOrEqualTo(expected.length));
    expect(engine.selectableKeys, isNot(contains('heavy_texture')));
    expect(engine.selectableKeys, isNot(contains('red_fruit')));
  });

  test('keys the contract cannot place are dropped before aroma ranking', () {
    final cases = [
      (run(category: 'sake', styles: ['red_wine']), run(category: 'sake')),
      (
        run(
          category: 'sake',
          styles: ['junmai'],
          processes: ['top_fermentation'],
        ),
        run(category: 'sake', styles: ['junmai']),
      ),
      (run(processes: ['not_a_process']), run()),
      (run(styles: ['red_wine', 'white_wine']), run(styles: [])),
    ];
    for (final (dropped, without) in cases) {
      expect(dropped.status, AromaChoiceStatus.ready);
      expect(keys(dropped), keys(without));
      expect(
        dropped.warnings.any((w) => w.startsWith('dropped_catalog_key:')),
        isTrue,
      );
    }
  });

  test('an unknown category stops before aroma ranking', () {
    final result = run(category: 'beer', styles: []);
    expect(result.status, AromaChoiceStatus.invalidInput);
    expect(result.ruled, isEmpty);
    expect(
      result.warnings,
      contains('invalid_catalog_assignment:unknown_category:category_key:'),
    );
  });

  test(
    'canonical aliases collapse without collapsing different fruit choices',
    () {
      final result = run(
        styles: ['white_wine'],
        aromas: [
          'black_cherry',
          'cherry',
          'korean_cherry',
          'apple',
          'green_apple',
          'pear',
          'peach',
        ],
      );
      // 청사과 and 블랙체리 are offered on their own now; they still sit under
      // 사과 and 체리 in the tree.
      expect(result.productKeys, {
        'cherry',
        'black_cherry',
        'apple',
        'green_apple',
        'pear',
        'peach',
      });
      expect(
        keys(result),
        containsAll([
          'cherry',
          'black_cherry',
          'apple',
          'green_apple',
          'pear',
          'peach',
        ]),
      );
      expect(keys(result).where((key) => key == 'cherry'), hasLength(1));
    },
  );

  test('visible dictionary mappings preserve source phase restrictions', () {
    final sourceByKey = <String, dynamic>{
      for (final section in ['descriptors', 'textures', 'finish_characters'])
        for (final row in source[section] as List) row['key'] as String: row,
    };
    for (final group in vocabulary['groups'] as List) {
      final aromaEligible =
          group['domain'] == 'descriptor' &&
          (group['phases'] as List).contains('aroma');
      for (final rawKey in group['source_keys'] as List) {
        final phases = sourceByKey[rawKey]['phases'] as List? ?? ['finish'];
        final expected =
            aromaEligible &&
                (rawKey == group['key'] || phases.contains('aroma'))
            ? group['key']
            : null;
        expect(
          engine.representativeFor(rawKey as String),
          expected,
          reason: rawKey,
        );
      }
    }
  });

  test('hidden, pending and non-aroma inputs cannot become options', () {
    final result = run(
      category: 'korean_traditional',
      styles: [],
      aromas: [
        'red_fruit',
        'yellow_fruit',
        'alcohol_aroma',
        'fruit',
        'rhubarb',
        'clean_finish',
        'heavy_texture',
        'creamy_texture',
        'new_unreviewed_key',
      ],
    );
    expect(result.productKeys, isEmpty);
    expect(result.ruled, isEmpty);
    expect(result.warnings, contains('unknown_aroma_key:new_unreviewed_key'));
  });

  test(
    'search is global, supports source labels and never creates a new answer',
    () {
      expect(engine.search('블랙체리').first.key, 'black_cherry');
      expect(engine.search('앵두').first.key, 'cherry');
      expect(engine.search('딸기').first.key, 'strawberry');
      expect(engine.search('블랙베리').first.key, 'blackberry');
      expect(engine.search('사과 향').first.key, 'apple');
      expect(engine.search('자스민').first.key, 'jasmine');
      expect(engine.search('cherry').first.key, 'cherry');
      expect(engine.search('알코올'), isEmpty);
      expect(engine.search('처음 보는 표현'), isEmpty);
      expect(engine.search('  '), isEmpty);
      // A family or a texture is no aroma's name; an everyday word in it may
      // still lead to aromas.
      expect(engine.search('검은 과일').map((found) => found.key), ['ginjo_aroma']);
      // What an everyday word finds stands in 가나다 order.
      expect(engine.search('묵직한 질감').map((found) => found.label), [
        '가죽',
        '다크초콜릿',
        '셰리',
        '흑설탕',
      ]);
    },
  );

  test('search puts the aroma the query names first, then the rest it '
      'finds in 가나다 order', () {
    Iterable<String> found(String query) =>
        engine.search(query).map((result) => result.label);
    Iterable<String> keys(String query) =>
        engine.search(query).map((result) => result.key);

    List<String> sorted(Iterable<String> labels) => [...labels]..sort();
    // First: an aroma whose own name is the query or begins with it, and one
    // a folded word that is the query leads to.
    expect(keys('레몬').take(2), ['lemon', 'lemon_lime']);
    expect(keys('체리').first, 'cherry');
    expect(found('타르').first, '스모키');
    expect(found('vanilla'), ['바닐라']);

    // A family brings its sub-aromas; after the family they stand in 가나다
    // order.
    expect(keys('곡물').first, 'cereal');
    expect(keys('곡물').skip(1).toSet(), engine.subAromas('cereal').toSet());
    expect(found('곡물').skip(1), sorted(found('곡물').skip(1)));
    expect(engine.subAromas('cereal').toSet(), {
      'barley',
      'corn',
      'malt',
      'rice',
      'wheat',
      'scorched_rice',
    });
    expect(keys('시트러스').first, 'citrus');
    expect(keys('시트러스'), containsAll(engine.subAromas('citrus')));
    expect(engine.subAromas('citrus'), hasLength(8));
    expect(engine.subAromas('nutty'), hasLength(9));
    expect(engine.subAromas('barley'), isEmpty);

    // What the dictionary relates to the aroma found by name, and an aroma
    // a folded word that only holds the query leads to (세이보리 → 고기·감칠맛),
    // follow it in 가나다 order.
    expect(found('보리'), ['보리', '고기·감칠맛', '누룽지', '맥아']);
    expect(found('보리차'), ['보리']);
    // What an everyday word finds is in 가나다 order from the first.
    expect(found('달콤'), sorted(found('달콤')));
    // A stem is found by a longer word; a one-syllable word is not.
    expect(keys('달콤한'), keys('달콤'));
    expect(keys('달콤'), contains('vanilla'));
    expect(keys('떡'), contains('rice'));
    expect(keys('떡갈나무'), isNot(contains('rice')));
    // Each aroma is found once.
    for (final query in ['달콤', '체리', '시트러스', '구수']) {
      expect(keys(query).toSet(), hasLength(keys(query).length));
    }
  });

  test('every visible aroma is searchable by its own displayed name', () {
    for (final group in vocabulary['groups'] as List) {
      if (engine.selectableKeys.contains(group['key'])) {
        expect(
          engine.search(group['label_ko'] as String).map((o) => o.key),
          contains(group['key']),
          reason: group['label_ko'],
        );
      }
    }
  });

  test('product features survive without fixed product/style slot quotas', () {
    const aromas = [
      'apple',
      'pear',
      'peach',
      'plum',
      'cherry',
      'berry',
      'banana',
      'mango',
      'pineapple',
    ];
    final result = run(aromas: aromas);
    expect(result.productKeys, containsAll(aromas));
    expect(keys(result), containsAll(aromas));
    expect(result.options, hasLength(10));
    expect(result.options.take(9).every((o) => o.productListed), isTrue);
  });

  test('only same representative is deduplicated; fruit can exceed half', () {
    final result = run(
      styles: ['white_wine'],
      aromas: ['apple', 'pear', 'peach'],
    );
    final fruit = (vocabulary['groups'] as List)
        .where((g) => g['category_key'] == 'fruit')
        .map((g) => g['key'])
        .toSet();
    expect(
      result.ruled.where((o) => fruit.contains(o.key)).length,
      greaterThan(result.ruled.length / 2),
    );
  });

  test(
    'permuted and duplicated input has identical ordering and provenance',
    () {
      final first = run(aromas: ['oak', 'cherry', 'black_cherry', 'spice']);
      final second = run(
        aromas: ['spice', 'black_cherry', 'oak', 'cherry', 'oak'],
      );
      expect(keys(first), keys(second));
      expect(
        first.ruled.map((o) => o.score).toList(),
        second.ruled.map((o) => o.score).toList(),
      );
      expect(
        first.ruled.map((o) => o.ruleIds).toList(),
        second.ruled.map((o) => o.ruleIds).toList(),
      );
    },
  );

  test('product evidence changes the result for the same style', () {
    expect(
      keys(run(aromas: ['oak', 'vanilla', 'spice'])),
      isNot(equals(keys(run(aromas: ['berry', 'cherry', 'floral'])))),
    );
  });

  test('category changes supplement pool without altering product facts', () {
    final wine = run(styles: ['white_wine'], aromas: ['apple']);
    final sake = run(category: 'sake', styles: ['ginjo'], aromas: ['apple']);
    expect(wine.productKeys, sake.productKeys);
    expect(keys(wine), isNot(keys(sake)));
    expect(wine.ruled.where((o) => !o.productListed), isNotEmpty);
  });

  test(
    'wood/peat are not padding; explicitly observed peat remains important',
    () {
      expect(keys(run()), isNot(contains('oak')));
      expect(
        keys(run(category: 'whisky', styles: ['single_malt_whisky'])),
        isNot(contains('peat')),
      );
      final peated = run(
        category: 'whisky',
        styles: ['single_malt_whisky'],
        aromas: ['peat'],
      );
      expect(keys(peated).first, 'peat');
      expect(keys(peated), contains('smoke'));
    },
  );

  test(
    'rule metadata conditions are effective and do not infer sake ageing',
    () {
      final ordinary = run(category: 'sake', styles: ['junmai']);
      final aged = run(
        category: 'sake',
        styles: ['junmai'],
        processes: ['extended_maturation'],
        target: AssignmentTarget.release,
      );
      expect(keys(ordinary), isNot(contains('savory')));
      expect(keys(aged), contains('savory'));
      final productClaim = run(
        category: 'sake',
        styles: ['junmai'],
        processes: ['extended_maturation'],
      );
      expect(keys(productClaim), keys(aged));
    },
  );

  test(
    'product without aroma data or rules still gets ten related options',
    () {
      final result = run(
        category: 'korean_traditional',
        styles: ['diluted_soju'],
      );
      expect(result.ruled, isEmpty);
      expect(result.status, AromaChoiceStatus.ready);
      expect(result.options, hasLength(10));
      expect(result.moreOptions, hasLength(10));
      expect(result.warnings, isEmpty);
    },
  );

  test('product aromas first, then rules, then related fill', () {
    final result = run(styles: ['white_wine'], aromas: ['apple']);
    final all = [...result.options, ...result.moreOptions];
    expect(result.options, hasLength(10));
    expect(result.moreOptions, hasLength(10));
    expect(all.first.key, 'apple');
    expect(all.first.productListed, isTrue);
    expect(all.map((o) => o.key).toSet(), hasLength(20));
    final ruleCount = all.indexWhere(
      (o) => o.ruleIds.isEmpty && !o.productListed,
    );
    expect(all.skip(ruleCount).every((o) => o.ruleIds.isEmpty), isTrue);
  });

  test('rich product exceeds ten only in the searchable dictionary', () {
    final result = run(aromas: engine.selectableKeys.toList());
    expect(result.options, hasLength(10));
    expect(result.moreOptions, hasLength(10));
    expect(result.options.every((o) => o.productListed), isTrue);
    expect(result.warnings, contains('some_product_aromas_search_only'));
    expect(result.productKeys, hasLength(engine.selectableKeys.length));
  });

  test(
    'reference styles/facets are existing category-specific taxonomy keys',
    () {
      final taxonomy = alcoholTaxonomy();
      final styles = {
        for (final s in taxonomy['primary_styles'] as List)
          s['style_key']: s['category_key'],
      };
      for (final entry in (taxonomy['style_redirects'] as Map).entries) {
        styles[entry.key] = styles[entry.value];
      }
      final production = taxonomy['production'] as Map;
      final facets = <String>{
        for (final term in [
          ...production['process_terms'] as List,
          ...production['maturation_terms'] as List,
        ])
          term['term_key'] as String,
      };
      final categories = (taxonomy['categories'] as List)
          .map((c) => c['category_key'])
          .toSet();
      expect((reference['category_limits'] as Map).keys.toSet(), categories);
      for (final rule in reference['rules'] as List) {
        final when = rule['when'] as Map;
        expect(categories.containsAll(when['categories'] as List), isTrue);
        for (final key in [
          ...when['styles_any'] as List? ?? [],
          ...when['styles_none'] as List? ?? [],
        ]) {
          expect(
            (when['categories'] as List),
            contains(styles[key]),
            reason: '$key in ${rule['id']}',
          );
        }
        expect(facets.containsAll(when['facets_any'] as List? ?? []), isTrue);
      }
    },
  );

  test('bad config fails closed instead of silently changing ranking', () {
    expect(
      () => build({...reference, 'vocabulary_version': 'wrong'}),
      throwsFormatException,
    );
    final copied = deepCopyJson(reference);
    (copied['rules'] as List).first['candidates']['heavy_texture'] = 70;
    expect(() => build(copied), throwsFormatException);
    final typo = deepCopyJson(reference);
    (typo['rules'] as List).first['when']['style_any'] = ['red_wine'];
    expect(() => build(typo), throwsFormatException);
  });

  test('reference input mutation cannot change an existing engine', () {
    final copy = deepCopyJson(reference);
    final stable = build(copy);
    final product = AromaProductContext(
      categoryKey: 'wine',
      styleKeys: ['red_wine'],
    );
    final before = keys(stable.resolve(product));
    (copy['rules'] as List).first['when']['styles_any'].clear();
    (copy['rules'] as List).first['when']['categories'].clear();
    expect(keys(stable.resolve(product)), before);
  });

  test(
    'condition typos/null/empty cannot silently disable or broaden a rule',
    () {
      for (final value in [
        null,
        <String>[],
        ['red_wien'],
        ['bourbon'],
      ]) {
        final copy = deepCopyJson(reference);
        (copy['rules'] as List).first['when']['styles_any'] = value;
        expect(() => build(copy), throwsFormatException, reason: '$value');
      }
    },
  );

  group('catalog row input', () {
    final adapter = AromaCatalogInputAdapter(
      engine: engine,
      reference: reference,
    );
    Map<String, dynamic> row(
      String category,
      String style, [
      String name = '',
    ]) => {
      'category': category,
      'style_key': style,
      'name': name,
      'aroma_keys': <String>[],
    };
    DirectAromaResolution runRow(Map<String, dynamic> input) =>
        engine.resolve(adapter.read(input).product);
    Set<String> rowKeys(DirectAromaResolution r) =>
        r.ruled.map((o) => o.key).toSet();

    test(
      'reviewed product cues provide choices without creating aroma facts',
      () {
        final context = reference['catalog_context'] as Map;
        final rules = (context['name_contexts'] as List).cast<Map>().where(
          (rule) => rule['review_basis'] != null,
        );
        expect(rules, isNotEmpty);
        for (final rule in rules) {
          final category = (rule['categories'] as List).single as String;
          final style = (rule['styles'] as List).single as String;
          final basis = rule['review_basis'] as Map;
          expect(basis['origin'], 'estimated');
          expect(basis['source'], isNotEmpty);
          for (final name in rule['words'] as List) {
            final input = row(category, style, name as String);
            final before = jsonEncode(input);
            final result = runRow(input);
            expect(result.hasEnoughOptions, isTrue, reason: name);
            expect(result.productKeys, isEmpty, reason: name);
            expect(jsonEncode(input), before);
            expect(
              adapter.read(row('wine', 'red_wine', name)).product.contextKeys,
              isEmpty,
              reason:
                  'Product cues must not cross category/style boundaries: $name',
            );
          }
        }
      },
    );

    const styles = {'gwahaju': 'korean_traditional', 'madeira_wine': 'wine'};
    for (final entry in styles.entries) {
      test(
        '${entry.key} has its own related choices, not fabricated product notes',
        () {
          final result = runRow(row(entry.value, entry.key));
          expect(result.hasEnoughOptions, isTrue);
          expect(result.warnings, isEmpty);
          expect(result.productKeys, isEmpty);
          expect(rowKeys(result).length, result.ruled.length);
          expect(engine.selectableKeys.containsAll(rowKeys(result)), isTrue);
        },
      );
    }

    const examples = [
      ['korean_traditional', 'korean_fruit_wine', '복숭아 와인', 'peach'],
      ['korean_traditional', 'korean_fruit_wine', '유자 와인', 'citrus'],
      ['korean_traditional', 'korean_fruit_wine', '블루베리 와인', 'berry'],
    ];
    for (final e in examples) {
      test(
        '${e[2]} uses an explicit name cue without changing catalog facts',
        () {
          final input = row(e[0], e[1], e[2]);
          final frozen = jsonEncode(input);
          final result = runRow(input);
          expect(result.hasEnoughOptions, isTrue);
          expect(result.ruled.first.key, e[3]);
          expect(result.productKeys, isEmpty);
          expect(jsonEncode(input), frozen);
        },
      );
    }

    test(
      'Korean drink suffixes match but names outside the scoped kind do not',
      () {
        final flower = adapter.read(
          row('korean_traditional', 'korean_fruit_wine', '금군 아카시아주'),
        );
        expect(flower.product.contextKeys, contains('floral'));
        for (final input in [
          row('wine', 'red_wine', '벨리니 에스테이트'),
          row('sake', 'junmai', '장미주'),
        ]) {
          expect(adapter.read(input).product.contextKeys, isEmpty);
        }
      },
    );

    test('sparse products without rule pools still show ten category '
        'options, not generic ones', () {
      final sparse = runRow(row('korean_traditional', 'diluted_soju'));
      expect(sparse.status, AromaChoiceStatus.ready);
      expect(sparse.options, hasLength(10));
      expect(sparse.moreOptions, hasLength(10));
      expect(sparse.warnings, isEmpty);
      expect(sparse.productKeys, isEmpty);
      final options = sparse.options.map((o) => o.key);
      expect(options, containsAll(['rice', 'nuruk', 'fermentation']));
      expect(options, isNot(contains('smoke')));

      final tagged = runRow({
        ...row('korean_traditional', 'diluted_soju'),
        'aroma_keys': ['cereal', 'fermentation'],
      });
      expect(rowKeys(tagged), {'cereal', 'fermentation'});
      expect(tagged.options.take(2).every((o) => o.productListed), isTrue);
      expect(engine.search('체리').map((o) => o.key), contains('cherry'));
    });

    test('keys this app cannot place still return options', () {
      for (final product in [
        AromaProductContext(categoryKey: 'wine', styleKeys: ['junmai']),
        AromaProductContext(
          categoryKey: 'sake',
          styleKeys: ['junmai', 'ginjo'],
        ),
        AromaProductContext(
          categoryKey: 'sake',
          styleKeys: ['junmai'],
          aromaKeys: ['not_an_aroma'],
        ),
        AromaProductContext(
          categoryKey: 'sake',
          styleKeys: ['junmai'],
          processKeys: ['unrecognized_process'],
        ),
      ]) {
        final result = engine.resolve(product);
        expect(result.status, AromaChoiceStatus.ready);
        expect(result.options, isNotEmpty);
        expect(result.productKeys, isEmpty);
      }
    });

    test(
      'sherry substyles require scoped explicit hints and remain distinct',
      () {
        final fino = runRow(row('wine', 'sherry_wine', '피노'));
        final oloroso = runRow(row('wine', 'sherry_wine', '드라이 올로로소'));
        expect(fino.hasEnoughOptions, isTrue);
        expect(oloroso.hasEnoughOptions, isTrue);
        expect(rowKeys(fino), contains('lemon_lime'));
        expect(rowKeys(fino), isNot(contains('coffee')));
        expect(rowKeys(oloroso), contains('walnut'));
        expect(fino.productKeys, isEmpty);
        expect(oloroso.productKeys, isEmpty);
        expect(
          adapter.read(row('wine', 'red_wine', '피노 누아')).product.contextKeys,
          isEmpty,
        );
      },
    );
  });

  group('style pools', () {
    DirectAromaResolution runStyle(
      String category,
      String style, [
      List<String> aromas = const [],
    ]) => run(category: category, styles: [style], aromas: aromas);

    const covered = {
      'port_wine': 'wine',
      'takju': 'korean_traditional',
      'junmai': 'sake',
    };
    for (final entry in covered.entries) {
      test(
        '${entry.key} has a bounded pool without inventing product evidence',
        () {
          final r = runStyle(entry.value, entry.key);
          expect(r.ruled.length, inInclusiveRange(8, 10));
          expect(r.productKeys, isEmpty);
          expect(
            r.ruled.every((o) => !o.productListed && o.ruleIds.isNotEmpty),
            isTrue,
          );
          expect(r.warnings, isEmpty);
        },
      );
    }

    test('distilled soju remains sparse without sufficient product cues', () {
      final sparse = runStyle('korean_traditional', 'distilled_soju');
      expect(sparse.hasEnoughOptions, isFalse);
      expect(
        keys(sparse),
        containsAll(['rice', 'floral', 'pear', 'vanilla', 'citrus']),
      );
      final withProduct = runStyle('korean_traditional', 'distilled_soju', [
        'cereal',
        'fermentation',
        'nuruk',
      ]);
      expect(withProduct.hasEnoughOptions, isTrue);
      expect(withProduct.productKeys, {'cereal', 'fermentation', 'nuruk'});
      expect(runStyle('korean_traditional', 'diluted_soju').ruled, isEmpty);
      final fruit = runStyle('korean_traditional', 'korean_fruit_wine');
      expect(fruit.hasEnoughOptions, isTrue);
      expect(keys(fruit), isNot(contains('nuruk')));
      expect(fruit.productKeys, isEmpty);
    });

    test(
      'fortified wine keeps plain and almond-only cases out of rich ranges',
      () {
        expect(runStyle('wine', 'fortified_wine').productKeys, isEmpty);
        final almond = runStyle('wine', 'fortified_wine', ['almond']);
        expect(almond.hasEnoughOptions, isTrue);
        expect(
          almond.ruled.expand((o) => o.ruleIds),
          isNot(contains('wine.fortified_nut_range')),
        );
        final dried = runStyle('wine', 'fortified_wine', ['dried_fruit']);
        expect(dried.hasEnoughOptions, isTrue);
        expect(keys(dried), contains('chocolate'));
        expect(
          dried.ruled.expand((o) => o.ruleIds),
          contains('wine.fortified_dried_range'),
        );
        expect(dried.productKeys, {'dried_fruit'});
        final nutty = runStyle('wine', 'fortified_wine', ['walnut']);
        expect(nutty.hasEnoughOptions, isTrue);
        expect(keys(nutty).first, 'walnut');
        expect(nutty.productKeys, {'walnut'});
      },
    );

    test('orange wine has a sufficient style range', () {
      expect(runStyle('wine', 'orange_wine').hasEnoughOptions, isTrue);
      expect(
        runStyle('wine', 'orange_wine', ['honey']).hasEnoughOptions,
        isTrue,
      );
    });
  });

  group('onboarding aroma menu', () {
    // Every kind the dictionary names, with the menu its drinks are asked.
    const menuOfKind = {
      'red_wine': 'wine_red',
      'white_wine': 'wine_white_sparkling_rose',
      'sparkling_wine': 'wine_white_sparkling_rose',
      'rose_wine': 'wine_white_sparkling_rose',
      'orange_wine': 'wine_white_sparkling_rose',
      'fortified_wine': 'wine_fortified',
      'port_wine': 'wine_fortified',
      'sherry_wine': 'wine_fortified',
      'madeira_wine': 'wine_fortified',
      'vermouth': 'wine_fortified',
      'single_malt_whisky': 'whisky_malt_blended',
      'blended_whisky': 'whisky_malt_blended',
      'blended_malt_whisky': 'whisky_malt_blended',
      'single_pot_still_whisky': 'whisky_malt_blended',
      'grain_whisky': 'whisky_malt_blended',
      'bourbon': 'whisky_american',
      'rye_whisky': 'whisky_american',
      'tennessee_whisky': 'whisky_american',
      'corn_whisky': 'whisky_american',
      'wheat_whisky': 'whisky_american',
      'american_whisky': 'whisky_american',
      'junmai': 'sake',
      'ginjo': 'sake',
      'daiginjo': 'sake',
      'junmai_ginjo': 'sake',
      'junmai_daiginjo': 'sake',
      'honjozo': 'sake',
      'futsushu': 'sake',
      'takju': 'korean_takju_yakju',
      'yakju': 'korean_takju_yakju',
      'korean_cheongju': 'korean_takju_yakju',
      'gwahaju': 'korean_takju_yakju',
      'distilled_soju': 'korean_distilled_soju',
      'diluted_soju': 'korean_distilled_soju',
      'korean_fruit_wine': 'korean_fruit_wine',
    };
    final categoryOfKind = {
      for (final row in alcoholTaxonomy()['primary_styles'] as List)
        row['style_key'] as String: row['category_key'] as String,
    };
    final menus = {
      for (final entry in categoryOfKind.entries)
        OnboardingAromaMenu.forDrink(entry.value, entry.key),
    };

    test('a drink gets the menu of its category and kind', () {
      expect(menuOfKind.keys.toSet(), categoryOfKind.keys.toSet());
      for (final entry in menuOfKind.entries) {
        expect(
          OnboardingAromaMenu.forDrink(
            categoryOfKind[entry.key],
            entry.key,
          ).name,
          entry.value,
          reason: entry.key,
        );
      }
      expect(menus.map((menu) => menu.name).toSet(), hasLength(9));
      // No kind, or one the category does not have: its widest menu.
      for (final style in [null, 'unknown', 'bourbon']) {
        expect(OnboardingAromaMenu.forDrink('wine', style).name, 'wine_red');
        expect(OnboardingAromaMenu.forDrink('sake', style).name, 'sake');
        expect(
          OnboardingAromaMenu.forDrink('korean_traditional', style).name,
          'korean_takju_yakju',
        );
      }
      for (final style in [null, 'unknown', 'white_wine']) {
        expect(
          OnboardingAromaMenu.forDrink('whisky', style).name,
          'whisky_malt_blended',
        );
      }
      // Any other category is asked as a malt whisky.
      for (final category in [null, 'unknown', 'beer']) {
        expect(
          OnboardingAromaMenu.forDrink(category, 'bourbon').name,
          'whisky_malt_blended',
        );
      }
    });

    test('the short lists of the palate and the finish follow the drink\'s '
        'category and kind', () {
      String listsOf(String? category, String? style) =>
          OnboardingCompactAromas.forDrink(category, style).name;
      for (final (category, style, name) in [
        ('wine', 'red_wine', 'wine_red'),
        ('wine', 'port_wine', 'wine_red'),
        ('wine', 'white_wine', 'wine_white_sparkling'),
        ('wine', 'sparkling_wine', 'wine_white_sparkling'),
        ('wine', 'rose_wine', 'wine_rose_natural'),
        ('wine', 'orange_wine', 'wine_rose_natural'),
        ('whisky', 'single_malt_whisky', 'whisky_single_malt'),
        ('whisky', 'blended_malt_whisky', 'whisky_single_malt'),
        ('whisky', 'bourbon', 'whisky_bourbon_blended'),
        ('whisky', 'rye_whisky', 'whisky_bourbon_blended'),
        ('whisky', 'blended_whisky', 'whisky_bourbon_blended'),
        ('whisky', 'grain_whisky', 'whisky_bourbon_blended'),
        ('korean_traditional', 'takju', 'korean_takju'),
        ('korean_traditional', 'yakju', 'korean_yakju_cheongju'),
        ('korean_traditional', 'korean_cheongju', 'korean_yakju_cheongju'),
        ('korean_traditional', 'distilled_soju', 'korean_distilled_soju'),
        ('korean_traditional', 'diluted_soju', 'korean_distilled_soju'),
        ('sake', 'junmai', 'sake'),
        ('korean_traditional', 'korean_fruit_wine', 'korean_fruit_wine'),
      ]) {
        expect(listsOf(category, style), name, reason: '$category $style');
      }
      // No kind, or one the category does not have: its widest lists.
      for (final style in [null, 'unknown', 'bourbon']) {
        expect(listsOf('wine', style), 'wine_red');
        expect(listsOf('sake', style), 'sake');
        expect(listsOf('korean_traditional', style), 'korean_takju');
      }
      for (final style in [null, 'unknown', 'white_wine']) {
        expect(listsOf('whisky', style), 'whisky_single_malt');
      }
      // Any other category is asked as a red wine.
      for (final category in [null, 'unknown', 'beer']) {
        expect(listsOf(category, 'bourbon'), 'wine_red');
      }
      // Every kind of the catalog has lists, ten pairs in all.
      expect({
        for (final entry in categoryOfKind.entries)
          listsOf(entry.value, entry.key),
      }, hasLength(10));

      final redWine = OnboardingCompactAromas.forDrink('wine', 'red_wine');
      expect(redWine.palate.take(6), [
        'black_cherry',
        'plum',
        'vanilla',
        'pepper',
        'mocha',
        'herbal',
      ]);
      expect(redWine.finish.take(6), [
        'oak',
        'dark_chocolate',
        'coffee',
        'dried_fruit',
        'leather',
        'clove',
      ]);
      // A fruit wine has lists of its own, not a rosé's.
      final rose = OnboardingCompactAromas.forDrink('wine', 'rose_wine');
      final fruitWine = OnboardingCompactAromas.forDrink(
        'korean_traditional',
        'korean_fruit_wine',
      );
      expect(rose.palate.first, 'strawberry');
      expect(fruitWine.palate, [
        'omija_bokbunja',
        'berry',
        'grape',
        'plum',
        'apple',
        'honey',
        'blackberry',
        'raspberry',
        'pear',
        'cherry',
        'floral',
        'herbal',
      ]);
      expect(fruitWine.finish, [
        'berry',
        'honey',
        'oak',
        'herbal',
        'cinnamon',
        'floral',
        'vanilla',
        'plum',
        'wood',
        'ginger',
        'medicinal_herb',
        'fermentation',
      ]);

      // The menu carries its drink's lists as chips, chosen apart from the
      // menu itself: a blended whisky has the malt menu and the bourbon
      // lists.
      final blended = OnboardingAromaMenu.forDrink('whisky', 'blended_whisky');
      final lists = OnboardingCompactAromas.forDrink(
        'whisky',
        'blended_whisky',
      );
      expect(blended.name, 'whisky_malt_blended');
      expect(blended.palateShortList.map((chip) => chip.key), lists.palate);
      expect(blended.finishShortList.map((chip) => chip.key), lists.finish);
      expect(lists.palate.first, 'caramel');
    });

    test('every menu chip stores a selectable dictionary key, once', () {
      for (final menu in menus) {
        final menuKeys = menu.keys.toList();
        expect(menuKeys.toSet(), hasLength(menuKeys.length), reason: menu.name);
        expect(engine.selectableKeys, containsAll(menuKeys), reason: menu.name);
        expect(menu.groups, isNotEmpty);
        for (final group in menu.groups) {
          expect(group.title, isNotEmpty);
          expect(group.chips, isNotEmpty);
        }
      }
    });

    test('a key has one emoji and the dictionary word in every menu', () {
      final words = {
        for (final group in vocabulary['groups'] as List)
          group['key'] as String: group['label_ko'] as String,
      };
      final emoji = <String, String>{};
      for (final chip
          in menus.expand((menu) => menu.groups).expand((g) => g.chips)) {
        expect(chip.label, words[chip.key], reason: chip.key);
        expect(chip.emoji, isNotEmpty);
        expect(emoji.putIfAbsent(chip.key, () => chip.emoji), chip.emoji);
      }
      expect(emoji, hasLength(128));
    });

    test('menus differ where the drinks do', () {
      Iterable<String> keysOf(String category, String? style) =>
          OnboardingAromaMenu.forDrink(category, style).keys;
      expect(keysOf('whisky', 'single_malt_whisky'), contains('peat'));
      expect(keysOf('whisky', 'bourbon'), isNot(contains('peat')));
      expect(keysOf('whisky', 'bourbon'), contains('corn'));
      expect(keysOf('wine', 'red_wine'), contains('blackberry'));
      expect(keysOf('wine', 'white_wine'), isNot(contains('blackberry')));
      expect(keysOf('wine', 'port_wine'), contains('sherry'));
      expect(keysOf('sake', 'junmai'), contains('ginjo_aroma'));
      expect(keysOf('sake', 'junmai'), isNot(contains('smoke')));
      expect(keysOf('korean_traditional', 'takju'), contains('mugwort'));
      expect(
        keysOf('korean_traditional', 'korean_fruit_wine').first,
        'omija_bokbunja',
      );
    });
  });
}
