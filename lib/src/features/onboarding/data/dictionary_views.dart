/// The dictionary's words for what is sensed (catalog/dictionary/senses.json),
/// read as the map the questionnaire takes: the service vocabulary, what the
/// reader is offered.
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

/// What the reader is offered: the offered words in order, each with the
/// words folded into it.
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
  return {
    'groups': [
      for (final r in shown)
        () {
          final key = r.word['key'] as String;
          return <String, dynamic>{
            'key': key,
            'label_ko': r.word['ko'],
            'domain': _domainOf[r.type],
            'source_keys': [
              for (final entry in targets.entries)
                if (entry.value == key && sources.contains(entry.key))
                  entry.key,
            ],
            'phases':
                _map(r.word['choice'])['said_of'] ??
                r.word['said_of'] ??
                const <String>[],
          };
        }(),
    ],
  };
}
