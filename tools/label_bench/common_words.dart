// Writes lib/src/features/taste_fit/data/label_common_words.g.dart, what
// the label search knows of the words in the catalog's names:
//   - how many drinks hold each word, for the words in twenty names or
//     more, which is what reading the word is worth;
//   - the words that say which grape is in the bottle and so tell a
//     producer's bottles apart and name none: a word many producers put
//     on bottles of one grape ("merlot", "shiraz", "chablis", "쉬라즈"), or
//     of the grapes whose key holds it ("sauvignon"), and the Korean
//     spelling of such a word, read off the names that carry both
//     spellings word for word.
//
//   - the words many places share ("valley", "county", "밸리"), which
//     name no place by themselves.
//
// The catalog is read from two files with tabs between the fields. One
// drink a line: Korean name, English name, grape keys with spaces
// between, producer id. One place a line: the names it goes by.
//
//   psql "$DB" -At -F $'\t' -c "select name_ko, coalesce(name_en, ''),
//     array_to_string(grape_variety_keys, ' '), coalesce(producer_id::text, '')
//     from public.alcohol_items where publish_status = 'published'" > names.tsv
//   psql "$DB" -At -F $'\t' -c "select label_ko, coalesce(label_en, ''),
//     array_to_string(synonyms, ' ') from public.catalog_taxonomy
//     where term_type = 'region'" > places.tsv
//   dart run tools/label_bench/common_words.dart names.tsv places.tsv
import 'dart:io';

import 'package:soolgyul/src/features/taste_fit/data/label_text.dart';

const int _fewestNames = 20;
const String _target =
    'lib/src/features/taste_fit/data/label_common_words.g.dart';

/// A word says the grape when this many producers use it and this share
/// of the drinks with it hold one same grape, or a grape whose key holds
/// the word.
const int _fewestProducers = 10;
const double _oneGrapeShare = 0.8;
const double _keyGrapeShare = 0.6;

/// A word names no place by itself when this many places hold it.
const int _fewestPlaces = 6;

/// A Korean word is a grape word's spelling when it stands where the
/// Latin word stands this often.
const int _fewestPairs = 10;

List<String> _nameWords(String name) => labelWords(
  withoutVintage(name),
).where((word) => !isVintageWord(word)).toList(growable: false);

void main(List<String> args) {
  final rows = <List<String>>[
    for (final line in File(args[0]).readAsLinesSync()) line.split('\t'),
  ];

  // A drink's years are one drink, and its words are counted once.
  final drinks = <String, Set<String>>{};
  for (final row in rows) {
    drinks.putIfAbsent(foldLabelText(withoutVintage(row[0])), () => <String>{})
      ..addAll(_nameWords(row[0]))
      ..addAll(_nameWords(row[1]));
  }
  final counts = <String, int>{};
  for (final words in drinks.values) {
    for (final word in words) {
      counts[word] = (counts[word] ?? 0) + 1;
    }
  }
  final common =
      counts.entries.where((entry) => entry.value >= _fewestNames).toList()
        ..sort((a, b) {
          final byCount = b.value.compareTo(a.value);
          return byCount != 0 ? byCount : a.key.compareTo(b.key);
        });

  // What the drinks whose name holds a word are made of.
  final drinksWith = <String, int>{};
  final producersWith = <String, Set<String>>{};
  final grapesWith = <String, Map<String, int>>{};
  final ownKeyWith = <String, int>{};
  for (final row in rows) {
    final keys = row[2].split(' ').where((key) => key.isNotEmpty).toList();
    if (keys.isEmpty) continue;
    for (final word in <String>{..._nameWords(row[0]), ..._nameWords(row[1])}) {
      drinksWith[word] = (drinksWith[word] ?? 0) + 1;
      producersWith.putIfAbsent(word, () => <String>{}).add(row[3]);
      final tally = grapesWith.putIfAbsent(word, () => <String, int>{});
      for (final key in keys) {
        tally[key] = (tally[key] ?? 0) + 1;
      }
      if (keys.any((key) => key.split('_').contains(word))) {
        ownKeyWith[word] = (ownKeyWith[word] ?? 0) + 1;
      }
    }
  }
  bool saysTheGrape(String word) {
    final drinks = drinksWith[word]!;
    if (drinks < _fewestNames ||
        producersWith[word]!.length < _fewestProducers) {
      return false;
    }
    final oneGrape = grapesWith[word]!.values.reduce((a, b) => a > b ? a : b);
    return oneGrape >= _oneGrapeShare * drinks ||
        (ownKeyWith[word] ?? 0) >= _keyGrapeShare * drinks;
  }

  bool readable(String word) => !isTooShortToRead(word) && !isNumberWord(word);
  final said = drinksWith.keys.where(readable).where(saysTheGrape).toSet();

  // A name in both spellings, word for word ("Montes Alpha Syrah", "몬테스
  // 알파 시라"), says which Korean word a grape's Latin word is.
  final paired = <String, int>{};
  final unpaired = <String, int>{};
  for (final row in rows) {
    final korean = _nameWords(row[0]);
    final latin = _nameWords(row[1]);
    if (korean.length != latin.length) continue;
    for (final (at, word) in korean.indexed) {
      final tally = said.contains(latin[at]) ? paired : unpaired;
      tally[word] = (tally[word] ?? 0) + 1;
    }
  }
  final grapes = <String>{
    ...said,
    for (final MapEntry(key: word, value: count) in paired.entries)
      if (count >= _fewestPairs &&
          count >= 4 * (unpaired[word] ?? 0) &&
          readable(word) &&
          !isLatinWord(word))
        word,
  }.toList()..sort();

  final placesWith = <String, int>{};
  for (final line in File(args[1]).readAsLinesSync()) {
    for (final word in labelWords(line).toSet()) {
      placesWith[word] = (placesWith[word] ?? 0) + 1;
    }
  }
  final placeWords = <String>[
    for (final MapEntry(key: word, value: count) in placesWith.entries)
      if (count >= _fewestPlaces && readable(word)) word,
  ]..sort();

  final out = StringBuffer()
    ..writeln(
      '// Written by tools/label_bench/common_words.dart; not edited by hand.',
    )
    ..writeln()
    ..writeln('/// The drinks the catalog had when the words were counted.')
    ..writeln('const int countedDrinks = ${drinks.length};')
    ..writeln()
    ..writeln('/// How many drinks hold each word of a name, for the words in')
    ..writeln('/// $_fewestNames names or more; a word not here is in fewer.')
    ..writeln('const int fewestCountedNames = $_fewestNames;')
    ..writeln('const Map<String, int> commonNameWords = <String, int>{');
  for (final MapEntry(key: word, value: count) in common) {
    out.writeln("  '$word': $count,");
  }
  out
    ..writeln('};')
    ..writeln()
    ..writeln(
      '/// The words that say which grape is in a bottle, as the catalog',
    )
    ..writeln('/// spells them.')
    ..writeln('const Set<String> grapeNameWords = <String>{');
  for (final word in grapes) {
    out.writeln("  '$word',");
  }
  out
    ..writeln('};')
    ..writeln()
    ..writeln(
      '/// The words many places share, which name no place by themselves.',
    )
    ..writeln('const Set<String> placeKindWords = <String>{');
  for (final word in placeWords) {
    out.writeln("  '$word',");
  }
  out.writeln('};');
  File(_target).writeAsStringSync(out.toString());
  stdout.writeln(
    '${drinks.length} drinks, ${common.length} words, '
    '${grapes.length} grape words, ${placeWords.length} place words',
  );
}
