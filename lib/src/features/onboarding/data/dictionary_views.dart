/// The one dictionary (catalog/dictionary/terms.json), read as the maps the
/// questionnaire engines take: the service vocabulary (what the reader is
/// offered), the sensory catalog (every aroma, texture and finish name) and the
/// enrichment taxonomy (categories, kinds and production terms).
library;

const _sensoryTypes = {'aroma_family', 'aroma', 'texture', 'finish_character'};

final _rowsOf = Expando<List<Map<String, dynamic>>>();

/// The file's rows as one flat list, each naming its type and parent, the
/// way the views below read them. The file keeps a row where it belongs
/// (attributes or senses, then its group and parent) and states its own
/// sections under `layout`; tools/catalog/dictionary/project.py writes it.
List<Map<String, dynamic>> _rows(Map<String, dynamic> dictionary) =>
    _rowsOf[dictionary] ??= _flatten(dictionary);

List<Map<String, dynamic>> _flatten(Map<String, dynamic> file) {
  final rows = <Map<String, dynamic>>[];
  void walk(List nodes, String type, Map section, Map<String, dynamic>? above) {
    // The rows of another type a row keeps under it (a region's styles).
    final held = section['held'] as List? ?? const [];
    for (final node in nodes) {
      final row = Map<String, dynamic>.from(node as Map)..remove('items');
      for (final kept in held) {
        row.remove((kept as Map)['under']);
      }
      row['type'] = type;
      if (above != null &&
          (above['type'] == type || section['link'] == 'parent')) {
        row['parent'] = above['key'];
      } else if (above != null) {
        row['extra'] = {..._map(row['extra']), 'family_key': above['key']};
      }
      rows.add(row);
      for (final kept in held) {
        for (final under in node[(kept as Map)['under']] as List? ?? const []) {
          rows.add({
            ...under as Map<String, dynamic>,
            'type': kept['item'],
            'extra': {..._map(under['extra']), kept['names']: node['key']},
          });
        }
      }
      walk(node['items'] as List? ?? const [], section['item'], section, row);
    }
  }

  for (final section in file['layout'] as List) {
    Object? nodes = file;
    for (final name in (section as Map)['path'] as List) {
      nodes = (nodes! as Map)[name];
    }
    walk(
      nodes! as List,
      (section['group'] ?? section['item']) as String,
      section,
      null,
    );
  }
  return rows;
}

