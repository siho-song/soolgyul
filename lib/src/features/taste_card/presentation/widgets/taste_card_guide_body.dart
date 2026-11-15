import '../../../../design/app_tokens.dart';
import 'package:flutter/material.dart';

import '../../../../design/app_typography.dart';
import '../../../../widgets/level_gauge.dart';
import '../../../../widgets/kept_text.dart';
import '../../../../widgets/paper_box.dart';
import '../../data/taste_card_snapshot_view_data.dart';
import 'taste_card_guide_parts.dart';

/// 다음에 음용하실 레드 와인은 아래의 기준에 맞게 찾아보세요: the sentence over
/// a guide's body, on the card and on the home carousel alike.
/// The kind and 아래의 기준 are the words to read, so they alone are [strong].
class TasteCardGuideLead extends StatelessWidget {
  const TasteCardGuideLead({
    required this.kindLabel,
    required this.categoryLabel,
    required this.style,
    required this.strong,
    super.key,
  });

  /// 레드 와인, 싱글 몰트 위스키, 버번.
  final String kindLabel;
  final String? categoryLabel;
  final TextStyle style;
  final TextStyle strong;

  /// 버번 위스키: a whisky kind whose name leaves the word out gets it back,
  /// so the sentence names a drink the way the other whiskies do.
  String get _kind => categoryLabel == '위스키' && !kindLabel.endsWith('위스키')
      ? '$kindLabel 위스키'
      : kindLabel;

  /// 와인은, 위스키는: by whether the kind's last syllable closes on a consonant.
  static String _topicParticle(String word) {
    final last = word.runes.last;
    final closed =
        last >= 0xAC00 && last <= 0xD7A3 && (last - 0xAC00) % 28 != 0;
    return closed ? '은' : '는';
  }

  @override
  Widget build(BuildContext context) => KeptText.rich(
    TextSpan(
      style: style,
      children: <InlineSpan>[
        const TextSpan(text: '다음에 음용하실 '),
        TextSpan(text: _kind, style: strong),
        TextSpan(text: '${_topicParticle(_kind)} '),
        TextSpan(text: '아래의 기준', style: strong),
        const TextSpan(text: '에 맞게 찾아보세요'),
      ],
    ),
  );
}

/// 다음 술은 이렇게 골라보세요, below its lead sentence: the picks under a
/// title that names what they are for this kind of drink, the drink in
/// words and the marks in a box, and the tip on using it in a shop. The card
/// and the home carousel both draw it under [TasteCardGuideLead].
class TasteCardGuideBody extends StatelessWidget {
  const TasteCardGuideBody({
    required this.guide,
    required this.categoryLabel,
    this.labelStyle = TasteCardGuideText.label,
    this.explainPicks = true,
    this.levelsKey,
    super.key,
  });

  final TasteCardGuideViewData guide;

  /// 와인, 위스키, 사케, 한국 전통주: names the picks' section.
  final String? categoryLabel;

  /// The style of the section labels (추천 품종 & 산지, 추천 맛 밸런스).
  final TextStyle labelStyle;

  /// A chip underlines each word the dictionary explains and opens its
  /// explanation.
  final bool explainPicks;

  /// Hung on the box of the profile and marks, for whoever needs to know
  /// where it starts.
  final Key? levelsKey;

  /// 추천 캐스크 & 제조 방식: what the chips name, by the kind of drink. A
  /// wine with no grape or a sake with no grade to name gets label words
  /// instead.
  static String picksTitle(
    String? categoryLabel, [
    List<TasteCardGuidePickViewData> picks = const [],
  ]) => switch (categoryLabel) {
    '와인' ||
    '사케' when picks.isNotEmpty && picks.every(_isLabelWord) => '라벨 추천 표기',
    '와인' => '추천 품종 및 산지',
    '위스키' => '추천 캐스크 및 숙성 방식',
    '사케' => '추천 등급',
    '한국 전통주' => '라벨 추천 표기',
    _ => '추천 키워드',
  };

  static const labelWordsDescription = '병 라벨에서 이런 표기를 찾아보세요';

  /// The title over a drink said in words (AROMA, FLAVOR, FINISH).
  static const profileTitle = '취향 테이스팅 노트';

  /// What to do with the chips, under their title: find these words, these
  /// grapes and regions, or these grades on the label.
  static String? picksDescription(
    String? categoryLabel, [
    List<TasteCardGuidePickViewData> picks = const [],
  ]) => switch (picksTitle(categoryLabel, picks)) {
    '추천 품종 및 산지' => '병 라벨에서 이런 품종과 산지를 찾아보세요',
    '추천 등급' => '병 라벨에서 이런 등급을 찾아보세요',
    '추천 키워드' when picks.isEmpty || !picks.every(_isLabelWord) => null,
    _ => labelWordsDescription,
  };

