import 'dart:math' as math;

import 'label_common_words.g.dart';
import 'label_text.dart';

/// Words every label of a kind carries ("single malt", "scotch whisky",
/// "純米大吟醸", "증류식 소주"). A line made of them names a category, not a
/// drink, and would pull in every drink of that kind; inside a naming line
/// they only narrow the every-word match for nothing. The catalog's names
/// cannot say which words these are, since a name leaves most of them out.
const Set<String> labelKindWords = <String>{
  // whisky and spirits
  'single', 'malt', 'malts', 'scotch', 'whisky', 'whiskey', 'bourbon',
  'blended', 'blend', 'grain', 'cask', 'strength', 'aged', 'years', 'year',
  'old', 'reserve', 'premium', 'special', 'distillery', 'distilled',
  'bottled', 'matured', 'finish', 'finished', 'product', 'of', 'the', 'and',
  'y', 'et', 'e', 'yo',
  'scotland', 'highland', 'speyside', 'islay', 'japan', 'korea', 'france',
  'italy', 'spain', 'gin', 'vodka', 'rum', 'tequila', 'brandy', 'cognac',
  'liqueur', 'spirit', 'spirits', 'beer', 'lager', 'ale',
  'kentucky', 'tennessee', 'straight', 'proof', 'barrel', 'batch',
  'japanese', 'irish', 'american', 'canadian',
  // wine
  'wine', 'vin', 'vino', 'red', 'white', 'rose', 'rosé', 'rouge', 'blanc',
  'rosso', 'bianco', 'tinto', 'blanco', 'brut', 'sec', 'dry', 'sweet',
  'sparkling', 'champagne', 'de', 'du', 'des', 'la', 'le', 'les', 'di', 'del',
  'della', 'appellation', 'controlee', 'contrôlée', 'doc', 'docg', 'aoc',
  // sake and shochu
  'sake', 'junmai', 'ginjo', 'daiginjo', 'honjozo', 'nigori', 'genshu',
  'namazake', 'tokubetsu', 'shochu', 'soju', 'makgeolli', 'takju', 'yakju',
  // sake grades and kinds as a label prints them: "特撰" is on many
  // brewers' bottles and names none
  '清酒', '日本酒', '純米', '吟醸', '大吟醸', '純米吟醸', '純米大吟醸', '本醸造',
  '特別純米', '特別本醸造', '普通酒', '原酒', '生酒', '生貯蔵', '特撰', '上撰', '佳撰',
  '辛口', '甘口',
  // Korean back labels
  '싱글', '몰트', '스카치', '위스키', '블렌디드', '사케', '준마이', '긴조', '다이긴조',
  '혼조조', '청주', '소주', '증류식', '희석식', '막걸리', '탁주', '약주', '과실주',
  '와인', '레드', '화이트', '로제', '스파클링', '샴페인', '리큐르', '맥주', '보드카',
  '브랜디', '꼬냑', '코냑', '원액', '숙성', '년', '년산', '알코올', '알콜', '용량',
  '제품명', '식품유형', '유형', '원재료명', '원재료', '제조원', '제조사', '수입원',
  '수입판매원', '수입자', '원산지', '주류', '주종', '주정', '정제수', '쌀', '누룩',
  '보리', '밀', '국내산', '수입산',
};

/// The words a label prints before the year its house began ("Since
/// 1892", "Depuis 1902"): on many labels and in a drink's name only by
/// chance ("신스 1974").
const Set<String> _foundingWords = <String>{
  'since',
  'depuis',
  'seit',
  'desde',
  'fondata',
  'founded',
  'established',
};

/// What reading a kind word is worth beside a word of weight 1, and the
/// least any other word is worth: read on a label, "chardonnay" tells a
/// producer's bottles apart however many names hold it.
const double _kindWordWeight = 0.25;
const double _leastWordWeight = 0.5;

final double _rarest = math.log(countedDrinks / fewestCountedNames);

/// How much reading [word], a word of a folded name, says for a drink
/// whose name holds it: 1 for a word in fewer than twenty names, less the
/// more names hold it (ln of the drinks per name with it, so "black", in
/// one name of two hundred, weighs 0.7), never under a half; and a
/// quarter for a kind word.
double labelWordWeight(String word) {
  if (labelKindWords.contains(word)) return _kindWordWeight;
  final names = commonNameWords[word];
  if (names == null) return 1;
  return math.max(_leastWordWeight, math.log(countedDrinks / names) / _rarest);
}

/// Whether [word] says which grape is in the bottle ("syrah", "chablis").
bool isGrapeWord(String word) => grapeNameWords.contains(word);

/// Whether many places share [word] ("valley", "county"), so that it
/// names no place by itself.
bool isPlaceKindWord(String word) =>
    placeKindWords.contains(word) || labelKindWords.contains(word);

/// Whether [word] belongs to a drink's name proper: not a kind of drink,
/// not a word that says the grape ("syrah", "chablis"), which tells a
/// producer's bottles apart and names none, and not an age or a strength
/// ("12", "40"), which is on many labels, nor the "since" of a house's
/// year; a longer number ("1865") is a name.
bool isNameWord(String word) =>
    !labelKindWords.contains(word) &&
    !_foundingWords.contains(word) &&
    !isGrapeWord(word) &&
    !(isNumberWord(word) && word.length < 3);

/// Whether [word] is one of a drink's own, which says whose bottle it is:
/// a word of its name proper that fewer names hold than the many whose
/// reading weighs the least ("chateau", "domaine", "reserva").
bool isOwnWord(String word) =>
    isNameWord(word) && labelWordWeight(word) > _leastWordWeight;
