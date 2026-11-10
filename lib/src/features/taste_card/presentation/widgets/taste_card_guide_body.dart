import '../../../../design/app_tokens.dart';
import 'package:flutter/material.dart';

import '../../../../design/app_typography.dart';
import '../../../../widgets/level_gauge.dart';
import '../../../../widgets/paper_box.dart';
import '../../data/taste_card_snapshot_view_data.dart';
import 'taste_card_guide_parts.dart';

/// 다음 술은 이렇게 골라보세요, below its head sentence: 내 취향 기준 (the
/// direction chips), the picks under a title that names what they are for
/// this kind of drink, the marks in a box, and the label tip. The card draws
/// it under the head; the home carousel under the bottle's kind, without the
/// tip.
class TasteCardGuideBody extends StatelessWidget {
  const TasteCardGuideBody({
    required this.guide,
    required this.categoryLabel,
    this.directionsLabel = '취향 분석 키워드',
    this.labelStyle = TasteCardGuideText.label,
    this.showTip = true,
    super.key,
  });

  final TasteCardGuideViewData guide;

  /// 와인, 위스키, 사케, 한국 전통주: names the picks' section.
  final String? categoryLabel;

  /// The label over the direction chips; null puts the chips right under
  /// whatever the caller drew above (the home's 내 취향에 맞춘 레드 와인).
  final String? directionsLabel;

  /// The style of the section labels (추천 품종 & 산지, 추천 맛 밸런스).
  final TextStyle labelStyle;
  final bool showTip;

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

  static bool _isLabelWord(TasteCardGuidePickViewData pick) =>
      pick.country == null && pick.place == null && pick.keyword.endsWith('표기');

  static String levelsTitle(TasteCardGuideViewData guide) =>
      guide.levels.length == 1 ? '추천 ${guide.levels.single.label}' : '취향 맛 밸런스';

  @override
  Widget build(BuildContext context) {
    final plain = guide.picks.where((pick) => pick.note == null).toList();
    final noted = guide.picks.where((pick) => pick.note != null).toList();
    final tip = guide.tip;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (guide.directions.isNotEmpty) ...<Widget>[
          if (directionsLabel case final label?) ...<Widget>[
            const SizedBox(height: 16),
            Text(label, style: labelStyle),
            const SizedBox(height: 8),
          ] else
            const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final direction in guide.directions)
                TasteCardDirectionChip(direction: direction),
            ],
          ),
        ],
        if (guide.picks.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          const Divider(height: 1, color: PaperInk.line),
          const SizedBox(height: 14),
          Text(picksTitle(categoryLabel, guide.picks), style: labelStyle),
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
            _NotedPick(pick: pick),
          ],
        ],
        if (guide.levels.isNotEmpty) ...<Widget>[
          const SizedBox(height: 20),
          Container(
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
              Expanded(child: Text(tip, style: TasteCardGuideText.caption)),
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
  const _NotedPick({required this.pick});

  final TasteCardGuidePickViewData pick;

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
          Text(
            place == null ? pick.keyword : '$place · ${pick.keyword}',
            style: const AppTextStyle(
              fontSize: 14,
              height: 1.4,
              fontWeight: FontWeight.w700,
              color: PaperInk.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(pick.note!, style: TasteCardGuideText.caption),
        ],
      ),
    );
  }
}

/// 코코넛 향 ✔ on a wine tint; 알코올 열감 ⬇ on a calm sage: what to keep is
/// told from what to turn down by its color, in every kind of guide.
class TasteCardDirectionChip extends StatelessWidget {
  const TasteCardDirectionChip({required this.direction, super.key});

  final TasteCardGuideDirectionViewData direction;

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
    );
  }
}

/// The small icon after a 핵심 요약 tag or a direction chip, by its kind.
const tasteCardTagIcons = <TasteCardTagKind, String>{
  TasteCardTagKind.liked: 'assets/component_assets/taste_card/tags/heart.svg',
  TasteCardTagKind.less:
      'assets/component_assets/taste_card/tags/arrow_down.svg',
  TasteCardTagKind.burden:
      'assets/component_assets/taste_card/tags/prohibit.svg',
  TasteCardTagKind.more: 'assets/component_assets/taste_card/tags/arrow_up.svg',
  TasteCardTagKind.fine: 'assets/component_assets/taste_card/tags/check.svg',
};
