import 'dart:collection';
import 'dart:typed_data';

import 'catalog_drink.dart';

/// How many matches one search call returns; a full page means more may follow.
const int catalogSearchPageSize = 20;

/// What one search answered: the drinks, and what to say about them.
class CatalogMatches extends UnmodifiableListView<CatalogDrink> {
  CatalogMatches(super.source, {this.guesses = false, this.notCarried});

  /// No name holds the words as typed: the drinks only sound or look alike.
  final bool guesses;

  /// The kind of drink the words name when the catalog does not carry it
  /// (`beer`, `soju`, `liqueur`, `gin`, `vodka`, `rum`, `tequila`, `brandy`,
  /// `baijiu`, `mass_market` for the everyday makgeolli and cheongju it leaves
  /// out), `not_listed` for a bottle of a kind it carries that is not in it
  /// yet, else `null`.
  final String? notCarried;
}

/// The line a search screen shows with an answer: that the catalog does not
/// carry the drink, or that the drinks shown are only like what was typed.
String? catalogSearchNote({
  required String? notCarried,
  required bool guesses,
}) {
  if (notCarried == 'not_listed') {
    return '찾으시는 술은 아직 술결에 등록되지 않았어요.';
  }
  final kind = switch (notCarried) {
    'beer' => '맥주는',
    'soju' => '일반 소주는',
    'liqueur' => '리큐르는',
    'gin' => '진은',
    'vodka' => '보드카는',
    'rum' => '럼은',
    'tequila' => '테킬라는',
    'brandy' => '브랜디와 코냑은',
    'baijiu' => '고량주와 백주는',
    'mass_market' => '마트에서 흔히 파는 막걸리·청주·매실주는',
    _ => null,
  };
  if (kind != null) {
    return '술결은 와인, 위스키, 사케, 전통주를 다뤄요. $kind 다루지 않아요.';
  }
  return guesses ? '입력하신 이름과 비슷한 술이에요.' : null;
}

abstract interface class CatalogSearchGateway {
  /// [offset] skips the matches already shown, for the next page. The
  /// catalog's own gateway answers a [CatalogMatches].
  Future<List<CatalogDrink>> search(
    String query, {
    int limit = catalogSearchPageSize,
    int offset = 0,
  });

  /// One answer per query, in order, from a single call: what [search]
  /// would return for each, up to [limit] drinks. At most eight queries.
  /// [readOffLabel] says the queries are lines a label photo was read
  /// into, which also finds a name read a letter or two wrong.
  Future<List<List<CatalogDrink>>> searchMany(
    List<String> queries, {
    int limit = 10,
    bool readOffLabel = false,
  });
}

/// A catalog that also answers the words a label photo was read into with
/// the drinks whose name words look like them, for the label match to rank.
abstract interface class LabelWordSearch {
  /// The drinks one of whose name words looks like one of [words], most
  /// found first, and the drinks of [alsoIds] whatever their words. Empty
  /// from a server that does not have this search yet.
  Future<List<LabelCandidate>> searchByLabelWords(
    List<String> words, {
    List<String> alsoIds = const <String>[],
  });
}

/// A drink the label word search answered, with the rarity of each word of
/// its names (how much reading it says) and how much the words read found
/// of it.
class LabelCandidate {
  const LabelCandidate({
    required this.drink,
    required this.kind,
    required this.nameRarity,
    required this.found,
  });

  final CatalogDrink drink;

  /// The catalog's kind of drink ('wine', 'whisky', 'sake',
  /// 'korean_traditional').
  final String kind;
  final Map<String, double> nameRarity;
  final double found;
}

/// A catalog that can also be shown the photo of one bottle and asked
/// which of the label's candidates it is: its server has a model read the
/// label itself, and the photo is kept nowhere.
abstract interface class LabelPhotoJudge {
  /// The most candidates one photo is judged against.
  static const int maxCandidates = 10;

  /// The drink among [candidateIds], likeliest first, that [photo] (a JPEG
  /// of the bottle) shows, or `null` when the server is sure of none of
  /// them. [appSure] says the label match is sure of the first. Throws
  /// [LabelPhotoJudgeException] when the server gave no answer.
  Future<String?> pickByPhoto(
    Uint8List photo,
    List<String> candidateIds, {
    required bool appSure,
  });
}

/// The server did not judge the photo: nobody is signed in, the call
/// failed, or it took too long. The label match's own answer stands.
class LabelPhotoJudgeException implements Exception {
  const LabelPhotoJudgeException();
}

class CatalogSearchException implements Exception {
  const CatalogSearchException();
}
