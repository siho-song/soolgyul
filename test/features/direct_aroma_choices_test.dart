import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/core/catalog/catalog_assignment.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/aroma_catalog_input.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/direct_aroma_choices.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/onboarding_aroma_menu.dart';

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

  test('invalid assignments stop before aroma ranking', () {
    final cases = [
      run(category: 'sake', styles: ['red_wine']),
      run(
        category: 'sake',
        styles: ['junmai'],
        processes: ['top_fermentation'],
      ),
      run(processes: ['not_a_process']),
      run(styles: ['red_wine', 'white_wine']),
    ];
    for (final result in cases) {
      expect(result.ruled, isEmpty);
      expect(
        result.warnings.any((w) => w.startsWith('invalid_catalog_assignment:')),
        isTrue,
      );
    }
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
      // 청사과 is offered on its own now; it still sits under 사과 in the tree.
      expect(result.productKeys, {
        'cherry',
        'apple',
        'green_apple',
        'pear',
        'peach',
      });
      expect(
        keys(result),
        containsAll(['cherry', 'apple', 'green_apple', 'pear', 'peach']),
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
      expect(engine.search('블랙체리').first.key, 'cherry');
      expect(engine.search('딸기').first.key, 'strawberry');
      expect(engine.search('블랙베리').first.key, 'berry');
      expect(engine.search('사과 향').first.key, 'apple');
      expect(engine.search('자스민').first.key, 'jasmine');
      expect(engine.search('cherry').first.key, 'cherry');
      expect(engine.search('검은 과일'), isEmpty);
      expect(engine.search('알코올'), isEmpty);
      expect(engine.search('묵직한 질감'), isEmpty);
      expect(engine.search('처음 보는 표현'), isEmpty);
      expect(engine.search('  '), isEmpty);
    },
  );

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
      vocabulary: vocabulary,
      sourceCatalog: source,
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
            expect(adapter.read(input).recoveredAromaKeys, isEmpty);
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
          expect(adapter.read(input).recoveredAromaKeys, isEmpty);
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

    test('invalid or missing assignments return no options', () {
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
        expect(result.status, AromaChoiceStatus.invalidInput);
        if (result.productKeys.isEmpty && product.aromaKeys.isEmpty) {
          expect(result.options, isEmpty);
        }
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
    const categories = ['wine', 'whisky', 'sake', 'korean_traditional'];

    test('every menu chip stores a selectable dictionary key, once', () {
      for (final category in [...categories, null, 'unknown']) {
        final menu = OnboardingAromaMenu.forCategory(category);
        final menuKeys = menu.keys.toList();
        expect(menuKeys.toSet(), hasLength(menuKeys.length), reason: category);
        expect(engine.selectableKeys, containsAll(menuKeys), reason: category);
        for (final chip in menu.groups.expand((group) => group.chips)) {
          expect(chip.label, isNotEmpty);
        }
      }
    });

    test('each category shows four headed groups of four chips', () {
      for (final category in categories) {
        final menu = OnboardingAromaMenu.forCategory(category);
        expect(menu.groups, hasLength(4), reason: category);
        for (final group in menu.groups) {
          expect(group.chips, hasLength(4), reason: '$category ${group.title}');
        }
      }
    });

    test('categories differ where the drinks do', () {
      expect(OnboardingAromaMenu.forCategory('whisky').keys, contains('smoke'));
      expect(
        OnboardingAromaMenu.forCategory('sake').keys,
        isNot(contains('smoke')),
      );
      expect(OnboardingAromaMenu.forCategory('sake').keys, contains('rice'));
      expect(
        OnboardingAromaMenu.forCategory(null).keys,
        isNot(contains('ginjo_aroma')),
      );
    });
  });
}
