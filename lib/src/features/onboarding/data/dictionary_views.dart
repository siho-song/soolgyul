/// The dictionary's words for what is sensed (catalog/dictionary/senses.json),
/// read as the maps the questionnaire engines take: the service vocabulary
/// (what the reader is offered) and the sensory catalog (every aroma, texture
/// and finish word a bottle can be tagged with). The kinds and production
/// terms the engines check rules against come from the DB term contract
/// (config/catalog/enrichment_taxonomy_v2.json), read as it is.
library;

const _senseType = {
  'descriptor': 'aroma',
  'texture': 'texture',
  'finish_character': 'finish_character',
};
const _domainOf = {
  'aroma': 'descriptor',
  'texture': 'texture',
  'finish_character': 'finish_character',
};

/// One word with its type, family and the word above it.
typedef _Row = ({
  Map<String, dynamic> word,
  String type,
  String? family,
  String? above,
});

final _rowsOf = Expando<List<_Row>>();

List<_Row> _rows(Map<String, dynamic> senses) =>
    _rowsOf[senses] ??= _walkSenses(senses);

List<_Row> _walkSenses(Map<String, dynamic> senses) {
  final out = <_Row>[];
  void walk(List words, String type, String? family, String? above) {
    for (final raw in words) {
      final word = Map<String, dynamic>.from(raw as Map);
      out.add((word: word, type: type, family: family, above: above));
      walk(word['words'] as List? ?? const [], type, family, word['key']);
    }
  }

  for (final raw in senses['families'] as List) {
    final family = raw as Map;
    walk(
      family['words'] as List,
      _senseType[family['of']]!,
      family['key'] as String,
      null,
    );
  }
  for (final entry in (senses['words_of_no_family'] as Map).entries) {
    walk(entry.value as List, entry.key as String, null, null);
  }
  return out;
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

List<String> _strings(Object? value) =>
    value is List ? value.cast<String>() : const [];

/// The offered word each word folds into: the one it names (`shown_as`), else
/// the nearest offered word at or above it.
Map<String, String?> _foldTargets(List<_Row> rows) {
  final shown = {
    for (final r in rows)
      if (r.word['choice'] != null) r.word['key'] as String,
  };
  final above = {for (final r in rows) r.word['key'] as String: r.above};
  return {
    for (final r in rows)
      r.word['key'] as String: r.word.containsKey('shown_as')
          ? r.word['shown_as'] as String?
          : () {
              String? key = r.word['key'] as String;
              while (key != null && !shown.contains(key)) {
                key = above[key];
              }
              return key;
            }(),
  };
}

/// The words a bottle can be tagged with: all but those kept for meaning only.
bool _isSource(_Row row) => row.word['meaning_only'] != true;

/// What the reader is offered: the groups in order, and the words kept back.
Map<String, dynamic> serviceVocabularyView(Map<String, dynamic> senses) {
  final rows = _rows(senses);
  final targets = _foldTargets(rows);
  final sources = {
    for (final r in rows)
      if (_isSource(r)) r.word['key'] as String,
  };
  final shown =
      [
        for (final r in rows)
          if (r.word['choice'] != null) r,
      ]..sort(
        (a, b) => (_map(a.word['choice'])['order'] as int).compareTo(
          _map(b.word['choice'])['order'] as int,
        ),
      );
  final groups = [
    for (final r in shown)
      () {
        final key = r.word['key'] as String;
        final choice = _map(r.word['choice']);
        return <String, dynamic>{
          'key': key,
          'label_ko': choice['label'],
          'category_key': choice['group'],
          'domain': _domainOf[r.type],
          'source_keys': [
            for (final entry in targets.entries)
              if (entry.value == key && sources.contains(entry.key)) entry.key,
          ],
          'user_source_labels': _strings(choice['found_by']),
          'phases': choice['said_of'] ?? r.word['said_of'] ?? const <String>[],
          'search_words': _strings(r.word['search']),
          'related_keys': _strings(r.word['search_related']),
        };
      }(),
  ];
  final pending = [
    for (final raw in senses['families'] as List)
      if ((raw as Map)['pending'] != null)
        {
          'key': raw['key'],
          'label_ko': _map(raw['pending'])['label'],
          'reason': _map(raw['pending'])['reason'],
        },
    for (final r in rows)
      if (r.word['pending'] != null)
        {
          'key': r.word['key'],
          'label_ko': _map(r.word['pending'])['label'],
          'reason': _map(r.word['pending'])['reason'],
        },
  ];
  final offered = {for (final r in shown) r.word['key'] as String};
  final held = {for (final p in pending) p['key'] as String};
  final hidden = [
    for (final r in rows)
      if (!offered.contains(r.word['key']) &&
          !held.contains(r.word['key']) &&
          !offered.contains(targets[r.word['key']]))
        r.word['key'] as String,
  ];
  final choice = _map(senses['choice']);
  return {
    'schema_version': choice['version'],
    'taxonomy_version': choice['taxonomy_version'],
    'categories': [
      for (final raw in choice['groups'] as List)
        {'key': (raw as Map)['key'], 'label_ko': raw['ko']},
    ],
    'groups': groups,
    'hidden': [
      if (hidden.isNotEmpty) {'reason': 'not offered', 'source_keys': hidden},
    ],
    'pending': pending,
    'legacy_aliases': {
      for (final r in rows)
        for (final old in _strings(r.word['old_keys'])) old: r.word['key'],
    },
  };
}

/// Every word a bottle can be tagged with, by section.
Map<String, dynamic> sensoryCatalogView(Map<String, dynamic> senses) {
  Map<String, dynamic> entry(_Row r) => {
    'key': r.word['key'],
    'label_ko': r.word['ko'],
    if (r.word['en'] != null) 'label_en': r.word['en'],
    if (r.type != 'finish_character') ...{
      'aliases': _strings(r.word['aliases']),
      'parent_key': r.above,
      'phases': _strings(r.word['said_of']),
    },
    if (r.family != null) 'family_key': r.family,
  };
  final rows = _rows(senses).where(_isSource).toList();
  return {
    'families': [
      for (final raw in senses['families'] as List)
        {
          'key': (raw as Map)['key'],
          'label_ko': raw['ko'],
          'domain': raw['of'],
          'kind': raw['kind'] ?? 'sensory',
        },
    ],
    'descriptors': [
      for (final r in rows)
        if (r.type == 'aroma') entry(r),
    ],
    'finish_characters': [
      for (final r in rows)
        if (r.type == 'finish_character') entry(r),
    ],
    'textures': [
      for (final r in rows)
        if (r.type == 'texture') entry(r),
    ],
  };
}
