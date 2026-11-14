import '../../../../design/app_tokens.dart';
import 'package:flutter/material.dart';

import '../../../../design/app_typography.dart';
import '../../../../widgets/level_gauge.dart';
import '../../../../widgets/app_term_tooltip.dart';
import '../../../../widgets/kept_text.dart';
import '../../../../widgets/paper_box.dart';
import '../../../../widgets/text_underline.dart';
import '../../data/taste_card_snapshot_view_data.dart';
import 'taste_card_guide_parts.dart';

/// 다음에 음용하실 레드 와인은 아래의 기준에 맞게 찾아보세요: the sentence over
/// a guide's direction chips, on the card and on the home carousel alike.
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

/// 다음 술은 이렇게 골라보세요, below its lead sentence: the direction chips,
/// the picks under a title that names what they are for this kind of drink,
/// the marks in a box, and the label tip. The card and the home carousel
/// both draw it under [TasteCardGuideLead]; the carousel without the tip.
class TasteCardGuideBody extends StatelessWidget {
  const TasteCardGuideBody({
    required this.guide,
    required this.categoryLabel,
    this.labelStyle = TasteCardGuideText.label,
    this.denseDirections = false,
    this.explainPicks = true,
    this.showTip = true,
    this.levelsKey,
    super.key,
  });

  final TasteCardGuideViewData guide;

  /// 와인, 위스키, 사케, 한국 전통주: names the picks' section.
  final String? categoryLabel;

  /// The style of the section labels (추천 품종 & 산지, 추천 맛 밸런스).
  final TextStyle labelStyle;

  /// The direction chips a size smaller, under the home's small lead line.
  final bool denseDirections;

  /// A cask or method chip underlines its name and opens its explanation;
  /// the home carousel opens the whole card on a touch instead.
  final bool explainPicks;
  final bool showTip;

  /// Hung on the box of marks, for whoever needs to know where it starts.
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

  /// 'Corn Whiskey' 표기 as 'Corn Whiskey': the description over the chips
  /// already says they are words on the label.
  static TasteCardGuidePickViewData _withoutLabelSuffix(
    TasteCardGuidePickViewData pick,
  ) => pick.keyword.endsWith(' 표기')
      ? TasteCardGuidePickViewData(
          keyword: pick.keyword.substring(0, pick.keyword.length - 3),
          country: pick.country,
          place: pick.place,
          note: pick.note,
        )
      : pick;

  static bool _isLabelWord(TasteCardGuidePickViewData pick) =>
      pick.country == null && pick.place == null && pick.keyword.endsWith('표기');

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
        if (guide.directions.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final direction in guide.directions)
                TasteCardDirectionChip(
                  direction: direction,
                  dense: denseDirections,
                ),
            ],
          ),
        ],
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
                for (final pick in plain) TasteCardPickTicket(pick: pick),
              ],
            ),
          ],
          for (final pick in noted) ...<Widget>[
            const SizedBox(height: 10),
            _NotedPick(pick: pick, explain: explainPicks),
          ],
        ],
        if (guide.levels.isNotEmpty) ...<Widget>[
          const SizedBox(height: 20),
          Container(
            key: levelsKey,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
            decoration: BoxDecoration(
              border: Border.all(color: TasteCardGuideColors.ticketLine),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(levelsTitle(guide), style: labelStyle),
                const SizedBox(height: 10),
                for (final (index, level) in guide.levels.indexed) ...<Widget>[
                  if (index > 0) const SizedBox(height: 13),
                  LevelGauge(
                    label: level.label,
                    mark: level.mark,
                    note: level.range,
                  ),
                ],
              ],
            ),
          ),
        ],
        if (showTip && tip != null) ...<Widget>[
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
    fontSize: 12,
    height: 1.5,
    color: PaperInk.grey,
  );
}

/// A pick with what it brings, on one ticket: the word to look for, and under
/// it the aroma or the label reading ("달콤하고 부드러운 코코넛 향이 나요").
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
    final term = explain ? pick.term : null;
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
          if (term == null)
            Text(
              place == null ? pick.keyword : '$place · ${pick.keyword}',
              style: _name,
            )
          else
            // Only the word the explanation is about is underlined and
            // opens it; the place before it is not that word.
            Wrap(
              children: <Widget>[
                if (place != null) Text('$place · ', style: _name),
                Builder(
                  builder: (wordContext) => GestureDetector(
                    key: ValueKey<String>(
                      'taste-card-pick-term-${pick.keyword}',
                    ),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => showTermTooltip(
                      wordContext,
                      title: term.label,
                      kind: term.kind,
                      text: term.description,
                    ),
                    child: TextUnderline(
                      color: PaperInk.ink,
                      fontSize: MediaQuery.textScalerOf(context).scale(14),
                      child: Text(pick.keyword, style: _name),
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 4),
          KeptText(pick.note!, style: TasteCardGuideText.caption),
        ],
      ),
    );
  }
}

/// 코코넛 향 ✔ on a wine tint; 알코올 열감 ⬇ on a calm sage: what to keep is
/// told from what to turn down by its color, in every kind of guide.
class TasteCardDirectionChip extends StatelessWidget {
  const TasteCardDirectionChip({
    required this.direction,
    this.dense = false,
    super.key,
  });

  final TasteCardGuideDirectionViewData direction;
  final bool dense;

  static const _keepBackground = Color(0xFFF5E6E7);
  static const _turnBackground = Color(0xFFEBEFE8);
  static const _turnInk = Color(0xFF4F5A52);

  @override
  Widget build(BuildContext context) {
    final keep = direction.change == TasteCardGuideChange.keep;
    final ink = keep ? TasteCardGuideColors.wineDeep : _turnInk;
    return PaperChip(
      text: direction.word,
      icon: switch (direction.change) {
        TasteCardGuideChange.keep => tasteCardTagIcons[TasteCardTagKind.fine]!,
        TasteCardGuideChange.lower => tasteCardTagIcons[TasteCardTagKind.less]!,
        TasteCardGuideChange.higher =>
          tasteCardTagIcons[TasteCardTagKind.more]!,
      },
      iconColor: ink,
      background: keep ? _keepBackground : _turnBackground,
      textColor: ink,
      dense: dense,
    );
  }
}

/// The small icon after a 핵심 요약 tag or a direction chip, by its kind.
const tasteCardTagIcons = <TasteCardTagKind, String>{
  TasteCardTagKind.liked: 'assets/icons/guide_tags/heart.svg',
  TasteCardTagKind.less: 'assets/icons/guide_tags/arrow_down.svg',
  TasteCardTagKind.burden: 'assets/icons/guide_tags/prohibit.svg',
  TasteCardTagKind.more: 'assets/icons/guide_tags/arrow_up.svg',
  TasteCardTagKind.fine: 'assets/icons/guide_tags/check.svg',
};