  /// 'Corn Whiskey' 표기 as 'Corn Whiskey', on a card stored before chips
  /// carried their words: the description over the chips already says they
  /// are words on the label.
  static TasteCardGuidePickViewData _withoutLabelSuffix(
    TasteCardGuidePickViewData pick,
  ) => pick.words.isEmpty && pick.keyword.endsWith(' 표기')
      ? TasteCardGuidePickViewData(
          keyword: pick.keyword.substring(0, pick.keyword.length - 3),
          country: pick.country,
          place: pick.place,
          note: pick.note,
          term: pick.term,
        )
      : pick;

  /// Words printed on the label, not a grape, a region or a grade. A chip
  /// that carries its words says which it is; a card stored before says it
  /// with a trailing 표기.
  static bool _isLabelWord(TasteCardGuidePickViewData pick) =>
      pick.labelWord ??
      (pick.country == null &&
          pick.place == null &&
          (pick.words.isNotEmpty || pick.keyword.endsWith('표기')));

  static String levelsTitle(TasteCardGuideViewData guide) =>
      guide.levels.length == 1 ? '추천 ${guide.levels.single.label}' : '취향 맛 밸런스';

  @override
  Widget build(BuildContext context) {
    final description = picksDescription(categoryLabel, guide.picks);
    final picks = description == labelWordsDescription
        ? guide.picks.map(_withoutLabelSuffix).toList()
        : guide.picks;
    final plain = picks.where((pick) => pick.note == null).toList();
    final noted = picks.where((pick) => pick.note != null).toList();
    final tip = guide.tip;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (guide.picks.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          const Divider(height: 1, color: PaperInk.line),
          const SizedBox(height: 14),
          Text(picksTitle(categoryLabel, guide.picks), style: labelStyle),
          if (description != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            KeptText(description, style: TasteCardGuideText.caption),
          ],
          if (plain.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final pick in plain)
                  TasteCardPickTicket(pick: pick, explain: explainPicks),
              ],
            ),
          ],
          for (final pick in noted) ...<Widget>[
            const SizedBox(height: 10),
            _NotedPick(pick: pick, explain: explainPicks),
          ],
        ],
        if (guide.profile.isNotEmpty || guide.levels.isNotEmpty) ...<Widget>[
          const SizedBox(height: 20),
          _TasteBox(key: levelsKey, guide: guide, labelStyle: labelStyle),
        ],
        if (tip != null) ...<Widget>[
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.lightbulb_outline_rounded,
                  size: AppSizes.iconXs,
                  color: PaperInk.grey,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(child: KeptText(tip, style: TasteCardGuideText.caption)),
            ],
          ),
        ],
      ],
    );
  }
}

/// The taste to look for in one box: the drink in words (a whisky's AROMA,
/// FLAVOR, FINISH), then the marks under their own title, a line between
/// the two.
class _TasteBox extends StatelessWidget {
  const _TasteBox({required this.guide, required this.labelStyle, super.key});

  final TasteCardGuideViewData guide;
  final TextStyle labelStyle;

  /// A range that only repeats the bar's five steps: 2, 1~2.
  static final _stepsOnly = RegExp(r'^[1-5](~[1-5])?$');

  /// The range beside a mark's word, when it says what the word does not
  /// (도수 40~43%); a mark without a word keeps its range as before.
  static String? _noteOf(TasteCardGuideLevelViewData level) =>
      level.word != null && _stepsOnly.hasMatch(level.range)
      ? null
      : level.range;