List<Map<String, dynamic>> _terms(
  Map<String, dynamic> dictionary,
  Set<String> types,
) {
  return [
    for (final row in _rows(dictionary))
      if (types.contains(row['type'])) Map<String, dynamic>.from(row),
  ];
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

/// What `catalog/sensory/service-vocabulary.json` held.
Map<String, dynamic> serviceVocabularyView(Map<String, dynamic> dictionary) {
  final sensory = _terms(dictionary, _sensoryTypes);
  final shown =
      [
        for (final term in sensory)
          if (_map(term['app'])['shown'] != null) term,
      ]..sort(
        (a, b) => (_map(_map(a['app'])['shown'])['order'] as int).compareTo(
          _map(_map(b['app'])['shown'])['order'] as int,
        ),
      );
  final groups = [
    for (final term in shown)
      () {
        final s = _map(_map(term['app'])['shown']);
        // What the aroma search also finds this word by; only aromas have it.
        final search = _map(_map(term['app'])['search']);
        return <String, dynamic>{
          'key': term['key'],
          'label_ko': s['label'],
          'category_key': s['category'],
          'domain': s['domain'],
          'source_keys': s['members'],
          'user_source_labels': s['source_labels'],
          'phases': s['phases'],
          'decision_origin': s['decision_origin'],
          'search_words': search['words'] ?? const <String>[],
          'related_keys': search['related'] ?? const <String>[],
        };
      }(),
  ];
  final hidden = <String, List<String>>{};
  final pending = <Map<String, dynamic>>[];
  final legacy = <String, String>{};
  for (final term in sensory) {
    final app = _map(term['app']);
    final reason = app['hidden_reason'];
    if (reason is String) {
      hidden.putIfAbsent(reason, () => []).add(term['key'] as String);
    }
    final pendingEntry = app['pending'];
    if (pendingEntry is Map) {
      pending.add({
        'key': term['key'],
        'label_ko': pendingEntry['label'],
        'reason': pendingEntry['reason'],
      });
    }
    for (final old
        in (_map(term['extra'])['legacy_keys'] as List?) ?? const []) {
      legacy[old as String] = term['key'] as String;
    }
  }
  final versions = _map(_map(dictionary['versions'])['service_vocabulary']);
  return {
    'schema_version': versions['schema_version'],
    'taxonomy_version': versions['taxonomy_version'],
    'decision': versions['decision'],
    'categories': dictionary['app_categories'],
    'groups': groups,
    'hidden': [
      for (final entry in hidden.entries)
        {'reason': entry.key, 'source_keys': entry.value},
    ],
    'pending': pending,
    'legacy_aliases': legacy,
  };
}

Map<String, dynamic> _sensoryEntry(
  Map<String, dynamic> term, {
  bool finish = false,
}) {
  final names = _map(term['names']);
  final app = _map(term['app']);
  final entry = <String, dynamic>{
    'key': term['key'],
    'label_ko': names['ko'],
    if (names['en'] != null) 'label_en': names['en'],
    if (!finish) 'aliases': names['aliases'] ?? const <String>[],
    if (!finish) 'parent_key': term['parent'],
    if (app['selectable'] != null) 'onboarding_selectable': app['selectable'],
    if (!finish) 'phases': app['phases'] ?? const <String>[],
    'source_aliases': const <String, dynamic>{},
  };
  for (final extra in _map(term['extra']).entries) {
    if (extra.key == 'legacy_keys' ||
        extra.key == 'knowledge_only' ||
        extra.key == 'taxonomy') {
      continue;
    }
    entry[extra.key] = extra.value;
  }
  return entry;
}

/// What `catalog/sensory/catalog.json` held.
Map<String, dynamic> sensoryCatalogView(Map<String, dynamic> dictionary) {
  List<Map<String, dynamic>> rows(String type, {bool finish = false}) => [
    for (final term in _terms(dictionary, {type}))
      if (_map(term['extra'])['knowledge_only'] != true)
        _sensoryEntry(term, finish: finish),
  ];
  return {
    'service_vocabulary': 'catalog/sensory/service-vocabulary.json',
    'families': [
      for (final term in _terms(dictionary, {'aroma_family'}))
        {
          'key': term['key'],
          'label_ko': _map(term['names'])['ko'],
          'domain': _map(term['extra'])['domain'],
          'kind': _map(term['extra'])['kind'],
        },
    ],
    'descriptors': rows('aroma'),
    'expression_rules': dictionary['expression_rules'],
    'finish_characters': rows('finish_character', finish: true),
    'textures': rows('texture'),
  };
}

/// One taxonomy item in its own field order: a null value is filled from the
/// row's taxonomy-only fields (extra.taxonomy) when it has one.
Map<String, dynamic> _taxonomyEntry(
  Map<String, dynamic> term,
  List<(String, Object?)> fields,
) {
  final rest = _map(_map(term['extra'])['taxonomy']);
  return {
    for (final (field, value) in fields)
      if (value != null)
        field: value
      else if (rest.containsKey(field))
        field: rest[field],
  };
}

Map<String, dynamic> _taxonomyTerm(
  Map<String, dynamic> term,
  String keyField, {
  String? parentField,
  List<String> middle = const [],
}) {
  final names = _map(term['names']);
  return _taxonomyEntry(term, [
    (keyField, term['key']),
    if (parentField != null) (parentField, term['parent']),
    for (final field in middle) (field, null),
    ('name_ko', names['ko']),
    ('name_en', names['en']),
    ('definition', term['definition_en']),
    ('definition_source', null),
    ('source_standard_url', null),
    ('aliases', names['aliases'] ?? const <String>[]),
    ('applies_to_categories', term['categories']),
    ('parent_ingredient_key', null),
    ('parent_term_key', null),
    ('excludes_term_keys', null),
    ('applies_to_styles', null),
  ]);
}

/// What `config/catalog/enrichment_taxonomy_v2.json` held.
Map<String, dynamic> taxonomyView(Map<String, dynamic> dictionary) {
  final byKey = {
    for (final row in _rows(dictionary))
      '${row['type']}:${row['key']}': Map<String, dynamic>.from(row),
  };
  List<Map<String, dynamic>> kindsOnly(String type) => [
    for (final term in _terms(dictionary, {type})) _taxonomyTerm(term, 'key'),
  ];
  List<Map<String, dynamic>> productionTerms(String type) => [
    for (final term in _terms(dictionary, {type}))
      _taxonomyTerm(
        term,
        'term_key',
        parentField: 'kind_key',
        middle: const ['process_stage'],
      ),
  ];
  final unplaced = {
    for (final raw in dictionary['unplaced_descriptors'] as List)
      (raw as Map)['descriptor_key']: Map<String, dynamic>.from(raw),
  };
  Map<String, dynamic> descriptor(String key) {
    final term = [
      'aroma',
      'texture',
      'finish_character',
      'aroma_family',
    ].map((type) => byKey['$type:$key']).firstWhere((t) => t != null)!;
    final x = _map(_map(term['extra'])['taxonomy']);
    return {
      'descriptor_key': key,
      'descriptor_family': x['descriptor_family'],
      'name_ko': x['name_ko'],
      'name_en': x['name_en'],
      'definition': term['definition_en'],
      for (final field in const [
        'aliases',
        'sensory_phases',
        'applies_to_categories',
        'parent_descriptor_key',
      ])
        if (x.containsKey(field)) field: x[field],
    };
  }

  final order = _map(dictionary['taxonomy_order']);
  final version = _map(_map(dictionary['versions'])['taxonomy']);
  return {
    r'$schema': version['schema'],
    'taxonomy_version': version['version'],
    'base_taxonomy': dictionary['base_taxonomy'],
    'ingredients': {
      'types': kindsOnly('ingredient_type'),
      'roles': dictionary['ingredient_roles'],
      'terms': [
        for (final term in _terms(dictionary, {'ingredient'}))
          _taxonomyTerm(
            term,
            'ingredient_key',
            parentField: 'ingredient_type_key',
          ),
      ],
    },
    'governance': dictionary['governance'],
    'source_mapping_policy': dictionary['source_mapping_policy'],
    'categories': [
      for (final term in _terms(dictionary, {'category'}))
        _taxonomyEntry(term, [
          ('category_key', term['key']),
          ('name_ko', _map(term['names'])['ko']),
          ('name_en', _map(term['names'])['en']),
          ('sort_order', null),
        ]),
    ],
    'primary_styles': [
      for (final key in order['kinds'] as List)
        _taxonomyTerm(
          byKey['kind:$key']!,
          'style_key',
          parentField: 'category_key',
        ),
    ],
    'sensory': {
      'phase_keys': dictionary['sensory_phases'],
      'descriptors': [
        for (final key in order['descriptors'] as List)
          unplaced[key] ?? descriptor(key as String),
      ],
      'scalar_dimensions': [
        for (final term in _terms(dictionary, {'axis'}))
          if (_map(term['extra'])['taxonomy'] != null)
            _taxonomyEntry(term, [
              ('dimension_key', term['key']),
              ('name_ko', _map(term['names'])['ko']),
              ('name_en', _map(term['names'])['en']),
              ('definition', term['definition_en']),
              for (final field in const [
                'sensory_phase',
                'minimum',
                'maximum',
                'unknown_allowed',
                'supports_explicit_absence',
                'applies_to_categories',
                'bands',
              ])
                (field, null),
            ]),
      ],
    },
    'production': {
      'process_kinds': kindsOnly('process_kind'),
      'process_terms': productionTerms('process'),
      'maturation_kinds': kindsOnly('maturation_kind'),
      'maturation_terms': productionTerms('maturation'),
    },
    'style_redirects': dictionary['style_redirects'],
  };
}