  @override
  Widget build(BuildContext context) {
    final levels = guide.levels;
    // One mark said in a word and every row leaves the end words out, so
    // the bars of a box still start on one line.
    // A box whose every range says more than the bar's steps (도수 40~43%,
    // a sake's 일본주도) reads the same way, the range where the word goes.
    final worded =
        levels.any((level) => level.word != null) ||
        levels.every((level) => !_stepsOnly.hasMatch(level.range));
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      decoration: BoxDecoration(
        border: Border.all(color: TasteCardGuideColors.ticketLine),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (guide.profile.isNotEmpty) ...<Widget>[
            Text(TasteCardGuideBody.profileTitle, style: labelStyle),
            const SizedBox(height: AppSpacing.sm),
            _Profile(lines: guide.profile),
          ],
          if (guide.profile.isNotEmpty && levels.isNotEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1, color: PaperInk.line),
            ),
          if (levels.isNotEmpty) ...<Widget>[
            Text(TasteCardGuideBody.levelsTitle(guide), style: labelStyle),
            const SizedBox(height: 10),
            for (final (index, level) in levels.indexed) ...<Widget>[
              if (index > 0) const SizedBox(height: 13),
              _gauge(level, worded: worded),
            ],
          ],
        ],
      ),
    );
  }

  static Widget _gauge(
    TasteCardGuideLevelViewData level, {
    required bool worded,
  }) {
    final term = level.term;
    final onExplain = term == null
        ? null
        : (BuildContext label) => showGuideTerm(label, term);
    return worded
        ? LevelGauge.worded(
            label: level.label,
            mark: level.mark,
            word: level.word,
            note: _noteOf(level),
            onExplain: onExplain,
          )
        : LevelGauge(
            label: level.label,
            mark: level.mark,
            note: level.range,
            onExplain: onExplain,
          );
  }
}

/// A drink said in words where another kind has gauges, one line each: the
/// line's name in small letters, then its words.
///
///   AROMA    바닐라 · 꿀 · 캐러멜
///   FLAVOR   토피 · 건포도
///   FINISH   길고 따뜻한 여운
class _Profile extends StatelessWidget {
  const _Profile({required this.lines});

  final List<TasteCardGuideProfileLineViewData> lines;

  static const _name = AppTextStyle(
    fontSize: 11,
    height: 1.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.8,
    color: PaperInk.grey,
  );
  static const _words = AppTextStyle(
    fontSize: 14,
    height: 1.5,
    fontWeight: FontWeight.w600,
    color: PaperInk.ink,
  );

  /// As wide as FLAVOR, so every line's words start under each other.
  static const double _nameWidth = 64;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      for (final (index, line) in lines.indexed) ...<Widget>[
        if (index > 0) const SizedBox(height: AppSpacing.s6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            SizedBox(
              width: _nameWidth,
              child: Text(line.label, style: _name),
            ),
            Expanded(child: KeptText(line.words.join(' · '), style: _words)),
          ],
        ),
      ],
    ],
  );
}

/// The section labels (내 취향 기준, 추천 캐스크 & 제조 방식) and the captions
/// under a pick or the tip, on the card and on the home carousel alike.
abstract final class TasteCardGuideText {
  static const label = AppTextStyle(
    fontSize: 13,
    height: 1.5,
    fontWeight: FontWeight.w700,
    color: PaperInk.inkSoft,
  );
  static const caption = AppTextStyle(
    fontSize: 14,
    height: 1.5,
    color: PaperInk.grey,
  );
}

/// A pick with why it is picked, on one ticket: the place and the words to
/// look for, and under them the reason ("좋아하신 바닐라 향이 담겨요").
class _NotedPick extends StatelessWidget {
  const _NotedPick({required this.pick, required this.explain});

  final TasteCardGuidePickViewData pick;
  final bool explain;

  static const _name = AppTextStyle(
    fontSize: 14,
    height: 1.4,
    fontWeight: FontWeight.w700,
    color: PaperInk.ink,
  );

  @override
  Widget build(BuildContext context) {
    final place = pick.place;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
      decoration: BoxDecoration(
        color: TasteCardGuideColors.ticket,
        border: Border.all(color: TasteCardGuideColors.ticketLine),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (place != null) ...<Widget>[
            TasteCardPickPlace(country: pick.country, place: place),
            const SizedBox(height: AppSpacing.xxs),
          ],
          TasteCardPickWords(
            words: pick.shownWords,
            trail: pick.trail,
            explain: explain,
            style: _name,
          ),
          const SizedBox(height: 4),
          KeptText(pick.note!, style: TasteCardGuideText.caption),
        ],
      ),
    );
  }
}

/// The small icon after a 핵심 요약 tag, by its kind.
const tasteCardTagIcons = <TasteCardTagKind, String>{
  TasteCardTagKind.liked: 'assets/icons/guide_tags/heart.svg',
  TasteCardTagKind.less: 'assets/icons/guide_tags/arrow_down.svg',
  TasteCardTagKind.burden: 'assets/icons/guide_tags/prohibit.svg',
  TasteCardTagKind.more: 'assets/icons/guide_tags/arrow_up.svg',
  TasteCardTagKind.fine: 'assets/icons/guide_tags/check.svg',
};
